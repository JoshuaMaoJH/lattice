import 'dart:ui';

import 'package:lattice_core/lattice_core.dart';

/// One socket on a node, in the order it is drawn.
final class PinSlot {
  const PinSlot({
    required this.ref,
    required this.label,
    required this.type,
    required this.kind,
    required this.isInput,
    required this.required,
    this.isPlaceholder = false,
  });

  final PinRef ref;
  final String label;
  final LatticeType type;
  final PinKind kind;
  final bool isInput;
  final bool required;

  /// The spare socket a variadic pin always shows, so there is somewhere to
  /// drop the next argument.
  final bool isPlaceholder;
}

/// Where a node and its pins sit on the canvas.
///
/// Geometry is computed, never measured: pin positions have to be known while
/// an edge is being dragged, before any of it has been laid out. Keeping it
/// arithmetic also means the painter and the hit test cannot disagree.
class NodeLayout {
  const NodeLayout._();

  static const double width = 176;
  static const double headerHeight = 24;
  static const double rowHeight = 18;
  static const double padTop = 4;
  static const double padBottom = 8;
  static const double pinRadius = 4.5;

  /// The lattice nodes snap to.
  static const double grid = 16;

  static Offset snap(Offset position) => Offset(
        (position.dx / grid).roundToDouble() * grid,
        (position.dy / grid).roundToDouble() * grid,
      );

  static Offset positionOf(WidgetUnit unit, String nodeId) {
    final layout = unit.layout[nodeId];
    return layout == null ? Offset.zero : Offset(layout.x, layout.y);
  }

  /// Outputs first, then inputs — the reading order of a data-flow graph is
  /// "what comes out of here" before "what goes in".
  static List<PinSlot> slotsFor(
    GraphNode node,
    NodeContext context,
    Graph graph,
  ) {
    final schema = NodeRegistry.lookup(node.type);
    if (schema == null) return const [];

    final slots = <PinSlot>[];

    for (final pin in schema.outputs(node, context)) {
      slots.add(
        PinSlot(
          ref: PinRef(node.id, pin.name),
          label: pin.name,
          type: pin.type,
          kind: pin.kind,
          isInput: false,
          required: false,
        ),
      );
    }

    for (final pin in schema.inputs(node, context)) {
      if (!pin.variadic) {
        slots.add(
          PinSlot(
            ref: PinRef(node.id, pin.name),
            label: pin.name,
            type: pin.type,
            kind: pin.kind,
            isInput: true,
            required: pin.required,
          ),
        );
        continue;
      }

      // A variadic pin shows every connected index plus one free socket.
      var highest = -1;
      for (final edge in graph.edges) {
        if (edge.to.nodeId == node.id &&
            edge.to.pin == pin.name &&
            edge.to.index != null &&
            edge.to.index! > highest) {
          highest = edge.to.index!;
        }
      }
      for (var index = 0; index <= highest + 1; index++) {
        slots.add(
          PinSlot(
            ref: PinRef(node.id, pin.name, index: index),
            label: '${pin.name}[$index]',
            type: pin.type,
            kind: pin.kind,
            isInput: true,
            required: false,
            isPlaceholder: index > highest,
          ),
        );
      }
    }

    return slots;
  }

  static double heightFor(int slotCount) =>
      headerHeight + padTop + slotCount * rowHeight + padBottom;

  static Rect rectFor(
    WidgetUnit unit,
    GraphNode node,
    NodeContext context,
  ) {
    final position = positionOf(unit, node.id);
    final slots = slotsFor(node, context, unit.graph);
    return Rect.fromLTWH(
      position.dx,
      position.dy,
      width,
      heightFor(slots.length),
    );
  }

  /// The centre of one socket in canvas coordinates.
  static Offset pinCenter(Rect rect, int slotIndex, {required bool isInput}) =>
      Offset(
        isInput ? rect.left : rect.right,
        rect.top +
            headerHeight +
            padTop +
            slotIndex * rowHeight +
            rowHeight / 2,
      );

  /// A short glyph standing for the node's role. Shape, not colour — colour is
  /// reserved for types.
  static String glyphFor(NodeCategory? category) => switch (category) {
        NodeCategory.state => '◆',
        NodeCategory.compute => 'ƒ',
        NodeCategory.event => '▷',
        NodeCategory.action => '●',
        NodeCategory.control => '⌘',
        NodeCategory.escape => '{}',
        NodeCategory.ui => '□',
        _ => '·',
      };
}
