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
