import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:lattice_codegen/io.dart';
import 'package:lattice_codegen/lattice_codegen.dart';
import 'package:lattice_core/io.dart';
import 'package:lattice_core/lattice_core.dart';
import 'package:path/path.dart' as p;

import 'editor_host.dart';

/// The desktop host: real files, and a real `flutter run` to preview against.
class IoHost implements EditorHost {
  IoHost();

  final _changes = StreamController<void>.broadcast();
  final List<String> _log = [];

  Process? _preview;
  PreviewStatus _status = PreviewStatus.stopped;

  @override
  String get description => 'the desktop editor';

  @override
  bool get canOpenProjects => true;

  @override
  bool get canRunPreview => true;

  @override
  PreviewStatus get previewStatus => _status;

  @override
  List<String> get previewLog => List.unmodifiable(_log);

  @override
  Stream<void> get previewChanges => _changes.stream;

  @override
  Future<Project> open(String root) => ProjectIo.load(root);

  @override
  Future<void> save(Project project, String root) =>
      ProjectIo.save(project, root);

  @override
  Future<String> build(Project project, String root) async {
    final output = p.join(root, '.lattice', 'build');
    final result = const LatticeGenerator().generate(project);
    if (!result.isSuccess) {
      throw StateError(
        result.errors.map((e) => e.toString()).join('\n'),
      );
    }
    await const LatticeGenerator()
        .write(result, output, customSource: p.join(root, 'custom'));
    return output;
  }

  @override
  Future<String> export(
    Project project,
    String root,
    String destination,
  ) async {
    final result = const LatticeGenerator().generate(project);
    if (!result.isSuccess) {
      throw StateError(result.errors.map((e) => e.toString()).join('\n'));
    }
    await const LatticeGenerator()
        .write(result, destination, customSource: p.join(root, 'custom'));
    return destination;
  }

  @override
  Future<void> startPreview(
    Project project,
    String root, {
    String? device,
  }) async {
    await stopPreview();
    final output = await build(project, root);

    _log.clear();
    _setStatus(PreviewStatus.starting);
    _append('flutter run -d ${device ?? 'linux'}');

    try {
      final process = await Process.start(
        Platform.isWindows ? 'flutter.bat' : 'flutter',
        ['run', '-d', device ?? 'linux'],
        workingDirectory: output,
      );
      _preview = process;

      process.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
        _append(line);
        // `flutter run` prints this once the app is up.
        if (line.contains('Flutter run key commands') ||
            line.contains('is available at')) {
          _setStatus(PreviewStatus.running);
        }
      });
      process.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(_append);

      unawaited(process.exitCode.then((code) {
        _preview = null;
        _setStatus(code == 0 ? PreviewStatus.stopped : PreviewStatus.failed);
        _append('preview exited with $code');
      }));
    } on ProcessException catch (e) {
      _setStatus(PreviewStatus.failed);
      _append('could not start flutter: ${e.message}');
    }
  }

  @override
  Future<void> reloadPreview(Project project, String root) async {
    final process = _preview;
    if (process == null) return;
    // Only the files that actually changed are rewritten, so the reload is as
    // small as the edit (§7.6).
    await build(project, root);
    // `r` on stdin is `flutter run`'s own hot-reload command and works on
    // every platform, unlike sending SIGUSR1.
    process.stdin.write('r');
    await process.stdin.flush();
    _append('hot reload');
  }

  @override
  Future<void> stopPreview() async {
    final process = _preview;
    if (process == null) return;
    process.stdin.write('q');
    await process.stdin.flush();
    _preview = null;
    _setStatus(PreviewStatus.stopped);
  }

  void _append(String line) {
    _log.add(line);
    if (_log.length > 500) _log.removeAt(0);
    _changes.add(null);
  }

  void _setStatus(PreviewStatus status) {
    _status = status;
    _changes.add(null);
  }
}

EditorHost createHost() => IoHost();
