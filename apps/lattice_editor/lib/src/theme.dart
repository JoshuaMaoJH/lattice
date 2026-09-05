import 'package:flutter/material.dart';
import 'package:lattice_core/lattice_core.dart';

/// The editor's visual rules, in one place.
///
/// One rule drives the whole thing: **colour means type**. The chrome is a
/// five-step neutral ramp and nothing else in it is saturated, so the only
/// coloured pixels on screen are pins, edges and the type badges that echo
/// them. In a data-flow editor that is not decoration — if colour is
/// overloaded, the graph stops being readable at a glance.
///
/// Diagnostics are the deliberate exception. They get red and amber precisely
/// because nothing else does.
class LatticeTheme {
  const LatticeTheme._();

  // ---- neutral ramp ---------------------------------------------------------
  // Desaturated indigo rather than grey: the canvas sits under it for hours.

  static const Color canvas = Color(0xFF0F121B);
  static const Color surface = Color(0xFF161A24);
  static const Color panel = Color(0xFF1C212D);
  static const Color raised = Color(0xFF242A38);
  static const Color hairline = Color(0xFF2E3546);
  static const Color hairlineBright = Color(0xFF3E4761);

  static const Color textPrimary = Color(0xFFDDE3F0);
  static const Color textSecondary = Color(0xFF8B93A8);
  static const Color textFaint = Color(0xFF5C647A);

  /// Selection is a lift plus a hairline, never a colour — see the note above.
  static const Color selectionFill = Color(0xFF2C3446);
  static const Color selectionEdge = Color(0xFF6B7794);

  // ---- the exception --------------------------------------------------------

  static const Color error = Color(0xFFE86A6A);
  static const Color warning = Color(0xFFE0A33C);

  // ---- type colours (§7.3) --------------------------------------------------

  static const Color _number = Color(0xFF6AA9F0);
  static const Color _text = Color(0xFFE3C766);
  static const Color _boolean = Color(0xFFE07A7A);
  static const Color _list = Color(0xFF74C98A);
  static const Color _model = Color(0xFFB08BE0);
  static const Color _widget = Color(0xFFE6EAF2);
  static const Color _event = Color(0xFFE39A55);
  static const Color _style = Color(0xFF7FD3C6);
  static const Color _special = Color(0xFF8B93A8);

  /// The colour that stands for a type family, straight from §7.3.
  static Color forFamily(TypeFamily family) => switch (family) {
        TypeFamily.number => _number,
        TypeFamily.text => _text,
        TypeFamily.boolean => _boolean,
        TypeFamily.list => _list,
        TypeFamily.map => _list,
        TypeFamily.model => _model,
        TypeFamily.widget => _widget,
        TypeFamily.event => _event,
        TypeFamily.style => _style,
        TypeFamily.special => _special,
      };

  static Color forType(LatticeType type) => forFamily(type.family);

  // ---- type ----------------------------------------------------------------
  // Sans for what the tool says; mono for anything that is a name in the
  // user's program. You can always tell the two apart.

  static const String monoFamily = 'monospace';

  static const TextStyle title = TextStyle(
    fontSize: 13,
    height: 1.2,
    fontWeight: FontWeight.w600,
    color: textPrimary,
    letterSpacing: 0.1,
  );

  static const TextStyle body = TextStyle(
    fontSize: 12.5,
    height: 1.35,
    color: textPrimary,
  );

  static const TextStyle secondary = TextStyle(
    fontSize: 12,
    height: 1.35,
    color: textSecondary,
  );

  /// Panel headers and column labels.
  static const TextStyle eyebrow = TextStyle(
    fontSize: 10.5,
    height: 1.2,
    fontWeight: FontWeight.w600,
    color: textFaint,
    letterSpacing: 0.9,
  );

  /// Anything that is an identifier in the user's program.
  static const TextStyle mono = TextStyle(
    fontFamily: monoFamily,
    fontSize: 12,
    height: 1.35,
    color: textPrimary,
  );

  static const TextStyle monoSmall = TextStyle(
    fontFamily: monoFamily,
    fontSize: 11,
    height: 1.3,
    color: textSecondary,
  );

  static const TextStyle code = TextStyle(
    fontFamily: monoFamily,
    fontSize: 12,
    height: 1.5,
    color: textPrimary,
  );

  // ---- metrics --------------------------------------------------------------

  static const double rowHeight = 24;
  static const double panelHeaderHeight = 28;
  static const double gutter = 10;

  /// The lattice the canvas is drawn on, and that nodes snap to.
  static const double gridStep = 16;
  static const int gridMajorEvery = 5;

  static ThemeData materialTheme() {
    const scheme = ColorScheme.dark(
      surface: surface,
      onSurface: textPrimary,
      primary: selectionEdge,
      onPrimary: canvas,
      secondary: raised,
      onSecondary: textPrimary,
      error: error,
      onError: canvas,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: canvas,
      splashFactory: NoSplash.splashFactory,
      textTheme: const TextTheme(bodyMedium: body, bodySmall: secondary),
      dividerTheme: const DividerThemeData(
        color: hairline,
        thickness: 1,
        space: 1,
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: raised,
          border: Border.all(color: hairlineBright),
          borderRadius: BorderRadius.circular(3),
        ),
        textStyle: secondary.copyWith(color: textPrimary),
        waitDuration: const Duration(milliseconds: 400),
      ),
      scrollbarTheme: ScrollbarThemeData(
        thickness: WidgetStateProperty.all(6),
        thumbColor: WidgetStateProperty.all(hairlineBright),
        radius: const Radius.circular(3),
      ),
    );
  }
}
