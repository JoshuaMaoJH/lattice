import 'package:collection/collection.dart';

import 'errors.dart';
import 'json_utils.dart';
import 'pin_ref.dart';

const _deepEquals = DeepCollectionEquality();

/// The value sitting in one widget parameter slot.
///
/// A parameter is either a plain value the Inspector edits directly, a
/// reference into the graph, or (for `child` / `children`-shaped parameters)
/// more widgets.
sealed class PropValue {
  const PropValue();

  /// Parses one prop. [ownerId] and [key] seed deterministic ids for widgets
  /// nested inside parameters, which the JSON is allowed to leave implicit.
  factory PropValue.fromJson(
    Object? json, {
    required String ownerId,
    required String key,
    required String path,
  }) {
    if (json is Map<String, Object?>) {
      if (json.containsKey(r'$bind')) {
        return BindProp(
          PinRef.parse(json.str(r'$bind', path), path: '$path.\$bind'),
        );
      }
      if (json.containsKey(r'$event')) {
        return EventProp(json.str(r'$event', path));
      }
      if (json.containsKey(r'$expr')) {
        return ExprProp(json.str(r'$expr', path));
      }
      if (json.containsKey(r'$literal')) {
        return LiteralProp(json[r'$literal']);
      }
      if (json.containsKey('type')) {
        return WidgetProp(
          WidgetNode.fromJson(json, path: path, fallbackId: '${ownerId}_$key'),
        );
      }
      return LiteralProp(json);
    }

    if (json is List && json.isNotEmpty && json.every(_looksLikeWidget)) {
      return WidgetListProp([
        for (var i = 0; i < json.length; i++)
          WidgetNode.fromJson(
            asObj(json[i], '$path[$i]'),
            path: '$path[$i]',
            fallbackId: '${ownerId}_${key}_$i',
          ),
      ]);
    }

    return LiteralProp(json);
  }

  static bool _looksLikeWidget(Object? e) =>
      e is Map<String, Object?> && e.containsKey('type');

  Object? toJson();
}

/// A constant written straight into the generated source.
final class LiteralProp extends PropValue {
  const LiteralProp(this.value);

  final Object? value;

  /// True when the raw JSON form would be mistaken for one of the special
  /// map shapes on the way back in, and therefore needs `$literal` armour.
  bool get _needsEscaping {
    final v = value;
    if (v is! Map<String, Object?>) return false;
    return v.keys.any((k) => k.startsWith(r'$') || k == 'type');
  }

  @override
  Object? toJson() => _needsEscaping ? {r'$literal': value} : value;

  @override
  bool operator ==(Object other) =>
      other is LiteralProp && _deepEquals.equals(other.value, value);

  @override
  int get hashCode => _deepEquals.hash(value);
}

/// A graph output feeding this parameter (§5, "Binding").
final class BindProp extends PropValue {
  const BindProp(this.source);

  final PinRef source;

  @override
  Object? toJson() => {r'$bind': source.toString()};

  @override
  bool operator ==(Object other) => other is BindProp && other.source == source;

  @override
  int get hashCode => source.hashCode;
}

/// A callback parameter wired to an `Event` node.
final class EventProp extends PropValue {
  const EventProp(this.eventNodeId);

  final String eventNodeId;

  @override
  Object? toJson() => {r'$event': eventNodeId};

  @override
  bool operator ==(Object other) =>
      other is EventProp && other.eventNodeId == eventNodeId;

  @override
  int get hashCode => eventNodeId.hashCode;
}

/// A short inline Dart expression typed directly into the Inspector.
///
/// This is the pressure valve that keeps simple arithmetic from spawning four
/// nodes (§12, "图变成意大利面").
final class ExprProp extends PropValue {
  const ExprProp(this.code);

  final String code;

  @override
  Object? toJson() => {r'$expr': code};

  @override
  bool operator ==(Object other) => other is ExprProp && other.code == code;

  @override
  int get hashCode => code.hashCode;
}

/// A single nested widget, e.g. `AppBar.title`.
final class WidgetProp extends PropValue {
  const WidgetProp(this.widget);

  final WidgetNode widget;

  @override
  Object? toJson() => widget.toJson();

  @override
  bool operator ==(Object other) =>
      other is WidgetProp && other.widget == widget;

  @override
  int get hashCode => widget.hashCode;
}

/// A list of nested widgets, e.g. `AppBar.actions`.
final class WidgetListProp extends PropValue {
  const WidgetListProp(this.widgets);

  final List<WidgetNode> widgets;

  @override
  Object? toJson() => [for (final w in widgets) w.toJson()];

  @override
  bool operator ==(Object other) =>
      other is WidgetListProp &&
      const ListEquality<WidgetNode>().equals(other.widgets, widgets);

  @override
  int get hashCode => const ListEquality<WidgetNode>().hash(widgets);
}

/// One node of the Hierarchy — a widget instance (§7.1).
final class WidgetNode {
  WidgetNode({
    required this.id,
    required this.type,
    Map<String, PropValue>? props,
    List<WidgetNode>? children,
  })  : props = Map.unmodifiable(props ?? const {}),
        children = List.unmodifiable(children ?? const []);

  final String id;
  final String type;
  final Map<String, PropValue> props;
  final List<WidgetNode> children;

  factory WidgetNode.fromJson(
    Map<String, Object?> json, {
    required String path,
    String? fallbackId,
  }) {
    final id = json['id'] as String? ?? fallbackId;
    if (id == null) {
      throw ProjectFormatException('widget is missing "id"', path: path);
    }
    final type = json.str('type', path);

    final rawProps = json.objOrNull('props', path) ?? const {};
    final props = <String, PropValue>{
      for (final entry in rawProps.entries)
        entry.key: PropValue.fromJson(
          entry.value,
          ownerId: id,
          key: entry.key,
          path: '$path.props.${entry.key}',
        ),
    };

    final rawChildren = json.arrOrEmpty('children', path);
    final children = <WidgetNode>[
      for (var i = 0; i < rawChildren.length; i++)
        WidgetNode.fromJson(
          asObj(rawChildren[i], '$path.children[$i]'),
          path: '$path.children[$i]',
          fallbackId: '${id}_c$i',
        ),
    ];

    return WidgetNode(id: id, type: type, props: props, children: children);
  }

  Map<String, Object?> toJson() => pruneEmpty({
        'id': id,
        'type': type,
        'props': sortedKeys({
          for (final entry in props.entries) entry.key: entry.value.toJson(),
        }),
        'children': [for (final c in children) c.toJson()],
      });

  /// Every widget in this subtree, including ones nested inside props,
  /// in a stable pre-order.
  Iterable<WidgetNode> get descendantsAndSelf sync* {
    yield this;
    for (final prop in props.values) {
      switch (prop) {
        case WidgetProp(:final widget):
          yield* widget.descendantsAndSelf;
        case WidgetListProp(:final widgets):
          for (final w in widgets) {
            yield* w.descendantsAndSelf;
          }
        default:
          break;
      }
    }
    for (final child in children) {
      yield* child.descendantsAndSelf;
    }
  }

  WidgetNode copyWith({
    String? id,
    String? type,
    Map<String, PropValue>? props,
    List<WidgetNode>? children,
  }) =>
      WidgetNode(
        id: id ?? this.id,
        type: type ?? this.type,
        props: props ?? this.props,
        children: children ?? this.children,
      );

  @override
  String toString() => '$type#$id';

  @override
  bool operator ==(Object other) =>
      other is WidgetNode &&
      other.id == id &&
      other.type == type &&
      const MapEquality<String, PropValue>().equals(other.props, props) &&
      const ListEquality<WidgetNode>().equals(other.children, children);

  @override
  int get hashCode => Object.hash(
        id,
        type,
        const MapEquality<String, PropValue>().hash(props),
        const ListEquality<WidgetNode>().hash(children),
      );
}
