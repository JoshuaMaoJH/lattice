import 'dart:io';

import 'package:lattice_server_gen/io.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// Which hand-written files reach the server, and which must not (§7.8).
void main() {
  late Directory root;
  late Directory output;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('lattice_custom_');
    output = Directory(p.join(root.path, 'out'));
    await Directory(p.join(root.path, 'custom')).create(recursive: true);
  });

  tearDown(() async {
    if (root.existsSync()) await root.delete(recursive: true);
  });

  Future<void> write(String relative, String contents) async {
    final file = File(p.join(root.path, relative));
    await file.parent.create(recursive: true);
    await file.writeAsString(contents);
  }

  File mirrored(String name) =>
      File(p.join(output.path, 'lib', 'custom', name));

  test('copies the file a server function imports', () async {
    await write('custom/pricing.dart', 'double price() => 1;');
    await write('custom/unused.dart', 'double other() => 2;');

    final problems = await const ServerCustomMirror()
        .mirror(root.path, output.path, ['custom/pricing.dart']);

    expect(problems, isEmpty);
    expect(mirrored('pricing.dart').existsSync(), isTrue);
    // The client's other helpers are none of the server's business.
    expect(mirrored('unused.dart').existsSync(), isFalse);
  });

  test('follows relative imports, so a helper need not be declared', () async {
    await write('custom/pricing.dart', """
import 'tiers.dart';

double price() => tier();
""");
    await write('custom/tiers.dart', 'double tier() => 3;');

    final problems = await const ServerCustomMirror()
        .mirror(root.path, output.path, ['custom/pricing.dart']);

    expect(problems, isEmpty);
    expect(mirrored('tiers.dart').existsSync(), isTrue);
  });

  test('refuses a file that needs Flutter', () async {
    await write('custom/widgets.dart', """
import 'package:flutter/material.dart';

Color brand() => Colors.blue;
""");

    final problems = await const ServerCustomMirror()
        .mirror(root.path, output.path, ['custom/widgets.dart']);

    expect(problems.map((d) => d.code), contains('flutter_on_server'));
    expect(
      problems.single.message,
      contains('cannot run on a server'),
      reason: 'the message has to say what to do about it',
    );
    expect(mirrored('widgets.dart').existsSync(), isFalse);
  });

  test('names a file that is not there', () async {
    final problems = await const ServerCustomMirror()
        .mirror(root.path, output.path, ['custom/gone.dart']);
    expect(problems.map((d) => d.code), contains('missing_custom_file'));
  });

  test('drops a file the server stopped importing', () async {
    await write('custom/a.dart', 'int a() => 1;');
    await write('custom/b.dart', 'int b() => 2;');

    await const ServerCustomMirror().mirror(
      root.path,
      output.path,
      ['custom/a.dart', 'custom/b.dart'],
    );
    expect(mirrored('b.dart').existsSync(), isTrue);

    await const ServerCustomMirror()
        .mirror(root.path, output.path, ['custom/a.dart']);
    expect(
      mirrored('b.dart').existsSync(),
      isFalse,
      reason: 'a stale helper would keep compiling long after it was dropped',
    );
  });
}
