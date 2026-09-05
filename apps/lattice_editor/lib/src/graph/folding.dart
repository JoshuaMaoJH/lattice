import 'package:lattice_core/lattice_core.dart';

/// One port on a collapsed fold: an edge that crosses its boundary.
final class FoldPort {
  const FoldPort({
    required this.label,
    required this.type,
    required this.kind,
    required this.isInput,
    required this.outerPin,
    required this.innerPin,
  });

  final String label;
  final LatticeType type;
  final PinKind kind;
  final bool isInput;

  /// The pin outside the fold that this port stands in for.
  final PinRef outerPin;

  /// The hidden pin inside it.
  final PinRef innerPin;
}

/// Which nodes are hidden by a collapsed fold, and where their edges go
/// instead (§7.2, R14).
///
/// Folding is presentation only — the members stay in the graph and the
/// generated code is identical either way. All this does is answer, for a
/// canvas that is drawing edges, "this endpoint is inside a closed box; which
/// port on the box should the wire attach to?"
final class FoldMap {
  FoldMap._(this._hiddenBy, this._ports);

  /// Member node id -> the collapsed Subgraph hiding it.
  final Map<String, String> _hiddenBy;

  /// Subgraph node id -> its ports, in draw order.
  final Map<String, List<FoldPort>> _ports;

  static final FoldMap empty = FoldMap._(const {}, const {});

  static FoldMap of(WidgetUnit unit, NodeContext context) {
    final hiddenBy = <String, String>{};

    for (final fold in unit.graph.ofType('Subgraph')) {
      if (fold.get<bool>('collapsed') != true) continue;
      for (final member in fold.get<List<Object?>>('members') ?? const []) {
        if (member is String && member != fold.id) hiddenBy[member] = fold.id;
      }
    }
    if (hiddenBy.isEmpty) return empty;

    final ports = <String, List<FoldPort>>{};
    for (final edge in unit.graph.edges) {
      final fromFold = hiddenBy[edge.from.nodeId];
      final toFold = hiddenBy[edge.to.nodeId];
      // An edge wholly inside one fold, or wholly outside, needs no port.
      if (fromFold == toFold) continue;

      if (fromFold != null) {
        _addPort(
          ports,
          fromFold,
          FoldPort(
            label: edge.from.toString(),
            type: context.outputType(edge.from),
            kind: _kindOf(unit, context, edge.from, isInput: false),
            isInput: false,
            outerPin: edge.to,
            innerPin: edge.from,
          ),
        );
      }
      if (toFold != null) {
        _addPort(
          ports,
          toFold,
          FoldPort(
            label: edge.to.toString(),
            type: context.outputType(edge.from),
            kind: _kindOf(unit, context, edge.to, isInput: true),
            isInput: true,
            outerPin: edge.from,
            innerPin: edge.to,
          ),
        );
      }
    }

    // Inputs above outputs, then by label, so ports do not jump around when an
    // unrelated edge is added.
    for (final list in ports.values) {
      list.sort((a, b) {
        if (a.isInput != b.isInput) return a.isInput ? -1 : 1;
        return a.label.compareTo(b.label);
      });
    }

    return FoldMap._(hiddenBy, ports);
  }

  static void _addPort(
    Map<String, List<FoldPort>> ports,
    String foldId,
    FoldPort port,
  ) {
    final list = ports.putIfAbsent(foldId, () => []);
    if (list
        .any((p) => p.innerPin == port.innerPin && p.isInput == port.isInput)) {
      return;
    }
    list.add(port);
  }

  static PinKind _kindOf(
    WidgetUnit unit,
    NodeContext context,
    PinRef ref, {
    required bool isInput,
  }) {
    final node = unit.graph.node(ref.nodeId);
    if (node == null) return PinKind.data;
    final schema = NodeRegistry.lookup(node.type);
    final pin = isInput
        ? schema?.input(node, context, ref.pin)
        : schema?.output(node, context, ref.pin);
    return pin?.kind ?? PinKind.data;
  }

  bool get isEmpty => _hiddenBy.isEmpty;

  bool isHidden(String nodeId) => _hiddenBy.containsKey(nodeId);

  /// The collapsed fold hiding [nodeId], if any.
  String? foldFor(String nodeId) => _hiddenBy[nodeId];

  List<FoldPort> portsOf(String foldId) => _ports[foldId] ?? const [];

  /// The index of the port standing in for [innerPin], or -1.
  int portIndexFor(String foldId, PinRef innerPin, {required bool isInput}) {
    final list = portsOf(foldId);
    for (var i = 0; i < list.length; i++) {
      if (list[i].innerPin == innerPin && list[i].isInput == isInput) return i;
    }
    return -1;
  }
}
