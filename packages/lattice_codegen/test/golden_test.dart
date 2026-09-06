import 'dart:io';

import 'package:lattice_codegen/lattice_codegen.dart';
import 'package:lattice_core/io.dart';
import 'package:test/test.dart';

import 'support/fixtures.dart';

/// Snapshot of the generated counter (§11, "golden test").
///
/// The point is not that this exact text is sacred — it is that a change to it
/// is always a deliberate act. Run with `-D update_goldens=true` (or
/// `UPDATE_GOLDENS=1`) to re-record after an intentional change, then read the
/// diff before committing it.
void main() {
  final updating = const bool.fromEnvironment('update_goldens') ||
      Platform.environment['UPDATE_GOLDENS'] == '1';

  final directory = Directory('test/goldens');

  void expectGolden(String name, String actual) {
    final file = File('${directory.path}/$name');
    if (updating || !file.existsSync()) {
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(actual);
      if (!updating) {
        // Recording a brand new golden is fine; silently passing a changed one
        // is not.
        printOnFailure('Recorded new golden ${file.path}');
      }
      return;
    }
    expect(
      actual,
      file.readAsStringSync(),
      reason: 'Generated output changed. If that was intended, re-run with '
          'UPDATE_GOLDENS=1 and review the diff.',
    );
  }

  test('counter project generates the expected files', () {
    final result = const LatticeGenerator().generate(counterProject());
    expect(result.isSuccess, isTrue, reason: result.diagnostics.join('\n'));

    expect(
      result.files.keys.toSet(),
      {
        'lib/pages/home_page.dart',
        'lib/main.dart',
        'pubspec.yaml',
        'analysis_options.yaml',
        'README.md',
        '.gitignore',
        '.github/workflows/build.yml',
        // R22: the release matrix is a second workflow — build.yml answers
        // "does main still compile", this one cuts a release.
        '.github/workflows/release.yml',
        'distribute_options.yaml',
      },
    );

    expectGolden('counter_home_page.dart.txt',
        result.files['lib/pages/home_page.dart']!);
    expectGolden('counter_main.dart.txt', result.files['lib/main.dart']!);
    expectGolden('counter_pubspec.yaml.txt', result.files['pubspec.yaml']!);
  });

  test('the todo example generates the expected page', () async {
    // Loaded from the shipped example rather than an inline fixture, so this
    // golden covers exactly what a reader sees in examples/todo.
    final project = await ProjectIo.load('../../examples/todo');
    final result = const LatticeGenerator().generate(project);
    expect(result.isSuccess, isTrue, reason: result.diagnostics.join('\n'));

    expectGolden(
      'todo_home_page.dart.txt',
      result.files['lib/pages/home_page.dart']!,
    );
    expectGolden(
      'todo_detail_page.dart.txt',
      result.files['lib/pages/detail_page.dart']!,
    );
    expectGolden(
      'todo_stat_card.dart.txt',
      result.files['lib/prefabs/stat_card.dart']!,
    );
    expectGolden('todo_main.dart.txt', result.files['lib/main.dart']!);
  });

  test('the weather example generates the expected page', () async {
    final project = await ProjectIo.load('../../examples/weather');
    final result = const LatticeGenerator().generate(project);
    expect(result.isSuccess, isTrue, reason: result.diagnostics.join('\n'));

    expectGolden(
      'weather_home_page.dart.txt',
      result.files['lib/pages/home_page.dart']!,
    );
    expectGolden('weather_models.dart.txt', result.files['lib/models.dart']!);
  });

  test('models generate immutable classes with JSON codecs', () {
    // Goes through the generator rather than the emitter directly, so the
    // golden is exactly what lands on disk — formatted.
    final project =
        counterProject().copyWith(models: [DataModelDefFixture.todo]);
    final result = const LatticeGenerator().generate(project);
    expect(result.isSuccess, isTrue, reason: result.diagnostics.join('\n'));
    expectGolden('todo_model.dart.txt', result.files['lib/models.dart']!);
  });
}
