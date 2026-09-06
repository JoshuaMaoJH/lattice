import 'dart:io';

import 'package:lattice_build/lattice_build.dart';
import 'package:lattice_core/lattice_core.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// What `lattice package` needs to exist before flutter_distributor will run
/// (§7.9 step 4).
void main() {
  _artifactNaming();
  late Directory output;

  const config = ProjectConfig(
    appName: 'Todos',
    packageName: 'todo_app',
    bundleId: 'com.example.todo_app',
    organization: 'com.example',
    description: 'A list you can tick off.',
  );

  setUp(() async {
    output = await Directory.systemTemp.createTemp('lattice_packaging_');
  });

  tearDown(() async {
    if (output.existsSync()) await output.delete(recursive: true);
  });

  File file(String relative) => File(p.join(output.path, relative));

  group('placeholder icon', () {
    test('is a valid PNG of the requested size', () async {
      final path = p.join(output.path, 'icon.png');
      expect(await const AppIcon().writePlaceholder(path, size: 64), isTrue);

      final bytes = await File(path).readAsBytes();
      expect(
        bytes.sublist(0, 8),
        [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A],
        reason: 'PNG signature',
      );
      // IHDR width and height, big-endian, right after the signature+length.
      final width = bytes.buffer.asByteData().getUint32(16);
      final height = bytes.buffer.asByteData().getUint32(20);
      expect([width, height], [64, 64]);
    });

    test('never overwrites a real icon someone put there', () async {
      final path = p.join(output.path, 'icon.png');
      await File(path).writeAsString('not really a png');

      expect(await const AppIcon().writePlaceholder(path), isFalse);
      expect(await File(path).readAsString(), 'not really a png');
    });
  });

  group('packaging config', () {
    test('writes what each Linux format asks for', () async {
      await const PackagingConfig()
          .write(output.path, config, [BuildTarget.linux]);

      expect(file('linux/packaging/appimage/make_config.yaml').existsSync(),
          isTrue);
      expect(file('linux/packaging/deb/make_config.yaml').existsSync(), isTrue);
      expect(file(PackagingConfig.iconPath).existsSync(), isTrue);
    });

    test('points at the icon the way the maker resolves it', () async {
      await const PackagingConfig()
          .write(output.path, config, [BuildTarget.linux]);

      // flutter_distributor does a plain File(icon) against the working
      // directory, which is the project root — not against the config file.
      expect(
        file('linux/packaging/appimage/make_config.yaml').readAsStringSync(),
        contains('icon: ${PackagingConfig.iconPath}'),
      );
    });

    test('carries the project metadata into the deb fields', () async {
      await const PackagingConfig()
          .write(output.path, config, [BuildTarget.linux]);
      final deb =
          file('linux/packaging/deb/make_config.yaml').readAsStringSync();

      expect(deb, contains("display_name: 'Todos'"));
      // Debian package names cannot contain underscores.
      expect(deb, contains("package_name: 'todo-app'"));
      expect(deb, contains("name: 'com.example'"));
    });

    test('leaves an edited config alone', () async {
      await const PackagingConfig()
          .write(output.path, config, [BuildTarget.linux]);
      final target = file('linux/packaging/deb/make_config.yaml');
      await target.writeAsString('# hand written\n');

      final second = await const PackagingConfig()
          .write(output.path, config, [BuildTarget.linux]);

      expect(second, isEmpty, reason: 'nothing left to write');
      expect(await target.readAsString(), '# hand written\n');
    });

    test('writes nothing for a target with no packaging formats', () async {
      final written = await const PackagingConfig()
          .write(output.path, config, [BuildTarget.web]);
      // Only the shared icon, which every project gets.
      expect(written, [PackagingConfig.iconPath]);
    });
  });
}

void _artifactNaming() {
  group('artifact naming', () {
    test('the platform is the segment before the extension', () {
      expect(
        Packager.belongsTo('todo_app-1.0.0+1-android.apk', BuildTarget.android),
        isTrue,
      );
      expect(
        Packager.belongsTo('todo_app-1.0.0+1-android.aab', BuildTarget.android),
        isTrue,
      );
      expect(
        Packager.belongsTo(
            'todo_app-1.0.0+1-linux.AppImage', BuildTarget.linux),
        isTrue,
      );
    });

    test('one dist directory holds every platform, so it must not overreach',
        () {
      // The same `dist/1.0.0+1/` accumulates yesterday's builds.
      expect(
        Packager.belongsTo('todo_app-1.0.0+1-android.apk', BuildTarget.linux),
        isFalse,
      );
      // A substring match would claim this one for android.
      expect(
        Packager.belongsTo(
            'my-android-app-1.0.0-linux.deb', BuildTarget.android),
        isFalse,
      );
    });
  });
}
