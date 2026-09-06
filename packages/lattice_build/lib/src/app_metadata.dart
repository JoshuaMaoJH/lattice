import 'dart:io';

import 'package:lattice_core/lattice_core.dart';
import 'package:path/path.dart' as p;

/// Step 2 of §7.9: push the project's application metadata into the per
/// platform configuration files that `flutter create` scaffolded.
///
/// These are the files a user would otherwise have to learn one at a time —
/// which is exactly the friction Lattice is meant to remove.
class AppMetadata {
  const AppMetadata();

  /// Applies [config] to whichever platform directories exist. Returns the
  /// files that changed.
  Future<List<String>> apply(String projectDir, ProjectConfig config) async {
    final changed = <String>[];

    Future<void> edit(
        String relative, String Function(String) transform) async {
      final file = File(p.join(projectDir, relative));
      if (!file.existsSync()) return;
      final before = await file.readAsString();
      final after = transform(before);
      if (after != before) {
        await file.writeAsString(after);
        changed.add(relative);
      }
    }

    await edit('linux/CMakeLists.txt', (s) => _linuxCMake(s, config));
    await edit('web/index.html', (s) => _webIndex(s, config));
    await edit('web/manifest.json', (s) => _webManifest(s, config));
    await edit(
      'android/app/src/main/AndroidManifest.xml',
      (s) => _androidManifest(s, config),
    );
    await edit(
      'android/app/build.gradle.kts',
      (s) => _androidGradle(s, config),
    );
    await edit('macos/Runner/Configs/AppInfo.xcconfig',
        (s) => _macosAppInfo(s, config));
    await edit('windows/CMakeLists.txt', (s) => _windowsCMake(s, config));

    return changed;
  }

  String _linuxCMake(String source, ProjectConfig config) => source
      .replaceAll(
        RegExp(r'set\(BINARY_NAME "[^"]*"\)'),
        'set(BINARY_NAME "${config.packageName}")',
      )
      .replaceAll(
        RegExp(r'set\(APPLICATION_ID "[^"]*"\)'),
        'set(APPLICATION_ID "${config.bundleId}")',
      );

  String _windowsCMake(String source, ProjectConfig config) =>
      source.replaceAll(
        RegExp(r'set\(BINARY_NAME "[^"]*"\)'),
        'set(BINARY_NAME "${config.packageName}")',
      );

  String _webIndex(String source, ProjectConfig config) => source
      .replaceAll(
        RegExp(r'<title>[^<]*</title>'),
        '<title>${_escapeHtml(config.appName)}</title>',
      )
      .replaceAll(
        RegExp(r'<meta name="apple-mobile-web-app-title" content="[^"]*">'),
        '<meta name="apple-mobile-web-app-title" '
        'content="${_escapeHtml(config.appName)}">',
      );

  String _webManifest(String source, ProjectConfig config) => source
      .replaceAll(
        RegExp(r'"name":\s*"[^"]*"'),
        '"name": "${_escapeJson(config.appName)}"',
      )
      .replaceAll(
        RegExp(r'"short_name":\s*"[^"]*"'),
        '"short_name": "${_escapeJson(config.appName)}"',
      )
      .replaceAll(
        RegExp(r'"description":\s*"[^"]*"'),
        '"description": "${_escapeJson(config.description)}"',
      );

  String _androidManifest(String source, ProjectConfig config) =>
      source.replaceAll(
        RegExp(r'android:label="[^"]*"'),
        'android:label="${_escapeXml(config.appName)}"',
      );

  /// Marks the signing block as already injected. `flutter create` runs once
  /// but this runs on every build, so the edit has to be idempotent.
  static const _signingMarker = '// lattice:signing';

  /// Two edits.
  ///
  /// `applicationId` — the identity the app ships under, the Android
  /// counterpart of macOS's `PRODUCT_BUNDLE_IDENTIFIER`. `namespace` is left
  /// alone: it names the package the Kotlin sources actually declare, and the
  /// manifest's `.MainActivity` resolves against it.
  ///
  /// The release signing config — §7.9 says credentials never enter project
  /// files, so the keystore is read from the environment at build time. With
  /// no keystore set this stays on Flutter's debug key, which is what makes
  /// `lattice package -t android` work without any setup at all.
  String _androidGradle(String source, ProjectConfig config) {
    var out = source.replaceAll(
      RegExp(r'applicationId = "[^"]*"'),
      'applicationId = "${config.bundleId}"',
    );
    if (out.contains(_signingMarker)) return out;

    out = out.replaceFirst(
      RegExp(r'^android \{', multiLine: true),
      '$_signingMarker\n'
      'val latticeKeystore: String? = System.getenv("LATTICE_ANDROID_KEYSTORE")\n'
      '\n'
      'android {\n'
      '    signingConfigs {\n'
      '        if (latticeKeystore != null) {\n'
      '            create("release") {\n'
      '                storeFile = file(latticeKeystore)\n'
      '                storePassword = '
      'System.getenv("LATTICE_ANDROID_STORE_PASSWORD")\n'
      '                keyAlias = System.getenv("LATTICE_ANDROID_KEY_ALIAS")\n'
      '                keyPassword = '
      'System.getenv("LATTICE_ANDROID_KEY_PASSWORD")\n'
      '            }\n'
      '        }\n'
      '    }\n',
    );

    return out.replaceFirst(
      RegExp(
        r'// TODO: Add your own signing config[^\n]*\n'
        r'\s*// Signing with the debug keys[^\n]*\n'
        r'\s*signingConfig = signingConfigs\.getByName\("debug"\)',
      ),
      'signingConfig = if (latticeKeystore != null) {\n'
      '                signingConfigs.getByName("release")\n'
      '            } else {\n'
      '                // No keystore in the environment: Flutter\'s debug key,\n'
      '                // so a release build still produces an installable apk.\n'
      '                signingConfigs.getByName("debug")\n'
      '            }',
    );
  }

  String _macosAppInfo(String source, ProjectConfig config) => source
      .replaceAll(
        RegExp(r'PRODUCT_NAME = .*'),
        'PRODUCT_NAME = ${config.appName}',
      )
      .replaceAll(
        RegExp(r'PRODUCT_BUNDLE_IDENTIFIER = .*'),
        'PRODUCT_BUNDLE_IDENTIFIER = ${config.bundleId}',
      );

  static String _escapeHtml(String value) => value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;');

  static String _escapeXml(String value) =>
      _escapeHtml(value).replaceAll('"', '&quot;');

  static String _escapeJson(String value) =>
      value.replaceAll(r'\', r'\\').replaceAll('"', r'\"');
}
