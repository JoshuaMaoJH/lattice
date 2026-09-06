import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:lattice_build/lattice_build.dart';
import 'package:lattice_codegen/io.dart';
import 'package:lattice_codegen/lattice_codegen.dart';
import 'package:lattice_core/io.dart';
import 'package:lattice_core/lattice_core.dart';
import 'package:path/path.dart' as p;

import 'editor_host.dart';

/// The desktop host: real files, and a real `flutter run` to preview against.
class IoHost implements EditorHost {
  IoHost({String? configDirectory}) : _configDirectory = configDirectory;

  /// Where per-user state goes. Injectable so a test never writes into the
  /// real config directory of whoever is running it.
  final String? _configDirectory;

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

  /// Where the recent-projects list is kept.
  ///
  /// Not in the project and not next to the binary: it is a fact about this
  /// user on this machine, so it belongs with their other per-user state.
  File get _recentsFile {
    final configured = _configDirectory;
    if (configured != null) return File(p.join(configured, 'recent.json'));
    final home = Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'] ??
        Directory.systemTemp.path;
    final base =
        Platform.environment['XDG_CONFIG_HOME'] ?? p.join(home, '.config');
    return File(p.join(base, 'lattice', 'recent.json'));
  }

  @override
  Set<String> presentEnvironment(Iterable<String> names) => {
        for (final name in names)
          if ((Platform.environment[name] ?? '').trim().isNotEmpty) name,
      };

  @override
  bool environmentPathExists(String name) {
    final value = Platform.environment[name];
    if (value == null || value.trim().isEmpty) return false;
    return File(value).existsSync();
  }

  @override
  Future<String> browseStart() async {
    final recents = await recentProjects();
    for (final root in recents) {
      final parent = parentOf(root);
      if (parent != null && Directory(parent).existsSync()) return parent;
    }
    return Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'] ??
        Directory.current.path;
  }

  @override
  Future<List<DirectoryEntry>> browse(String path) async {
    final dir = Directory(path);
    if (!dir.existsSync()) return const [];
    final entries = <DirectoryEntry>[];
    for (final entity in dir.listSync(followLinks: false)) {
      if (entity is! Directory) continue;
      final name = p.basename(entity.path);
      // Dotted directories are machinery, not somewhere a project lives.
      if (name.startsWith('.')) continue;
      entries.add(DirectoryEntry(
        name: name,
        path: entity.path,
        isProject: File(p.join(entity.path, 'project.json')).existsSync(),
      ));
    }
    entries
        .sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return entries;
  }

  @override
  String? parentOf(String path) {
    final parent = p.dirname(path);
    return parent == path ? null : parent;
  }

  @override
  Future<List<String>> recentProjects() async {
    final file = _recentsFile;
    if (!file.existsSync()) return const [];
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! List) return const [];
      return [
        for (final entry in decoded)
          if (entry is String &&
              File(p.join(entry, 'project.json')).existsSync())
            entry,
      ];
    } on Object {
      // A corrupt list is not worth an error dialog on startup; the user loses
      // their history, not their work.
      return const [];
    }
  }

  Future<void> _remember(String root) async {
    final existing = await recentProjects();
    final updated =
        [root, ...existing.where((e) => e != root)].take(10).toList();
    final file = _recentsFile;
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode(updated));
  }

  @override
  Future<Project> createProject(String root, {String? appName}) async {
    final directory = Directory(root);
    if (directory.existsSync() && directory.listSync().isNotEmpty) {
      throw StateError('"$root" already exists and is not empty.');
    }
    final project = Starter.project(p.basename(root), appName: appName);
    await ProjectIo.save(project, root);
    await _remember(root);
    return project;
  }

  @override
  Future<Project> open(String root) async {
    final project = await ProjectIo.load(root);
    await _remember(root);
    return project;
  }

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

  /// Generates the project *and* makes sure the platform directories exist.
  ///
  /// Writing Dart is not enough to run anything: `flutter run -d linux` needs a
  /// `linux/` directory, which `flutter create` produces once and then leaves
  /// alone (§7.9 step 1). The CLI has always done this; the preview did not,
  /// and failed with "No Linux desktop project configured" on any project that
  /// had never been built from the command line.
  Future<String> _buildRunnable(
    Project project,
    String root,
    BuildTarget target,
  ) async {
    final output = await build(project, root);

    final scaffold = await const PlatformScaffolder().ensure(
      output,
      project.config,
      [target],
      onLog: _append,
    );
    if (!scaffold.isSuccess) {
      throw StateError('flutter create failed for ${target.id}.');
    }
    await const AppMetadata().apply(output, project.config);
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

    _log.clear();
    _setStatus(PreviewStatus.starting);

    final targetId = device ?? 'linux';
    final target = BuildTarget.fromId(targetId) ?? BuildTarget.linux;
    if (!Host.canBuild(target)) {
      _setStatus(PreviewStatus.failed);
      _append(Host.explain(target));
      return;
    }

    final String output;
    try {
      output = await _buildRunnable(project, root, target);
    } on Object catch (error) {
      _setStatus(PreviewStatus.failed);
      _append('$error');
      return;
    }

    _append('flutter run -d $targetId');

    try {
      final process = await Process.start(
        Platform.isWindows ? 'flutter.bat' : 'flutter',
        ['run', '-d', targetId],
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
