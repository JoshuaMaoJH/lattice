import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lattice_core/lattice_core.dart';

import '../state/editor_controller.dart';
import '../state/project_edits.dart';
import '../state/tree_edits.dart';
import '../theme.dart';
import '../widgets/chrome.dart';

/// The property sheet (§7.1, R2).
///
/// Every row is generated from the schema, so a widget the registry knows
/// about is editable the day it is added — there is no per-widget form to
/// write. Each value parameter carries the "⚡" that turns it into a graph
/// input; that button is the whole of R4's user-facing surface.
class InspectorPanel extends StatelessWidget {
  const InspectorPanel({super.key, required this.controller});

  final EditorController controller;

  @override
  Widget build(BuildContext context) {
    return Panel(
      title: 'Inspector',
      child: switch (controller.selection) {
        WidgetSelection(:final widgetId) => _widgetForm(context, widgetId),
        NodeSelection(:final nodeId) => _nodeForm(context, nodeId),
        NoSelection() => const _Empty(
            'Select a widget in the Hierarchy or a node in the Graph.',
          ),
      },
    );
  }

  // ---------------------------------------------------------------------------

  Widget _widgetForm(BuildContext context, String widgetId) {
    final widget = TreeEdits.find(controller.activeUnit.hierarchy, widgetId);
    if (widget == null) {
      return const _Empty('That widget is gone.');
    }
    final schema = WidgetLookup(controller.project).lookup(widget.type);
    if (schema == null) {
      return _Empty('"${widget.type}" is not a known widget.');
    }

    final problems = controller.diagnosticsFor(widgetId: widgetId).toList();

    return ListView(
      padding: const EdgeInsets.only(bottom: 16),
      children: [
        _Header(title: widget.type, subtitle: widget.id),
        if (problems.isNotEmpty) _Problems(problems),
        for (final param in schema.params)
          _ParamRow(
            controller: controller,
            widgetId: widgetId,
            schema: schema,
            param: param,
          ),
        if (schema.acceptsChildren)
          _Note(
            schema.childArity == ChildArity.one
                ? 'Takes one child, emitted as ${schema.childrenParam}.'
                : 'Takes any number of children, emitted as '
                    '${schema.childrenParam}.',
          ),
      ],
    );
  }

  Widget _nodeForm(BuildContext context, String nodeId) {
    final unit = controller.activeUnit;
    final node = unit.graph.node(nodeId);
    if (node == null) return const _Empty('That node is gone.');

    final schema = controller.nodes.lookup(node.type);
    final problems = controller.diagnosticsFor(nodeId: nodeId).toList();

    return ListView(
      padding: const EdgeInsets.only(bottom: 16),
      children: [
        _Header(title: node.type, subtitle: node.id),
        if (schema != null && schema.summary.isNotEmpty) _Note(schema.summary),
        if (problems.isNotEmpty) _Problems(problems),
        for (final key in schema?.configKeys ?? const <String>[])
          _ConfigRow(controller: controller, node: node, configKey: key),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(LatticeTheme.gutter, 10, 10, 10),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: LatticeTheme.hairline)),
        ),
        child: Row(
          children: [
            Text(title, style: LatticeTheme.title),
            const SizedBox(width: 8),
            Text(subtitle, style: LatticeTheme.monoSmall),
          ],
        ),
      );
}

class _Note extends StatelessWidget {
  const _Note(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(LatticeTheme.gutter, 8, 10, 8),
        child: Text(text, style: LatticeTheme.secondary),
      );
}

class _Empty extends StatelessWidget {
  const _Empty(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: LatticeTheme.secondary,
          ),
        ),
      );
}

class _Problems extends StatelessWidget {
  const _Problems(this.problems);

  final List<Diagnostic> problems;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(LatticeTheme.gutter, 8, 10, 8),
        color: LatticeTheme.error.withValues(alpha: 0.08),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final problem in problems)
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Text(
                  problem.message,
                  style: LatticeTheme.secondary.copyWith(
                    color: problem.isError
                        ? LatticeTheme.error
                        : LatticeTheme.warning,
                  ),
                ),
              ),
          ],
        ),
      );
}

/// One parameter: its name, its current value, and the controls that change
/// how it is supplied.
class _ParamRow extends StatelessWidget {
  const _ParamRow({
    required this.controller,
    required this.widgetId,
    required this.schema,
    required this.param,
  });

  final EditorController controller;
  final String widgetId;
  final WidgetSchema schema;
  final ParamSchema param;

  @override
  Widget build(BuildContext context) {
    final widget = TreeEdits.find(controller.activeUnit.hierarchy, widgetId)!;
    final prop = widget.props[param.name];

    return Container(
      padding: const EdgeInsets.fromLTRB(LatticeTheme.gutter, 6, 8, 6),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: LatticeTheme.hairline)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              TypeDot(
                param.type,
                size: 7,
                hollow: param.kind == ParamKind.callback,
              ),
              const SizedBox(width: 6),
              Text(param.name, style: LatticeTheme.mono),
              if (param.required)
                Text(' *',
                    style: LatticeTheme.monoSmall.copyWith(
                      color: LatticeTheme.textFaint,
                    )),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  param.kind == ParamKind.callback
                      ? '(${param.type == PrimitiveType.void_ ? '' : param.type.dartName})'
                      : param.type.dartName,
                  overflow: TextOverflow.ellipsis,
                  style: LatticeTheme.monoSmall.copyWith(fontSize: 10),
                ),
              ),
              ..._actions(context, prop),
            ],
          ),
          const SizedBox(height: 4),
          _editor(context, prop),
        ],
      ),
    );
  }

  List<Widget> _actions(BuildContext context, PropValue? prop) {
    if (param.kind == ParamKind.callback) {
      return [
        ToolButton(
          icon: Icons.bolt_outlined,
          tooltip: prop is EventProp
              ? 'Already wired to ${prop.eventNodeId}'
              : 'Create an Event node for this callback',
          isActive: prop is EventProp,
          onPressed: prop is EventProp ? null : _wireEvent,
        ),
        if (prop is EventProp)
          ToolButton(
            icon: Icons.link_off,
            tooltip: 'Unwire',
            onPressed: () => _set(null),
          ),
      ];
    }
    if (!param.bindable || param.kind != ParamKind.value) return const [];

    final pending = controller.pendingBinding;
    final isPending =
        pending?.widgetId == widgetId && pending?.param == param.name;

    return [
      ToolButton(
        icon: Icons.bolt_outlined,
        tooltip: isPending
            ? 'Pick an output pin in the Graph, or press Escape'
            : 'Bind this parameter to a graph output',
        isActive: isPending || prop is BindProp,
        onPressed: () => isPending
            ? controller.cancelBinding()
            : controller.beginBinding(widgetId, param.name, param.type),
      ),
      if (prop is BindProp)
        ToolButton(
          icon: Icons.link_off,
          tooltip: 'Unbind and go back to a literal value',
          onPressed: () => _set(null),
        ),
    ];
  }

  Widget _editor(BuildContext context, PropValue? prop) {
    switch (prop) {
      case BindProp(:final source):
        return _Bound(controller: controller, source: source);
      case EventProp(:final eventNodeId):
        return _Wired(controller: controller, eventNodeId: eventNodeId);
      case WidgetProp(:final widget):
        return Text('${widget.type} · ${widget.id}',
            style: LatticeTheme.monoSmall);
      case WidgetListProp(:final widgets):
        return Text('${widgets.length} widget(s)',
            style: LatticeTheme.monoSmall);
      case ExprProp(:final code):
        return _ValueField(
          initial: code,
          hint: 'Dart expression',
          onSubmit: (value) => _set(ExprProp(value)),
        );
      case LiteralProp(:final value):
        return _literalEditor(value);
      case null:
        return _literalEditor(null);
    }
  }

  Widget _literalEditor(Object? value) {
    final type = param.type is NullableType
        ? (param.type as NullableType).inner
        : param.type;

    if (type is PrimitiveType && type.kind == PrimitiveKind.bool$) {
      return Row(
        children: [
          SizedBox(
            height: 20,
            child: Switch(
              value: value == true,
              onChanged: (next) => _set(LiteralProp(next)),
            ),
          ),
          const SizedBox(width: 8),
          Text('${value == true}', style: LatticeTheme.monoSmall),
        ],
      );
    }

    if (type is EnumType) {
      return DropdownButton<String>(
        value: value is String && type.values.contains(value) ? value : null,
        isDense: true,
        isExpanded: true,
        dropdownColor: LatticeTheme.raised,
        underline: const Hairline(),
        style: LatticeTheme.mono,
        hint: Text('unset', style: LatticeTheme.monoSmall),
        items: [
          for (final option in type.values)
            DropdownMenuItem(value: option, child: Text(option)),
        ],
        onChanged: (next) => _set(next == null ? null : LiteralProp(next)),
      );
    }

    return _ValueField(
      initial: value == null ? '' : '$value',
      hint: param.defaultValue == null ? 'unset' : '${param.defaultValue}',
      numeric: type is PrimitiveType &&
          const {
            PrimitiveKind.int$,
            PrimitiveKind.double$,
            PrimitiveKind.num$,
            PrimitiveKind.edgeInsets$,
          }.contains(type.kind),
      onSubmit: (text) {
        if (text.isEmpty) return _set(null);
        final parsed = num.tryParse(text);
        _set(LiteralProp(parsed ?? text));
      },
    );
  }

  void _set(PropValue? value) => controller.apply(
        'Set ${param.name}',
        (project) => ProjectEdits.setProp(
          project,
          controller.activeUnitId,
          widgetId,
          param.name,
          value,
        ),
      );

  void _wireEvent() {
    late String nodeId;
    controller.apply('Wire ${param.name}', (project) {
      final (next, id) = ProjectEdits.bindEvent(
        project,
        controller.activeUnitId,
        widgetId,
        param.name,
      );
      nodeId = id;
      return next;
    });
    controller.select(NodeSelection(nodeId));
  }
}

/// Shows what a bound parameter is reading, in the type's own colour so the
/// link back to the Graph is visible without reading the id.
class _Bound extends StatelessWidget {
  const _Bound({required this.controller, required this.source});

  final EditorController controller;
  final PinRef source;

  @override
  Widget build(BuildContext context) {
    final context0 = NodeContext(
      graph: controller.activeUnit.graph,
      unit: controller.activeUnit,
      project: controller.project,
    );
    final type = context0.outputType(source);

    return InkWell(
      onTap: () => controller.select(NodeSelection(source.nodeId)),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        decoration: BoxDecoration(
          color: LatticeTheme.forType(type).withValues(alpha: 0.12),
          border: Border(
            left: BorderSide(color: LatticeTheme.forType(type), width: 2),
          ),
        ),
        child: Row(
          children: [
            Text('$source', style: LatticeTheme.mono),
            const Spacer(),
            Text(type.dartName,
                style: LatticeTheme.monoSmall.copyWith(fontSize: 10)),
          ],
        ),
      ),
    );
  }
}

class _Wired extends StatelessWidget {
  const _Wired({required this.controller, required this.eventNodeId});

  final EditorController controller;
  final String eventNodeId;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: () => controller.select(NodeSelection(eventNodeId)),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          decoration: BoxDecoration(
            color: LatticeTheme.forFamily(TypeFamily.event)
                .withValues(alpha: 0.12),
            border: Border(
              left: BorderSide(
                color: LatticeTheme.forFamily(TypeFamily.event),
                width: 2,
              ),
            ),
          ),
          child: Text(eventNodeId, style: LatticeTheme.mono),
        ),
      );
}

/// A text field that commits on Enter or on losing focus, so editing a value
/// does not push one undo entry per keystroke.
class _ValueField extends StatefulWidget {
  const _ValueField({
    required this.initial,
    required this.onSubmit,
    this.hint = '',
    this.numeric = false,
  });

  final String initial;
  final String hint;
  final bool numeric;
  final void Function(String value) onSubmit;

  @override
  State<_ValueField> createState() => _ValueFieldState();
}

class _ValueFieldState extends State<_ValueField> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initial);
  final FocusNode _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus) _commit();
    });
  }

  @override
  void didUpdateWidget(_ValueField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_focus.hasFocus && widget.initial != _controller.text) {
      _controller.text = widget.initial;
    }
  }

  void _commit() {
    if (_controller.text != widget.initial) widget.onSubmit(_controller.text);
  }

  @override
  void dispose() {
    _focus.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 24,
        child: TextField(
          controller: _controller,
          focusNode: _focus,
          style: LatticeTheme.mono,
          keyboardType: widget.numeric ? TextInputType.number : null,
          inputFormatters: widget.numeric
              ? [FilteringTextInputFormatter.allow(RegExp(r'[0-9.\-]'))]
              : null,
          onSubmitted: (_) => _commit(),
          decoration: InputDecoration(
            isDense: true,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            hintText: widget.hint,
            hintStyle: LatticeTheme.monoSmall,
            filled: true,
            fillColor: LatticeTheme.canvas,
            border: const OutlineInputBorder(
              borderSide: BorderSide(color: LatticeTheme.hairline),
            ),
            enabledBorder: const OutlineInputBorder(
              borderSide: BorderSide(color: LatticeTheme.hairline),
            ),
          ),
        ),
      );
}

/// One config key of a graph node — `dartType`, `template`, `fn` and friends.
class _ConfigRow extends StatelessWidget {
  const _ConfigRow({
    required this.controller,
    required this.node,
    required this.configKey,
  });

  final EditorController controller;
  final GraphNode node;
  final String configKey;

  @override
  Widget build(BuildContext context) {
    final value = node.config[configKey];
    return Container(
      padding: const EdgeInsets.fromLTRB(LatticeTheme.gutter, 6, 8, 6),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: LatticeTheme.hairline)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(configKey, style: LatticeTheme.mono),
          const SizedBox(height: 4),
          if (value is List)
            // A list config — a Subgraph's members, most of all — is editable
            // as comma-separated ids. Without multi-select on the canvas this
            // is how a fold gets its contents.
            _ValueField(
              initial: value.whereType<Object>().join(', '),
              hint: 'node ids, comma separated',
              onSubmit: (text) {
                final items = [
                  for (final part in text.split(','))
                    if (part.trim().isNotEmpty) part.trim(),
                ];
                controller.apply(
                  'Set $configKey',
                  (project) => ProjectEdits.setNodeConfig(
                    project,
                    controller.activeUnitId,
                    node.id,
                    configKey,
                    items.isEmpty ? null : items,
                  ),
                );
              },
            )
          else if (value is Map)
            Text('$value', style: LatticeTheme.monoSmall)
          else
            _ValueField(
              initial: value == null ? '' : '$value',
              hint: 'unset',
              onSubmit: (text) {
                final parsed = text.isEmpty
                    ? null
                    : (num.tryParse(text) ??
                        (text == 'true'
                            ? true
                            : text == 'false'
                                ? false
                                : text));
                controller.apply(
                  'Set $configKey',
                  (project) => ProjectEdits.setNodeConfig(
                    project,
                    controller.activeUnitId,
                    node.id,
                    configKey,
                    parsed,
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}
