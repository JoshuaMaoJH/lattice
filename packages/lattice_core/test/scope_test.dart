import 'package:lattice_core/lattice_core.dart';
import 'package:test/test.dart';

import 'support/fixtures.dart';

/// The rules from ADR-009: `item` exists only inside its template, and a list
/// of models must say what identifies an item.
void main() {
  const validator = Validator();

  Iterable<String> codesFor(Project project) =>
      validator.validate(project).diagnostics.map((d) => d.code);

  test('a well-formed ForEach validates clean', () {
    final result = validator.validate(listProject());
    expect(result.isValid, isTrue, reason: result.toString());
  });

  group('scope', () {
    test('rejects reading item from outside the template', () {
      expect(
        codesFor(listProject(titleOutsideTemplate: true)),
        contains('item_out_of_scope'),
      );
    });

    test('ScopeMap knows which templates a widget sits inside', () {
      final scopes = ScopeMap.of(listPage());
      expect(scopes.enclosing('w_tile'), ['w_each']);
      expect(scopes.enclosing('w_list'), isEmpty);
      // The ForEach's own props are evaluated outside its loop.
      expect(scopes.enclosing('w_each'), isEmpty);
    });

    test('ScopeMap tracks scopes transitively through computations', () {
      final scopes = ScopeMap.of(listPage());
      expect(scopes.scopesOf('n_title'), {'w_each'});
      expect(scopes.scopesOf('n_todos'), isEmpty);
    });
  });

  group('item identity', () {
    test('requires itemKey for a list of models', () {
      expect(
        codesFor(listProject(itemKey: null)),
        contains('missing_item_key'),
      );
    });

    test('rejects an itemKey that is not a field of the model', () {
      expect(
        codesFor(listProject(itemKey: 'nope')),
        contains('unknown_item_key'),
      );
    });

    test('accepts a real field', () {
      expect(codesFor(listProject(itemKey: 'title')), isEmpty);
    });
  });

  group('placement', () {
    test('rejects a ForEach whose parent takes a single child', () {
      expect(
        codesFor(listProject(listParent: 'Center')),
        contains('foreach_needs_list_parent'),
      );
    });

    test('accepts every many-children parent', () {
      for (final parent in ['Column', 'Row', 'ListView', 'Stack', 'Wrap']) {
        expect(
          codesFor(listProject(listParent: parent)),
          isEmpty,
          reason: parent,
        );
      }
    });

    test('rejects a ForEach with no template', () {
      final page = listPage();
      final broken = page.copyWith(
        hierarchy: WidgetNode(
          id: 'w_root',
          type: 'Scaffold',
          children: [
            WidgetNode(
              id: 'w_list',
              type: 'Column',
              children: [
                WidgetNode(
                  id: 'w_each',
                  type: 'ForEach',
                  props: {
                    'items': const BindProp(PinRef('n_todos', 'value')),
                    'itemKey': const LiteralProp('id'),
                  },
                ),
              ],
            ),
          ],
        ),
      );
      expect(
        codesFor(listProject().copyWith(pages: [broken])),
        contains('missing_template'),
      );
    });
  });

  group('element type inference', () {
    test('reads the item type through the items binding', () {
      final page = listPage();
      final ctx = NodeContext(
        graph: page.graph,
        unit: page,
        project: listProject(),
      );
      expect(ctx.forEachElementType('w_each'), const ModelType('Todo'));
      expect(
        ctx.outputType(const PinRef('n_item', 'item')),
        const ModelType('Todo'),
      );
      expect(
        ctx.outputType(const PinRef('n_item', 'index')),
        PrimitiveType.int_,
      );
    });
  });
}
