import 'package:flutter_test/flutter_test.dart';
import 'package:lattice_core/lattice_core.dart';
import 'package:lattice_editor/src/state/editor_controller.dart';
import 'package:lattice_editor/src/state/node_clipboard.dart';
import 'package:lattice_editor/src/state/project_edits.dart';

/// Multi-select and copy/paste operate on a set of graph nodes.
void main() {
  Page page() => Page(
        id: 'page_home',
        name: 'Home',
        route: '/',
        isHome: true,
        hierarchy: WidgetNode(id: 'w_root', type: 'Scaffold'),
        graph: Graph(
          nodes: [
            GraphNode(
              id: 'n_count',
              type: 'Signal',
              config: {'dartType': 'int', 'init': 0, 'name': 'count'},
            ),
            GraphNode(
              id: 'n_fmt',
              type: 'Format',
              config: {'template': 'Count: {0}'},
            ),
            GraphNode(
              id: 'a_inc',
              type: 'UpdateSignal',
              config: {'signal': 'n_count', 'fn': '(x) => x + 1'},
            ),
          ],
          edges: const [
            Edge(PinRef('n_count', 'value'), PinRef('n_fmt', 'args', index: 0)),
          ],
        ),
        layout: const {
          'n_count': CanvasPos(100, 100),
          'n_fmt': CanvasPos(300, 140),
          'a_inc': CanvasPos(100, 300),
        },
      );

  Project project() => Project(
        id: 'p',
        config: const ProjectConfig(
          appName: 'C',
          packageName: 'c_app',
          bundleId: 'com.example.c_app',
        ),
        pages: [page()],
        prefabs: [
          Prefab(
            id: 'prefab_card',
            name: 'Card2',
            hierarchy: WidgetNode(id: 'w_card', type: 'Card'),
          ),
        ],
      );

  group('selection', () {
    test('selecting one node replaces the set', () {
      final controller = EditorController(project: project());
      controller.selectNodes({'n_count', 'n_fmt'});

      controller.select(const NodeSelection('a_inc'));

      expect(controller.selectedNodes, {'a_inc'});
    });

    test('toggling adds and removes without disturbing the rest', () {
      final controller = EditorController(project: project())
        ..select(const NodeSelection('n_count'));

      controller.toggleNode('n_fmt');
      expect(controller.selectedNodes, {'n_count', 'n_fmt'});

      controller.toggleNode('n_count');
      expect(controller.selectedNodes, {'n_fmt'});
    });

    test('the Inspector follows, and empties when the last one goes', () {
      final controller = EditorController(project: project())
        ..select(const NodeSelection('n_count'));

      controller.toggleNode('n_count');

      expect(controller.selectedNodes, isEmpty);
      expect(controller.selection, isA<NoSelection>());
    });

    test('opening another unit does not carry the selection over', () {
      final controller = EditorController(project: project())
        ..selectNodes({'n_count', 'n_fmt'})
        ..openUnit('prefab_card');

      expect(controller.selectedNodes, isEmpty);
    });

    test('re-opening the unit you are already in changes nothing', () {
      final controller = EditorController(project: project())
        ..selectNodes({'n_count', 'n_fmt'})
        ..openUnit('page_home');

      expect(controller.selectedNodes, {'n_count', 'n_fmt'});
    });
  });

  group('copy and paste', () {
    test('edges inside the selection come along', () {
      final clipboard = NodeClipboard.copyFrom(page(), {'n_count', 'n_fmt'});

      expect(clipboard.nodes.map((n) => n.id), ['n_count', 'n_fmt']);
      expect(clipboard.edges, hasLength(1));
    });

    test('edges that leave the selection are dropped', () {
      // There is no second place for that wire to land, and reconnecting a
      // copy to the original's neighbours would be a surprise.
      final clipboard = NodeClipboard.copyFrom(page(), {'n_fmt'});

      expect(clipboard.nodes, hasLength(1));
      expect(clipboard.edges, isEmpty);
    });

    test('a paste gets fresh ids and keeps its internal shape', () {
      final unit = page();
      final clipboard = NodeClipboard.copyFrom(unit, {'n_count', 'n_fmt'});

      final pasted = clipboard.paste(unit, const CanvasPos(500, 500));

      expect(pasted.nodes.map((n) => n.id), ['n_count2', 'n_fmt2']);
      expect(pasted.edges.single.from.nodeId, 'n_count2');
      expect(pasted.edges.single.to.nodeId, 'n_fmt2');
      // Relative positions are preserved, translated to the paste point.
      expect(pasted.layout['n_count2'], const CanvasPos(500, 500));
      expect(pasted.layout['n_fmt2'], const CanvasPos(700, 540));
    });

    test('config that names a copied node is rewritten to the copy', () {
      // A pasted action that still wrote to the original signal only shows up
      // as a bug when someone edits the copy.
      final unit = page();
      final clipboard = NodeClipboard.copyFrom(unit, {'n_count', 'a_inc'});

      final pasted = clipboard.paste(unit, const CanvasPos(0, 0));
      final action = pasted.nodes.firstWhere((n) => n.type == 'UpdateSignal');

      expect(action.config['signal'], 'n_count2');
    });

    test('config that names something outside the copy is left alone', () {
      final unit = page();
      final clipboard = NodeClipboard.copyFrom(unit, {'a_inc'});

      final pasted = clipboard.paste(unit, const CanvasPos(0, 0));

      expect(pasted.nodes.single.config['signal'], 'n_count');
    });
  });

  group('deleting a set', () {
    test('removes every node and the edges between them, as one edit', () {
      final controller = EditorController(project: project());

      controller.apply(
        'Delete 2 nodes',
        (project) => ProjectEdits.removeNodes(
          project,
          'page_home',
          {'n_count', 'n_fmt'},
        ),
      );

      expect(controller.activeUnit.graph.nodes.map((n) => n.id), ['a_inc']);
      expect(controller.activeUnit.graph.edges, isEmpty);
      expect(controller.activeUnit.layout.keys, ['a_inc']);

      // One edit, so one undo.
      controller.undo();
      expect(controller.activeUnit.graph.nodes, hasLength(3));
    });
  });
}
