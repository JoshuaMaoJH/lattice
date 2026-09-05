import '../model/graph.dart';
import '../model/hierarchy.dart';
import '../model/graph_unit.dart';
import '../model/page.dart';
import '../model/server_function.dart';
import '../model/widget_unit.dart';
import '../model/pin_ref.dart';
import '../model/project.dart';
import '../types/lattice_type.dart';
import '../types/type_parser.dart';
// A deliberate import cycle: resolving a pin's type needs the registry, and
// the registry's schemas need this context. Dart resolves libraries lazily, so
// this is well defined.
import 'node_registry.dart';
import 'pin_schema.dart';
import 'widget_lookup.dart';
import 'widget_schema.dart';

enum NodeCategory {
  /// The only mutable state in the system.
  state,

  /// Pure functions of their inputs.
  compute,

  /// Bridges to the Hierarchy.
  ui,

  /// Sources of event edges.
  event,

  /// The only place side effects are allowed (§5, rule 2).
  action,

  /// Structural: ForEach, If, Switch.
  control,

  /// Hand-written Dart.
  escape,

  /// Comments, reroutes, subgraphs.
  organize,
}

/// Everything a pin resolver may need to look beyond the node itself.
final class NodeContext {
  NodeContext({required this.graph, this.unit, this.project});

  final Graph graph;

  /// The page, prefab or server function being compiled.
  final GraphUnit? unit;

  final Project? project;

  /// Resolves widget types against the whitelist *and* the project's prefabs.
  late final WidgetLookup widgets = WidgetLookup(project);

  /// Guards the `ForEach` -> `ForEachItem` -> `ForEach` loop that a nested
  /// repeat creates while types are being resolved.
  final Set<String> _resolving = {};

  /// The declared type of a `Signal` node, or `dynamic` if unknown.
  LatticeType signalType(String? signalNodeId) {
    if (signalNodeId == null) return PrimitiveType.dynamic_;
    final node = graph.node(signalNodeId);
    final spec = node?.get<String>('dartType');
    if (spec == null) return PrimitiveType.dynamic_;
    return TypeParser.tryParse(spec) ?? PrimitiveType.dynamic_;
  }

  /// The whitelisted schema behind a Hierarchy node id.
  WidgetSchema? widgetSchema(String? widgetId) {
    final owner = unit;
    if (widgetId == null || owner is! WidgetUnit) return null;
    for (final w in owner.hierarchy.descendantsAndSelf) {
      if (w.id == widgetId) return widgets.lookup(w.type);
    }
    return null;
  }

  /// The payload a widget callback hands over, e.g. `String` for
  /// `TextField.onChanged`.
  LatticeType eventPayload(String? widgetId, String? eventName) {
    if (eventName == null) return PrimitiveType.void_;
    final param = widgetSchema(widgetId)?.param(eventName);
    if (param == null || param.kind != ParamKind.callback) {
      return PrimitiveType.void_;
    }
    return param.type;
  }

  /// What the server function being compiled answers with, if that is what
  /// this is.
  LatticeType? get returnType =>
      unit is ServerFunction ? (unit! as ServerFunction).returns : null;

  ServerFunction? serverFunction(String? name) {
    if (name == null || project == null) return null;
    return project!.serverFunction(name);
  }

  /// The Hierarchy node with this id, searching nested widget props too.
  WidgetNode? widgetNode(String? widgetId) {
    final owner = unit;
    if (widgetId == null || owner is! WidgetUnit) return null;
    for (final widget in owner.hierarchy.descendantsAndSelf) {
      if (widget.id == widgetId) return widget;
    }
    return null;
  }

  /// The declared type of any output pin in this page's graph.
  LatticeType outputType(PinRef ref) {
    final node = graph.node(ref.nodeId);
    if (node == null) return PrimitiveType.dynamic_;
    final schema = NodeRegistry.lookup(node.type);
    return schema?.output(node, this, ref.pin)?.type ?? PrimitiveType.dynamic_;
  }

  /// The element type behind a `ForEach` widget's `items` binding — that is,
  /// the type of `item` inside its template.
  LatticeType forEachElementType(String? forEachWidgetId) {
    if (forEachWidgetId == null) return PrimitiveType.dynamic_;
    if (!_resolving.add(forEachWidgetId)) return PrimitiveType.dynamic_;
    try {
      final items = widgetNode(forEachWidgetId)?.props['items'];
      if (items is! BindProp) return PrimitiveType.dynamic_;
      final type = outputType(items.source);
      return switch (type) {
        ListType(:final element) => element,
        NullableType(inner: ListType(:final element)) => element,
        _ => PrimitiveType.dynamic_,
      };
    } finally {
      _resolving.remove(forEachWidgetId);
    }
  }

  /// The page a `Navigate` node targets.
  Page? pageForRoute(String? route) {
    if (route == null || project == null) return null;
    for (final candidate in project!.pages) {
      if (candidate.route == route) return candidate;
    }
    return null;
  }

  /// Resolves a type spelling in the context of this project's models.
  LatticeType resolve(String? spec,
      {LatticeType fallback = PrimitiveType.dynamic_}) {
    if (spec == null) return fallback;
    return TypeParser.tryParse(spec) ?? fallback;
  }
}

typedef PinResolver = List<PinSchema> Function(GraphNode node, NodeContext ctx);

/// The definition of a node kind (§7.2).
///
/// Pins are resolved per instance rather than declared statically because most
/// interesting nodes are generic over their configured type — a `Signal` is a
/// `Signal<int>` or a `Signal<List<Todo>>` depending on `dartType`.
final class NodeSchema {
  const NodeSchema({
    required this.type,
    required this.category,
    required this.inputsFor,
    required this.outputsFor,
    this.summary = '',
    this.configKeys = const [],
  });

  /// Convenience for nodes whose pins never vary.
  NodeSchema.fixed({
    required this.type,
    required this.category,
    List<PinSchema> inputs = const [],
    List<PinSchema> outputs = const [],
    this.summary = '',
    this.configKeys = const [],
  })  : inputsFor = _constant(inputs),
        outputsFor = _constant(outputs);

  static PinResolver _constant(List<PinSchema> pins) => (_, __) => pins;

  final String type;
  final NodeCategory category;
  final PinResolver inputsFor;
  final PinResolver outputsFor;
  final String summary;

  /// Config keys the Inspector should offer for this node.
  final List<String> configKeys;

  /// Actions are the only nodes allowed to write state or perform effects.
  bool get isAction => category == NodeCategory.action;

  /// Pure nodes must not appear downstream of an event edge.
  bool get isPure =>
      category == NodeCategory.compute || category == NodeCategory.state;

  List<PinSchema> inputs(GraphNode node, NodeContext ctx) =>
      inputsFor(node, ctx);

  List<PinSchema> outputs(GraphNode node, NodeContext ctx) =>
      outputsFor(node, ctx);

  PinSchema? input(GraphNode node, NodeContext ctx, String name) {
    for (final p in inputs(node, ctx)) {
      if (p.name == name) return p;
    }
    return null;
  }

  PinSchema? output(GraphNode node, NodeContext ctx, String name) {
    for (final p in outputs(node, ctx)) {
      if (p.name == name) return p;
    }
    return null;
  }

  @override
  String toString() => type;
}
