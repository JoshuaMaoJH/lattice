import 'package:collection/collection.dart';

import '../types/lattice_type.dart';
import '../types/type_parser.dart';
import 'data_model.dart';
import 'errors.dart';
import 'graph.dart';
import 'graph_unit.dart';
import 'json_utils.dart';
import 'page.dart';

/// A subgraph that runs on the server (§7.7, R17).
///
/// It is a function, not a fold: it has declared parameters and one return
/// value, both of which must survive JSON, because that is what crossing a
/// network means. The client never runs its body — it calls it and waits.
///
/// The graph inside is pure: no `Signal`, no `Event`, no widget. Those are
/// client concepts, and a validator says so rather than letting the failure
/// surface as a compile error in a project the user did not write.
final class ServerFunction implements GraphUnit {
  ServerFunction({
    required this.id,
    required this.name,
    required this.returns,
    Graph? graph,
    List<FieldDef>? parameters,
    Map<String, CanvasPos>? layout,
  })  : graph = graph ?? Graph.empty,
        parameters = List.unmodifiable(parameters ?? const []),
        layout = Map.unmodifiable(layout ?? const {});

  @override
  final String id;

  /// The RPC name: the route is `POST /rpc/<name>` and the client stub is a
  /// Dart function of the same name.
  @override
  final String name;

  /// What the function answers with.
  final LatticeType returns;

  @override
  final Graph graph;

  @override
  final List<FieldDef> parameters;

  @override
  final Map<String, CanvasPos> layout;

  factory ServerFunction.fromJson(
    Map<String, Object?> json, {
    String path = 'server',
  }) {
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

    final returnSpec = json.str('returns', path);
    final returns = TypeParser.tryParse(returnSpec);
    if (returns == null) {
      throw ProjectFormatException(
        '"$returnSpec" is not a valid type',
        path: '$path.returns',
      );
    }

    return ServerFunction(
      id: id,
      name: json.strOr('name', _defaultName(id)),
      returns: returns,
      parameters: parameters,
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
        'params': {for (final p in parameters) p.name: p.type.dartName},
        'paramDefaults': {
          for (final p in parameters)
            if (p.defaultValue != null) p.name: p.defaultValue,
        },
        'returns': returns.dartName,
        'graph': graph.toJson(),
        'layout': sortedKeys({
          for (final entry in layout.entries) entry.key: entry.value.toJson(),
        }),
      });

  /// `POST /rpc/<name>` (§7.7).
  String get route => '/rpc/$name';

  /// The generated file, both sides.
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
  FieldDef? parameter(String name) =>
      parameters.firstWhereOrNull((p) => p.name == name);

  /// Whether everything crossing the boundary survives JSON — the one
  /// constraint §7.7 puts on a server function.
  bool get boundaryIsSerializable =>
      returns.isSerializable && parameters.every((p) => p.type.isSerializable);

  static String _defaultName(String id) {
    final base = id.replaceFirst(RegExp('^(server|fn)_'), '');
    final parts = base.split(RegExp('[_-]')).where((p) => p.isNotEmpty);
    if (parts.isEmpty) return 'call';
    return parts.first +
        parts.skip(1).map((p) => p[0].toUpperCase() + p.substring(1)).join();
  }

  ServerFunction copyWith({
    String? name,
    LatticeType? returns,
    Graph? graph,
    List<FieldDef>? parameters,
    Map<String, CanvasPos>? layout,
  }) =>
      ServerFunction(
        id: id,
        name: name ?? this.name,
        returns: returns ?? this.returns,
        graph: graph ?? this.graph,
        parameters: parameters ?? this.parameters,
        layout: layout ?? this.layout,
      );

  @override
  bool operator ==(Object other) =>
      other is ServerFunction &&
      other.id == id &&
      other.name == name &&
      other.returns == returns &&
      other.graph == graph &&
      const ListEquality<FieldDef>().equals(other.parameters, parameters);

  @override
  int get hashCode => Object.hash(id, name, returns, graph);
}
