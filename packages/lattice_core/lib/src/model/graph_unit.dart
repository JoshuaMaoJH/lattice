import 'data_model.dart';
import 'graph.dart';
import 'page.dart';

/// Anything that owns a graph and a set of named parameters.
///
/// A [WidgetUnit] is one of these that also owns a widget tree; a
/// [ServerFunction] is one that does not. Splitting the two lets `Param`,
/// validation and expression lowering work the same either side of the
/// network boundary (§7.7).
abstract interface class GraphUnit {
  String get id;

  String get name;

  Graph get graph;

  /// Values the unit is given before it runs.
  List<FieldDef> get parameters;

  Map<String, CanvasPos> get layout;

  FieldDef? parameter(String name);
}
