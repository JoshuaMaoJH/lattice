import '../model/custom_node.dart';
import '../model/graph.dart';
import '../model/project.dart';
import 'node_registry.dart';
import 'node_schema.dart';
import 'pin_schema.dart';

/// Resolves a graph node's `type` against the built-in library *and* the
/// project's own node definitions (R20).
///
/// The same shape as [WidgetLookup] and for the same reason: a project-defined
/// node is a node. It has a schema, its pins type-check, the Inspector lists
/// it, the validator judges it. Nothing downstream asks where it came from.
final class NodeLookup {
  NodeLookup(this.project) {
    for (final def in project?.customNodes ?? const <CustomNodeDef>[]) {
      _custom[def.type] = schemaFor(def);
      _defs[def.type] = def;
    }
  }

  /// A lookup with no project behind it — built-ins only.
  static final NodeLookup builtinsOnly = NodeLookup(null);

  final Project? project;
  final Map<String, NodeSchema> _custom = {};
  final Map<String, CustomNodeDef> _defs = {};

  /// Built-ins win. A definition that collides with one is reported by the
  /// validator rather than silently shadowing the compiler's own lowering.
  NodeSchema? lookup(String type) => NodeRegistry.lookup(type) ?? _custom[type];

  NodeSchema? forNode(GraphNode node) => lookup(node.type);

  bool isKnown(String type) => lookup(type) != null;

  bool isCustom(String type) =>
      !NodeRegistry.isKnown(type) && _custom.containsKey(type);

  CustomNodeDef? definition(String type) =>
      NodeRegistry.isKnown(type) ? null : _defs[type];

  /// Every node the palette should offer here.
  List<NodeSchema> get all => [...NodeRegistry.all, ..._custom.values];

  /// The schema a project-defined node presents to the rest of the compiler.
  static NodeSchema schemaFor(CustomNodeDef def) => NodeSchema.fixed(
        type: def.type,
        category: def.category,
        summary: def.summary,
        inputs: [
          if (def.isAction) const PinSchema.event('exec'),
          for (final pin in def.inputs)
            PinSchema(name: pin.name, type: pin.type, required: true),
        ],
        outputs: [
          if (def.isAction) const PinSchema.event('next', required: false),
          for (final pin in def.outputs)
            PinSchema(name: pin.name, type: pin.type),
        ],
      );
}
