import 'package:lattice_core/lattice_core.dart';

/// Allocates the stable ids §7.4 asks for.
///
/// Readable rather than random (`w_text`, `w_text2`) because these ids end up
/// as comments in generated code and as anchors in diagnostics — `n_7f3a` tells
/// a reader nothing that `n_count` does not tell them better.
class Ids {
  const Ids._();

  static String forWidget(WidgetUnit unit, String widgetType) =>
      _unique('w_${_slug(widgetType)}', {
        for (final w in unit.hierarchy.descendantsAndSelf) w.id,
      });

  static String forNode(WidgetUnit unit, String nodeType) {
    final schema = NodeRegistry.lookup(nodeType);
    // The prefix carries the node's role, which is what makes an id readable
    // at a glance on the canvas.
    final prefix = switch (schema?.category) {
      NodeCategory.event => 'ev',
      NodeCategory.action => 'a',
      _ => 'n',
    };
    return _unique(
      '${prefix}_${_slug(nodeType)}',
      {for (final n in unit.graph.nodes) n.id},
    );
  }

  static String forUnit(Project project, String name, {required bool isPage}) =>
      _unique(
        '${isPage ? 'page' : 'prefab'}_${_slug(name)}',
        {for (final unit in project.units) unit.id},
      );

  static String _unique(String preferred, Set<String> taken) {
    if (!taken.contains(preferred)) return preferred;
    var counter = 2;
    while (taken.contains('$preferred$counter')) {
      counter++;
    }
    return '$preferred$counter';
  }

  static String _slug(String raw) {
    final snake = raw
        .replaceAllMapped(RegExp('([a-z0-9])([A-Z])'), (m) => '${m[1]}_${m[2]}')
        .toLowerCase()
        .replaceAll(RegExp('[^a-z0-9]+'), '_')
        .replaceAll(RegExp('^_+|_+\$'), '');
    return snake.isEmpty ? 'x' : snake;
  }
}
