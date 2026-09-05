import 'dart:io';

import 'package:lattice_core/lattice_core.dart';

/// Which targets this machine can actually build (§7.9, ADR-006).
///
/// Flutter can only build a desktop target on its own operating system. Rather
/// than let a user discover that by watching a build fail, unbuildable targets
/// are reported here with the reason, and the Build panel greys them out.
class Host {
  const Host._();

  static String get os {
    if (Platform.isLinux) return 'linux';
    if (Platform.isMacOS) return 'macos';
    if (Platform.isWindows) return 'windows';
    return Platform.operatingSystem;
  }

  static bool canBuild(BuildTarget target) => target.buildableOn.contains(os);

  static List<BuildTarget> buildable(Iterable<BuildTarget> targets) =>
      targets.where(canBuild).toList();

  static List<BuildTarget> notBuildable(Iterable<BuildTarget> targets) =>
      targets.where((t) => !canBuild(t)).toList();

  /// A sentence explaining why [target] is unavailable here, phrased as the
  /// next thing to do rather than as a failure.
  static String explain(BuildTarget target) {
    if (canBuild(target)) return 'Can be built on this machine.';
    final hosts = target.buildableOn.join(' or ');
    return '${target.id} must be built on $hosts. '
        'Push the repository and let .github/workflows/build.yml produce it.';
  }
}
