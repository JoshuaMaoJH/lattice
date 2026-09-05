import 'errors.dart';

/// Small typed readers over decoded JSON. Every failure carries the path that
/// produced it, so a malformed project file points at the offending key
/// instead of throwing a bare cast error.
extension JsonMapReader on Map<String, Object?> {
  Map<String, Object?> obj(String key, String path) {
    final value = this[key];
    if (value is! Map<String, Object?>) {
      throw ProjectFormatException(
        'expected an object, got ${value.runtimeType}',
        path: '$path.$key',
      );
    }
    return value;
  }

  Map<String, Object?>? objOrNull(String key, String path) =>
      this[key] == null ? null : obj(key, path);

  List<Object?> arr(String key, String path) {
    final value = this[key];
    if (value is! List) {
      throw ProjectFormatException(
        'expected an array, got ${value.runtimeType}',
        path: '$path.$key',
      );
    }
    return value;
  }

  List<Object?> arrOrEmpty(String key, String path) =>
      this[key] == null ? const [] : arr(key, path);

  String str(String key, String path) {
    final value = this[key];
    if (value is! String) {
      throw ProjectFormatException(
        'expected a string, got ${value.runtimeType}',
        path: '$path.$key',
      );
    }
    return value;
  }

  String strOr(String key, String fallback) {
    final value = this[key];
    return value is String ? value : fallback;
  }

  bool boolOr(String key, {required bool fallback}) {
    final value = this[key];
    return value is bool ? value : fallback;
  }
}

/// Casts a decoded JSON element to an object map, reporting [path] on failure.
Map<String, Object?> asObj(Object? value, String path) {
  if (value is! Map<String, Object?>) {
    throw ProjectFormatException(
      'expected an object, got ${value.runtimeType}',
      path: path,
    );
  }
  return value;
}

/// Returns a copy of [map] with keys in sorted order.
///
/// Project files are written with sorted keys so that a semantic change
/// produces a minimal `git diff` (§7.4).
Map<String, Object?> sortedKeys(Map<String, Object?> map) {
  final keys = map.keys.toList()..sort();
  return {for (final k in keys) k: map[k]};
}

/// Drops entries whose value is `null` or an empty collection, so default
/// values never show up in the serialized form.
Map<String, Object?> pruneEmpty(Map<String, Object?> map) {
  final out = <String, Object?>{};
  for (final entry in map.entries) {
    final value = entry.value;
    if (value == null) continue;
    if (value is Iterable && value.isEmpty) continue;
    if (value is Map && value.isEmpty) continue;
    out[entry.key] = value;
  }
  return out;
}
