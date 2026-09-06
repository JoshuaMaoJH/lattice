import 'package:lattice_codegen/lattice_codegen.dart';
import 'package:lattice_core/io.dart';
import 'package:lattice_core/lattice_core.dart';
import 'package:test/test.dart';

/// R19, against the shipped example rather than a fixture.
void main() {
  late Project notes;
  late Map<String, String> files;

  setUpAll(() async {
    notes = await ProjectIo.load('../../examples/notes');
    final result = const LatticeGenerator().generate(notes);
    expect(result.isSuccess, isTrue, reason: result.diagnostics.join('\n'));
    files = result.files;
  });

  test('the example validates clean', () {
    final result = const Validator().validate(notes);
    expect(result.diagnostics, isEmpty, reason: result.toString());
  });

  test('one declaration becomes one typed collection', () {
    final collections = files['lib/collections.dart']!;
    expect(collections, contains('LatticeCollection<Note>('));
    expect(collections, contains('decode: Note.fromJson'));
    expect(collections, contains("key: 'notes'"));
  });

  test('storage is chosen by platform, not by a package', () {
    expect(
      files['lib/store.dart'],
      contains("if (dart.library.js_interop) 'store_web.dart'"),
    );
    expect(files['lib/store_io.dart'], contains('dart:io'));
    expect(files['lib/store_web.dart'], contains('localStorage'));
  });

  test('main waits for storage before the first frame', () {
    // Rendering empty and then jumping reads as data loss.
    final app = files['lib/app.dart'] ?? files['lib/main.dart']!;
    expect(app, contains('await loadCollections()'));
    expect(app, contains('WidgetsFlutterBinding.ensureInitialized()'));
  });

  test('reads are reactive, writes are awaited', () {
    final page =
        files.entries.firstWhere((e) => e.key.endsWith('home_page.dart')).value;
    expect(page, contains('notes.items.value'));
    expect(page, contains('await notes.add('));
    expect(page, contains('await notes.removeAt('));
    // A collection read is a signal read, so the list rebuilds itself.
    expect(page, contains('SignalBuilder'));
  });

  group('validation', () {
    Project withCollection(CollectionDef collection,
            {List<DataModelDef> models = const []}) =>
        Project(
          id: 'p',
          config: const ProjectConfig(
            appName: 'C',
            packageName: 'c_app',
            bundleId: 'com.example.c_app',
          ),
          models: models,
          collections: [collection],
          pages: [
            Page(
              id: 'page_home',
              name: 'Home',
              route: '/',
              isHome: true,
              hierarchy: WidgetNode(id: 'w', type: 'Scaffold'),
            ),
          ],
        );

    test('a collection of a model that does not exist is refused', () {
      final result = const Validator().validate(
        withCollection(const CollectionDef(name: 'x', element: 'Ghost')),
      );
      expect(
        result.diagnostics.map((d) => d.code),
        contains('unknown_collection_model'),
      );
    });

    test('a persisted collection of something unstorable is refused', () {
      // Same rule as the server boundary: no JSON form, no storage.
      final model = DataModelDef.fromJson(const {
        'name': 'Handler',
        'fields': {'onTap': 'Event'},
      }, 'models.Handler');

      final result = const Validator().validate(
        withCollection(
          const CollectionDef(name: 'handlers', element: 'Handler'),
          models: [model],
        ),
      );
      expect(
        result.diagnostics.map((d) => d.code),
        contains('unstorable_collection'),
      );
    });

    test('the same collection unpersisted is allowed', () {
      final model = DataModelDef.fromJson(const {
        'name': 'Handler',
        'fields': {'onTap': 'Event'},
      }, 'models.Handler');

      final result = const Validator().validate(
        withCollection(
          const CollectionDef(
            name: 'handlers',
            element: 'Handler',
            persist: false,
          ),
          models: [model],
        ),
      );
      expect(
        result.diagnostics.map((d) => d.code),
        isNot(contains('unstorable_collection')),
      );
    });
  });
}
