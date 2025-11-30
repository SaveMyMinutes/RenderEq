// macos/Runner/EquationsHelperPlugin.swift
//
// Clipboard-only K-math converter:
// - Arm registers ⌥⇧V.
// - User selects text in any app, presses ⌥⇧V.
// - We snapshot the pasteboard, copy the current selection, detect $…$/$$…$$ spans
//   using UTF-16 offsets (to match arrow movement), collapse to selection start,
//   then for each span we shift-select the exact range and trigger ⌘⇧E.
// - Clipboard snapshot/restore clones pasteboard items to avoid AppKit exceptions.
//

import ApplicationServices
import Carbon
import Cocoa
import FlutterMacOS

// MARK: - Key codes
private let KC_RETURN: CGKeyCode = 0x24
private let KC_LEFT: CGKeyCode = CGKeyCode(kVK_LeftArrow)
private let KC_RIGHT: CGKeyCode = CGKeyCode(kVK_RightArrow)
private let KC_A: CGKeyCode = CGKeyCode(kVK_ANSI_A)
private let KC_C: CGKeyCode = CGKeyCode(kVK_ANSI_C)
private let KC_E: CGKeyCode = CGKeyCode(kVK_ANSI_E)
private let KC_V: CGKeyCode = CGKeyCode(kVK_ANSI_V)

// Modifier virtual keycodes (for real key down/up)
private let KC_CMD: CGKeyCode = CGKeyCode(kVK_Command)
private let KC_SHIFT: CGKeyCode = CGKeyCode(kVK_Shift)

public class EquationsHelperPlugin: NSObject, FlutterPlugin {

    // State
    private var isArmed = false
    private var hotKeyRef: EventHotKeyRef?
    private var hotKeyHandler: EventHandlerRef?
    private var isRunning = false

    // Event source
    private let src = CGEventSource(stateID: .hidSystemState)

    // Configurable delays (in microseconds)
    private var moveRightDelay: UInt32 = 45_000  // default 45ms
    private var shiftSelectDelay: UInt32 = 65_000  // default 65ms

    // MARK: - Flutter registration
    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: "equations_helper",
            binaryMessenger: registrar.messenger)
        let instance = EquationsHelperPlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)
    }

    // MARK: - Flutter channel
    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "arm":
            // Extract delay parameters from arguments
            if let args = call.arguments as? [String: Any] {
                if let moveDelay = args["moveRightDelay"] as? Int {
                    self.moveRightDelay = UInt32(moveDelay)
                }
                if let selectDelay = args["shiftSelectDelay"] as? Int {
                    self.shiftSelectDelay = UInt32(selectDelay)
                }
            }
            self.isArmed = true
            self.registerHotKey()  // ⌥⇧V
            result(true)

        case "disarm":
            self.isArmed = false
            self.unregisterHotKey()
            result(true)

        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // MARK: - Global Hotkey: Option + Shift + V
    private func registerHotKey() {
        if hotKeyRef != nil { return }  // already registered
        var hotKeyID = EventHotKeyID(signature: fourChar("EQHP"), id: 1)
        let modifiers: UInt32 = UInt32(optionKey | shiftKey)
        let keyCode: UInt32 = UInt32(kVK_ANSI_V)

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed))

        InstallEventHandler(
            GetApplicationEventTarget(),
            { (_, _, userData) -> OSStatus in
                guard let userData = userData else { return noErr }
                let me = Unmanaged<EquationsHelperPlugin>.fromOpaque(userData).takeUnretainedValue()
                me.onHotKey()
                return noErr
            },
            1, &eventType, Unmanaged.passUnretained(self).toOpaque(), &hotKeyHandler
        )

        RegisterEventHotKey(
            keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
    }

    private func unregisterHotKey() {
        if let hk = hotKeyRef { UnregisterEventHotKey(hk) }
        if let h = hotKeyHandler { RemoveEventHandler(h) }
        hotKeyRef = nil
        hotKeyHandler = nil
    }

    private func onHotKey() {
        guard isArmed, !isRunning else { return }
        isRunning = true
        DispatchQueue.global(qos: .userInitiated).async {
            self.runViaClipboardSelection()
            self.isRunning = false
        }
    }

    private func fourChar(_ s: String) -> OSType {
        var r: OSType = 0
        for u in s.utf16 { r = (r << 8) + OSType(u) }
        return r
    }

    // MARK: - Entry point (clipboard-only)
    private func runViaClipboardSelection() {
        guard let s = copyCurrentSelectionString(), !s.isEmpty else {
            return
        }

        // Detect $…$ / $$…$$ spans (inclusive) using UTF-16 offsets
        let spans = findDollarSegments(in: s)
        if spans.isEmpty { return }

        // Build skip mask in UTF-16 space for formatting tokens we don't want to count toward moveBy
        let u16 = Array(s.utf16)

        // Start with bold, then layer in everything else
        var skip = skipMaskForBold(u16)  // **…**
        applyItalicsToSkipMask(u16, skip: &skip)  // *…* (single *)
        applyCodeFencesToSkipMask(u16, skip: &skip)  // ``` … ```
        applyHeadingsToSkipMask(u16, skip: &skip)  // # / ## / ### + following space
        applyDividerLineToSkipMask(u16, skip: &skip)  // line '---' alone
        applyBulletsToSkipMask(u16, skip: &skip)  // "- " (incl. nested)
        applyNumberedListToSkipMask(u16, skip: &skip)  // "1. " (incl. nested)
        applyBlockquotesToSkipMask(u16, skip: &skip)  // "> " (incl. nested)
        applyLeadingIndent4SpacesToSkipMask(u16, skip: &skip)  // 4-space "tabs"
        applyEmptyLineNewlinesToSkipMask(u16, skip: &skip)  // skip LF of empty/whitespace-only lines

        // Log the collapsed (formatting-skipped) string for debugging
        var collapsedU16: [UInt16] = []
        collapsedU16.reserveCapacity(u16.count)
        for i in 0..<u16.count {
            if !skip[i] { collapsedU16.append(u16[i]) }
        }
        let collapsed: String = collapsedU16.withUnsafeBufferPointer { buf in
            guard let base = buf.baseAddress else { return "" }
            return String(utf16CodeUnits: base, count: buf.count)
        }

        // --- NEW: map UTF-16 indices -> grapheme (cursor) indices ---

        // For every UTF-16 code unit, remember which grapheme cluster (Character) it belongs to.
        var u16ToCluster = [Int](repeating: 0, count: u16.count)
        var clusterStarts: [Int] = []
        clusterStarts.reserveCapacity(s.count)

        var currentU16 = 0
        var clusterIndex = 0
        for ch in s {
            clusterStarts.append(currentU16)
            let len = ch.utf16.count
            for j in 0..<len {
                u16ToCluster[currentU16 + j] = clusterIndex
            }
            currentU16 += len
            clusterIndex += 1
        }
        let clusterCount = clusterIndex

        // For each grapheme cluster, mark if it contributes a "visible" movement step
        // (i.e. it has at least one non-skipped UTF-16 code unit).
        var visibleStep = [Int](repeating: 0, count: clusterCount)
        for i in 0..<u16.count {
            let cIdx = u16ToCluster[i]
            if !skip[i] && visibleStep[cIdx] == 0 {
                visibleStep[cIdx] = 1
            }
        }

        // Build prefix over *clusters* instead of raw UTF-16 units.
        var prefixCluster = [Int](repeating: 0, count: clusterCount + 1)
        for i in 0..<clusterCount {
            prefixCluster[i + 1] = prefixCluster[i] + visibleStep[i]
        }

        // Compute movements in cluster-space:
        // - moveBy = how many *visible* clusters to move from previous span start
        // - lengthClusters = how many cursor steps to select that $…$ span
        var movements: [(Int, Int)] = []
        var prevStartCluster = 0

        for (startUTF16, lenInclUTF16) in spans {
            let startCluster = u16ToCluster[startUTF16]
            let endUTF16 = startUTF16 + lenInclUTF16 - 1
            let endCluster = u16ToCluster[endUTF16]
            let lengthClusters = endCluster - startCluster + 1

            let moveByCollapsed = prefixCluster[startCluster] - prefixCluster[prevStartCluster]
            movements.append((moveByCollapsed, lengthClusters))

            prevStartCluster = startCluster + lengthClusters
        }

        // Collapse selection to its start, then iterate spans
        keyTap(KC_LEFT)  // collapse to leading edge of the selection
        usleep(150_000)

        for (moveBy, lenIncl) in movements {
            moveRight(count: moveBy)  // counts exclude skipped markdown tokens & empty-line LFs
            shiftSelectRight(count: lenIncl)  // selection length unchanged
            usleep(150_000)
            sendCmdShiftE()
            usleep(150_000)
            keyTap(KC_RETURN)
            usleep(120_000)
        }
    }

    private func applyLeadingIndent4SpacesToSkipMask(_ u16: [UInt16], skip: inout [Bool]) {
        // Treat “tabs” as groups of four spaces at the start of each line.
        // For each line, skip as many complete 4-space groups as appear at the start.
        // (Any leftover 1–3 spaces remain counted.)
        let n = u16.count
        let LF: UInt16 = 10
        let SP: UInt16 = 32

        // Gather line starts: index 0 and any char after an LF
        var lineStarts: [Int] = [0]
        for i in 0..<n where u16[i] == LF && i + 1 < n { lineStarts.append(i + 1) }

        for ls in lineStarts {
            var i = ls
            var spaces = 0
            while i < n, u16[i] == SP {
                spaces += 1
                i += 1
            }
            let groups = spaces / 4
            if groups > 0 {
                let end = ls + groups * 4
                var k = ls
                while k < end {
                    skip[k] = true
                    k += 1
                }
            }
        }
    }

    private func applyLeadingTabsToSkipMask(_ u16: [UInt16], skip: inout [Bool]) {
        // Skip TABs (U+0009) that appear at the start of a line (indentation).
        // This affects top-level and nested items alike and is applied BEFORE
        // empty-line detection so lines with only tabs get their LF skipped too.
        let n = u16.count
        let LF: UInt16 = 10
        let TAB: UInt16 = 9

        // Collect line starts (0 and any index after an LF)
        var lineStarts: [Int] = [0]
        for i in 0..<n where u16[i] == LF && i + 1 < n { lineStarts.append(i + 1) }

        for ls in lineStarts {
            var i = ls
            while i < n, u16[i] == TAB {
                skip[i] = true
                i += 1
            }
        }
    }

    // MARK: - Markdown emphasis helpers (bold + italics)
    private func skipMaskForBold(_ u16: [UInt16]) -> [Bool] {
        let n = u16.count
        var skip = [Bool](repeating: false, count: n)

        @inline(__always) func isAsterisk(_ i: Int) -> Bool { i >= 0 && i < n && u16[i] == 42 }  // '*'
        @inline(__always) func isBackslash(_ i: Int) -> Bool { i >= 0 && i < n && u16[i] == 92 }  // '\'
        @inline(__always) func isEscaped(_ i: Int) -> Bool {
            if i - 1 >= 0, isBackslash(i - 1) {
                if i - 2 >= 0, isBackslash(i - 2) { return false }  // '\\*' => not escaped
                return true
            }
            return false
        }

        var i = 0
        var stack: [Int] = []  // positions of '**' openers (index of the first star)
        while i < n - 1 {
            if isAsterisk(i), isAsterisk(i + 1), !isEscaped(i), !isEscaped(i + 1) {
                if let open = stack.popLast() {
                    // Close prior '**' pair: skip both opener and closer pairs
                    skip[open] = true
                    skip[open + 1] = true
                    skip[i] = true
                    skip[i + 1] = true
                } else {
                    // Open new '**'
                    stack.append(i)
                }
                i += 2
                continue
            }
            i += 1
        }
        // Unmatched '**' are ignored (not skipped)
        return skip
    }

    private func applyItalicsToSkipMask(_ u16: [UInt16], skip: inout [Bool]) {
        let n = u16.count
        @inline(__always) func isAsterisk(_ i: Int) -> Bool { i >= 0 && i < n && u16[i] == 42 }  // '*'
        @inline(__always) func isBackslash(_ i: Int) -> Bool { i >= 0 && i < n && u16[i] == 92 }  // '\'
        @inline(__always) func isEscaped(_ i: Int) -> Bool {
            if i - 1 >= 0, isBackslash(i - 1) {
                if i - 2 >= 0, isBackslash(i - 2) { return false }
                return true
            }
            return false
        }

        var i = 0
        var stack: [Int] = []  // positions of single '*' openers
        while i < n {
            if isAsterisk(i), !isEscaped(i) {
                // Treat as italics delimiter only if it is a SINGLE '*' (not adjacent to another '*')
                let leftIsStar = (i - 1 >= 0 && isAsterisk(i - 1) && !isEscaped(i - 1))
                let rightIsStar = (i + 1 < n && isAsterisk(i + 1) && !isEscaped(i + 1))
                if !(leftIsStar || rightIsStar) {
                    if let open = stack.popLast() {
                        skip[open] = true
                        skip[i] = true
                    } else {
                        stack.append(i)
                    }
                }
            }
            i += 1
        }
        // Unmatched '*' are ignored
    }

    // MARK: - Additional Markdown helpers (headings, divider, fences, bullets, numbered, empty lines)
    private func applyHeadingsToSkipMask(_ u16: [UInt16], skip: inout [Bool]) {
        // Skip leading heading markers '#', '##', '###' *and the single following space* at line start.
        let n = u16.count
        let LF: UInt16 = 10
        let SP: UInt16 = 32
        let HASH: UInt16 = 35

        // Precompute line starts
        var lineStarts: [Int] = [0]
        for i in 0..<n where u16[i] == LF && i + 1 < n { lineStarts.append(i + 1) }

        for ls in lineStarts {
            var i = ls
            // Up to three leading spaces are allowed before a heading in Markdown
            var consumedSpaces = 0
            while i < n && u16[i] == SP && consumedSpaces < 3 {
                i += 1
                consumedSpaces += 1
            }
            // Count leading #'s (1..3)
            var hashes = 0
            var j = i
            while j < n && u16[j] == HASH && hashes < 3 {
                hashes += 1
                j += 1
            }
            guard hashes > 0 else { continue }
            // Require at least one space after the hashes
            guard j < n, u16[j] == SP else { continue }
            // Skip the hashes and a single following space
            for k in i..<i + hashes { skip[k] = true }
            skip[j] = true
        }
    }

    private func applyDividerLineToSkipMask(_ u16: [UInt16], skip: inout [Bool]) {
        // Skip '---' when it is the ONLY non-space token on a line.
        let n = u16.count
        let LF: UInt16 = 10
        let SP: UInt16 = 32
        let DASH: UInt16 = 45

        var lineStarts: [Int] = [0]
        for i in 0..<n where u16[i] == LF && i + 1 < n { lineStarts.append(i + 1) }

        for ls in lineStarts {
            var i = ls
            // Allow any number of leading spaces
            while i < n && u16[i] == SP { i += 1 }
            // Need exactly '---' and then end of line or end of string
            guard i + 2 < n, u16[i] == DASH, u16[i + 1] == DASH, u16[i + 2] == DASH else {
                continue
            }
            var j = i + 3
            // Only spaces allowed after the dashes until EOL/EOF
            while j < n, u16[j] == SP { j += 1 }
            if j == n || u16[j] == LF {
                skip[i] = true
                skip[i + 1] = true
                skip[i + 2] = true
            }
        }
    }

    private func applyCodeFencesToSkipMask(_ u16: [UInt16], skip: inout [Bool]) {
        // Skip the three backticks at both fences, and skip the language token (if any)
        // immediately following the opening fence on the same line. Do NOT skip the
        // fenced contents.
        let n = u16.count
        let BT: UInt16 = 96  // backtick `
        let SP: UInt16 = 32
        let TAB: UInt16 = 9
        let LF: UInt16 = 10
        let CR: UInt16 = 13

        @inline(__always) func isFence(_ i: Int) -> Bool {
            i >= 0 && i + 2 < n && u16[i] == BT && u16[i + 1] == BT && u16[i + 2] == BT
        }

        var i = 0
        var inside = false

        while i < n {
            if isFence(i) {
                if inside {
                    // Closing fence: skip the three ticks
                    skip[i] = true
                    skip[i + 1] = true
                    skip[i + 2] = true
                    i += 3
                    inside = false
                    continue
                } else {
                    // Opening fence: skip the three ticks
                    skip[i] = true
                    skip[i + 1] = true
                    skip[i + 2] = true

                    // Skip the language token right after the opening fence (first non-whitespace run)
                    var j = i + 3
                    // Optional spaces/tabs before language token
                    while j < n && (u16[j] == SP || u16[j] == TAB) { j += 1 }
                    // Now skip the token itself (until whitespace or end-of-line)
                    while j < n && u16[j] != SP && u16[j] != TAB && u16[j] != LF && u16[j] != CR {
                        skip[j] = true
                        j += 1
                    }

                    i += 3
                    inside = true
                    continue
                }
            }
            i += 1
        }
        // If there's an unmatched opening fence, we only skipped its ticks and language token.
    }

    private func applyBulletsToSkipMask(_ u16: [UInt16], skip: inout [Bool]) {
        // Skip "- " at the start of a list item, including nested items (leading spaces or tabs allowed).
        let n = u16.count
        let LF: UInt16 = 10
        let SP: UInt16 = 32
        let TAB: UInt16 = 9
        let DASH: UInt16 = 45

        var lineStarts: [Int] = [0]
        for i in 0..<n where u16[i] == LF && i + 1 < n { lineStarts.append(i + 1) }

        for ls in lineStarts {
            var i = ls
            // Allow indentation (spaces or tabs)
            while i < n, u16[i] == SP || u16[i] == TAB { i += 1 }
            guard i + 1 < n, u16[i] == DASH, u16[i + 1] == SP else { continue }
            // Skip '-' and the following space
            skip[i] = true
            skip[i + 1] = true
        }
    }

    private func applyNumberedListToSkipMask(_ u16: [UInt16], skip: inout [Bool]) {
        // Skip "1. " / "10. " etc. at the start of list items (including nested, with leading spaces/tabs).
        let n = u16.count
        let LF: UInt16 = 10
        let SP: UInt16 = 32
        let TAB: UInt16 = 9
        let DOT: UInt16 = 46

        @inline(__always) func isDigit(_ i: Int) -> Bool {
            i >= 0 && i < n && u16[i] >= 48 && u16[i] <= 57
        }

        var lineStarts: [Int] = [0]
        for i in 0..<n where u16[i] == LF && i + 1 < n { lineStarts.append(i + 1) }

        for ls in lineStarts {
            var i = ls
            // Allow indentation (spaces or tabs)
            while i < n, u16[i] == SP || u16[i] == TAB { i += 1 }
            let first = i
            guard i < n, isDigit(i) else { continue }
            // Consume one or more digits
            var j = i
            while j < n, isDigit(j) { j += 1 }
            // Expect '.' then space
            guard j + 1 < n, u16[j] == DOT, u16[j + 1] == SP else { continue }
            // Skip from first digit through '.' and the following space
            for k in first...j { skip[k] = true }
            skip[j + 1] = true
        }
    }

    private func applyBlockquotesToSkipMask(_ u16: [UInt16], skip: inout [Bool]) {
        // Skip "> " at the start of lines.
        // If "> " is the only content on the line, skip the entire line including newline.
        let n = u16.count
        let LF: UInt16 = 10
        let SP: UInt16 = 32
        let TAB: UInt16 = 9
        let GT: UInt16 = 62  // '>'
        let CR: UInt16 = 13

        var lineStarts: [Int] = [0]
        for i in 0..<n where u16[i] == LF && i + 1 < n { lineStarts.append(i + 1) }

        for ls in lineStarts {
            var i = ls
            // Check for "> " at line start (no indentation allowed)
            guard i + 1 < n, u16[i] == GT, u16[i + 1] == SP else { continue }

            // Skip the "> " marker
            skip[i] = true
            skip[i + 1] = true

            // Check if the rest of the line is only whitespace
            var j = i + 2
            var onlyWhitespace = true
            while j < n, u16[j] != LF {
                if u16[j] != SP && u16[j] != TAB && u16[j] != CR {
                    onlyWhitespace = false
                    break
                }
                j += 1
            }

            // If line has only "> " + whitespace, skip the newline too
            if onlyWhitespace && j < n && u16[j] == LF {
                skip[j] = true
            }
        }
    }

    private func applyEmptyLineNewlinesToSkipMask(_ u16: [UInt16], skip: inout [Bool]) {
        // Skip the LF character of any line that is empty/whitespace-only AFTER other skips are applied.
        let n = u16.count
        let LF: UInt16 = 10
        let SP: UInt16 = 32
        let TAB: UInt16 = 9
        let CR: UInt16 = 13

        var lineStart = 0
        var i = 0
        while i <= n {
            if i == n || u16[i] == LF {
                // Examine [lineStart, i) for any NON-whitespace, NON-skipped code units
                var hasVisible = false
                var j = lineStart
                while j < i {
                    if !skip[j] {
                        let ch = u16[j]
                        if ch != SP && ch != TAB && ch != CR {
                            hasVisible = true
                            break
                        }
                    }
                    j += 1
                }
                if !hasVisible, i < n {
                    // Mark this newline as skipped
                    skip[i] = true
                }
                lineStart = i + 1
            }
            i += 1
        }
    }

    // MARK: - Clipboard snapshot/restore (clone items to avoid AppKit exception)
    private typealias PBItemSnapshot = [NSPasteboard.PasteboardType: Data]

    private func snapshotPasteboard() -> [PBItemSnapshot] {
        var snap: [PBItemSnapshot] = []
        DispatchQueue.main.sync {
            let pb = NSPasteboard.general
            guard let items = pb.pasteboardItems, !items.isEmpty else { return }
            for item in items {
                var dict: PBItemSnapshot = [:]
                for type in item.types {
                    if let data = item.data(forType: type) {
                        dict[type] = data
                    }
                }
                if !dict.isEmpty { snap.append(dict) }
            }
        }
        return snap
    }

    private func restorePasteboard(_ snapshot: [PBItemSnapshot]) {
        DispatchQueue.main.sync {
            let pb = NSPasteboard.general
            pb.clearContents()
            guard !snapshot.isEmpty else { return }
            let clones: [NSPasteboardItem] = snapshot.map { dict in
                let it = NSPasteboardItem()
                for (type, data) in dict {
                    _ = it.setData(data, forType: type)
                }
                return it
            }
            pb.writeObjects(clones)
        }
    }

    // MARK: - Clipboard helpers
    private func copyCurrentSelectionString() -> String? {
        // Take a safe snapshot (cloned data) of the current pasteboard
        let snap = snapshotPasteboard()

        // Ask app to copy current selection
        sendCmdC()
        usleep(160_000)

        // Read selection as plain string
        var selection: String?
        DispatchQueue.main.sync {
            selection = NSPasteboard.general.string(forType: .string)
        }

        // Restore prior clipboard contents using clones
        restorePasteboard(snap)

        return selection
    }

    // MARK: - Segment detection: $…$ / $$…$$ (inclusive)
    // Returns (start, length) in UTF-16 offsets so they align with arrow-key movement.
    // Skips escaped dollars: \$ and \$$ won’t open/close spans.
    func findDollarSegments(in s: String) -> [(Int, Int)] {
        let u16 = Array(s.utf16)
        let n = u16.count
        var i = 0
        var spans: [(Int, Int)] = []

        @inline(__always) func isDollar(_ idx: Int) -> Bool {
            return idx >= 0 && idx < n && u16[idx] == 36  // '$'
        }
        @inline(__always) func isBackslash(_ idx: Int) -> Bool {
            return idx >= 0 && idx < n && u16[idx] == 92  // '\'
        }
        @inline(__always) func isEscaped(_ idx: Int) -> Bool {
            // Dollar at idx is escaped if a single '\' immediately precedes it.
            // Treat '\\$' as NOT escaped (common for literal backslash then dollar).
            if idx - 1 >= 0, isBackslash(idx - 1) {
                // If there are two backslashes, consider it not escaped: \\$
                if idx - 2 >= 0, isBackslash(idx - 2) { return false }
                return true
            }
            return false
        }

        while i < n {
            if isDollar(i), !isEscaped(i) {
                if isDollar(i + 1), !isEscaped(i + 1) {
                    // $$…$$ (display)
                    let start = i
                    i += 2
                    var closed = false
                    while i + 1 < n {
                        if isDollar(i), isDollar(i + 1), !isEscaped(i) {
                            let end = i + 1
                            spans.append((start, end - start + 1))  // inclusive
                            i = end + 1
                            closed = true
                            break
                        }
                        i += 1
                    }
                    if !closed { i = start + 1 }  // unmatched open $$
                } else {
                    // $…$ (inline)
                    let start = i
                    i += 1
                    var closed = false
                    while i < n {
                        if isDollar(i), !isEscaped(i) {
                            // Don’t close on the first $ of a $$ pair
                            if !(isDollar(i + 1) && !isEscaped(i + 1)) {
                                let end = i
                                spans.append((start, end - start + 1))  // inclusive
                                i = end + 1
                                closed = true
                                break
                            }
                        }
                        i += 1
                    }
                    if !closed { i = start + 1 }  // unmatched open $
                }
            } else {
                i += 1
            }
        }
        return spans
    }

    // MARK: - Navigation & selection helpers
    private func moveRight(count: Int) {
        for _ in 0..<max(0, count) {
            keyTap(KC_RIGHT)
            usleep(moveRightDelay)
        }
    }

    private func shiftSelectRight(count: Int) {
        for _ in 0..<max(0, count) {
            pressWithModifiers(modKeys: [KC_SHIFT], flags: [.maskShift], key: KC_RIGHT)
            usleep(shiftSelectDelay)
        }
    }

    // MARK: - Shortcuts (send flags on the key event)
    private func tapWithFlags(_ key: CGKeyCode, flags: CGEventFlags) {
        keyDown(key, flags: flags)
        keyUp(key, flags: flags)
    }

    private func pressWithModifiers(modKeys: [CGKeyCode], flags: CGEventFlags, key: CGKeyCode) {
        for m in modKeys { keyDown(m) }
        usleep(1_000)
        tapWithFlags(key, flags: flags)
        usleep(1_000)
        for m in modKeys.reversed() { keyUp(m) }
    }

    private func sendCmdC() {
        pressWithModifiers(modKeys: [KC_CMD], flags: [.maskCommand], key: KC_C)
    }
    private func sendCmdShiftE() {
        pressWithModifiers(
            modKeys: [KC_CMD, KC_SHIFT], flags: [.maskCommand, .maskShift], key: KC_E)
    }

    // MARK: - Low-level key helpers
    private func keyTap(_ key: CGKeyCode, flags: CGEventFlags = []) {
        keyDown(key, flags: flags)
        keyUp(key, flags: flags)
    }
    private func keyDown(_ key: CGKeyCode, flags: CGEventFlags = []) {
        if let ev = CGEvent(keyboardEventSource: src, virtualKey: key, keyDown: true) {
            ev.flags = flags
            ev.post(tap: .cghidEventTap)
        }
    }
    private func keyUp(_ key: CGKeyCode, flags: CGEventFlags = []) {
        if let ev = CGEvent(keyboardEventSource: src, virtualKey: key, keyDown: false) {
            ev.flags = flags
            ev.post(tap: .cghidEventTap)
        }
    }
}
