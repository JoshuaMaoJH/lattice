import 'package:collection/collection.dart';

import '../types/lattice_type.dart';
import '../types/type_parser.dart';
import 'errors.dart';
import 'json_utils.dart';

/// One field of a user-defined struct.
final class FieldDef {
  const FieldDef({required this.name, required this.type, this.defaultValue});

  final String name;
  final LatticeType type;

  /// JSON-encodable default, used as the constructor default and by the
  /// Inspector when seeding a new value.
  final Object? defaultValue;

  @override
  bool operator ==(Object other) =>
      other is FieldDef &&
      other.name == name &&
      other.type == type &&
      const DeepCollectionEquality().equals(other.defaultValue, defaultValue);

  @override
  int get hashCode => Object.hash(name, type, defaultValue);
}

/// A struct from `models/` (§5). Compiles to a Dart class with `copyWith`
/// and hand-rolled `toJson`/`fromJson` — no build_runner (§9).
final class DataModelDef {
  DataModelDef({required this.name, required List<FieldDef> fields})
      : fields = List.unmodifiable(fields);

  final String name;
  final List<FieldDef> fields;

  factory DataModelDef.fromJson(Map<String, Object?> json, String path) {
    final name = json.str('name', path);
    final rawFields = json.objOrNull('fields', path) ?? const {};
    final defaults = json.objOrNull('defaults', path) ?? const {};

    final fields = <FieldDef>[];
    for (final entry in rawFields.entries) {
      final spec = entry.value;
      if (spec is! String) {
        throw ProjectFormatException(
          'field type must be a string, got ${spec.runtimeType}',
          path: '$path.fields.${entry.key}',
        );
      }
      final LatticeType type;
      try {
        type = TypeParser.parse(spec);
      } on TypeParseException catch (e) {
        throw ProjectFormatException(
          e.reason,
          path: '$path.fields.${entry.key}',
        );
      }
      fields.add(
        FieldDef(
          name: entry.key,
          type: type,
          defaultValue: defaults[entry.key],
        ),
      );
    }
    return DataModelDef(name: name, fields: fields);
  }

  /// Field order is declaration order, so the generated constructor is stable.
  Map<String, Object?> toJson() => pruneEmpty({
        'name': name,
        'fields': {for (final f in fields) f.name: f.type.dartName},
        'defaults': {
          for (final f in fields)
            if (f.defaultValue != null) f.name: f.defaultValue,
        },
      });

  ModelType get type => ModelType(name);

  FieldDef? field(String name) =>
      fields.firstWhereOrNull((f) => f.name == name);

  /// Whether every field can cross a `@server` boundary (§7.7).
  bool get isSerializable => fields.every((f) => f.type.isSerializable);

  @override
  bool operator ==(Object other) =>
      other is DataModelDef &&
      other.name == name &&
      const ListEquality<FieldDef>().equals(other.fields, fields);

  @override
  int get hashCode =>
      Object.hash(name, const ListEquality<FieldDef>().hash(fields));
}
