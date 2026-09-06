import 'package:collection/collection.dart';

/// Pin colour families (§7.3).
///
/// The editor paints a pin by family, so a user can tell at a glance whether
/// two pins are even plausibly connectable before attempting the drag.
enum TypeFamily {
  number,
  text,
  boolean,
  list,
  map,
  model,
  widget,
  event,
  style,
  special,
}

/// A type in the Lattice type system.
///
/// Deliberately narrower than Dart's: only the promotions listed in §7.2 are
/// allowed, so a mis-wire is rejected while the user is dragging the edge
/// rather than by `dart analyze` after codegen.
sealed class LatticeType {
  const LatticeType();

  /// The Dart source spelling, e.g. `List<String>?`. This is what lands in
  /// generated code, so it has to be a type Dart knows.
  String get dartName;

  /// How the type is written in a project file. The same as [dartName] for
  /// everything except `Event`, whose Dart form is a function type.
  String get spelling => dartName;

  TypeFamily get family;

  /// Whether values round-trip through JSON without a hand-written codec.
  /// Gates what may cross a `@server` subgraph boundary (§7.7).
  bool get isSerializable;

  /// Whether a value of this type may be stored in a pin of type [target].
  bool isAssignableTo(LatticeType target);

  @override
  String toString() => dartName;

  @override
  bool operator ==(Object other) =>
      other is LatticeType &&
      other.runtimeType == runtimeType &&
      other.dartName == dartName;

  @override
  int get hashCode => Object.hash(runtimeType, dartName);
}

/// The built-in scalar types.
enum PrimitiveKind {
  int$('int', TypeFamily.number, true),
  double$('double', TypeFamily.number, true),
  num$('num', TypeFamily.number, true),
  bool$('bool', TypeFamily.boolean, true),
  string$('String', TypeFamily.text, true),
  color$('Color', TypeFamily.style, false),
  edgeInsets$('EdgeInsets', TypeFamily.style, false),
  textStyle$('TextStyle', TypeFamily.style, false),
  iconData$('IconData', TypeFamily.style, false),
  alignment$('Alignment', TypeFamily.style, false),
  duration$('Duration', TypeFamily.special, false),
  dynamic$('dynamic', TypeFamily.special, false),
  void$('void', TypeFamily.special, false);

  const PrimitiveKind(this.dartName, this.family, this.isSerializable);

  final String dartName;
  final TypeFamily family;
  final bool isSerializable;

  static PrimitiveKind? byName(String name) =>
      values.firstWhereOrNull((k) => k.dartName == name);
}

final class PrimitiveType extends LatticeType {
  const PrimitiveType(this.kind);

  final PrimitiveKind kind;

  static const int_ = PrimitiveType(PrimitiveKind.int$);
  static const double_ = PrimitiveType(PrimitiveKind.double$);
  static const num_ = PrimitiveType(PrimitiveKind.num$);
  static const bool_ = PrimitiveType(PrimitiveKind.bool$);
  static const string = PrimitiveType(PrimitiveKind.string$);
  static const color = PrimitiveType(PrimitiveKind.color$);
  static const edgeInsets = PrimitiveType(PrimitiveKind.edgeInsets$);
  static const textStyle = PrimitiveType(PrimitiveKind.textStyle$);
  static const iconData = PrimitiveType(PrimitiveKind.iconData$);
  static const alignment = PrimitiveType(PrimitiveKind.alignment$);
  static const duration = PrimitiveType(PrimitiveKind.duration$);
  static const dynamic_ = PrimitiveType(PrimitiveKind.dynamic$);
  static const void_ = PrimitiveType(PrimitiveKind.void$);

  @override
  String get dartName => kind.dartName;

  @override
  TypeFamily get family => kind.family;

  @override
  bool get isSerializable => kind.isSerializable;

  @override
  bool isAssignableTo(LatticeType target) {
    if (target is NullableType) return isAssignableTo(target.inner);
    if (kind == PrimitiveKind.dynamic$ || target == dynamic_) return true;
    if (target is! PrimitiveType) return false;
    if (target.kind == kind) return true;
    // The only widening the graph permits (§7.2).
    return switch ((kind, target.kind)) {
      (PrimitiveKind.int$, PrimitiveKind.double$) => true,
      (PrimitiveKind.int$, PrimitiveKind.num$) => true,
      (PrimitiveKind.double$, PrimitiveKind.num$) => true,
      _ => false,
    };
  }
}

/// A Flutter enum exposed to the graph, e.g. `MainAxisAlignment`.
final class EnumType extends LatticeType {
  const EnumType(this.name, this.values);

  final String name;
  final List<String> values;

  @override
  String get dartName => name;

  @override
  TypeFamily get family => TypeFamily.style;

  @override
  bool get isSerializable => true;

  @override
  bool isAssignableTo(LatticeType target) {
    if (target is NullableType) return isAssignableTo(target.inner);
    if (target == PrimitiveType.dynamic_) return true;
    return target is EnumType && target.name == name;
  }
}

final class ListType extends LatticeType {
  const ListType(this.element);

  final LatticeType element;

  @override
  String get dartName => 'List<${element.dartName}>';

  @override
  TypeFamily get family => TypeFamily.list;

  @override
  bool get isSerializable => element.isSerializable;

  @override
  bool isAssignableTo(LatticeType target) {
    if (target is NullableType) return isAssignableTo(target.inner);
    if (target == PrimitiveType.dynamic_) return true;
    return target is ListType && element.isAssignableTo(target.element);
  }
}

final class MapType extends LatticeType {
  const MapType(this.key, this.value);

  final LatticeType key;
  final LatticeType value;

  @override
  String get dartName => 'Map<${key.dartName}, ${value.dartName}>';

  @override
  TypeFamily get family => TypeFamily.map;

  @override
  bool get isSerializable => key.isSerializable && value.isSerializable;

  @override
  bool isAssignableTo(LatticeType target) {
    if (target is NullableType) return isAssignableTo(target.inner);
    if (target == PrimitiveType.dynamic_) return true;
    return target is MapType &&
        key.isAssignableTo(target.key) &&
        value.isAssignableTo(target.value);
  }
}

final class NullableType extends LatticeType {
  const NullableType(this.inner);

  final LatticeType inner;

  @override
  String get dartName => '${inner.dartName}?';

  @override
  TypeFamily get family => inner.family;

  @override
  bool get isSerializable => inner.isSerializable;

  @override
  bool isAssignableTo(LatticeType target) {
    if (target == PrimitiveType.dynamic_) return true;
    // A nullable value only fits a nullable slot.
    return target is NullableType && inner.isAssignableTo(target.inner);
  }
}

/// A user-defined struct from `models/` (§5).
final class ModelType extends LatticeType {
  const ModelType(this.name);

  final String name;

  @override
  String get dartName => name;

  @override
  TypeFamily get family => TypeFamily.model;

  @override
  bool get isSerializable => true;

  @override
  bool isAssignableTo(LatticeType target) {
    if (target is NullableType) return isAssignableTo(target.inner);
    if (target == PrimitiveType.dynamic_) return true;
    return target is ModelType && target.name == name;
  }
}

/// The output of a template subgraph (`ForEach`, `If`).
final class WidgetType extends LatticeType {
  const WidgetType();

  @override
  String get dartName => 'Widget';

  @override
  TypeFamily get family => TypeFamily.widget;

  @override
  bool get isSerializable => false;

  @override
  bool isAssignableTo(LatticeType target) {
    if (target is NullableType) return isAssignableTo(target.inner);
    return target is WidgetType || target == PrimitiveType.dynamic_;
  }
}

final class FutureType extends LatticeType {
  const FutureType(this.inner);

  final LatticeType inner;

  @override
  String get dartName => 'Future<${inner.dartName}>';

  @override
  TypeFamily get family => TypeFamily.special;

  @override
  bool get isSerializable => false;

  @override
  bool isAssignableTo(LatticeType target) {
    if (target is NullableType) return isAssignableTo(target.inner);
    if (target == PrimitiveType.dynamic_) return true;
    return target is FutureType && inner.isAssignableTo(target.inner);
  }
}

/// The type of an event pin (hollow triangle, §7.2). [payload] is what the
/// callback hands over, e.g. `String` for `TextField.onChanged`.
final class EventType extends LatticeType {
  const EventType([this.payload]);

  final LatticeType? payload;

  /// `Event` is Lattice's word for it; Dart's word is a function type, and
  /// this is the name that has to compile. A prefab parameter declared
  /// `Event` becomes a `VoidCallback` field on the generated widget.
  @override
  String get dartName =>
      payload == null ? 'VoidCallback' : 'void Function(${payload!.dartName})';

  /// What a person writes in `params`, and what round-trips through JSON.
  @override
  String get spelling =>
      payload == null ? 'Event' : 'Event<${payload!.dartName}>';

  @override
  TypeFamily get family => TypeFamily.event;

  @override
  bool get isSerializable => false;

  @override
  bool isAssignableTo(LatticeType target) =>
      target is EventType &&
      (target.payload == null || target.payload == payload);
}
