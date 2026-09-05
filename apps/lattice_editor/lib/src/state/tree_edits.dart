import 'package:lattice_core/lattice_core.dart';

/// Pure edits over a widget tree.
///
/// Every function returns a new tree; nothing is mutated. That is what makes
/// undo a matter of keeping old snapshots rather than writing an inverse for
/// each operation — and inverses are where editors grow their subtlest bugs.
class TreeEdits {
  const TreeEdits._();

  /// Replaces the node with [id], searching children *and* widget-valued
  /// props, so `AppBar.title` is reachable the same way a child is.
  static WidgetNode replace(
      WidgetNode root, String id, WidgetNode replacement) {
    if (root.id == id) return replacement;
    return root.copyWith(
      props: _mapProps(root.props, (w) => replace(w, id, replacement)),
      children: [for (final c in root.children) replace(c, id, replacement)],
    );
  }

  /// Removes the node with [id]. Returns null when [root] itself was removed.
  static WidgetNode? remove(WidgetNode root, String id) {
    if (root.id == id) return null;
    return root.copyWith(
      props: {
        for (final entry in root.props.entries)
          if (_removeFromProp(entry.value, id) case final prop?)
            entry.key: prop,
      },
      children: [
        for (final child in root.children)
          if (remove(child, id) case final kept?) kept,
      ],
    );
  }

  /// Inserts [child] under [parentId] at [index] (appending when null).
  static WidgetNode insert(
    WidgetNode root,
    String parentId,
    WidgetNode child, {
    int? index,
  }) {
    if (root.id == parentId) {
      final children = [...root.children];
      children.insert(
          (index ?? children.length).clamp(0, children.length), child);
      return root.copyWith(children: children);
    }
    return root.copyWith(
      props: _mapProps(
          root.props, (w) => insert(w, parentId, child, index: index)),
      children: [
        for (final c in root.children) insert(c, parentId, child, index: index),
      ],
    );
  }

  /// Moves [widgetId] to sit under [parentId] at [index].
  ///
  /// Removal happens first, so [index] refers to the list *after* the node has
  /// left its old position — which is what a drag actually means when it
  /// reorders within one parent.
  static WidgetNode? move(
    WidgetNode root,
    String widgetId,
    String parentId, {
    int? index,
  }) {
    final moving = find(root, widgetId);
    if (moving == null) return root;
    if (widgetId == parentId || contains(moving, parentId)) {
      // Dropping a node into its own subtree would detach the tree.
      return root;
    }
    final without = remove(root, widgetId);
    if (without == null) return null;
    return insert(without, parentId, moving, index: index);
  }

  static WidgetNode? find(WidgetNode root, String id) {
    for (final widget in root.descendantsAndSelf) {
      if (widget.id == id) return widget;
    }
    return null;
  }

  /// The id of [childId]'s parent, or null for the root.
  static String? parentOf(WidgetNode root, String childId) {
    for (final widget in root.descendantsAndSelf) {
      final isParent = widget.children.any((c) => c.id == childId) ||
          widget.props.values.any((p) => switch (p) {
                WidgetProp(:final widget) => widget.id == childId,
                WidgetListProp(:final widgets) =>
                  widgets.any((w) => w.id == childId),
                _ => false,
              });
      if (isParent) return widget.id;
    }
    return null;
  }

  static bool contains(WidgetNode root, String id) =>
      root.descendantsAndSelf.any((w) => w.id == id);

  /// Sets or clears one prop.
  static WidgetNode setProp(
    WidgetNode root,
    String widgetId,
    String name,
    PropValue? value,
  ) {
    final target = find(root, widgetId);
    if (target == null) return root;
    final props = {...target.props};
    if (value == null) {
      props.remove(name);
    } else {
      props[name] = value;
    }
    return replace(root, widgetId, target.copyWith(props: props));
  }

  /// Every id in the subtree, so a caller can free the graph nodes that
  /// referred to a deleted widget.
  static Set<String> idsIn(WidgetNode root) =>
      {for (final w in root.descendantsAndSelf) w.id};

  static Map<String, PropValue> _mapProps(
    Map<String, PropValue> props,
    WidgetNode Function(WidgetNode) transform,
  ) =>
      {
        for (final entry in props.entries)
          entry.key: switch (entry.value) {
            WidgetProp(:final widget) => WidgetProp(transform(widget)),
            WidgetListProp(:final widgets) =>
              WidgetListProp([for (final w in widgets) transform(w)]),
            final other => other,
          },
      };

  static PropValue? _removeFromProp(PropValue prop, String id) =>
      switch (prop) {
        WidgetProp(:final widget) =>
          widget.id == id ? null : WidgetProp(remove(widget, id) ?? widget),
        WidgetListProp(:final widgets) => WidgetListProp([
            for (final w in widgets)
              if (w.id != id)
                if (remove(w, id) case final kept?) kept,
          ]),
        final other => other,
      };
}
