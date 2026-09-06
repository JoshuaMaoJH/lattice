import 'package:collection/collection.dart';

import '../types/lattice_type.dart';
import '../types/type_parser.dart';
import 'data_model.dart';
import 'errors.dart';
import 'graph.dart';
import 'hierarchy.dart';
import 'json_utils.dart';
import 'widget_unit.dart';

/// A node's position on the canvas.
///
/// Stored apart from the semantic model so that moving a node produces no
/// diff in the parts of the file that matter (ADR-005).
final class CanvasPos {
  const CanvasPos(this.x, this.y);

  final double x;
  final double y;

  factory CanvasPos.fromJson(Object? json) {
    if (json is List && json.length == 2) {
      final x = json[0];
      final y = json[1];
      if (x is num && y is num) return CanvasPos(x.toDouble(), y.toDouble());
    }
    return const CanvasPos(0, 0);
  }

  List<double> toJson() => [x, y];

  @override
  String toString() => '($x, $y)';

  @override
  bool operator ==(Object other) =>
      other is CanvasPos && other.x == x && other.y == y;

  @override
  int get hashCode => Object.hash(x, y);
}

/// One route: a widget tree plus the graph that drives it (§5).
final class Page implements WidgetUnit {
  Page({
    required this.id,
    required this.name,
    required this.hierarchy,
    String? route,
    Graph? graph,
    Map<String, CanvasPos>? layout,
    List<FieldDef>? parameters,
    this.isHome = false,
  })  : route = route ?? '/${id.replaceFirst(RegExp('^page_'), '')}',
        graph = graph ?? Graph.empty,
        layout = Map.unmodifiable(layout ?? const {}),
        parameters = List.unmodifiable(parameters ?? const []);

  @override
  final String id;

  @override
  final String name;

  final String route;

  @override
  final WidgetNode hierarchy;

  @override
  final Graph graph;

  @override
  final Map<String, CanvasPos> layout;

  /// The route the generated app opens on.
  final bool isHome;

  /// Values this page must be given to be shown at all — the compiled form of
  /// "两页互跳，传参" (R12). They become constructor parameters, and the route
  /// table unpacks them from `settings.arguments`.
  @override
  final List<FieldDef> parameters;

  @override
  FieldDef? parameter(String name) =>
      parameters.where((p) => p.name == name).firstOrNull;

  /// Whether the page can be opened without arguments — a requirement for the
  /// app's initial route.
  bool get isDirectlyReachable =>
      parameters.every((p) => p.defaultValue != null || p.type is NullableType);

  factory Page.fromJson(Map<String, Object?> json, {String path = 'page'}) {
    final id = json.str('id', path);
    final rawLayout = json.objOrNull('layout', path) ?? const {};
    final rawParams = json.objOrNull('params', path) ?? const {};
    final defaults = json.objOrNull('paramDefaults', path) ?? const {};

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

    return Page(
      id: id,
      name: json.strOr('name', _titleCase(id)),
      route: json['route'] as String?,
      isHome: json.boolOr('isHome', fallback: false),
      parameters: parameters,
      hierarchy: WidgetNode.fromJson(
        json.obj('hierarchy', path),
        path: '$path.hierarchy',
      ),
      graph: Graph.fromJson(
          json.objOrNull('graph', path) ?? const {}, '$path.graph'),
      layout: {
        for (final entry in rawLayout.entries)
          entry.key: CanvasPos.fromJson(entry.value),
      },
    );
  }

  Map<String, Object?> toJson() => pruneEmpty({
        'id': id,
        'name': name,
        'route': route,
        if (isHome) 'isHome': true,
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
  String get directory => 'pages';

  /// The Dart class name for this page, e.g. `page_home` -> `HomePage`.
  @override
  String get className {
    final base = id.replaceFirst(RegExp('^page_'), '');
    final camel = base
        .split(RegExp('[_-]'))
        .where((p) => p.isNotEmpty)
        .map((p) => p[0].toUpperCase() + p.substring(1))
        .join();
    return camel.endsWith('Page') ? camel : '${camel}Page';
  }

  /// The generated file name, e.g. `home_page.dart`.
  @override
  String get fileName {
    final snake = className
        .replaceAllMapped(
          RegExp('([a-z0-9])([A-Z])'),
          (m) => '${m[1]}_${m[2]}',
        )
        .toLowerCase();
    return '$snake.dart';
  }

  static String _titleCase(String id) {
    final base = id.replaceFirst(RegExp('^page_'), '');
    return base
        .split(RegExp('[_-]'))
        .where((p) => p.isNotEmpty)
        .map((p) => p[0].toUpperCase() + p.substring(1))
        .join(' ');
  }

  Page copyWith({
    String? name,
    String? route,
    WidgetNode? hierarchy,
    Graph? graph,
    Map<String, CanvasPos>? layout,
    List<FieldDef>? parameters,
    bool? isHome,
  }) =>
      Page(
        id: id,
        name: name ?? this.name,
        route: route ?? this.route,
        hierarchy: hierarchy ?? this.hierarchy,
        graph: graph ?? this.graph,
        layout: layout ?? this.layout,
        parameters: parameters ?? this.parameters,
        isHome: isHome ?? this.isHome,
      );

  @override
  bool operator ==(Object other) =>
      other is Page &&
      other.id == id &&
      other.name == name &&
      other.route == route &&
      other.isHome == isHome &&
      other.hierarchy == hierarchy &&
      other.graph == graph &&
      const MapEquality<String, CanvasPos>().equals(other.layout, layout);

  @override
  int get hashCode => Object.hash(id, name, route, isHome, hierarchy, graph);
}
