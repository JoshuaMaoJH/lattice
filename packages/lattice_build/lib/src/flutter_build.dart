import 'dart:convert';
import 'dart:io';

import 'package:lattice_core/lattice_core.dart';
import 'package:path/path.dart' as p;

enum BuildMode {
  debug('debug'),
  profile('profile'),
  release('release');

  const BuildMode(this.flag);

  final String flag;
}

final class BuildOutcome {
  const BuildOutcome({
    required this.target,
    required this.exitCode,
    required this.artifact,
  });

  final BuildTarget target;
  final int exitCode;

  /// Path to the produced bundle, or null when the build failed or the
  /// location is not known.
  final String? artifact;

  bool get isSuccess => exitCode == 0;
}

/// Step 3 of §7.9: invoke `flutter build` per target and report where the
/// artefact landed.
class FlutterBuild {
  const FlutterBuild({this.flutterExecutable = 'flutter'});

  final String flutterExecutable;

  /// The `flutter build` subcommand for a target. Android defaults to an APK
  /// because that is the thing a user can actually hand to someone; the AAB is
  /// for store upload and is a separate, explicit choice.
  static String subcommandFor(BuildTarget target) => switch (target) {
        BuildTarget.linux => 'linux',
        BuildTarget.windows => 'windows',
        BuildTarget.macos => 'macos',
        BuildTarget.android => 'apk',
        BuildTarget.ios => 'ios',
        BuildTarget.web => 'web',
      };

  /// Where `flutter build` leaves its output, relative to the project.
  static String artifactPathFor(BuildTarget target, BuildMode mode) =>
      switch (target) {
        BuildTarget.linux => 'build/linux/x64/${mode.flag}/bundle',
        BuildTarget.windows => 'build/windows/x64/runner/${_titled(mode.flag)}',
        BuildTarget.macos => 'build/macos/Build/Products/${_titled(mode.flag)}',
        BuildTarget.android => 'build/app/outputs/flutter-apk',
        BuildTarget.ios => 'build/ios/iphoneos',
        BuildTarget.web => 'build/web',
      };

  static String _titled(String value) =>
      value[0].toUpperCase() + value.substring(1);

  Future<BuildOutcome> build(
    String projectDir,
    BuildTarget target, {
    BuildMode mode = BuildMode.release,
    void Function(String line)? onLog,
  }) async {
    final arguments = ['build', subcommandFor(target), '--${mode.flag}'];
    onLog?.call('flutter ${arguments.join(' ')}');

    final process = await Process.start(
      flutterExecutable,
      arguments,
      workingDirectory: projectDir,
    );
    final stdoutDone = process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .forEach((line) => onLog?.call(line));
    final stderrDone = process.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .forEach((line) => onLog?.call(line));

    final exitCode = await process.exitCode;
    await stdoutDone;
    await stderrDone;

    final artifact = p.join(projectDir, artifactPathFor(target, mode));
    return BuildOutcome(
      target: target,
      exitCode: exitCode,
      artifact:
          exitCode == 0 && Directory(artifact).existsSync() ? artifact : null,
    );
  }
}
