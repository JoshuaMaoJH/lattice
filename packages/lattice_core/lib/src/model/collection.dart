import 'json_utils.dart';

/// A typed, persisted list of a model (R19).
///
/// The data layer is deliberately thin: a collection is a `List<T>` that
/// survives a restart. Anything more — indexes, queries, migrations — is a
/// database, and a project that needs one should use one rather than have
/// Lattice grow a bad imitation.
///
/// Serialization is the models' own, which is what §7.7 already needs for the
/// server boundary. A collection of a model that cannot cross that boundary
/// cannot be stored either, and the validator says so in those terms.
final class CollectionDef {
  const CollectionDef({
    required this.name,
    required this.element,
    this.persist = true,
  });

  /// The generated accessor, e.g. `todos`.
  final String name;

  /// The model each entry is, by name.
  final String element;

  /// Whether it is written to storage. An in-memory collection is still
  /// useful — a session's worth of state that outlives one page.
  final bool persist;

  factory CollectionDef.fromJson(Map<String, Object?> json, String path) =>
      CollectionDef(
        name: json.str('name', path),
        element: json.str('of', path),
        persist: json.boolOr('persist', fallback: true),
      );

  Map<String, Object?> toJson() => pruneEmpty({
        'name': name,
        'of': element,
        if (!persist) 'persist': false,
      });

  @override
  bool operator ==(Object other) =>
      other is CollectionDef &&
      other.name == name &&
      other.element == element &&
      other.persist == persist;

  @override
  int get hashCode => Object.hash(name, element, persist);
}
