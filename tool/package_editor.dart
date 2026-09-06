// Packages the editor itself with Lattice's own packaging code.
//
// The editor is a plain Flutter app, not a Lattice project, so nothing
// generates its packaging config. Everything it needs — make_config.yaml per
// format, an icon, the app metadata — is the same thing `lattice package`
// writes for a generated project, so this hands the editor to the same code
// rather than keeping a second hand-maintained copy of those files.
//
//   dart run tool/package_editor.dart
import 'dart:io';

import 'package:lattice_build/lattice_build.dart';
import 'package:lattice_core/lattice_core.dart';

Future<void> main() async {
  const projectDir = 'apps/lattice_editor';

  const config = ProjectConfig(
    appName: 'Lattice',
    packageName: 'lattice_editor',
    organization: 'com.lattice',
    bundleId: 'com.lattice.editor',
    description: 'Draw a Flutter app as a node graph; read the Dart it emits.',
    version: '0.1.0+1',
    targets: [BuildTarget.linux],
  );

  final metadata = await const AppMetadata().apply(projectDir, config);
  stdout.writeln('metadata: ${metadata.join(', ')}');

  final packaging = await const PackagingConfig()
      .write(projectDir, config, const [BuildTarget.linux]);
  stdout.writeln('packaging: ${packaging.join(', ')}');

  final built = await const FlutterBuild().build(
    projectDir,
    BuildTarget.linux,
    onLog: stdout.writeln,
  );
  if (!built.isSuccess) {
    stderr.writeln('flutter build linux failed.');
    exit(1);
  }

  final outcome = await const Packager().package(
    projectDir,
    projectDir,
    config,
    BuildTarget.linux,
    onLog: stdout.writeln,
  );
  if (!outcome.isSuccess) {
    stderr.writeln(outcome.skippedBecause);
    exit(1);
  }
  stdout.writeln('-> ${outcome.artifact}');
}
