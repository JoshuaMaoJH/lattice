import 'dart:convert';

import 'package:lattice_core/lattice_core.dart';
import 'package:test/test.dart';

import 'support/fixtures.dart';

void main() {
  group('round trip (R7)', () {
    test('a page survives encode -> decode unchanged', () {
      final original = counterPage();
      final decoded = Page.fromJson(
        jsonDecode(jsonEncode(original.toJson())) as Map<String, Object?>,
      );
      expect(decoded, original);
    });

    test('a second pass is byte-identical', () {
      final once = jsonEncode(counterPage().toJson());
      final twice = jsonEncode(
        Page.fromJson(jsonDecode(once) as Map<String, Object?>).toJson(),
      );
      expect(twice, once);
    });

    test('models round-trip', () {
      final model = DataModelDef.fromJson(const {
        'name': 'Todo',
        'fields': {'id': 'String', 'title': 'String', 'done': 'bool'},
        'defaults': {'done': false},
      }, 'test');
      final again = DataModelDef.fromJson(
        jsonDecode(jsonEncode(model.toJson())) as Map<String, Object?>,
        'test',
      );
      expect(again, model);
      expect(again.field('done')?.defaultValue, false);
    });
  });

  group('prop encoding', () {
    test('distinguishes bindings, events and literals', () {
      final page = counterPage();
      final text =
          page.hierarchy.descendantsAndSelf.firstWhere((w) => w.id == 'w_txt');
      expect(text.props['data'], isA<BindProp>());
      expect(text.toJson()['props'], {
        'data': {r'$bind': 'n_fmt.out'},
      });
    });

    test('escapes a literal map that looks like a special form', () {
      const prop = LiteralProp({'type': 'not a widget'});
      final encoded = prop.toJson();
      expect(encoded, {
        r'$literal': {'type': 'not a widget'},
      });
      final decoded = PropValue.fromJson(
        encoded,
        ownerId: 'w',
        key: 'k',
        path: 'test',
      );
      expect(decoded, prop);
    });

    test('gives nested widgets deterministic ids when the file omits them', () {
      final widget = WidgetNode.fromJson(const {
        'id': 'w_root',
        'type': 'Scaffold',
        'props': {
          'appBar': {
            'type': 'AppBar',
            'props': {
              'title': {
                'type': 'Text',
                'props': {'data': 'Hi'}
              },
            },
          },
        },
      }, path: 'test');

      final ids = widget.descendantsAndSelf.map((w) => w.id).toList();
      expect(ids, ['w_root', 'w_root_appBar', 'w_root_appBar_title']);
    });
  });

  group('layout separation (ADR-005)', () {
    test('canvas positions live outside the semantic model', () {
      final page = counterPage();
      final moved = page.copyWith(
        layout: {...page.layout, 'n_count': const CanvasPos(999, 999)},
      );
      // Different files...
      expect(moved.toJson()['layout'], isNot(page.toJson()['layout']));
      // ...but the same program.
      expect(moved.hierarchy, page.hierarchy);
      expect(moved.graph, page.graph);
    });
  });

  group('naming', () {
    test('derives Dart identifiers from page ids', () {
      expect(counterPage().className, 'HomePage');
      expect(counterPage().fileName, 'home_page.dart');
      expect(
        Page(
                id: 'page_todo_list',
                name: 'x',
                hierarchy: WidgetNode(id: 'r', type: 'Scaffold'))
            .className,
        'TodoListPage',
      );
    });

    test('defaults a route from the page id', () {
      final page = Page(
        id: 'page_about',
        name: 'About',
        hierarchy: WidgetNode(id: 'r', type: 'Scaffold'),
      );
      expect(page.route, '/about');
    });
  });
}
