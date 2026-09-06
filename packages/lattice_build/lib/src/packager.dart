import 'dart:io';

import 'package:archive/archive.dart';
import 'package:lattice_core/lattice_core.dart';
import 'package:path/path.dart' as p;

import 'flutter_build.dart';
import 'host.dart';

/// What a packaging attempt produced, or why it could not (§7.9 step 4-5).
final class PackageOutcome {
  const PackageOutcome.success(this.target, this.artifact)
      : skippedBecause = null;

  const PackageOutcome.skipped(this.target, this.skippedBecause)
      : artifact = null;

  final BuildTarget target;

  /// Path to the distributable, when one was produced.
  final String? artifact;

  /// Why nothing was produced. Phrased as the next thing to do — a packaging
  /// step that cannot run should say what is missing, not just fail.
  final String? skippedBecause;

  bool get isSuccess => artifact != null;
}

/// Turns `flutter build` output into something you can hand to someone.
///
/// Web is packaged here directly, because a static site is just a zip and
/// shelling out for that would add a dependency on the host having `zip`.
/// Every other format goes through `flutter_distributor`, which is the one
/// tool that covers dmg / msix / deb / appimage / apk / aab / ipa from a single
/// configuration (§9).
class Packager {
  const Packager({this.flutterExecutable = 'flutter'});

  final String flutterExecutable;

  /// Where distributables land, per §7.9 step 5.
  static String outputDirFor(
          String projectDir, ProjectConfig config, BuildTarget target) =>
      p.join(projectDir, 'dist', target.id, config.semver);

  /// Whether `flutter_distributor` can actually be run.
  ///
  /// Checked by running it, not by looking for it on PATH: `pub global
  /// activate` installs into `~/.pub-cache/bin`, which is not on PATH by
  /// default, and "installed but invisible" is the state people actually end
  /// up in.
  static bool get hasDistributor {
    for (final executable in _distributorCandidates) {
      try {
        if (Process.runSync(executable, ['--version']).exitCode == 0) {
          _resolvedDistributor = executable;
          return true;
        }
      } on ProcessException {
        continue;
      }
    }
    return false;
  }

  static String? _resolvedDistributor;

  /// PATH first, then the place `pub global activate` puts it.
  static List<String> get _distributorCandidates {
    final home = Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'] ??
        '';
    return [
      'flutter_distributor',
      if (home.isNotEmpty)
        p.join(home, '.pub-cache', 'bin', 'flutter_distributor'),
    ];
  }

  Future<PackageOutcome> package(
    String buildDir,
    String projectDir,
    ProjectConfig config,
    BuildTarget target, {
    BuildMode mode = BuildMode.release,
    void Function(String line)? onLog,
  }) async {
    if (!Host.canBuild(target)) {
      return PackageOutcome.skipped(target, Host.explain(target));
    }

    final destination = Directory(outputDirFor(projectDir, config, target));
    await destination.create(recursive: true);

    if (target == BuildTarget.web) {
      return _zipWeb(buildDir, destination.path, config, mode, onLog);
    }

    if (!hasDistributor) {
      return PackageOutcome.skipped(
        target,
        'flutter_distributor could not be run. Install it with '
        '`dart pub global activate flutter_distributor`, and make sure '
        r'`$HOME/.pub-cache/bin` is on your PATH — activate puts it there but '
        'does not add it. The generated distribute_options.yaml already '
        'describes this target.',
      );
    }

    // Note there is no --build-target-platform here: that flag forwards
    // `--target-platform` to `flutter build`, which means an Android ABI, not
    // a desktop platform. Passing "linux" to it produces an invalid build.
    final arguments = [
      'package',
      '--platform',
      target.id,
      '--targets',
      _distributorTargetsFor(target).join(','),
    ];
    onLog?.call('flutter_distributor ${arguments.join(' ')}');

    final process = await Process.start(
      _resolvedDistributor ?? 'flutter_distributor',
      arguments,
      workingDirectory: buildDir,
      mode: ProcessStartMode.inheritStdio,
    );
    final exitCode = await process.exitCode;
    if (exitCode != 0) {
      return PackageOutcome.skipped(
        target,
        'flutter_distributor exited with $exitCode.',
      );
    }
    return PackageOutcome.success(target, p.join(buildDir, 'dist'));
  }

  /// The formats worth producing per platform: something installable, and for
  /// Android also the store upload bundle.
  static List<String> _distributorTargetsFor(BuildTarget target) =>
      switch (target) {
        BuildTarget.linux => ['appimage', 'deb'],
        BuildTarget.windows => ['exe', 'msix'],
        BuildTarget.macos => ['dmg'],
        BuildTarget.android => ['apk', 'aab'],
        BuildTarget.ios => ['ipa'],
        BuildTarget.web => ['zip'],
      };

  Future<PackageOutcome> _zipWeb(
    String buildDir,
    String destination,
    ProjectConfig config,
    BuildMode mode,
    void Function(String line)? onLog,
  ) async {
    final source = Directory(
      p.join(buildDir, FlutterBuild.artifactPathFor(BuildTarget.web, mode)),
    );
    if (!source.existsSync()) {
      return PackageOutcome.skipped(
        BuildTarget.web,
        'No web build found. Run `lattice build --target web --compile` first.',
      );
    }

    final archive = Archive();
    for (final entity in source.listSync(recursive: true)) {
      if (entity is! File) continue;
      final bytes = await entity.readAsBytes();
      archive.addFile(
        ArchiveFile(
          p.relative(entity.path, from: source.path),
          bytes.length,
          bytes,
        ),
      );
    }

    final encoded = ZipEncoder().encode(archive);
    final artifact = p.join(
      destination,
      '${config.packageName}-${config.semver}-web.zip',
    );
    await File(artifact).writeAsBytes(encoded);
    onLog?.call('zipped ${archive.length} file(s)');
    return PackageOutcome.success(BuildTarget.web, artifact);
  }
}
