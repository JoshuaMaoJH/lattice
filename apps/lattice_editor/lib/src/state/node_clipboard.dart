import 'package:lattice_core/lattice_core.dart';

import 'ids.dart';

/// A copied piece of graph, ready to be pasted somewhere.
///
/// Holds the nodes, the edges *between* them, and their relative positions.
/// Edges that leave the selection are dropped on purpose: pasting a copy that
/// silently reconnects itself to the original's neighbours is a surprise, and
/// there is no second place for those wires to land.
final class NodeClipboard {
  const NodeClipboard(this.nodes, this.edges, this.offsets);

  final List<GraphNode> nodes;
  final List<Edge> edges;

  /// Positions relative to the top-left of the copied set, so a paste lands
  /// where the user is looking rather than back on the original.
  final Map<String, CanvasPos> offsets;

  bool get isEmpty => nodes.isEmpty;

  /// Everything in [unit] whose id is in [ids].
  static NodeClipboard copyFrom(GraphUnit unit, Set<String> ids) {
    final nodes = [
      for (final node in unit.graph.nodes)
        if (ids.contains(node.id)) node,
    ];
    if (nodes.isEmpty) return const NodeClipboard([], [], {});

    final edges = [
      for (final edge in unit.graph.edges)
        if (ids.contains(edge.from.nodeId) && ids.contains(edge.to.nodeId))
          edge,
    ];

    final positions = {
      for (final node in nodes)
        if (unit.layout[node.id] != null) node.id: unit.layout[node.id]!,
    };
    final left = positions.values
        .map((p) => p.x)
        .fold<double>(double.infinity, (a, b) => a < b ? a : b);
    final top = positions.values
        .map((p) => p.y)
        .fold<double>(double.infinity, (a, b) => a < b ? a : b);

    return NodeClipboard(
      nodes,
      edges,
      {
        for (final entry in positions.entries)
          entry.key: CanvasPos(entry.value.x - left, entry.value.y - top),
      },
    );
  }

  /// A fresh copy with new ids, placed at [at].
  ///
  /// Config values that name another copied node — `Subgraph.members`, an
  /// action's `signal` — are rewritten to the new ids. A pasted action that
  /// still wrote to the original's signal would be the kind of bug that only
  /// shows up when someone edits the copy.
  ({List<GraphNode> nodes, List<Edge> edges, Map<String, CanvasPos> layout})
      paste(GraphUnit unit, CanvasPos at) {
    final taken = {for (final node in unit.graph.nodes) node.id};
    final renamed = <String, String>{};
    for (final node in nodes) {
      final fresh = Ids.unique(_prefixOf(node.id), taken);
      taken.add(fresh);
      renamed[node.id] = fresh;
    }

    String rewrite(String id) => renamed[id] ?? id;

    Object? rewriteValue(Object? value) => switch (value) {
          final String text when renamed.containsKey(text) => renamed[text],
          final List<Object?> list => [for (final v in list) rewriteValue(v)],
          _ => value,
        };

    return (
      nodes: [
        for (final node in nodes)
          GraphNode(
            id: renamed[node.id]!,
            type: node.type,
            config: {
              for (final entry in node.config.entries)
                entry.key: rewriteValue(entry.value),
            },
          ),
      ],
      edges: [
        for (final edge in edges)
          Edge(
            PinRef(rewrite(edge.from.nodeId), edge.from.pin,
                index: edge.from.index),
            PinRef(rewrite(edge.to.nodeId), edge.to.pin, index: edge.to.index),
          ),
      ],
      layout: {
        for (final entry in offsets.entries)
          renamed[entry.key]!:
              CanvasPos(at.x + entry.value.x, at.y + entry.value.y),
      },
    );
  }

  /// `n_count_2` copies as another `n_count`, not as `n_count_2_2`.
  static String _prefixOf(String id) => id.replaceFirst(RegExp(r'_\d+$'), '');
}
