import '../types/lattice_type.dart';

/// Data pins are solid circles and form the reactive dependency graph; event
/// pins are hollow triangles and only ever join `Event` to `Action` (§7.2).
enum PinKind { data, event }

enum PinDirection { input, output }

/// One socket on a graph node.
final class PinSchema {
  const PinSchema({
    required this.name,
    required this.type,
    this.kind = PinKind.data,
    this.required = false,
    this.variadic = false,
    this.label,
  });

  /// An event pin, e.g. `Event.fire` or `SetSignal.exec`.
  const PinSchema.event(this.name, {this.required = true, LatticeType? payload})
      : type = payload ?? const EventType(),
        kind = PinKind.event,
        variadic = false,
        label = null;

  final String name;
  final LatticeType type;
  final PinKind kind;

  /// An unconnected required input is a hard error at codegen time.
  final bool required;

  /// A growable row of sockets addressed as `name[i]`, e.g. `Format.args`.
  final bool variadic;

  /// Display name; falls back to [name].
  final String? label;

  String get displayName => label ?? name;

  @override
  String toString() => '$name: ${type.dartName}${variadic ? '...' : ''}';
}
