import 'package:collection/collection.dart';

import '../types/lattice_type.dart';
import '../types/type_parser.dart';
import 'data_model.dart';
import 'errors.dart';
import 'graph.dart';
import 'hierarchy.dart';
import 'json_utils.dart';
import 'page.dart';
import 'widget_unit.dart';

/// A reusable component: a subtree, its graph, and the parameters it exposes
/// (§5, R9).
///
/// Compiles to a custom widget class, so using one three times costs three
/// constructor calls rather than three copies of a subtree — which is the
/// whole point of lifting it out.
final class Prefab implements WidgetUnit {
  Prefab({
    required this.id,
    required this.name,
    required this.hierarchy,
    Graph? graph,
    List<FieldDef>? parameters,
    Map<String, CanvasPos>? layout,
  })  : graph = graph ?? Graph.empty,
        parameters = List.unmodifiable(parameters ?? const []),
        layout = Map.unmodifiable(layout ?? const {});

  @override
  final String id;

  /// The generated class name; also the type used in a Hierarchy.
  @override
  final String name;

  @override
  final WidgetNode hierarchy;

  @override
  final Graph graph;

  @override
  final List<FieldDef> parameters;

  @override
  final Map<String, CanvasPos> layout;

  factory Prefab.fromJson(Map<String, Object?> json, {String path = 'prefab'}) {
    final id = json.str('id', path);
    final rawParams = json.objOrNull('params', path) ?? const {};
    final defaults = json.objOrNull('paramDefaults', path) ?? const {};
    final rawLayout = json.objOrNull('layout', path) ?? const {};

    final parameters = <FieldDef>[];
    for (final entry in rawParams.entries) {
      final spec = entry.value;
      if (spec is! String) {
        throw ProjectFormatException(
          'parameter type must be a string',
          path: '$path.params.${entry.key}',
        );
      }
      final type = TypeParser.tryParse(spec);
      if (type == null) {
        throw ProjectFormatException(
          '"$spec" is not a valid type',
          path: '$path.params.${entry.key}',
        );
      }
      parameters.add(
        FieldDef(
          name: entry.key,
          type: type,
          defaultValue: defaults[entry.key],
        ),
      );
    }

    return Prefab(
      id: id,
      name: json.strOr('name', _defaultName(id)),
      parameters: parameters,
      hierarchy: WidgetNode.fromJson(
        json.obj('hierarchy', path),
        path: '$path.hierarchy',
      ),
      graph: Graph.fromJson(
        json.objOrNull('graph', path) ?? const {},
        '$path.graph',
      ),
      layout: {
        for (final entry in rawLayout.entries)
          entry.key: CanvasPos.fromJson(entry.value),
      },
    );
  }

  Map<String, Object?> toJson() => pruneEmpty({
        'id': id,
        'name': name,
        'params': {for (final p in parameters) p.name: p.type.spelling},
        'paramDefaults': {
          for (final p in parameters)
            if (p.defaultValue != null) p.name: p.defaultValue,
        },
        'hierarchy': hierarchy.toJson(),
        'graph': graph.toJson(),
        'layout': sortedKeys({
          for (final entry in layout.entries) entry.key: entry.value.toJson(),
        }),
      });

  @override
  String get className => name;

  @override
  String get fileName {
    final snake = name
        .replaceAllMapped(
          RegExp('([a-z0-9])([A-Z])'),
          (m) => '${m[1]}_${m[2]}',
        )
        .toLowerCase();
    return '$snake.dart';
  }

  @override
  String get directory => 'prefabs';

  @override
  FieldDef? parameter(String name) =>
      parameters.firstWhereOrNull((p) => p.name == name);

  /// Whether every parameter has a value without the caller supplying one.
  bool get parametersAreOptional =>
      parameters.every((p) => p.defaultValue != null || p.type is NullableType);

  static String _defaultName(String id) {
    final base = id.replaceFirst(RegExp('^prefab_'), '');
    return base
        .split(RegExp('[_-]'))
        .where((p) => p.isNotEmpty)
        .map((p) => p[0].toUpperCase() + p.substring(1))
        .join();
  }

  Prefab copyWith({
    String? name,
    WidgetNode? hierarchy,
    Graph? graph,
    List<FieldDef>? parameters,
    Map<String, CanvasPos>? layout,
  }) =>
      Prefab(
        id: id,
        name: name ?? this.name,
        hierarchy: hierarchy ?? this.hierarchy,
        graph: graph ?? this.graph,
        parameters: parameters ?? this.parameters,
        layout: layout ?? this.layout,
      );

  @override
  bool operator ==(Object other) =>
      other is Prefab &&
      other.id == id &&
      other.name == name &&
      other.hierarchy == hierarchy &&
      other.graph == graph &&
      const ListEquality<FieldDef>().equals(other.parameters, parameters);

  @override
  int get hashCode => Object.hash(id, name, hierarchy, graph);
}
