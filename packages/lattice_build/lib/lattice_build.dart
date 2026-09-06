/// Platform configuration, build and packaging orchestration (§7.9).
///
/// The editor's Build panel and the `lattice build` command are both front
/// ends over this package, so a GUI build and a CLI build cannot drift.
library;

export 'src/app_icon.dart';
export 'src/app_metadata.dart';
export 'src/flutter_build.dart';
export 'src/host.dart';
export 'src/packager.dart';
export 'src/packaging_config.dart';
export 'src/platform_scaffolder.dart';
export 'src/signing.dart';
