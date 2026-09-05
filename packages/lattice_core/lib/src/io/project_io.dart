import 'dart:convert';
import 'dart:io';

import '../model/data_model.dart';
import '../model/errors.dart';
import '../model/json_utils.dart';
import '../model/page.dart';
import '../model/prefab.dart';
import '../model/project.dart';

/// Reads and writes the on-disk project format (§7.4).
///
/// ```
/// <root>/
///   project.json      manifest + build config
///   pages/<id>.json   one file per page — keeps git diffs local
///   models/<n>.json   one file per struct
/// ```
class ProjectIo {
  const ProjectIo._();

  static const JsonEncoder _encoder = JsonEncoder.withIndent('  ');

  static File manifestFile(String root) =>
      File('$root${Platform.pathSeparator}project.json');

  static Future<Project> load(String root) async {
    final manifest = manifestFile(root);
    if (!manifest.existsSync()) {
      throw ProjectFormatException('no project.json found in "$root"');
    }
    final manifestJson = asObj(
      jsonDecode(await manifest.readAsString()),
      'project.json',
    );

    final models = <DataModelDef>[];
    final modelsDir = Directory('$root/models');
    if (modelsDir.existsSync()) {
      final files = modelsDir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.json'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));
      for (final file in files) {
        models.add(
          DataModelDef.fromJson(
            asObj(jsonDecode(await file.readAsString()), file.path),
            file.path,
          ),
        );
      }
    }

    final prefabs = <Prefab>[];
    final prefabsDir = Directory('$root/prefabs');
    if (prefabsDir.existsSync()) {
      final files = prefabsDir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.json'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));
      for (final file in files) {
        prefabs.add(
          Prefab.fromJson(
            asObj(jsonDecode(await file.readAsString()), file.path),
            path: file.path,
          ),
        );
      }
    }

    // The manifest's `pages` array fixes declaration order; anything found on
    // disk but unlisted is appended so a hand-added file is never silently
    // ignored.
    final declared = <String>[
      for (final id in manifestJson.arrOrEmpty('pages', 'project.json'))
        if (id is String) id,
    ];
    final pagesDir = Directory('$root/pages');
    final onDisk = <String, File>{};
    if (pagesDir.existsSync()) {
      for (final file in pagesDir.listSync().whereType<File>()) {
        if (!file.path.endsWith('.json')) continue;
        final name = file.uri.pathSegments.last;
        onDisk[name.substring(0, name.length - 5)] = file;
      }
    }
    final order = <String>[
      ...declared.where(onDisk.containsKey),
      ...(onDisk.keys.where((k) => !declared.contains(k)).toList()..sort()),
    ];

    final pages = <Page>[];
    for (final id in order) {
      final file = onDisk[id]!;
      pages.add(
        Page.fromJson(
          asObj(jsonDecode(await file.readAsString()), file.path),
          path: 'pages/$id.json',
        ),
      );
    }

    return Project.fromManifest(
      manifestJson,
      pages: pages,
      models: models,
      prefabs: prefabs,
    );
  }

  static Future<void> save(Project project, String root) async {
    await Directory(root).create(recursive: true);
    await manifestFile(root)
        .writeAsString('${_encoder.convert(project.toManifestJson())}\n');

    final pagesDir = Directory('$root/pages');
    await pagesDir.create(recursive: true);
    for (final page in project.pages) {
      await File('${pagesDir.path}/${page.id}.json')
          .writeAsString('${_encoder.convert(page.toJson())}\n');
    }

    if (project.prefabs.isNotEmpty) {
      final prefabsDir = Directory('$root/prefabs');
      await prefabsDir.create(recursive: true);
      for (final prefab in project.prefabs) {
        await File('${prefabsDir.path}/${prefab.id}.json')
            .writeAsString('${_encoder.convert(prefab.toJson())}\n');
      }
    }

    if (project.models.isNotEmpty) {
      final modelsDir = Directory('$root/models');
      await modelsDir.create(recursive: true);
      for (final model in project.models) {
        await File('${modelsDir.path}/${model.name}.json')
            .writeAsString('${_encoder.convert(model.toJson())}\n');
      }
    }
  }
}
