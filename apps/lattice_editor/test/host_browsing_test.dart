import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lattice_editor/src/host/io_host.dart';
import 'package:path/path.dart' as p;

/// Browsing and creating touch the filesystem but not the Flutter toolchain,
/// so unlike the preview these run everywhere.
void main() {
  late Directory root;
  late IoHost host;

  setUp(() {
    root = Directory.systemTemp.createTempSync('lattice_browse');
    // Recents go in the sandbox: a test must not rewrite the config of
    // whoever is running it.
    host = IoHost(configDirectory: p.join(root.path, 'config'));
  });

  tearDown(() => root.deleteSync(recursive: true));

  Directory dir(String relative) =>
      Directory(p.join(root.path, relative))..createSync(recursive: true);

  test('a directory with a project.json is reported as a project', () async {
    dir('plain');
    final project = dir('app');
    File(p.join(project.path, 'project.json')).writeAsStringSync('{}');

    final entries = await host.browse(root.path);

    expect(entries.map((e) => e.name), ['app', 'plain']);
    expect(entries.firstWhere((e) => e.name == 'app').isProject, isTrue);
    expect(entries.firstWhere((e) => e.name == 'plain').isProject, isFalse);
  });

  test('dotted directories are machinery, not somewhere a project lives',
      () async {
    dir('.git');
    dir('visible');

    final entries = await host.browse(root.path);

    expect(entries.map((e) => e.name), ['visible']);
  });

  test('files are not listed — a project is a directory', () async {
    File(p.join(root.path, 'notes.txt')).writeAsStringSync('hi');
    dir('folder');

    final entries = await host.browse(root.path);

    expect(entries.map((e) => e.name), ['folder']);
  });

  test('a directory that cannot be read comes back empty, not thrown',
      () async {
    expect(await host.browse(p.join(root.path, 'nope')), isEmpty);
  });

  test('parentOf stops at the filesystem root', () {
    expect(host.parentOf('/a/b'), '/a');
    expect(host.parentOf('/'), isNull);
  });

  test('creating a project writes one that loads back', () async {
    final target = p.join(root.path, 'fresh_app');

    final project = await host.createProject(target, appName: 'Fresh');

    expect(project.config.appName, 'Fresh');
    expect(project.config.packageName, 'fresh_app');
    expect(File(p.join(target, 'project.json')).existsSync(), isTrue);

    final reloaded = await host.open(target);
    expect(reloaded.pages.single.route, '/');
  });

  test('creating into a non-empty directory refuses rather than merges',
      () async {
    final target = dir('occupied');
    File(p.join(target.path, 'something.txt')).writeAsStringSync('x');

    expect(
      () => host.createProject(target.path),
      throwsA(isA<StateError>()),
    );
  });

  test('the recents list drops projects that are no longer there', () async {
    final gone = p.join(root.path, 'deleted_app');
    await host.createProject(gone);
    Directory(gone).deleteSync(recursive: true);

    expect(await host.recentProjects(), isNot(contains(gone)));
  });

  test('a corrupt recents file loses history, not work', () async {
    final file = File(p.join(root.path, 'config', 'recent.json'));
    file.parent.createSync(recursive: true);
    file.writeAsStringSync('{not json');

    expect(await host.recentProjects(), isEmpty);

    // And it recovers: the next open rewrites the file.
    final target = p.join(root.path, 'recovered');
    await host.createProject(target);
    expect(await host.recentProjects(), contains(target));
    expect(jsonDecode(file.readAsStringSync()), isA<List<Object?>>());
  });
}
