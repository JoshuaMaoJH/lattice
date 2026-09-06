import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lattice_editor/src/host/editor_host.dart';
import 'package:lattice_editor/src/panels/project_browser.dart';

/// A host with a fixed tree, so the browser can be driven without a disk.
class _FakeHost extends MemoryHost {
  _FakeHost() : super(description: 'a test');

  final List<String> opened = [];

  @override
  bool get canOpenProjects => true;

  @override
  Future<String> browseStart() async => '/home/me';

  @override
  String? parentOf(String path) =>
      path == '/' ? null : path.substring(0, path.lastIndexOf('/'));

  @override
  Future<List<DirectoryEntry>> browse(String path) async => switch (path) {
        '/home/me' => const [
            DirectoryEntry(
                name: 'notes', path: '/home/me/notes', isProject: false),
            DirectoryEntry(
                name: 'todo', path: '/home/me/todo', isProject: true),
          ],
        '/home/me/notes' => const [],
        _ => const [],
      };

  @override
  Future<List<String>> recentProjects() async => ['/home/me/weather'];
}

void main() {
  Future<ProjectChoice?> open(
    WidgetTester tester,
    _FakeHost host, {
    ProjectBrowserMode mode = ProjectBrowserMode.open,
  }) async {
    ProjectChoice? result;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () async =>
              result = await ProjectBrowser.show(context, host, mode: mode),
          child: const Text('go'),
        ),
      ),
    ));
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    return result;
  }

  testWidgets('a directory with a project.json is marked and openable',
      (tester) async {
    final host = _FakeHost();
    await open(tester, host);

    // Both directories are listed, but only the project offers an Open.
    expect(find.text('notes'), findsOneWidget);
    expect(find.text('todo'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Open'), findsOneWidget);
  });

  testWidgets('recent projects are offered before browsing', (tester) async {
    final host = _FakeHost();
    await open(tester, host);

    expect(find.text('Recent'), findsOneWidget);
    expect(find.text('/home/me/weather'), findsOneWidget);
  });

  testWidgets('descending into a plain directory says it is empty',
      (tester) async {
    final host = _FakeHost();
    await open(tester, host);

    await tester.tap(find.text('notes'));
    await tester.pumpAndSettle();

    expect(find.text('No sub-directories.'), findsOneWidget);
    // Having descended, the user can climb back out.
    expect(find.text('/home/me/notes'), findsOneWidget);
  });

  testWidgets('create mode asks for a folder name, not an existing project',
      (tester) async {
    final host = _FakeHost();
    await open(tester, host, mode: ProjectBrowserMode.create);

    expect(find.text('Folder name'), findsOneWidget);
    // Recents are for opening; creating is about where to put a new one.
    expect(find.text('Recent'), findsNothing);
  });
}
