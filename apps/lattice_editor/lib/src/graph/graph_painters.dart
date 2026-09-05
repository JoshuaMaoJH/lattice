import 'package:flutter/material.dart';

import '../theme.dart';
import 'node_layout.dart';

/// The lattice the canvas sits on.
///
/// Two tiers: a fine dot at every step, a brighter one every fifth. It is the
/// one place the editor lets itself be seen, and it does a job — nodes snap to
/// it, so alignment is something you can rely on rather than eyeball.
class LatticePainter extends CustomPainter {
  const LatticePainter({required this.scale});

  final double scale;

  @override
  void paint(Canvas canvas, Size size) {
    // Below a certain zoom the fine tier turns into noise, so it drops out.
    final showMinor = scale > 0.55;
    final minor = Paint()
      ..color = LatticeTheme.hairline.withValues(alpha: 0.55);
    final major = Paint()..color = LatticeTheme.hairlineBright;

    const step = NodeLayout.grid;
    const every = LatticeTheme.gridMajorEvery;

    for (var x = 0.0; x <= size.width; x += step) {
      final column = (x / step).round();
      for (var y = 0.0; y <= size.height; y += step) {
        final row = (y / step).round();
        final isMajor = column % every == 0 && row % every == 0;
        if (!isMajor && !showMinor) continue;
        canvas.drawCircle(
          Offset(x, y),
          isMajor ? 1.1 : 0.6,
          isMajor ? major : minor,
        );
      }
    }
  }

  @override
  bool shouldRepaint(LatticePainter oldDelegate) => oldDelegate.scale != scale;
}

/// One edge to draw.
final class EdgeGeometry {
  const EdgeGeometry({
    required this.from,
    required this.to,
    required this.color,
    required this.isEvent,
    this.isDimmed = false,
  });

  final Offset from;
  final Offset to;
  final Color color;
  final bool isEvent;
  final bool isDimmed;
}

/// Draws the connections.
///
/// Data edges curve; event edges are drawn with a dashed stroke so the two
/// kinds are distinguishable even to someone who cannot separate the orange
/// from the yellow (§7.2 makes them different in shape as well as colour).
class EdgePainter extends CustomPainter {
  const EdgePainter({required this.edges, this.pending});

  final List<EdgeGeometry> edges;

  /// The link currently being dragged out of a pin.
  final EdgeGeometry? pending;

  @override
  void paint(Canvas canvas, Size size) {
    for (final edge in edges) {
      _drawEdge(canvas, edge);
    }
    if (pending != null) _drawEdge(canvas, pending!, isPending: true);
  }

  void _drawEdge(Canvas canvas, EdgeGeometry edge, {bool isPending = false}) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = edge.isEvent ? 1.8 : 1.6
      ..strokeCap = StrokeCap.round
      ..color = edge.color.withValues(
        alpha: edge.isDimmed ? 0.15 : (isPending ? 0.9 : 0.75),
      );

    // The horizontal pull scales with the gap, so short hops stay tight and
    // long ones sweep — a constant control offset makes both look wrong.
    final span = (edge.to.dx - edge.from.dx).abs().clamp(40.0, 180.0);
    final path = Path()
      ..moveTo(edge.from.dx, edge.from.dy)
      ..cubicTo(
        edge.from.dx + span * 0.6,
        edge.from.dy,
        edge.to.dx - span * 0.6,
        edge.to.dy,
        edge.to.dx,
        edge.to.dy,
      );

    canvas.drawPath(edge.isEvent ? _dashed(path) : path, paint);
  }

  static Path _dashed(Path source) {
    const on = 6.0;
    const off = 4.0;
    final dashed = Path();
    for (final metric in source.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final end = (distance + on).clamp(0.0, metric.length);
        dashed.addPath(metric.extractPath(distance, end), Offset.zero);
        distance = end + off;
      }
    }
    return dashed;
  }

  @override
  bool shouldRepaint(EdgePainter oldDelegate) =>
      oldDelegate.edges != edges || oldDelegate.pending != pending;
}
