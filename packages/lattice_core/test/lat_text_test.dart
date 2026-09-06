import 'package:lattice_core/io.dart';
import 'package:lattice_core/lattice_core.dart';
import 'package:test/test.dart';

/// R18's acceptance: every shipped unit survives a trip through text.
///
/// Round-trip against the real examples rather than inline fixtures, because
/// the format has to carry whatever the examples actually contain — nested
/// slots, widget lists, expressions, canvas positions — not whatever a
/// fixture author remembered.
void main() {
  const writer = LatWriter();
  const reader = LatReader();

  GraphUnit roundTrip(GraphUnit unit) => reader.read(writer.write(unit));

  late List<Project> projects;

  setUpAll(() async {
    projects = [
      for (final name in ['counter', 'todo', 'weather', 'signup', 'quote'])
        await ProjectIo.load('../../examples/$name'),
    ];
  });

  test('every page round-trips to an identical page', () {
    for (final project in projects) {
      for (final page in project.pages) {
        final back = roundTrip(page) as Page;
        expect(back.id, page.id, reason: page.id);
        expect(back.name, page.name, reason: page.id);
        expect(back.route, page.route, reason: page.id);
        expect(back.isHome, page.isHome, reason: page.id);
        expect(back.hierarchy, page.hierarchy, reason: page.id);
        expect(back.graph.nodes, page.graph.nodes, reason: page.id);
        expect(back.graph.edges, page.graph.edges, reason: page.id);
        expect(back.layout, page.layout, reason: page.id);
        expect(back.parameters, page.parameters, reason: page.id);
      }
    }
  });

  test('every prefab round-trips', () {
    var seen = 0;
    for (final project in projects) {
      for (final prefab in project.prefabs) {
        seen++;
        final back = roundTrip(prefab) as Prefab;
        expect(back.name, prefab.name);
        expect(back.hierarchy, prefab.hierarchy);
        expect(back.parameters, prefab.parameters);
        expect(back.graph.edges, prefab.graph.edges);
      }
    }
    expect(seen, greaterThan(0), reason: 'no prefab was exercised');
  });

  test('every server function round-trips', () {
    var seen = 0;
    for (final project in projects) {
      for (final function in project.serverFunctions) {
        seen++;
        final back = roundTrip(function) as ServerFunction;
        expect(back.name, function.name);
        expect(back.returns, function.returns);
        expect(back.parameters, function.parameters);
        expect(back.graph.nodes, function.graph.nodes);
      }
    }
    expect(seen, greaterThan(0), reason: 'no server function was exercised');
  });

  test('a written page reads the way a person would write it', () {
    final counter = projects.first.pages.first;
    final text = writer.write(counter);

    expect(text, startsWith('page Home #page_home route "/" home'));
    // Bindings, events and nesting each have one obvious spelling.
    expect(text, contains('data=<n_fmt.out'));
    expect(text, contains('onPressed=!ev_btn'));
    expect(text, contains('title: Text #w_title data="Counter"'));
    expect(text, contains('n_count.value -> n_fmt.args[0]'));
  });

  group('errors say where', () {
    test('an unknown section', () {
      expect(
        () => reader.read('page Home #p route "/"\n  nonsense\n'),
        throwsA(
            isA<LatFormatException>().having((e) => e.path, 'path', 'line 2')),
      );
    });

    test('a malformed wire', () {
      expect(
        () => reader.read(
          'page Home #p route "/"\n'
          '  hierarchy\n'
          '    Scaffold #w\n'
          '  wires\n'
          '    n_a.out n_b.in\n',
        ),
        throwsA(
            isA<LatFormatException>().having((e) => e.path, 'path', 'line 5')),
      );
    });

    test('a value that is not a value', () {
      expect(
        () => reader.read(
          'page Home #p route "/"\n'
          '  hierarchy\n'
          '    Text #w data=unquoted\n',
        ),
        throwsA(isA<LatFormatException>()),
      );
    });
  });
}
