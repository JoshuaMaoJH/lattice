import 'package:flutter/material.dart';
import 'package:lattice_core/lattice_core.dart';

import '../theme.dart';

/// A titled region of the editor. Every panel wears the same chrome so the
/// eye can tell structure from content without any of it being loud.
class Panel extends StatelessWidget {
  const Panel({
    super.key,
    required this.title,
    required this.child,
    this.actions = const [],
    this.badge,
  });

  final String title;
  final Widget child;
  final List<Widget> actions;

  /// A small count shown after the title, e.g. the number of problems.
  final Widget? badge;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: LatticeTheme.panel,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: LatticeTheme.panelHeaderHeight,
            padding: const EdgeInsets.only(left: LatticeTheme.gutter, right: 4),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: LatticeTheme.hairline)),
            ),
            child: Row(
              children: [
                Text(title.toUpperCase(), style: LatticeTheme.eyebrow),
                if (badge != null) ...[const SizedBox(width: 6), badge!],
                const Spacer(),
                ...actions,
              ],
            ),
          ),
          Expanded(child: child),
        ],
      ),
    );
  }
}

/// A compact square icon button, sized for a dense tool.
class ToolButton extends StatelessWidget {
  const ToolButton({
    super.key,
    required this.icon,
    required this.tooltip,
    this.onPressed,
    this.isActive = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool isActive;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onPressed,
        child: Container(
          width: 24,
          height: 24,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isActive ? LatticeTheme.selectionFill : null,
            borderRadius: BorderRadius.circular(3),
          ),
          child: Icon(
            icon,
            size: 15,
            color: enabled
                ? (isActive
                    ? LatticeTheme.textPrimary
                    : LatticeTheme.textSecondary)
                : LatticeTheme.textFaint,
          ),
        ),
      ),
    );
  }
}

/// The dot that stands for a type. Same shape and colour wherever a type
/// appears — on a pin, next to a bound parameter, in a picker — so a binding
/// is legible across panels without reading a word.
class TypeDot extends StatelessWidget {
  const TypeDot(this.type, {super.key, this.size = 8, this.hollow = false});

  final LatticeType type;
  final double size;

  /// Event pins are hollow; data pins are solid (§7.2).
  final bool hollow;

  @override
  Widget build(BuildContext context) {
    final color = LatticeTheme.forType(type);
    return Tooltip(
      message: type.dartName,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: hollow ? null : color,
          border: hollow ? Border.all(color: color, width: 1.5) : null,
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}

/// A one-pixel rule. Used instead of gaps to separate dense rows.
class Hairline extends StatelessWidget {
  const Hairline({super.key, this.axis = Axis.horizontal});

  final Axis axis;

  @override
  Widget build(BuildContext context) => axis == Axis.horizontal
      ? const SizedBox(
          height: 1, child: ColoredBox(color: LatticeTheme.hairline))
      : const SizedBox(
          width: 1, child: ColoredBox(color: LatticeTheme.hairline));
}

/// A draggable divider between two panels.
class SplitHandle extends StatelessWidget {
  const SplitHandle({super.key, required this.axis, required this.onDrag});

  final Axis axis;
  final void Function(double delta) onDrag;

  @override
  Widget build(BuildContext context) {
    final horizontal = axis == Axis.horizontal;
    return MouseRegion(
      cursor: horizontal
          ? SystemMouseCursors.resizeColumn
          : SystemMouseCursors.resizeRow,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onHorizontalDragUpdate: horizontal ? (d) => onDrag(d.delta.dx) : null,
        onVerticalDragUpdate: horizontal ? null : (d) => onDrag(d.delta.dy),
        child: SizedBox(
          width: horizontal ? 5 : null,
          height: horizontal ? null : 5,
          child: Center(
              child:
                  Hairline(axis: horizontal ? Axis.vertical : Axis.horizontal)),
        ),
      ),
    );
  }
}

/// A count badge, e.g. "3" next to PROBLEMS.
class CountBadge extends StatelessWidget {
  const CountBadge(this.count, {super.key, required this.color});

  final int count;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          '$count',
          style: LatticeTheme.monoSmall.copyWith(color: color, fontSize: 10),
        ),
      );
}
