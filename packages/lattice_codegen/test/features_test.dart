import 'package:lattice_codegen/lattice_codegen.dart';
import 'package:lattice_core/lattice_core.dart';
import 'package:test/test.dart';

/// Asserts against the shipped examples rather than inline fixtures.
///
/// These are the projects a reader opens first, so if a feature regresses the
/// example is where it matters, and a test that reads the example cannot drift
/// away from it.
void main() {
  late Project todo;
  late Project weather;

  setUpAll(() async {
    todo = await ProjectIo.load('../../examples/todo');
    weather = await ProjectIo.load('../../examples/weather');
  });

  Map<String, String> generate(Project project) {
    final result = const LatticeGenerator().generate(project);
    expect(result.isSuccess, isTrue, reason: result.diagnostics.join('\n'));
    return {
      for (final entry in result.files.entries)
        entry.key: entry.value.replaceAll(RegExp(r'\s+'), ' '),
    };
  }

  group('both examples validate clean', () {
    test('todo', () {
      final result = const Validator().validate(todo);
      expect(result.isValid, isTrue, reason: result.toString());
      expect(result.diagnostics, isEmpty);
    });

    test('weather', () {
      final result = const Validator().validate(weather);
      expect(result.isValid, isTrue, reason: result.toString());
      expect(result.diagnostics, isEmpty);
    });
  });

  group('TextField controller binding', () {
    test('allocates, seeds, syncs and disposes the controller', () {
      final page = generate(todo)['lib/pages/home_page.dart']!;
      expect(
          page, contains('late final TextEditingController _inputController'));
      expect(
          page,
          contains(
              '_inputController = TextEditingController(text: draft.value)'));
      expect(page, contains('_inputController.dispose()'));
      // The guard is what stops a rebuild from resetting the cursor.
      expect(page, contains('if (_inputController.text != next)'));
    });

    test('passes the controller rather than a value', () {
      expect(
        generate(todo)['lib/pages/home_page.dart'],
        contains('controller: _inputController'),
      );
    });

    test('a controller-bound field is not wrapped in a rebuild boundary', () {
      // One boundary on the page, and it is not around the TextField.
      final page = generate(todo)['lib/pages/home_page.dart']!;
      expect('SignalBuilder'.allMatches(page).length, 1);
    });
  });

  group('Dart Code and lib/custom (R11)', () {
    test('imports the hand-written file the node asked for', () {
      expect(
        generate(todo)['lib/pages/home_page.dart'],
        contains("import '../custom/labels.dart'"),
      );
    });

    test('calls into it from the generated helper', () {
      expect(
        generate(todo)['lib/pages/home_page.dart'],
        contains('return decorate(item.title, done: item.done);'),
      );
    });
  });

  group('pages and navigation (R12)', () {
    test('a parameterised page becomes constructor arguments', () {
      final detail = generate(todo)['lib/pages/detail_page.dart']!;
      expect(detail, contains('required this.title'));
      // A non-nullable optional parameter is only legal with a default.
      expect(detail, contains('this.done = false'));
      expect(detail, contains('final String title;'));
    });

    test('a stateless page reads its parameters directly', () {
      // `widget.x` would not compile outside a State.
      final detail = generate(todo)['lib/pages/detail_page.dart']!;
      expect(detail, contains("Text(done ? 'Done' : 'Still to do')"));
      expect(detail, isNot(contains('widget.')));
    });

    test('the route table unpacks navigation arguments', () {
      final main = generate(todo)['lib/main.dart']!;
      expect(main, contains('ModalRoute.of(context)!.settings.arguments'));
      expect(main, contains("title: arguments['title']! as String"));
      expect(
        main,
        contains(
            "done: arguments['done'] == null ? false : arguments['done'] as bool"),
      );
    });

    test('Navigate passes one argument per declared parameter', () {
      expect(
        generate(todo)['lib/pages/home_page.dart'],
        contains("Navigator.of(context).pushNamed( '/detail', arguments: "
            "{'title': _rawTitleOf(item), 'done': _doneOf(item)}, )"),
      );
    });
  });

  group('HTTP (R13)', () {
    test('the handler becomes async and guards its states', () {
      final page = generate(weather)['lib/pages/home_page.dart']!;
      expect(page, contains('Future<void> _onFetchPressed() async'));
      expect(page, contains('loading.value = true;'));
      expect(page, contains('await http.get(Uri.parse(_urlFor(city.value)))'));
      expect(page, contains('} finally { loading.value = false; }'));
    });

    test('decodes the body into the target signal\'s model', () {
      expect(
        generate(weather)['lib/pages/home_page.dart'],
        contains(
            'forecast.value = Forecast.fromJson( jsonDecode(response.body) as Map<String, Object?>, )'),
      );
    });

    test('adds the http dependency only where it is used', () {
      expect(generate(weather)['pubspec.yaml'], contains('http: ^1.2.0'));
      expect(generate(todo)['pubspec.yaml'], isNot(contains('http:')));
    });

    test('honours a field\'s JSON key', () {
      final models = generate(weather)['lib/models.dart']!;
      expect(models, contains("json['current_weather']"));
      expect(models, contains('final CurrentWeather currentWeather;'));
    });
  });

  group('Prefab (R9)', () {
    test('compiles to its own widget class', () {
      final files = generate(todo);
      expect(files.containsKey('lib/prefabs/stat_card.dart'), isTrue);
      expect(
        files['lib/prefabs/stat_card.dart'],
        contains('class StatCard extends StatelessWidget'),
      );
    });

    test('exposes its parameters as constructor arguments', () {
      final card = generate(todo)['lib/prefabs/stat_card.dart']!;
      expect(card, contains('required this.label'));
      expect(card, contains('required this.value'));
      expect(card, contains('this.accent'));
      expect(card, contains('final Color? accent;'));
    });

    test('is placed by name, three times, from one definition', () {
      final page = generate(todo)['lib/pages/home_page.dart']!;
      expect('StatCard('.allMatches(page).length, 3);
      expect(page, contains("import '../prefabs/stat_card.dart'"));
    });
  });

  group('packaging configuration (R16)', () {
    test('emits a distributor configuration covering each target', () {
      final options = generate(todo)['distribute_options.yaml']!;
      for (final job in [
        'release-linux-appimage',
        'release-android-apk',
        'release-web-zip'
      ]) {
        expect(options, contains(job), reason: job);
      }
    });
  });
}
