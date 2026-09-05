import 'dart:io';

import 'package:path/path.dart' as p;

import 'emit/support_files.dart';
import 'generator.dart';

/// Writing a [GenerationResult] to disk.
///
/// Kept apart from [LatticeGenerator] so that generation itself — validate,
/// lower, emit, format — has no `dart:io` dependency and runs anywhere,
/// including in the editor compiled for the web.
extension GenerationWriter on LatticeGenerator {
  /// Directories whose contents are always the generator's to replace.
  static const ownedDirectories = ['lib/pages', 'lib/prefabs'];

  /// [customSource] is the project's own `custom/` directory. Its contents are
  /// mirrored into the generated project's `lib/custom/`.
  ///
  /// The user's hand-written Dart lives in the project directory — the one
  /// under version control — rather than in `.lattice/build/`, which is
  /// disposable. Codegen never writes *into* `lib/custom/` beyond this mirror,
  /// which is what §7.8's promise amounts to in practice.
  Future<List<String>> write(
    GenerationResult result,
    String outputDir, {
    String? customSource,
  }) async {
    final written = <String>[];

    for (final entry in result.files.entries) {
      final file = File(p.join(outputDir, entry.key));
      await file.parent.create(recursive: true);
      // Skipping an identical write keeps file mtimes stable, so the preview
      // process only hot-reloads pages that actually changed (§7.6).
      if (file.existsSync() && await file.readAsString() == entry.value) {
        continue;
      }
      await file.writeAsString(entry.value);
      written.add(entry.key);
    }

    written.addAll(await _mirrorCustom(customSource, outputDir));
    await _pruneStale(result, outputDir);
    return written;
  }

  Future<List<String>> _mirrorCustom(
    String? customSource,
    String outputDir,
  ) async {
    final target = Directory(p.join(outputDir, 'lib', 'custom'));
    await target.create(recursive: true);

    final written = <String>[];
    final readme = File(p.join(target.path, 'README.md'));
    if (!readme.existsSync()) {
      await readme.writeAsString(const SupportFiles().customReadme());
      written.add('lib/custom/README.md');
    }

    final source = customSource == null ? null : Directory(customSource);
    final expected = <String>{'README.md'};

    if (source != null && source.existsSync()) {
      for (final entity in source.listSync(recursive: true)) {
        if (entity is! File) continue;
        final relative = p.relative(entity.path, from: source.path);
        expected.add(relative);
        final destination = File(p.join(target.path, relative));
        await destination.parent.create(recursive: true);
        final contents = await entity.readAsString();
        if (destination.existsSync() &&
            await destination.readAsString() == contents) {
          continue;
        }
        await destination.writeAsString(contents);
        written.add('lib/custom/$relative');
      }
    }

    // A file removed from the project should disappear from the build too,
    // or a stale helper keeps compiling long after it was deleted.
    for (final entity in target.listSync(recursive: true)) {
      if (entity is! File) continue;
      final relative = p.relative(entity.path, from: target.path);
      if (!expected.contains(relative)) await entity.delete();
    }

    return written;
  }

  /// Deletes files under generator-owned directories that this run did not
  /// produce, so a renamed or removed page does not leave a stale file behind.
  Future<void> _pruneStale(GenerationResult result, String outputDir) async {
    for (final owned in ownedDirectories) {
      final directory = Directory(p.join(outputDir, owned));
      if (!directory.existsSync()) continue;
      for (final entity in directory.listSync()) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final relative =
            p.url.joinAll(p.split(p.relative(entity.path, from: outputDir)));
        if (!result.files.containsKey(relative)) {
          await entity.delete();
        }
      }
    }
  }
}
