import 'dart:convert';
import 'dart:io';

import 'package:lattice_core/lattice_core.dart';
import 'package:path/path.dart' as p;

/// Step 1 of §7.9: make sure the generated project has the platform
/// directories its targets need.
///
/// `flutter create` owns those directories, so they are produced once and then
/// left alone — regenerating them on every build would stomp on any signing or
/// permission edits the user made.
class PlatformScaffolder {
  const PlatformScaffolder({this.flutterExecutable = 'flutter'});

  final String flutterExecutable;

  /// Directory each target's platform files live in.
  static const Map<String, String> _directories = {
    'linux': 'linux',
    'windows': 'windows',
    'macos': 'macos',
    'android': 'android',
    'ios': 'ios',
    'web': 'web',
  };

  static String directoryFor(BuildTarget target) => _directories[target.id]!;

  /// Targets in [targets] whose platform directory is not present yet.
  List<BuildTarget> missing(String projectDir, Iterable<BuildTarget> targets) =>
      targets
          .where((t) =>
              !Directory(p.join(projectDir, directoryFor(t))).existsSync())
          .toList();

  /// Creates the platform directories for any missing [targets].
  ///
  /// Returns the targets that were scaffolded, or an empty list when there was
  /// nothing to do.
  Future<ScaffoldResult> ensure(
    String projectDir,
    ProjectConfig config,
    Iterable<BuildTarget> targets, {
    void Function(String line)? onLog,
  }) async {
    final todo = missing(projectDir, targets);
    if (todo.isEmpty) return const ScaffoldResult(created: [], exitCode: 0);

    final arguments = [
      'create',
      '--project-name',
      config.packageName,
      '--org',
      config.organization,
      '--platforms',
      todo.map((t) => t.id).join(','),
      // Without this, `flutter create` drops its demo counter app on top of the
      // generated sources.
      '--empty',
      '.',
    ];
    onLog?.call('flutter ${arguments.join(' ')}');

    final process = await Process.start(
      flutterExecutable,
      arguments,
      workingDirectory: projectDir,
    );
    // Both pipes must be consumed while the process runs, or a chatty
    // `flutter create` can fill a buffer and deadlock.
    final output = StringBuffer();
    final stdoutDone =
        process.stdout.transform(utf8.decoder).forEach(output.write);
    final stderrDone =
        process.stderr.transform(utf8.decoder).forEach(output.write);
    final exitCode = await process.exitCode;
    await stdoutDone;
    await stderrDone;

    if (exitCode != 0) {
      onLog?.call(output.toString());
      return ScaffoldResult(created: const [], exitCode: exitCode);
    }

    await _removeTemplateLeftovers(projectDir);
    return ScaffoldResult(created: todo, exitCode: 0);
  }

  /// `flutter create` leaves a smoke test that refers to its own demo app.
  /// It would not compile against generated sources, so it goes.
  Future<void> _removeTemplateLeftovers(String projectDir) async {
    final test = File(p.join(projectDir, 'test', 'widget_test.dart'));
    if (test.existsSync()) {
      final contents = await test.readAsString();
      if (contents.contains('smoke test') || contents.contains('MyApp')) {
        await test.delete();
        final directory = Directory(p.join(projectDir, 'test'));
        if (directory.existsSync() && directory.listSync().isEmpty) {
          await directory.delete();
        }
      }
    }
  }
}

final class ScaffoldResult {
  const ScaffoldResult({required this.created, required this.exitCode});

  final List<BuildTarget> created;
  final int exitCode;

  bool get isSuccess => exitCode == 0;
}
