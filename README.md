# RenderEq

**Website**: [https://SaveMyMinutes.github.io/RenderEq/](https://SaveMyMinutes.github.io/RenderEq/)

This macOS app instantly converts all your LaTeX/KaTeX equations (`$...$` and `$$...$$`) in Notion into rendered equations with a single keystroke.

## Why This Exists

If you're taking notes on math heavy subjects whether from LLM conversations, lectures, or research papers you know the pain: you paste content into Notion, ready to build your knowledge base, but then you're stuck manually selecting and converting dozens of equations, one by one. It's tedious, breaks your note taking flow, and honestly? Life's too short for that.

This app fixes it. Just press a hotkey (`Option + Shift + V`), and watch all your equations transform automatically.

## The Workflow

Here's the typical flow when working with LLMs:

1. **Get your markdown ready** - Most LLMs output math equations in KaTeX format wrapped in `$` or `$$` delimiters (Though you won't see this in the UI, this is how the text will be copied to your clipboard when you click the copy icon)
   - **Gemini**: The built in clipboard option copies clean markdown including the equations directly
   - **ChatGPT**: Grab my browser extension ([link here]) that adds a markdown clipboard option, since ChatGPT's native clipboard option doesn't copy the MATH equations in correct syntax.

2. **Paste into Notion** - Your content appears with raw equation code like `$E = mc^2$`

3. **Hit the magic button** - Arm the formatter, select your text, then press `Option + Shift + V`

4. **Done** - All your equations are now rendered beautifully, and you didn't have to manually convert each one

## Permissions

The app requires accessibility permissions on macOS to:
- Register global hotkeys
- Simulate keyboard events
- Read/write clipboard contents

macOS will prompt you to grant these permissions on first run.

## How to use the formatter?

1. **Press "Arm Formatter"** - Starts listening for the hotkey
2. **Select Your Text** - Manually select text containing equations in Notion
3. **Press `⌥ + ⇧ + V`** - The hotkey triggers automatic formatting
4. **Watch the Magic** - Each `$...$` or `$$...$$` gets converted to a visual equation

## Usage Tips

### DO:
- Select text manually using click & drag or `Shift + Arrow Keys`
- Keep your selection limited to consecutive Notion blocks that aren't seperated by new lines.

**Example of consecutive blocks (✓ Works):**

<img src="assets/readme/Consecutive Blocks.png" width="250">

**Example of non-consecutive blocks (✗ Won't work):**

<img src="assets/readme/Not Consecutive Blocks.png" width="250">

### DON'T:
- Don't use `Cmd + A + A` or select across multiple Notion blocks
- Cross-block selections won't work properly

## Features

- Works across all apps once armed (currently optimized for Notion)
- Snapshots and restores clipboard contents

## What happens behind the scenes?

The app intelligently:

- Detects inline equations (`$...$`) and display equations (`$$...$$`)
- Skips over Markdown formatting tokens like bold, italics, code fences, headings, lists, etc.
- Handles complex text selections with proper UTF-16 and grapheme cluster support
- Triggers Notion's equation formatter (`Cmd + Shift + E`) for each equation found
- Preserves your pre existing clipboard contents throughout the process


# Development

## Requirements

- macOS (uses native Swift plugin for keyboard events)
- Flutter SDK
- Notion app (currently the primary supported application)

## Setup

1. Clone the repository:
   ```bash
   git clone <repository-url>
   cd rendereq
   ```

2. Install dependencies:
   ```bash
   flutter pub get
   ```

3. Run the app:
   ```bash
   flutter run -d macos
   ```

## Technical Details

The app consists of:

- **Flutter UI** ([main.dart](lib/main.dart)) - Clean, modern interface with Material Design 3
- **Swift Plugin** ([EquationsHelperPlugin.swift](macos/Runner/EquationsHelperPlugin.swift)) - Native macOS integration for:
  - Global hotkey registration
  - Clipboard operations
  - Keyboard event simulation
  - Text parsing and navigation

## Architecture

```
rendereq/
├── lib/
│   └── main.dart              # Flutter UI
├── macos/
│   └── Runner/
│       └── EquationsHelperPlugin.swift  # Native hotkey & keyboard handling
└── README.md
```