import 'package:collection/collection.dart';

import 'json_utils.dart';
import 'pin_ref.dart';

/// One node on the canvas.
///
/// Everything beyond `id`/`type` lives in [config] and is interpreted by the
/// node's schema, so adding a node kind never means touching this class (R20).
final class GraphNode {
  GraphNode({
    required this.id,
    required this.type,
    Map<String, Object?>? config,
  }) : config = Map.unmodifiable(config ?? const {});

  final String id;
  final String type;
  final Map<String, Object?> config;

  factory GraphNode.fromJson(Map<String, Object?> json, String path) {
    final id = json.str('id', path);
    final type = json.str('type', path);
    final config = <String, Object?>{
      for (final entry in json.entries)
        if (entry.key != 'id' && entry.key != 'type') entry.key: entry.value,
    };
    return GraphNode(id: id, type: type, config: config);
  }

  Map<String, Object?> toJson() =>
      sortedKeys({'id': id, 'type': type, ...config});

  T? get<T>(String key) {
    final value = config[key];
    return value is T ? value : null;
  }

  @override
  String toString() => '$type#$id';

  @override
  bool operator ==(Object other) =>
      other is GraphNode &&
      other.id == id &&
      other.type == type &&
      const DeepCollectionEquality().equals(other.config, config);

  @override
  int get hashCode =>
      Object.hash(id, type, const DeepCollectionEquality().hash(config));
}

/// A directed connection between two pins.
final class Edge {
  const Edge(this.from, this.to);

  final PinRef from;
  final PinRef to;

  factory Edge.fromJson(Map<String, Object?> json, String path) => Edge(
        PinRef.parse(json.str('from', path), path: '$path.from'),
        PinRef.parse(json.str('to', path), path: '$path.to'),
      );

  Map<String, Object?> toJson() =>
      {'from': from.toString(), 'to': to.toString()};

  @override
  String toString() => '$from -> $to';

  @override
  bool operator ==(Object other) =>
      other is Edge && other.from == from && other.to == to;

  @override
  int get hashCode => Object.hash(from, to);
}

/// A page's node graph, plus the indices every consumer ends up wanting.
final class Graph {
  Graph({List<GraphNode>? nodes, List<Edge>? edges})
      : nodes = List.unmodifiable(nodes ?? const []),
        edges = List.unmodifiable(edges ?? const []) {
    for (final node in this.nodes) {
      _byId[node.id] = node;
    }
    for (final edge in this.edges) {
      _incoming.putIfAbsent(edge.to, () => []).add(edge);
      _outgoing.putIfAbsent(edge.from.base, () => []).add(edge);
    }
  }

  static final Graph empty = Graph();

  final List<GraphNode> nodes;
  final List<Edge> edges;

  final Map<String, GraphNode> _byId = {};
  final Map<PinRef, List<Edge>> _incoming = {};
  final Map<PinRef, List<Edge>> _outgoing = {};

  factory Graph.fromJson(Map<String, Object?> json, String path) {
    final rawNodes = json.arrOrEmpty('nodes', path);
    final rawEdges = json.arrOrEmpty('edges', path);
    return Graph(
      nodes: [
        for (var i = 0; i < rawNodes.length; i++)
          GraphNode.fromJson(
            asObj(rawNodes[i], '$path.nodes[$i]'),
            '$path.nodes[$i]',
          ),
      ],
      edges: [
        for (var i = 0; i < rawEdges.length; i++)
          Edge.fromJson(
            asObj(rawEdges[i], '$path.edges[$i]'),
            '$path.edges[$i]',
          ),
      ],
    );
  }

  Map<String, Object?> toJson() => pruneEmpty({
        'nodes': [for (final n in nodes) n.toJson()],
        'edges': [for (final e in edges) e.toJson()],
      });

  GraphNode? node(String id) => _byId[id];

  /// Edges arriving at [target]. A well-formed graph has at most one, but the
  /// validator needs to see duplicates in order to report them (§7.2).
  List<Edge> incoming(PinRef target) => _incoming[target] ?? const [];

  /// The single edge feeding [target], or null.
  Edge? source(PinRef target) {
    final list = incoming(target);
    return list.length == 1 ? list.single : null;
  }

  /// Edges leaving [source]; output pins may fan out freely.
  List<Edge> outgoing(PinRef source) => _outgoing[source.base] ?? const [];

  /// All edges leaving any pin of [nodeId].
  Iterable<Edge> outgoingFrom(String nodeId) =>
      edges.where((e) => e.from.nodeId == nodeId);

  Iterable<GraphNode> ofType(String type) => nodes.where((n) => n.type == type);

  @override
  bool operator ==(Object other) =>
      other is Graph &&
      const ListEquality<GraphNode>().equals(other.nodes, nodes) &&
      const ListEquality<Edge>().equals(other.edges, edges);

  @override
  int get hashCode => Object.hash(
        const ListEquality<GraphNode>().hash(nodes),
        const ListEquality<Edge>().hash(edges),
      );
}
