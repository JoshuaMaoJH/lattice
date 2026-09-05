import 'errors.dart';

/// A reference to one pin on one graph node, e.g. `n_fmt.args[0]`.
///
/// [index] is set for variadic pins (`Format.args`), which the editor renders
/// as a growable row of sockets.
final class PinRef {
  const PinRef(this.nodeId, this.pin, {this.index});

  final String nodeId;
  final String pin;
  final int? index;

  static final RegExp _pattern =
      RegExp(r'^([A-Za-z0-9_]+)\.([A-Za-z0-9_]+)(?:\[(\d+)\])?$');

  factory PinRef.parse(String source, {String? path}) {
    final match = _pattern.firstMatch(source.trim());
    if (match == null) {
      throw ProjectFormatException(
        'malformed pin reference "$source" (expected "node.pin" or "node.pin[i]")',
        path: path,
      );
    }
    final index = match.group(3);
    return PinRef(
      match.group(1)!,
      match.group(2)!,
      index: index == null ? null : int.parse(index),
    );
  }

  /// The same pin without its index — `n_fmt.args[0]` becomes `n_fmt.args`.
  PinRef get base => index == null ? this : PinRef(nodeId, pin);

  @override
  String toString() => index == null ? '$nodeId.$pin' : '$nodeId.$pin[$index]';

  @override
  bool operator ==(Object other) =>
      other is PinRef &&
      other.nodeId == nodeId &&
      other.pin == pin &&
      other.index == index;

  @override
  int get hashCode => Object.hash(nodeId, pin, index);
}
