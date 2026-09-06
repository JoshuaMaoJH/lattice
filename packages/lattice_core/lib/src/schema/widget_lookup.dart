import '../model/prefab.dart';
import '../model/project.dart';
import '../model/widget_unit.dart';
import '../types/lattice_type.dart';
import 'widget_schema.dart';
import 'widget_registry.dart';

/// Resolves a Hierarchy node's `type` against the built-in whitelist *and* the
/// project's own prefabs.
///
/// A prefab is a widget as far as everything downstream is concerned — it has
/// a schema, its parameters are pins, the Inspector edits them. That is the
/// point of R9: the boundary between "built in" and "mine" should not show.
final class WidgetLookup {
  WidgetLookup(this.project) {
    for (final prefab in project?.prefabs ?? const <Prefab>[]) {
      _prefabs[prefab.name] = schemaFor(prefab);
    }
  }

  /// A lookup with no project behind it — built-in widgets only.
  static final WidgetLookup builtinsOnly = WidgetLookup(null);

  final Project? project;
  final Map<String, WidgetSchema> _prefabs = {};

  /// Prefabs shadow nothing: a name that collides with a built-in widget is
  /// rejected by the validator, so this order is a formality.
  WidgetSchema? lookup(String type) =>
      WidgetRegistry.lookup(type) ?? _prefabs[type];

  bool isKnown(String type) => lookup(type) != null;

  bool isPrefab(String type) =>
      !WidgetRegistry.isKnown(type) && _prefabs.containsKey(type);

  /// What a prefab parameter *is*, read off its declared type (R9).
  ///
  /// No separate `kind` field in the JSON: `Widget` already means "a subtree
  /// goes here" and `Event` already means "the host hands me something to
  /// call". Adding a second place to say the same thing invites the two to
  /// disagree.
  static ParamKind kindOf(LatticeType type) => switch (type) {
        WidgetType() => ParamKind.widget,
        ListType(element: WidgetType()) => ParamKind.widgetList,
        EventType() => ParamKind.callback,
        NullableType(inner: WidgetType()) => ParamKind.widget,
        NullableType(inner: EventType()) => ParamKind.callback,
        _ => ParamKind.value,
      };

  /// The schema a prefab presents to the rest of the compiler.
  static WidgetSchema schemaFor(Prefab prefab) => WidgetSchema(
        type: prefab.name,
        category: WidgetCategory.structure,
        summary: 'Prefab ${prefab.id}.',
        // A prefab with no state of its own gets a const constructor, so
        // placing one costs nothing at run time.
        constCtor: !prefab.isStateful,
        params: [
          for (final parameter in prefab.parameters)
            ParamSchema(
              name: parameter.name,
              type: parameter.type,
              kind: kindOf(parameter.type),
              required: parameter.defaultValue == null &&
                  parameter.type is! NullableType &&
                  kindOf(parameter.type) != ParamKind.callback,
              defaultValue: parameter.defaultValue,
              // A slot takes a subtree and a callback takes an event edge;
              // neither is a value the graph can bind a signal to.
              bindable: kindOf(parameter.type) == ParamKind.value,
            ),
        ],
      );
}
