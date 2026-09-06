import 'dart:io';

import 'package:lattice_build/lattice_build.dart';
import 'package:lattice_core/lattice_core.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory dir;

  setUp(() => dir = Directory.systemTemp.createTempSync('lattice_metadata'));
  tearDown(() => dir.deleteSync(recursive: true));

  void write(String relative, String contents) {
    final file = File(p.join(dir.path, relative));
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(contents);
  }

  String read(String relative) =>
      File(p.join(dir.path, relative)).readAsStringSync();

  // What `flutter create --org com.example` leaves behind for a project named
  // `todo_app`: both identifiers derived from the org, neither from bundleId.
  const gradle = '''
android {
    namespace = "com.example.todo_app"
    defaultConfig {
        applicationId = "com.example.todo_app"
        minSdk = flutter.minSdkVersion
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}
''';

  const config = ProjectConfig(
    appName: 'Todos',
    packageName: 'todo_app',
    organization: 'com.example',
    bundleId: 'com.acme.todos',
  );

  test('applicationId comes from bundleId, namespace is left alone', () async {
    write('android/app/build.gradle.kts', gradle);

    final changed = await const AppMetadata().apply(dir.path, config);

    expect(changed, contains('android/app/build.gradle.kts'));
    final after = read('android/app/build.gradle.kts');
    expect(after, contains('applicationId = "com.acme.todos"'));
    // The Kotlin sources declare this package and the manifest's
    // `.MainActivity` resolves against it; rewriting it would break the build.
    expect(after, contains('namespace = "com.example.todo_app"'));
  });

  test('android label comes from appName', () async {
    write(
      'android/app/src/main/AndroidManifest.xml',
      '<application android:label="todo_app" />',
    );

    await const AppMetadata().apply(dir.path, config);

    expect(
      read('android/app/src/main/AndroidManifest.xml'),
      contains('android:label="Todos"'),
    );
  });

  test('a platform that was never scaffolded is skipped, not created',
      () async {
    final changed = await const AppMetadata().apply(dir.path, config);

    expect(changed, isEmpty);
    expect(Directory(p.join(dir.path, 'android')).existsSync(), isFalse);
  });

  test('the release signing config reads the keystore from the environment',
      () async {
    write('android/app/build.gradle.kts', gradle);

    await const AppMetadata().apply(dir.path, config);

    final after = read('android/app/build.gradle.kts');
    // §7.9: the path is read at build time, never written into the project.
    expect(after, contains('System.getenv("LATTICE_ANDROID_KEYSTORE")'));
    expect(after, contains('storeFile = file(latticeKeystore)'));
    // With nothing in the environment a release build must still work.
    expect(after, contains('signingConfigs.getByName("debug")'));
    expect(after, isNot(contains('TODO: Add your own signing config')));
  });

  test('re-applying does not inject the signing block twice', () async {
    write('android/app/build.gradle.kts', gradle);

    await const AppMetadata().apply(dir.path, config);
    final once = read('android/app/build.gradle.kts');
    final changed = await const AppMetadata().apply(dir.path, config);

    expect(changed, isEmpty);
    expect(read('android/app/build.gradle.kts'), once);
  });
}
