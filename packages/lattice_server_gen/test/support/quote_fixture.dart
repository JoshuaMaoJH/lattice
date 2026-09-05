import 'dart:convert';
import 'dart:io';

import 'package:lattice_core/lattice_core.dart';

Project? _cached;

/// The shipped `examples/quote`, loaded once.
///
/// Read from the example rather than rebuilt inline, so the tests cannot drift
/// away from the project a reader actually opens.
Project quoteProject() => _cached ??= _load('../../examples/quote');

Project _load(String root) {
  // ProjectIo is async; these tests are not, and the fixture is four files.
  final manifest = jsonDecode(
    File('$root/project.json').readAsStringSync(),
  ) as Map<String, Object?>;

  return Project.fromManifest(
    manifest,
    models: [
      for (final file in _jsonFiles('$root/models'))
        DataModelDef.fromJson(_read(file), file.path),
    ],
    prefabs: const [],
    serverFunctions: [
      for (final file in _jsonFiles('$root/server'))
        ServerFunction.fromJson(_read(file), path: file.path),
    ],
    pages: [
      for (final file in _jsonFiles('$root/pages'))
        Page.fromJson(_read(file), path: file.path),
    ],
  );
}

Iterable<File> _jsonFiles(String directory) {
  final dir = Directory(directory);
  if (!dir.existsSync()) return const [];
  return (dir
      .listSync()
      .whereType<File>()
      .where(
        (f) => f.path.endsWith('.json'),
      )
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path)));
}

Map<String, Object?> _read(File file) =>
    jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
