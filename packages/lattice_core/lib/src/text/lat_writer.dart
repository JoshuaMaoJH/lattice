import 'dart:convert';

import '../model/data_model.dart';
import '../model/graph_unit.dart';
import '../model/hierarchy.dart';
import '../model/page.dart';
import '../model/prefab.dart';
import '../model/server_function.dart';
import '../model/widget_unit.dart';

/// Writes a unit as `.lat` text (R18).
///
/// The point is git review and hand editing, so the format is line-oriented
/// and indented: a moved widget is a moved block, not a rewritten JSON file
/// with every sibling's braces shifted. It carries everything the JSON does,
/// including canvas positions — a lossy "readable form" would be a second
/// source of truth that quietly disagrees with the first.
class LatWriter {
  const LatWriter();

  String write(GraphUnit unit) {
    final out = StringBuffer();
    out.writeln(_header(unit));

    if (unit is WidgetUnit) {
      out.writeln('  hierarchy');
      _widget(out, unit.hierarchy, 1, null);
    }

    if (unit.graph.nodes.isNotEmpty) {
      out.writeln('  graph');
      for (final node in unit.graph.nodes) {
        out.writeln('    ${node.type} #${node.id}${_config(node.config)}');
      }
    }

    if (unit.graph.edges.isNotEmpty) {
      out.writeln('  wires');
      for (final edge in unit.graph.edges) {
        out.writeln('    ${edge.from} -> ${edge.to}');
      }
    }

    final layout = unit.layout;
    if (layout.isNotEmpty) {
      out.writeln('  layout');
      final keys = layout.keys.toList()..sort();
      for (final key in keys) {
        final pos = layout[key]!;
        out.writeln('    $key @ ${_number(pos.x)},${_number(pos.y)}');
      }
    }

    return out.toString();
  }

  String _header(GraphUnit unit) => switch (unit) {
        final Page page => [
            'page ${_word(page.name)} #${page.id}',
            'route ${_string(page.route)}',
            if (page.isHome) 'home',
            ..._parameters(page.parameters),
          ].join(' '),
        final Prefab prefab => [
            'prefab ${_word(prefab.name)} #${prefab.id}',
            ..._parameters(prefab.parameters),
          ].join(' '),
        final ServerFunction fn => [
            'server ${_word(fn.name)} #${fn.id}',
            'returns ${fn.returns.spelling}',
            ..._parameters(fn.parameters),
          ].join(' '),
        _ => 'unit #${unit.id}',
      };

  List<String> _parameters(List<FieldDef> parameters) => [
        for (final parameter in parameters)
          'param ${parameter.name}: ${parameter.type.spelling}'
              '${parameter.defaultValue == null ? '' : ' = ${_value(parameter.defaultValue)}'}',
      ];

  void _widget(StringBuffer out, WidgetNode node, int depth, String? slot) {
    final pad = '  ' * (depth + 1);
    final inline = <String>[];
    final nested = <MapEntry<String, PropValue>>[];

    for (final entry in node.props.entries) {
      final value = entry.value;
      if (value is WidgetProp || value is WidgetListProp) {
        nested.add(entry);
      } else {
        inline.add('${entry.key}=${_prop(value)}');
      }
    }

    final prefix = slot == null ? '' : '$slot: ';
    out.writeln(
      '$pad$prefix${node.type} #${node.id}'
      '${inline.isEmpty ? '' : ' ${inline.join(' ')}'}',
    );

    for (final entry in nested) {
      final value = entry.value;
      if (value is WidgetProp) {
        _widget(out, value.widget, depth + 1, entry.key);
      } else if (value is WidgetListProp) {
        out.writeln('${'  ' * (depth + 2)}${entry.key}:');
        for (final child in value.widgets) {
          _widget(out, child, depth + 2, null);
        }
      }
    }

    for (final child in node.children) {
      _widget(out, child, depth + 1, null);
    }
  }

  String _prop(PropValue value) => switch (value) {
        LiteralProp(:final value) => _value(value),
        BindProp(:final source) => '<$source',
        EventProp(:final eventNodeId) => '!$eventNodeId',
        ExprProp(:final code) => '`${code.replaceAll('`', r'\`')}`',
        // Handled by the caller, which knows the slot name.
        _ => throw StateError('nested props are written by _widget'),
      };

  String _config(Map<String, Object?> config) {
    if (config.isEmpty) return '';
    final keys = config.keys.toList()..sort();
    return ' ${[for (final k in keys) '$k=${_value(config[k])}'].join(' ')}';
  }

  /// Values are JSON, which keeps strings, numbers, lists and maps unambiguous
  /// without inventing a second literal syntax to get wrong.
  String _value(Object? value) => switch (value) {
        null => 'null',
        bool() || num() => '$value',
        String() => _string(value),
        _ => jsonEncode(value),
      };

  static String _string(String value) => jsonEncode(value);

  /// A bare word where one is safe, so `page Home` does not read as `page
  /// "Home"` for no reason.
  static String _word(String value) =>
      RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$').hasMatch(value)
          ? value
          : _string(value);

  static String _number(double value) =>
      value == value.roundToDouble() ? '${value.round()}' : '$value';
}
