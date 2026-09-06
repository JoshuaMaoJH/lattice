import 'package:lattice_build/lattice_build.dart';
import 'package:lattice_core/lattice_core.dart';
import 'package:test/test.dart';

void main() {
  test('linux and web are not code-signed, so they ask for nothing', () {
    expect(Signing.requirementsFor(BuildTarget.linux), isEmpty);
    expect(Signing.requirementsFor(BuildTarget.web), isEmpty);
    expect(Signing.isReady(BuildTarget.linux, environment: const {}), isTrue);
  });

  test('an unset variable is missing, not ready', () {
    final status =
        Signing.statusFor(BuildTarget.android, environment: const {});

    expect(status, hasLength(4));
    expect(status.every((s) => s.state == CredentialState.missing), isTrue);
    expect(
        Signing.isReady(BuildTarget.android, environment: const {}), isFalse);
  });

  test('a variable set to whitespace is missing, not ready', () {
    final status = Signing.statusFor(
      BuildTarget.android,
      environment: const {'LATTICE_ANDROID_KEY_ALIAS': '   '},
      fileExists: (_) => true,
    );

    final alias = status.firstWhere(
        (s) => s.credential.variable == 'LATTICE_ANDROID_KEY_ALIAS');
    expect(alias.state, CredentialState.missing);
  });

  test('a keystore path that is not there is its own state', () {
    // Distinct from "missing" because the fix is different: one is "set this",
    // the other is "you moved the file".
    final status = Signing.statusFor(
      BuildTarget.android,
      environment: const {
        'LATTICE_ANDROID_KEYSTORE': '/gone/upload.jks',
        'LATTICE_ANDROID_KEY_ALIAS': 'upload',
        'LATTICE_ANDROID_STORE_PASSWORD': 'x',
        'LATTICE_ANDROID_KEY_PASSWORD': 'x',
      },
      fileExists: (path) => false,
    );

    final keystore = status
        .firstWhere((s) => s.credential.variable == 'LATTICE_ANDROID_KEYSTORE');
    expect(keystore.state, CredentialState.danglingPath);
    expect(
        Signing.isReady(BuildTarget.android, environment: const {}), isFalse);
  });

  test('everything present reads as ready', () {
    final status = Signing.statusFor(
      BuildTarget.android,
      environment: const {
        'LATTICE_ANDROID_KEYSTORE': '/keys/upload.jks',
        'LATTICE_ANDROID_KEY_ALIAS': 'upload',
        'LATTICE_ANDROID_STORE_PASSWORD': 'x',
        'LATTICE_ANDROID_KEY_PASSWORD': 'x',
      },
      fileExists: (_) => true,
    );

    expect(status.every((s) => s.isReady), isTrue);
  });

  test('the requirements never carry a value, only a variable name', () {
    // The whole point of §7.9: this module reports presence and nothing else,
    // so a screenshot of the wizard leaks nothing.
    for (final target in BuildTarget.values) {
      for (final credential in Signing.requirementsFor(target)) {
        expect(credential.variable, startsWith('LATTICE_'));
        expect(credential.what, isNotEmpty);
      }
    }
  });
}
