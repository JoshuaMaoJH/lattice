import 'package:collection/collection.dart';

import 'graph.dart';
import 'hierarchy.dart';
import 'json_utils.dart';

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
final class Page {
  Page({
    required this.id,
    required this.name,
    required this.hierarchy,
    String? route,
    Graph? graph,
    Map<String, CanvasPos>? layout,
    this.isHome = false,
  })  : route = route ?? '/${id.replaceFirst(RegExp('^page_'), '')}',
        graph = graph ?? Graph.empty,
        layout = Map.unmodifiable(layout ?? const {});

  final String id;
  final String name;
  final String route;
  final WidgetNode hierarchy;
  final Graph graph;
  final Map<String, CanvasPos> layout;

  /// The route the generated app opens on.
  final bool isHome;

  factory Page.fromJson(Map<String, Object?> json, {String path = 'page'}) {
    final id = json.str('id', path);
    final rawLayout = json.objOrNull('layout', path) ?? const {};
    return Page(
      id: id,
      name: json.strOr('name', _titleCase(id)),
      route: json['route'] as String?,
      isHome: json.boolOr('isHome', fallback: false),
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
        'hierarchy': hierarchy.toJson(),
        'graph': graph.toJson(),
        'layout': sortedKeys({
          for (final entry in layout.entries) entry.key: entry.value.toJson(),
        }),
      });

  /// The Dart class name for this page, e.g. `page_home` -> `HomePage`.
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
    bool? isHome,
  }) =>
      Page(
        id: id,
        name: name ?? this.name,
        route: route ?? this.route,
        hierarchy: hierarchy ?? this.hierarchy,
        graph: graph ?? this.graph,
        layout: layout ?? this.layout,
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
