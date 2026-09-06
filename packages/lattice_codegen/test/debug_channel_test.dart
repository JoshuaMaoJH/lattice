import 'package:lattice_codegen/lattice_codegen.dart';
import 'package:lattice_core/lattice_core.dart';
import 'package:test/test.dart';

import 'support/fixtures.dart';

/// The generated half of R21's data-flow channel.
///
/// The editor's parser is tested on its own; what has to hold here is that the
/// two ends agree on the same line format. The literals below are the contract
/// — `DebugChannel` in the editor scans for exactly these.
void main() {
  late Map<String, String> files;

  setUpAll(() {
    final result = const LatticeGenerator().generate(counterProject());
    expect(result.isSuccess, isTrue, reason: result.diagnostics.join('\n'));
    files = result.files;
  });

  test('the channel file is emitted with the marker the editor scans for', () {
    final debug = files['lib/debug.dart']!;
    expect(debug, contains("static const marker = '__lattice__'"));
    expect(debug, contains("'node':"));
    expect(debug, contains("'value':"));
    expect(debug, contains("'event':"));
  });

  test('it compiles out of release builds', () {
    // Shipping an app must never print its state to a terminal.
    final debug = files['lib/debug.dart']!;
    expect(debug, contains('if (!kDebugMode) return;'));
  });

  test('a signal write reports itself, by node id', () {
    final page =
        files.entries.firstWhere((e) => e.key.endsWith('home_page.dart')).value;
    expect(page, contains("LatticeDebug.value('n_count', count.value)"));
    expect(page, contains("import '../debug.dart'"));
  });

  test('a page that writes nothing does not import the channel', () {
    final project = Project(
      id: 'p',
      config: const ProjectConfig(
        appName: 'Static',
        packageName: 'static_app',
        bundleId: 'com.example.static_app',
      ),
      pages: [
        Page(
          id: 'page_home',
          name: 'Home',
          route: '/',
          isHome: true,
          hierarchy: WidgetNode(id: 'w_root', type: 'Scaffold', children: [
            WidgetNode(
              id: 'w_t',
              type: 'Text',
              props: {'data': const LiteralProp('hi')},
            ),
          ]),
        ),
      ],
    );

    final result = const LatticeGenerator().generate(project);
    final page = result.files.entries
        .firstWhere((e) => e.key.endsWith('home_page.dart'))
        .value;
    expect(page, isNot(contains('debug.dart')));
  });
}
