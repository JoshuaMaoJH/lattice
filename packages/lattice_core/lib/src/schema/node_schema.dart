import '../model/graph.dart';
import '../model/page.dart';
import '../model/project.dart';
import '../types/lattice_type.dart';
import '../types/type_parser.dart';
import 'pin_schema.dart';
import 'widget_registry.dart';
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
  const NodeContext({required this.graph, this.page, this.project});

  final Graph graph;
  final Page? page;
  final Project? project;

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
    if (widgetId == null || page == null) return null;
    for (final w in page!.hierarchy.descendantsAndSelf) {
      if (w.id == widgetId) return WidgetRegistry.lookup(w.type);
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
