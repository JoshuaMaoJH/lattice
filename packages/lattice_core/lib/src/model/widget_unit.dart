import '../schema/widget_registry.dart';
import 'data_model.dart';
import 'graph.dart';
import 'hierarchy.dart';
import 'page.dart';

/// Something that compiles to one Flutter widget class: a [Page] or a
/// [Prefab].
///
/// The two differ only in how they are reached — a page by a route, a prefab
/// by being placed in another hierarchy. Everything downstream (validation,
/// lowering, emission) treats them identically, which is why the compiler has
/// one path rather than two.
abstract interface class WidgetUnit {
  String get id;

  /// Human-facing name.
  String get name;

  /// The generated Dart class, e.g. `HomePage` or `StatCard`.
  String get className;

  /// The generated file name, e.g. `home_page.dart`.
  String get fileName;

  /// Where the generated file goes, relative to `lib/`.
  String get directory;

  WidgetNode get hierarchy;

  Graph get graph;

  /// Values the unit must be constructed with.
  List<FieldDef> get parameters;

  Map<String, CanvasPos> get layout;

  FieldDef? parameter(String name);
}

extension WidgetUnitCompilation on WidgetUnit {
  /// Whether this unit compiles to a `StatefulWidget`.
  ///
  /// Decided structurally, before anything is lowered: `PageParam` reads a
  /// constructor field, which is `widget.x` from a State and plain `x` from a
  /// StatelessWidget, and a prefab's schema needs to know whether callers may
  /// write `const`.
  bool get isStateful {
    if (graph.ofType('Signal').isNotEmpty) return true;
    if (graph.ofType('Event').isNotEmpty) return true;
    return hierarchy.descendantsAndSelf.any((widget) {
      final schema = WidgetRegistry.lookup(widget.type);
      return schema?.params.any(
            (p) => p.controller != null && widget.props.containsKey(p.name),
          ) ??
          false;
    });
  }
}
