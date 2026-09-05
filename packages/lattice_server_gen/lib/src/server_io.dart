import 'dart:io';

import 'package:lattice_core/lattice_core.dart';
import 'package:path/path.dart' as p;

/// Copies the hand-written files a server function reaches for (§7.8, §7.7).
///
/// Only the ones it actually imports, plus whatever those import in turn. The
/// client's `custom/` may well use Flutter; a server that mirrored the whole
/// directory would fail to compile over a file nothing on it uses.
class ServerCustomMirror {
  const ServerCustomMirror();

  /// Mirrors [imports] and their relative-import closure from
  /// `<root>/custom/` into `<output>/lib/custom/`.
  ///
  /// Returns diagnostics for anything missing or unusable on a server.
  Future<List<Diagnostic>> mirror(
    String root,
    String output,
    List<String> imports,
  ) async {
    final diagnostics = <Diagnostic>[];
    final target = Directory(p.join(output, 'lib', 'custom'));

    final needed = <String>{};
    final queue = [...imports];

    while (queue.isNotEmpty) {
      final relative = queue.removeLast();
      if (!needed.add(relative)) continue;

      final source = File(p.join(root, relative));
      if (!source.existsSync()) {
        diagnostics.add(
          Diagnostic.error(
            code: 'missing_custom_file',
            message: 'A server function imports "$relative", which is not in '
                'the project.',
          ),
        );
        needed.remove(relative);
        continue;
      }

      final contents = await source.readAsString();
      final flutterImport = _flutterImportIn(contents);
      if (flutterImport != null) {
        diagnostics.add(
          Diagnostic.error(
            code: 'flutter_on_server',
            message: '"$relative" imports $flutterImport, so it cannot run on '
                'a server. Split the part the server needs into its own file.',
          ),
        );
        // It was added on the way in; a refused file must not be copied.
        needed.remove(relative);
        continue;
      }

      // Follow relative imports so a helper file does not have to be declared
      // on the node that reaches it only indirectly.
      for (final sibling in _relativeImportsIn(contents)) {
        queue.add(p.normalize(p.join(p.dirname(relative), sibling)));
      }
    }

    if (needed.isEmpty) {
      if (target.existsSync()) await target.delete(recursive: true);
      return diagnostics;
    }

    await target.create(recursive: true);
    for (final relative in needed) {
      // `custom/pricing.dart` -> `lib/custom/pricing.dart`.
      final destination = File(
        p.join(target.path, p.relative(relative, from: 'custom')),
      );
      await destination.parent.create(recursive: true);
      final contents = await File(p.join(root, relative)).readAsString();
      if (destination.existsSync() &&
          await destination.readAsString() == contents) {
        continue;
      }
      await destination.writeAsString(contents);
    }

    // A file the server stopped importing should stop being compiled.
    final expected = {
      for (final relative in needed) p.relative(relative, from: 'custom'),
    };
    for (final entity in target.listSync(recursive: true)) {
      if (entity is! File) continue;
      final relative = p.relative(entity.path, from: target.path);
      if (!expected.contains(relative)) await entity.delete();
    }

    return diagnostics;
  }

  static final RegExp _import = RegExp(
    '''import\\s+['"]([^'"]+)['"]''',
  );

  static String? _flutterImportIn(String source) {
    for (final match in _import.allMatches(source)) {
      final uri = match.group(1)!;
      if (uri.startsWith('package:flutter')) return uri;
    }
    return null;
  }

  static Iterable<String> _relativeImportsIn(String source) sync* {
    for (final match in _import.allMatches(source)) {
      final uri = match.group(1)!;
      if (uri.startsWith('package:') || uri.startsWith('dart:')) continue;
      // `../models.dart` is the generated models file, which the server
      // already has its own copy of.
      if (uri.startsWith('..')) continue;
      yield uri;
    }
  }
}
