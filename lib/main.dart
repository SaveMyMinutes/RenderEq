import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

const _channel = MethodChannel('equations_helper');

void main() => runApp(const App());

// Custom color palette
class AppColors {
  // Primary/Accent
  static const primary = Color(0xFF6366F1);

  // Success/Armed
  static const success = Color(0xFF10B981);

  // Caution/Don't
  static const caution = Color(0xFFEF4444);

  // Light theme colors
  static const lightBackground = Color(0xFFFFFFFF);
  static const lightCardBackground = Color(0xFFF9FAFB);
  static const lightPrimaryText = Color(0xFF111827);
  static const lightSecondaryText = Color(0xFF6B7281);

  // Dark theme colors
  static const darkBackground = Color(0xFF111827);
  static const darkCardBackground = Color(0xFF1F2937);
  static const darkPrimaryText = Color(0xFFE5E7EB);
  static const darkSecondaryText = Color(0xFF9CA3AF);
}

class App extends StatelessWidget {
  const App({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'RenderEq',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppColors.primary,
          brightness: Brightness.light,
          primary: AppColors.primary,
          surface: AppColors.lightBackground,
        ),
        scaffoldBackgroundColor: AppColors.lightBackground,
        cardTheme: const CardThemeData(
          color: AppColors.lightCardBackground,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(12)),
          ),
        ),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppColors.primary,
          brightness: Brightness.dark,
          primary: AppColors.primary,
          surface: AppColors.darkBackground,
        ),
        scaffoldBackgroundColor: AppColors.darkBackground,
        cardTheme: const CardThemeData(
          color: AppColors.darkCardBackground,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(12)),
          ),
        ),
      ),
      themeMode: ThemeMode.system,
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage>
    with SingleTickerProviderStateMixin {
  bool _armed = false;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  // Default delay values (in milliseconds)
  static const double _defaultMoveRightDelay = 45.0;
  static const double _defaultShiftSelectDelay = 65.0;

  // Delay parameters (in milliseconds)
  double _moveRightDelay = _defaultMoveRightDelay;
  double _shiftSelectDelay = _defaultShiftSelectDelay;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _arm() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await _channel.invokeMethod('arm', {
        'moveRightDelay': (_moveRightDelay * 1000).toInt(), // convert to microseconds
        'shiftSelectDelay': (_shiftSelectDelay * 1000).toInt(), // convert to microseconds
      });
      if (!mounted) return;
      setState(() => _armed = true);
    } on PlatformException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Error: ${e.message}')));
    }
  }

  Future<void> _disarm() async {
    try {
      await _channel.invokeMethod('disarm');
      if (!mounted) return;
      setState(() => _armed = false);
    } catch (_) {}
  }

  void _resetDelays() {
    setState(() {
      _moveRightDelay = _defaultMoveRightDelay;
      _shiftSelectDelay = _defaultShiftSelectDelay;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final secondaryTextColor = isDark
        ? AppColors.darkSecondaryText
        : AppColors.lightSecondaryText;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          children: [
            Text(
              'Render Equations',
              style: TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 24,
                letterSpacing: 0.5,
                color: isDark ? Colors.white : Colors.black,
              ),
            ),
            const SizedBox(height: 4),
            GestureDetector(
              onTap: () async {
                final url = Uri.parse('https://SaveMyMinutes.github.io/RenderEq/');
                if (await canLaunchUrl(url)) {
                  await launchUrl(url);
                }
              },
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: Text(
                  'https://SaveMyMinutes.github.io/RenderEq/',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w400,
                    color: AppColors.primary,
                    letterSpacing: 0,
                    decoration: TextDecoration.underline,
                  ),
                ),
              ),
            ),
          ],
        ),
        centerTitle: true,
        elevation: 0,
        backgroundColor: Colors.transparent,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Status Card
            _buildStatusCard(theme, isDark),
            const SizedBox(height: 24),
            // Settings Card
            _buildSettingsCard(theme, isDark, secondaryTextColor),
            const SizedBox(height: 24),
            // Instructions Card
            _buildInstructionsCard(theme, secondaryTextColor),
            const SizedBox(height: 24),
            // How-To Card
            _buildHowToCard(theme, secondaryTextColor),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusCard(ThemeData theme, bool isDark) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            if (!_armed) ...[
              // Disarmed State
              Icon(Icons.bolt, size: 64, color: theme.colorScheme.primary),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _arm,
                icon: const Icon(Icons.bolt),
                label: const Text('Arm Formatter (⌥⇧V)'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 32,
                    vertical: 16,
                  ),
                  textStyle: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Click to start listening for the hotkey.',
                style: TextStyle(
                  color: isDark
                      ? AppColors.darkSecondaryText
                      : AppColors.lightSecondaryText,
                  fontSize: 14,
                ),
              ),
            ] else ...[
              // Armed State
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  FadeTransition(
                    opacity: _pulseAnimation,
                    child: Container(
                      width: 12,
                      height: 12,
                      decoration: const BoxDecoration(
                        color: AppColors.success,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.success.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: AppColors.success, width: 2),
                    ),
                    child: const Text(
                      'ARMED',
                      style: TextStyle(
                        color: AppColors.success,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.5,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              OutlinedButton.icon(
                onPressed: _disarm,
                icon: const Icon(Icons.cancel),
                label: const Text('Disarm'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSettingsCard(
      ThemeData theme, bool isDark, Color secondaryTextColor) {
    final primaryTextColor = isDark
        ? AppColors.darkPrimaryText
        : AppColors.lightPrimaryText;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.settings, color: AppColors.primary, size: 24),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Timing Settings',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                TextButton.icon(
                  onPressed: _resetDelays,
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('Reset'),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.primary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Adjust delays if formatting is too fast or too slow for your system',
              style: TextStyle(color: secondaryTextColor, fontSize: 13),
            ),
            const SizedBox(height: 24),
            // Move Right Delay
            Text(
              'Move Right Delay: ${_moveRightDelay.toInt()}ms',
              style: TextStyle(
                color: primaryTextColor,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Text('20ms',
                    style: TextStyle(color: secondaryTextColor, fontSize: 12)),
                Expanded(
                  child: Slider(
                    value: _moveRightDelay,
                    min: 20,
                    max: 150,
                    divisions: 130,
                    label: '${_moveRightDelay.toInt()}ms',
                    onChanged: (value) {
                      setState(() => _moveRightDelay = value);
                    },
                  ),
                ),
                Text('150ms',
                    style: TextStyle(color: secondaryTextColor, fontSize: 12)),
              ],
            ),
            const SizedBox(height: 20),
            // Shift Select Delay
            Text(
              'Shift Select Delay: ${_shiftSelectDelay.toInt()}ms',
              style: TextStyle(
                color: primaryTextColor,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Text('30ms',
                    style: TextStyle(color: secondaryTextColor, fontSize: 12)),
                Expanded(
                  child: Slider(
                    value: _shiftSelectDelay,
                    min: 30,
                    max: 200,
                    divisions: 170,
                    label: '${_shiftSelectDelay.toInt()}ms',
                    onChanged: (value) {
                      setState(() => _shiftSelectDelay = value);
                    },
                  ),
                ),
                Text('200ms',
                    style: TextStyle(color: secondaryTextColor, fontSize: 12)),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: AppColors.primary.withValues(alpha: 0.3),
                  width: 1,
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.info_outline,
                    color: AppColors.primary,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Changes take effect when you arm the formatter',
                      style: TextStyle(
                        color: secondaryTextColor,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInstructionsCard(ThemeData theme, Color secondaryTextColor) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'How It Works',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: AppColors.primary.withValues(alpha: 0.3),
                  width: 1,
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.info_outline,
                    color: AppColors.primary,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Currently works only with the Notion app',
                      style: TextStyle(
                        color: secondaryTextColor,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            _buildInstructionStep(
              theme,
              secondaryTextColor,
              1,
              'Press Arm Formatter',
              'Click the button above to start listening',
              Icons.bolt,
              AppColors.primary,
            ),
            const SizedBox(height: 16),
            _buildInstructionStep(
              theme,
              secondaryTextColor,
              2,
              'Select the Text',
              'Manually select your equation text in any app',
              Icons.text_fields,
              AppColors.primary,
            ),
            const SizedBox(height: 16),
            _buildInstructionStep(
              theme,
              secondaryTextColor,
              3,
              'Press the Hotkey',
              'Press ⌥ + ⇧ + V (Option + Shift + V)',
              Icons.keyboard,
              AppColors.primary,
            ),
            const SizedBox(height: 16),
            _buildInstructionStep(
              theme,
              secondaryTextColor,
              4,
              'Turn your Equations in Code into Visual Equations',
              'Watch as your \$…\$ and \$\$…\$\$ are formatted automatically',
              Icons.auto_fix_high,
              AppColors.success,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInstructionStep(
    ThemeData theme,
    Color secondaryTextColor,
    int stepNumber,
    String title,
    String description,
    IconData icon,
    Color iconColor,
  ) {
    final isDark = theme.brightness == Brightness.dark;
    final primaryTextColor = isDark
        ? AppColors.darkPrimaryText
        : AppColors.lightPrimaryText;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: iconColor.withValues(alpha: 0.15),
            shape: BoxShape.circle,
            border: Border.all(
              color: iconColor.withValues(alpha: 0.4),
              width: 2,
            ),
          ),
          child: Center(
            child: Text(
              '$stepNumber',
              style: TextStyle(
                color: iconColor,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, size: 20, color: iconColor),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      title,
                      style: TextStyle(
                        color: primaryTextColor,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                description,
                style: TextStyle(color: secondaryTextColor, fontSize: 14),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildHowToCard(ThemeData theme, Color secondaryTextColor) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'How to Select Text',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 20),
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // DO Column
                  Expanded(child: _buildDoColumn(theme, secondaryTextColor)),
                  const SizedBox(width: 16),
                  // DON'T Column
                  Expanded(child: _buildDontColumn(theme, secondaryTextColor)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDontColumn(ThemeData theme, Color secondaryTextColor) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.caution.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: AppColors.caution.withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.cancel_outlined, color: AppColors.caution, size: 48),
          const SizedBox(height: 12),
          const Text(
            "DON'T Select Across Blocks",
            style: TextStyle(
              color: AppColors.caution,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: AppColors.caution.withValues(alpha: 0.3),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildKey('⌘'),
                const Text(' + ', style: TextStyle(color: Colors.black54)),
                _buildKey('A'),
                const Text(' + ', style: TextStyle(color: Colors.black54)),
                _buildKey('A'),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Text(
            "Selection across different blocks in Notion will not work.",
            style: TextStyle(color: secondaryTextColor, fontSize: 12),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildDoColumn(ThemeData theme, Color secondaryTextColor) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.success.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: AppColors.success.withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.check_circle_outline,
            color: AppColors.success,
            size: 48,
          ),
          const SizedBox(height: 12),
          const Text(
            'DO Select Manually',
            style: TextStyle(
              color: AppColors.success,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: AppColors.success.withValues(alpha: 0.3),
              ),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.mouse, size: 20, color: Colors.black54),
                    const SizedBox(width: 4),
                    const Text(
                      'Click & Drag',
                      style: TextStyle(
                        color: Colors.black87,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                const Text(
                  'or',
                  style: TextStyle(color: Colors.black54, fontSize: 10),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _buildKey('⇧'),
                    const Text(' + ', style: TextStyle(color: Colors.black54)),
                    _buildKey('←'),
                    const Text(' / ', style: TextStyle(color: Colors.black54)),
                    _buildKey('→'),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Click and drag, or use Shift + Arrow Keys to make your selection.',
            style: TextStyle(color: secondaryTextColor, fontSize: 12),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildKey(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.grey[200],
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Colors.grey[400]!),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            offset: const Offset(0, 2),
            blurRadius: 2,
          ),
        ],
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.black87,
          fontSize: 14,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
