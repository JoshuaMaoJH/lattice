import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lattice_core/io.dart';
import 'package:lattice_core/lattice_core.dart';
import 'package:lattice_editor/src/host/editor_host.dart';
import 'package:lattice_editor/src/host/io_host.dart';
import 'package:lattice_editor/src/sample_project.dart';
import 'package:lattice_editor/src/state/project_edits.dart';
import 'package:path/path.dart' as p;

/// The preview link (§7.6, R6), tested against a real `flutter run`.
///
/// Off by default: it needs the Linux desktop toolchain and takes minutes.
///
///     LATTICE_DESKTOP_TESTS=1 flutter test test/io_host_test.dart
///
/// A `@Tags` annotation would not have done this — a tag labels a test, it
/// does not skip it, which is how this ran on a CI machine with no GTK and
/// failed inside CMake.
final _reason = Platform.environment['LATTICE_DESKTOP_TESTS'] == '1'
    ? null
    : 'needs the desktop toolchain — set LATTICE_DESKTOP_TESTS=1 to run';

void main() {
  late Directory root;
  late IoHost host;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('lattice_preview_');
    await ProjectIo.save(sampleProject(), root.path);
    host = IoHost();
  });

  tearDown(() async {
    await host.stopPreview();
    if (root.existsSync()) await root.delete(recursive: true);
  });

  test('generates a project that exists on disk', skip: _reason, () async {
    final output = await host.build(sampleProject(), root.path);
    expect(File(p.join(output, 'lib', 'main.dart')).existsSync(), isTrue);
    expect(
      File(p.join(output, 'lib', 'pages', 'home_page.dart')).existsSync(),
      isTrue,
    );
  });

  test('a second build rewrites nothing when nothing changed', skip: _reason,
      () async {
    await host.build(sampleProject(), root.path);
    final page = File(
      p.join(root.path, '.lattice', 'build', 'lib', 'pages', 'home_page.dart'),
    );
    final before = page.lastModifiedSync();

    await Future<void>.delayed(const Duration(milliseconds: 1100));
    await host.build(sampleProject(), root.path);

    // Stable mtimes are what keep a hot reload as small as the edit.
    expect(page.lastModifiedSync(), before);
  });

  test('an edit rewrites only the page it touched', skip: _reason, () async {
    await host.build(sampleProject(), root.path);
    final buildDir = p.join(root.path, '.lattice', 'build');
    final page = File(p.join(buildDir, 'lib', 'pages', 'home_page.dart'));
    final main = File(p.join(buildDir, 'lib', 'main.dart'));
    final mainBefore = main.lastModifiedSync();

    await Future<void>.delayed(const Duration(milliseconds: 1100));
    final edited = ProjectEdits.setProp(
      sampleProject(),
      'page_home',
      'w_title',
      'data',
      const LiteralProp('Edited'),
    );
    await host.build(edited, root.path);

    expect(page.readAsStringSync(), contains("Text('Edited')"));
    expect(main.lastModifiedSync(), mainBefore, reason: 'main.dart untouched');
  });

  test(
    'runs the preview and hot-reloads an edit into it',
    () async {
      await host.startPreview(sampleProject(), root.path, device: 'linux');

      await _until(
        () => host.previewStatus == PreviewStatus.running,
        timeout: const Duration(minutes: 6),
        describe: () => 'preview never started:\n${host.previewLog.join('\n')}',
      );

      final edited = ProjectEdits.setProp(
        sampleProject(),
        'page_home',
        'w_title',
        'data',
        const LiteralProp('Reloaded'),
      );

      final stopwatch = Stopwatch()..start();
      await host.reloadPreview(edited, root.path);
      await _until(
        () => host.previewLog.any((line) => line.contains('Reloaded ')),
        timeout: const Duration(seconds: 30),
        describe: () =>
            'no reload confirmation:\n${host.previewLog.join('\n')}',
      );
      stopwatch.stop();

      // R6 asks for two seconds; this is one sample, not a P90, but a reload
      // that takes ten would mean the link is not doing what it claims.
      expect(
        stopwatch.elapsed,
        lessThan(const Duration(seconds: 10)),
        reason: 'reload took ${stopwatch.elapsedMilliseconds}ms',
      );
      // ignore: avoid_print
      print('hot reload round trip: ${stopwatch.elapsedMilliseconds}ms');

      await host.stopPreview();
    },
    timeout: const Timeout(Duration(minutes: 8)),
    skip: _reason,
  );
}

Future<void> _until(
  bool Function() condition, {
  required Duration timeout,
  required String Function() describe,
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) fail(describe());
    await Future<void>.delayed(const Duration(milliseconds: 250));
  }
}
