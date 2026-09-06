import 'dart:io';

import 'package:lattice_core/lattice_core.dart';

/// One credential a signed build needs.
final class Credential {
  const Credential({
    required this.variable,
    required this.what,
    this.isFile = false,
  });

  /// The environment variable the build reads it from.
  final String variable;

  /// What to put there, in one line.
  final String what;

  /// Whether the value is a path, so "set but missing" is a distinct state
  /// from "not set" — a stale path is the failure that wastes the most time.
  final bool isFile;
}

/// Whether one credential is ready on this machine.
enum CredentialState {
  /// The variable is not set.
  missing,

  /// Set, and if it names a file that file is there.
  ready,

  /// Set to a path that does not exist.
  danglingPath,
}

final class CredentialStatus {
  const CredentialStatus(this.credential, this.state);

  final Credential credential;
  final CredentialState state;

  bool get isReady => state == CredentialState.ready;
}

/// What signing each target needs, and whether this machine has it (R22).
///
/// §7.9's rule is that credentials never enter project files, which means the
/// only place to look is the environment — and the only thing worth reporting
/// is *presence*. Nothing here reads a value.
class Signing {
  const Signing();

  /// The credentials [target] needs, or empty when signing does not apply.
  static List<Credential> requirementsFor(BuildTarget target) =>
      switch (target) {
        BuildTarget.android => const [
            Credential(
              variable: 'LATTICE_ANDROID_KEYSTORE',
              what: 'Path to the .jks keystore. Back it up: losing it means '
                  'never updating this app on Play again.',
              isFile: true,
            ),
            Credential(
              variable: 'LATTICE_ANDROID_KEY_ALIAS',
              what: 'The key alias inside the keystore, e.g. "upload".',
            ),
            Credential(
              variable: 'LATTICE_ANDROID_STORE_PASSWORD',
              what: 'Password for the keystore file.',
            ),
            Credential(
              variable: 'LATTICE_ANDROID_KEY_PASSWORD',
              what: 'Password for the key itself.',
            ),
          ],
        BuildTarget.macos || BuildTarget.ios => const [
            Credential(
              variable: 'LATTICE_APPLE_IDENTITY',
              what: 'Signing identity, e.g. "Developer ID Application: You".',
            ),
            Credential(
              variable: 'LATTICE_APPLE_ID',
              what: 'The Apple ID used for notarisation.',
            ),
            Credential(
              variable: 'LATTICE_APPLE_TEAM_ID',
              what: 'Your ten-character team id.',
            ),
            Credential(
              variable: 'LATTICE_APPLE_APP_PASSWORD',
              what: 'An app-specific password, not your Apple ID password.',
            ),
          ],
        BuildTarget.windows => const [
            Credential(
              variable: 'LATTICE_WINDOWS_CERTIFICATE',
              what: 'Path to the .pfx code-signing certificate.',
              isFile: true,
            ),
            Credential(
              variable: 'LATTICE_WINDOWS_CERTIFICATE_PASSWORD',
              what: 'Password for the .pfx.',
            ),
          ],
        // Linux packages and web bundles are not code-signed; distribution
        // trust comes from the repository or the host, not from the file.
        BuildTarget.linux || BuildTarget.web => const [],
      };

  /// Reads presence only, from [environment] (defaulting to this process's).
  static List<CredentialStatus> statusFor(
    BuildTarget target, {
    Map<String, String>? environment,
    bool Function(String path)? fileExists,
  }) {
    final env = environment ?? Platform.environment;
    final exists = fileExists ?? (path) => File(path).existsSync();
    return [
      for (final credential in requirementsFor(target))
        CredentialStatus(
          credential,
          switch (env[credential.variable]) {
            null => CredentialState.missing,
            final value when value.trim().isEmpty => CredentialState.missing,
            final value when credential.isFile && !exists(value) =>
              CredentialState.danglingPath,
            _ => CredentialState.ready,
          },
        ),
    ];
  }

  /// Whether a signed build of [target] can go ahead here.
  static bool isReady(BuildTarget target, {Map<String, String>? environment}) =>
      statusFor(target, environment: environment).every((s) => s.isReady);
}
