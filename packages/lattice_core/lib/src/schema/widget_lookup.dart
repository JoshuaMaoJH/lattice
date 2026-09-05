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

  /// The schema a prefab presents to the rest of the compiler.
  static WidgetSchema schemaFor(Prefab prefab) => WidgetSchema(
        type: prefab.name,
        category: WidgetCategory.structure,
        summary: 'Prefab ${prefab.id}.',
        // v1 prefabs take values, not children or callbacks; a prefab that
        // needs to call back out to its host is a separate design problem.
        // A prefab with no state of its own gets a const constructor, so
        // placing one costs nothing at run time.
        constCtor: !prefab.isStateful,
        params: [
          for (final parameter in prefab.parameters)
            ParamSchema(
              name: parameter.name,
              type: parameter.type,
              required: parameter.defaultValue == null &&
                  parameter.type is! NullableType,
              defaultValue: parameter.defaultValue,
            ),
        ],
      );
}
