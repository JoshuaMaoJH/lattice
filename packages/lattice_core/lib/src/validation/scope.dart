import '../model/graph.dart';
import '../model/hierarchy.dart';
import '../model/page.dart';
import '../model/pin_ref.dart';

/// Which `ForEach` templates each widget sits inside, and which ones each
/// graph node needs.
///
/// This is the whole of ADR-009's scope rule in one place: a widget may read
/// `item` only if it is inside the template that defines it. Everything else —
/// validation, codegen's variable naming, the decision not to hoist a
/// scope-dependent computation — reads off this map.
final class ScopeMap {
  ScopeMap._(this._enclosing, this._nodeScopes);

  /// Widget id -> enclosing `ForEach` widget ids, outermost first.
  final Map<String, List<String>> _enclosing;

  /// Graph node id -> `ForEach` widget ids its value depends on.
  final Map<String, Set<String>> _nodeScopes;

  static ScopeMap of(Page page) {
    final enclosing = <String, List<String>>{};

    void walk(WidgetNode widget, List<String> chain) {
      enclosing[widget.id] = chain;
      // A ForEach's own `items` are evaluated outside its loop, so widgets
      // nested in its props do not gain its scope; only its template does.
      final inner = widget.type == 'ForEach' ? [...chain, widget.id] : chain;

      for (final prop in widget.props.values) {
        switch (prop) {
          case WidgetProp(:final widget):
            walk(widget, chain);
          case WidgetListProp(:final widgets):
            for (final w in widgets) {
              walk(w, chain);
            }
          default:
            break;
        }
      }
      for (final child in widget.children) {
        walk(child, inner);
      }
    }

    walk(page.hierarchy, const []);
    return ScopeMap._(enclosing, _resolveNodeScopes(page.graph));
  }

  /// Transitive `ForEachItem` dependencies of every node, by data edges.
  static Map<String, Set<String>> _resolveNodeScopes(Graph graph) {
    final result = <String, Set<String>>{};

    Set<String> visit(String nodeId, Set<String> visiting) {
      final cached = result[nodeId];
      if (cached != null) return cached;
      if (!visiting.add(nodeId)) return const {};

      final node = graph.node(nodeId);
      final scopes = <String>{};
      if (node != null) {
        if (node.type == 'ForEachItem') {
          final owner = node.get<String>('forEach');
          if (owner != null) scopes.add(owner);
        }
        for (final edge in graph.edges) {
          if (edge.to.nodeId != nodeId) continue;
          scopes.addAll(visit(edge.from.nodeId, visiting));
        }
      }

      visiting.remove(nodeId);
      result[nodeId] = scopes;
      return scopes;
    }

    for (final node in graph.nodes) {
      visit(node.id, {});
    }
    return result;
  }

  /// The `ForEach` templates [widgetId] is inside, outermost first.
  List<String> enclosing(String widgetId) => _enclosing[widgetId] ?? const [];

  /// The `ForEach` templates a value produced by [nodeId] belongs to.
  Set<String> scopesOf(String nodeId) => _nodeScopes[nodeId] ?? const {};

  /// The scopes reachable through [pin].
  Set<String> scopesOfPin(PinRef pin) => scopesOf(pin.nodeId);

  /// Scopes [nodeId] needs that [widgetId] is not inside. Empty means the
  /// reference is legal.
  Set<String> missingFor(String widgetId, String nodeId) {
    final available = enclosing(widgetId).toSet();
    return scopesOf(nodeId).difference(available);
  }

  bool isInsideTemplate(String widgetId) => enclosing(widgetId).isNotEmpty;
}
