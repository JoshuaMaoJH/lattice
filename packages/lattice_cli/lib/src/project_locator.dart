import 'dart:io';

import 'package:path/path.dart' as p;

/// Resolves the paths the CLI needs from wherever the user happened to run it.
class ProjectLocator {
  const ProjectLocator._();

  /// Walks up from [start] looking for a `project.json`, so `lattice build`
  /// works from anywhere inside a project the way `git` does.
  static String? findProjectRoot(String start) {
    var directory = Directory(p.absolute(start));
    while (true) {
      if (File(p.join(directory.path, 'project.json')).existsSync()) {
        return directory.path;
      }
      final parent = directory.parent;
      if (parent.path == directory.path) return null;
      directory = parent;
    }
  }

  /// Locates `packages/lattice_runtime`.
  ///
  /// Searched first from [start], so a project living inside the Lattice
  /// checkout uses that copy, and then from this executable's own location,
  /// so a project anywhere else still finds the runtime that shipped with the
  /// CLI. Only the zero-dependency backend needs it; the signals backend
  /// depends on a published package and does not care where this checkout is.
  static String? findRuntimePackage(String start) =>
      _searchUp(start) ?? _searchUp(_executableDirectory());

  static String? _searchUp(String? start) {
    if (start == null) return null;
    var directory = Directory(p.absolute(start));
    while (true) {
      final candidate =
          p.join(directory.path, 'packages', 'lattice_runtime', 'pubspec.yaml');
      if (File(candidate).existsSync()) {
        return p.dirname(candidate);
      }
      final parent = directory.parent;
      if (parent.path == directory.path) return null;
      directory = parent;
    }
  }

  static String? _executableDirectory() {
    final script = Platform.script;
    if (script.scheme != 'file') return null;
    return p.dirname(script.toFilePath());
  }

  /// The default place generated sources go: inside the project, ignored by
  /// git, next to nothing the user hand-edits (§6).
  static String defaultBuildDir(String projectRoot) =>
      p.join(projectRoot, '.lattice', 'build');
}
