import 'dart:math' as math;

import 'package:flutter/material.dart';

/// The app's palette, in light and dark.
class ZenColors extends ThemeExtension<ZenColors> {
  const ZenColors({
    required this.bg,
    required this.surface,
    required this.ink,
    required this.muted,
    required this.line,
    required this.accent,
    required this.accentSoft,
    required this.accentInk,
  });

  final Color bg, surface, ink, muted, line, accent, accentSoft, accentInk;

  static const light = ZenColors(
    bg: Color(0xFFF4F1EA),
    surface: Color(0xFFFBF9F4),
    ink: Color(0xFF2B2D2A),
    muted: Color(0xFF7A7D74),
    line: Color(0xFFE2DDD1),
    accent: Color(0xFF6F8A6A),
    accentSoft: Color(0xFFDFE7DA),
    accentInk: Color(0xFFFBF9F4),
  );

  static const dark = ZenColors(
    bg: Color(0xFF14171A),
    surface: Color(0xFF1C2024),
    ink: Color(0xFFE8E6E1),
    muted: Color(0xFF8D928C),
    line: Color(0xFF2B3035),
    accent: Color(0xFF93AD8D),
    accentSoft: Color(0xFF263027),
    accentInk: Color(0xFF14171A),
  );

  static ZenColors of(BuildContext context) => Theme.of(context).extension<ZenColors>()!;

  @override
  ZenColors copyWith() => this;

  @override
  ZenColors lerp(ZenColors? other, double t) => t < 0.5 || other == null ? this : other;
}

ThemeData buildTheme(Brightness brightness) {
  final c = brightness == Brightness.dark ? ZenColors.dark : ZenColors.light;
  final scheme = ColorScheme.fromSeed(seedColor: c.accent, brightness: brightness).copyWith(
    primary: c.accent,
    onPrimary: c.accentInk,
    surface: c.bg,
    onSurface: c.ink,
    secondaryContainer: c.accentSoft,
    outline: c.line,
  );
  return ThemeData(
    colorScheme: scheme,
    scaffoldBackgroundColor: c.bg,
    extensions: [c],
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: c.bg,
      indicatorColor: c.accentSoft,
      surfaceTintColor: Colors.transparent,
      labelTextStyle: WidgetStatePropertyAll(TextStyle(fontSize: 12, color: c.muted)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: c.accent,
        foregroundColor: c.accentInk,
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
        textStyle: const TextStyle(fontSize: 16),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: c.accent,
        side: BorderSide(color: c.accent),
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
        textStyle: const TextStyle(fontSize: 16),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: c.ink,
      contentTextStyle: TextStyle(color: c.bg),
      behavior: SnackBarBehavior.floating,
      shape: const StadiumBorder(),
    ),
  );
}

/// Serif heading used at the top of each screen.
class ScreenHeader extends StatelessWidget {
  const ScreenHeader({super.key, required this.eyebrow, required this.title});

  final String eyebrow;
  final String title;

  @override
  Widget build(BuildContext context) {
    final c = ZenColors.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(eyebrow.toUpperCase(), style: TextStyle(fontSize: 13, letterSpacing: 1.1, color: c.muted)),
          const SizedBox(height: 4),
          Text(
            title,
            style: TextStyle(fontFamily: 'serif', fontSize: 30, height: 1.2, color: c.ink),
          ),
        ],
      ),
    );
  }
}

/// Rounded card with the app's surface color and hairline border.
class ZenCard extends StatelessWidget {
  const ZenCard({super.key, required this.child, this.padding = const EdgeInsets.all(16)});

  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final c = ZenColors.of(context);
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: c.surface,
        border: Border.all(color: c.line),
        borderRadius: BorderRadius.circular(18),
      ),
      child: child,
    );
  }
}

/// A row of pill-shaped single-choice chips.
class ChoiceChips<T> extends StatelessWidget {
  const ChoiceChips({
    super.key,
    required this.options,
    required this.selected,
    required this.onSelected,
    this.enabled = true,
  });

  final Map<T, String> options;
  final T selected;
  final ValueChanged<T> onSelected;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final c = ZenColors.of(context);
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final MapEntry(:key, :value) in options.entries)
          ChoiceChip(
            label: Text(value),
            selected: key == selected,
            showCheckmark: false,
            onSelected: enabled ? (_) => onSelected(key) : null,
            backgroundColor: c.surface,
            selectedColor: c.accentSoft,
            disabledColor: c.surface,
            labelStyle: TextStyle(color: c.ink.withValues(alpha: enabled ? 1 : 0.5)),
            side: BorderSide(color: key == selected ? c.accent : c.line),
            shape: const StadiumBorder(),
          ),
      ],
    );
  }
}

/// Checkbox row used for session options.
class ZenToggle extends StatelessWidget {
  const ZenToggle({super.key, required this.label, required this.value, required this.onChanged});

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = ZenColors.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 320),
        child: CheckboxListTile(
          value: value,
          onChanged: (v) => onChanged(v ?? false),
          title: Text(label, style: TextStyle(fontSize: 15, color: c.ink)),
          controlAffinity: ListTileControlAffinity.leading,
          activeColor: c.accent,
          dense: true,
          contentPadding: EdgeInsets.zero,
        ),
      ),
    );
  }
}

/// Circular progress ring, drawn clockwise from 12 o'clock.
class RingPainter extends CustomPainter {
  RingPainter({required this.progress, required this.track, required this.color});

  final double progress;
  final Color track;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 4.0;
    final rect = Offset.zero & size;
    final arcRect = rect.deflate(stroke);
    canvas.drawCircle(
      rect.center,
      arcRect.width / 2,
      Paint()
        ..color = track
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke,
    );
    canvas.drawArc(
      arcRect,
      -math.pi / 2,
      2 * math.pi * progress.clamp(0, 1),
      false,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(RingPainter old) => old.progress != progress || old.color != color || old.track != track;
}
