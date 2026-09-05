import 'package:flutter_test/flutter_test.dart';
import 'package:lattice_core/lattice_core.dart';
import 'package:lattice_editor/src/state/editor_controller.dart';
import 'package:lattice_editor/src/state/project_edits.dart';
import 'package:lattice_editor/src/state/tree_edits.dart';

import 'support/sample_project.dart';

/// The editing rules, tested without any UI. Everything the panels do goes
/// through this layer, so a bug caught here is a bug caught in every panel.
void main() {
  group('TreeEdits', () {
    test('finds widgets nested in props, not just in children', () {
      final page = counterPage();
      expect(TreeEdits.find(page.hierarchy, 'w_title')?.type, 'Text');
      expect(TreeEdits.parentOf(page.hierarchy, 'w_title'), 'w_appbar');
    });

    test('removes a subtree and leaves the rest intact', () {
      final page = counterPage();
      final without = TreeEdits.remove(page.hierarchy, 'w_btn')!;
      expect(TreeEdits.find(without, 'w_btn'), isNull);
      // The button's own label goes with it...
      expect(TreeEdits.find(without, 'w_btn_label'), isNull);
      // ...and its siblings do not.
      expect(TreeEdits.find(without, 'w_txt'), isNotNull);
    });

    test('inserts at a position', () {
      final page = counterPage();
      final divider = WidgetNode(id: 'w_div', type: 'Divider');
      final withDivider =
          TreeEdits.insert(page.hierarchy, 'w_col', divider, index: 0);
      final column = TreeEdits.find(withDivider, 'w_col')!;
      expect(column.children.first.id, 'w_div');
    });

    test('reorders within one parent', () {
      final page = counterPage();
      final moved = TreeEdits.move(page.hierarchy, 'w_btn', 'w_col', index: 0)!;
      final column = TreeEdits.find(moved, 'w_col')!;
      expect(column.children.map((c) => c.id), ['w_btn', 'w_txt']);
    });

    test('refuses to drop a node into its own subtree', () {
      final page = counterPage();
      // Dropping the Column into the button it contains would detach the tree.
      final moved = TreeEdits.move(page.hierarchy, 'w_col', 'w_btn');
      expect(moved, page.hierarchy);
    });
  });

  group('ProjectEdits', () {
    test('a new widget arrives already valid', () {
      final project = counterProject();
      final (next, id) =
          ProjectEdits.addWidget(project, 'page_home', 'w_col', 'Text');
      // Text.data is required, so it is seeded rather than left empty.
      final added = TreeEdits.find(
        ProjectEdits.unit(next, 'page_home')!.hierarchy,
        id,
      )!;
      expect(added.props['data'], isA<LiteralProp>());
      expect(const Validator().validate(next).isValid, isTrue);
    });

    test('ids are readable and unique', () {
      var project = counterProject();
      final ids = <String>[];
      for (var i = 0; i < 3; i++) {
        final (next, id) =
            ProjectEdits.addWidget(project, 'page_home', 'w_col', 'Divider');
        project = next;
        ids.add(id);
      }
      expect(ids, ['w_divider', 'w_divider2', 'w_divider3']);
    });

    test('deleting a widget deletes the events that named it', () {
      final project = counterProject();
      expect(project.pages.first.graph.node('ev_btn'), isNotNull);

      final next = ProjectEdits.removeWidget(project, 'page_home', 'w_btn');
      final unit = ProjectEdits.unit(next, 'page_home')!;
      expect(unit.graph.node('ev_btn'), isNull, reason: 'orphaned event');

      // The project still compiles: nothing refers to a ghost. The action the
      // button used to trigger is now unreachable, which is worth saying but
      // does not stop anything.
      final result = const Validator().validate(next);
      expect(result.isValid, isTrue, reason: result.toString());
      expect(
          result.warnings.map((w) => w.code), contains('unreachable_action'));
    });

    test('deleting a node clears the bindings that pointed at it', () {
      final project = counterProject();
      final next = ProjectEdits.removeNode(project, 'page_home', 'n_fmt');
      final text = TreeEdits.find(
        ProjectEdits.unit(next, 'page_home')!.hierarchy,
        'w_txt',
      )!;
      expect(text.props.containsKey('data'), isFalse);
    });

    test('an input pin keeps at most one edge', () {
      var project = counterProject();
      project = ProjectEdits.connect(
        project,
        'page_home',
        const PinRef('n_count', 'value'),
        const PinRef('n_fmt', 'args', index: 0),
      );
      final edges = ProjectEdits.unit(project, 'page_home')!
          .graph
          .incoming(const PinRef('n_fmt', 'args', index: 0));
      expect(edges.length, 1);
    });

    test('binding a callback creates the Event node and wires it', () {
      final project = counterProject();
      final stripped = ProjectEdits.setProp(
          project, 'page_home', 'w_btn', 'onPressed', null);
      final cleaned = ProjectEdits.removeNode(stripped, 'page_home', 'ev_btn');

      final (next, eventId) =
          ProjectEdits.bindEvent(cleaned, 'page_home', 'w_btn', 'onPressed');
      final unit = ProjectEdits.unit(next, 'page_home')!;
      expect(unit.graph.node(eventId)?.type, 'Event');
      expect(
        TreeEdits.find(unit.hierarchy, 'w_btn')!.props['onPressed'],
        EventProp(eventId),
      );
    });

    test('binding the same callback twice reuses the node', () {
      final project = counterProject();
      final (next, id) =
          ProjectEdits.bindEvent(project, 'page_home', 'w_btn', 'onPressed');
      expect(id, 'ev_btn');
      expect(ProjectEdits.unit(next, 'page_home')!.graph.ofType('Event').length,
          1);
    });
  });

  group('EditorController', () {
    test('undo restores both the project and the selection', () {
      final controller = EditorController(project: counterProject());
      controller.select(const WidgetSelection('w_txt'));

      controller.apply(
        'Add Divider',
        (p) => ProjectEdits.addWidget(p, 'page_home', 'w_col', 'Divider').$1,
      );
      controller.select(const WidgetSelection('w_col'));

      expect(controller.canUndo, isTrue);
      controller.undo();

      expect(
        TreeEdits.find(controller.activeUnit.hierarchy, 'w_divider'),
        isNull,
      );
      expect(controller.selection, const WidgetSelection('w_txt'));

      controller.redo();
      expect(
        TreeEdits.find(controller.activeUnit.hierarchy, 'w_divider'),
        isNotNull,
      );
    });

    test('an edit that changes nothing is not undoable', () {
      final controller = EditorController(project: counterProject());
      controller.apply('No-op', (p) => p);
      expect(controller.canUndo, isFalse);
      expect(controller.isDirty, isFalse);
    });

    test('diagnostics and generated code refresh after an edit', () {
      final controller = EditorController(project: counterProject());
      expect(controller.diagnostics.isValid, isTrue);
      expect(
        controller.generated.files['lib/pages/home_page.dart'],
        contains('signal<int>(0)'),
      );

      controller.apply(
        'Break it',
        (p) => ProjectEdits.setProp(p, 'page_home', 'w_txt', 'data', null),
      );
      expect(controller.diagnostics.isValid, isFalse);
      expect(
        controller.diagnostics.errors.map((e) => e.code),
        contains('missing_required_param'),
      );
    });

    test('a binding is refused when the types do not fit', () {
      final controller = EditorController(project: counterProject());
      controller.beginBinding('w_txt', 'data', PrimitiveType.string);

      // n_count is an int Signal; Text.data is a String.
      final refusal =
          controller.completeBinding(const PinRef('n_count', 'value'));
      expect(refusal, contains('int does not fit'));
      expect(controller.pendingBinding, isNotNull, reason: 'still pending');

      expect(controller.completeBinding(const PinRef('n_fmt', 'out')), isNull);
      expect(controller.pendingBinding, isNull);
    });

    test('history is bounded', () {
      final controller = EditorController(project: counterProject());
      for (var i = 0; i < 150; i++) {
        controller.apply(
          'Add $i',
          (p) => ProjectEdits.addWidget(p, 'page_home', 'w_col', 'Divider').$1,
        );
      }
      // Undo cannot walk back further than the limit, but it must not throw.
      var steps = 0;
      while (controller.canUndo && steps < 200) {
        controller.undo();
        steps++;
      }
      expect(steps, 100);
    });
  });
}
