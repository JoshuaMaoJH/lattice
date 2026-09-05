import 'package:flutter/material.dart' hide Page;
import 'package:flutter_test/flutter_test.dart';
import 'package:lattice_core/lattice_core.dart';
import 'package:lattice_editor/src/editor_shell.dart';
import 'package:lattice_editor/src/panels/diagnostics_panel.dart';
import 'package:lattice_editor/src/host/editor_host.dart';
import 'package:lattice_editor/src/state/editor_controller.dart';
import 'package:lattice_editor/src/state/tree_edits.dart';
import 'package:lattice_editor/src/theme.dart';

import 'support/sample_project.dart';

/// The panels, driven the way a user drives them.
///
/// These run headless, which is the only way this editor can be tested on a
/// machine without a desktop toolchain — and a better way regardless, because
/// they assert on behaviour rather than on pixels.
void main() {
  late EditorController controller;

  Future<void> pumpEditor(WidgetTester tester) async {
    controller = EditorController(project: counterProject());
    await tester.binding.setSurfaceSize(const Size(1600, 950));
    await tester.pumpWidget(
      MaterialApp(
        theme: LatticeTheme.materialTheme(),
        home: EditorShell(controller: controller, host: MemoryHost()),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('shell', () {
    testWidgets('shows all four panels and the problems strip', (tester) async {
      await pumpEditor(tester);
      for (final title in [
        'HIERARCHY',
        'INSPECTOR',
        'GRAPH',
        'PREVIEW',
        'PROBLEMS'
      ]) {
        expect(find.text(title), findsOneWidget, reason: title);
      }
      expect(find.text('The project is valid.'), findsOneWidget);
    });

    testWidgets('lists every page and prefab as a tab', (tester) async {
      await pumpEditor(tester);
      expect(find.text('Home'), findsOneWidget);
    });
  });

  group('hierarchy (R1)', () {
    testWidgets('renders the tree, including widgets nested in props',
        (tester) async {
      await pumpEditor(tester);
      // `AppBar` sits in Scaffold.appBar, not in children.
      expect(find.text('AppBar'), findsOneWidget);
      expect(find.text('appBar:'), findsOneWidget);
      expect(find.text('w_appbar'), findsOneWidget);
    });

    testWidgets('selecting a row fills the Inspector', (tester) async {
      await pumpEditor(tester);
      expect(
        find.text('Select a widget in the Hierarchy or a node in the Graph.'),
        findsOneWidget,
      );

      await tester.tap(find.text('w_txt'));
      await tester.pumpAndSettle();

      expect(controller.selection, const WidgetSelection('w_txt'));
      // The parameter sheet is generated from the schema.
      expect(find.text('data'), findsOneWidget);
      expect(find.text('maxLines'), findsOneWidget);
    });
  });

  group('inspector (R2)', () {
    testWidgets('shows a bound parameter as its source pin', (tester) async {
      await pumpEditor(tester);
      await tester.tap(find.text('w_txt'));
      await tester.pumpAndSettle();
      expect(find.text('n_fmt.out'), findsOneWidget);
    });

    testWidgets('editing a literal changes the project', (tester) async {
      await pumpEditor(tester);
      await tester.tap(find.text('w_title'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).first, 'Renamed');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      final title = TreeEdits.find(controller.activeUnit.hierarchy, 'w_title')!;
      expect(title.props['data'], const LiteralProp('Renamed'));
      expect(controller.isDirty, isTrue);
    });
  });

  group('binding (R4)', () {
    testWidgets('the bolt puts the graph into binding mode', (tester) async {
      await pumpEditor(tester);
      await tester.tap(find.text('w_txt'));
      await tester.pumpAndSettle();

      controller.beginBinding('w_txt', 'maxLines', TypeParser.parse('int?'));
      await tester.pumpAndSettle();

      // The Graph says what it is waiting for.
      expect(find.text('binding maxLines'), findsOneWidget);
    });

    testWidgets('tapping a compatible pin completes it', (tester) async {
      await pumpEditor(tester);
      controller.beginBinding('w_txt', 'maxLines', TypeParser.parse('int?'));
      await tester.pumpAndSettle();

      expect(
          controller.completeBinding(const PinRef('n_count', 'value')), isNull);
      await tester.pumpAndSettle();

      expect(
        controller.generated.files['lib/pages/home_page.dart'],
        contains('maxLines: count.value'),
      );
    });

    testWidgets('an incompatible pin is refused *and says why*',
        (tester) async {
      await pumpEditor(tester);
      controller.beginBinding('w_txt', 'data', PrimitiveType.string);
      await tester.pumpAndSettle();

      // n_count is an int; Text.data is a String.
      await tester.tap(find.byKey(const ValueKey('pin:n_count.value:out')));
      // Not pumpAndSettle: the banner clears itself on a timer, and settling
      // would wait it out before the assertion.
      await tester.pump();

      expect(controller.pendingBinding, isNotNull, reason: 'still pending');
      expect(
        find.textContaining('int does not fit'),
        findsOneWidget,
        reason: 'refusing silently is the thing to avoid',
      );

      // Let the banner expire so no timer outlives the test.
      await tester.pump(const Duration(seconds: 3));
    });
  });

  group('graph (R3)', () {
    testWidgets('draws a card per node with its pins', (tester) async {
      await pumpEditor(tester);
      expect(find.text('Signal'), findsOneWidget);
      expect(find.text('Format'), findsOneWidget);
      // A variadic pin always offers one free socket.
      expect(find.text('args[0]'), findsOneWidget);
      expect(find.text('args[1]'), findsOneWidget);
    });

    testWidgets('selecting a node fills the Inspector with its config',
        (tester) async {
      await pumpEditor(tester);
      controller.select(const NodeSelection('n_count'));
      await tester.pumpAndSettle();
      expect(find.text('dartType'), findsOneWidget);
      expect(find.text('init'), findsOneWidget);
    });
  });

  group('problems (R15)', () {
    testWidgets('lists errors and reveals what produced them', (tester) async {
      await pumpEditor(tester);
      controller.apply(
        'Break it',
        (project) => project.withPage(
          project.pages.first.copyWith(
            hierarchy: TreeEdits.setProp(
              project.pages.first.hierarchy,
              'w_title',
              'data',
              null,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // The message shows in Problems and, because nothing is generated while
      // the project has errors, in the Preview too.
      final inProblems = find.descendant(
        of: find.byType(DiagnosticsPanel),
        matching: find.textContaining('Text requires "data"'),
      );
      expect(inProblems, findsOneWidget);

      await tester.tap(inProblems);
      await tester.pumpAndSettle();
      expect(controller.selection, const WidgetSelection('w_title'));
    });
  });

  group('preview (R5)', () {
    testWidgets('shows the generated file for the unit being edited',
        (tester) async {
      await pumpEditor(tester);
      expect(find.text('home_page.dart'), findsOneWidget);
      expect(
          find.textContaining('final count = signal<int>(0);'), findsOneWidget);
    });

    testWidgets('explains that the live preview needs the desktop editor',
        (tester) async {
      await pumpEditor(tester);
      await tester
          .tap(find.byTooltip('Running the app needs the desktop editor'));
      await tester.pumpAndSettle();
      expect(find.textContaining('needs a filesystem and a subprocess'),
          findsOneWidget);
    });
  });

  group('undo (R7 groundwork)', () {
    testWidgets('the toolbar undo reverses the last edit', (tester) async {
      await pumpEditor(tester);
      await tester.tap(find.text('w_title'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).first, 'Changed');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Undo Set data'));
      await tester.pumpAndSettle();

      final title = TreeEdits.find(controller.activeUnit.hierarchy, 'w_title')!;
      expect(title.props['data'], const LiteralProp('Counter'));
    });
  });
}
