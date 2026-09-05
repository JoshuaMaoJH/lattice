// Regenerates docs/node-reference.md from the registries, so the reference
// cannot drift from the code that implements it.
//
//   dart run tool/generate_node_reference.dart
import 'dart:io';

import 'package:lattice_core/lattice_core.dart';

void main() {
  final buffer = StringBuffer()
    ..writeln('# 节点与 Widget 参考')
    ..writeln()
    ..writeln('> 本文件由 `dart run tool/generate_node_reference.dart` 从')
    ..writeln('> `lattice_core` 的注册表生成，请勿手工编辑。')
    ..writeln();

  _writeNodes(buffer);
  _writeWidgets(buffer);
  _writeTypes(buffer);

  File('docs/node-reference.md').writeAsStringSync(buffer.toString());
  stdout.writeln('Wrote docs/node-reference.md');
}

const _categoryTitles = {
  NodeCategory.state: '状态',
  NodeCategory.compute: '计算（纯函数）',
  NodeCategory.ui: '界面',
  NodeCategory.event: '事件',
  NodeCategory.action: '动作（唯一允许副作用的地方）',
  NodeCategory.control: '控制',
  NodeCategory.escape: '逃生舱',
  NodeCategory.organize: '组织',
};

void _writeNodes(StringBuffer buffer) {
  buffer
    ..writeln('## 节点库')
    ..writeln()
    ..writeln('引脚类型随节点配置而变，下表展示的是默认配置下的形状。')
    ..writeln('`…` 表示可变长引脚（如 `Format.args[0]`、`args[1]`）。')
    ..writeln();

  // A throwaway context: pins that depend on a specific project resolve to
  // their defaults, which is exactly what a reference table should show.
  final context = NodeContext(graph: Graph.empty);

  for (final category in NodeCategory.values) {
    final schemas = NodeRegistry.byCategory(category).toList();
    if (schemas.isEmpty) continue;

    buffer
      ..writeln('### ${_categoryTitles[category] ?? category.name}')
      ..writeln()
      ..writeln('| 节点 | 输入 | 输出 | 配置 | 说明 |')
      ..writeln('|---|---|---|---|---|');

    for (final schema in schemas) {
      final node = GraphNode(id: 'n', type: schema.type);
      final inputs = schema.inputs(node, context).map(_pin).join('<br>');
      final outputs = schema.outputs(node, context).map(_pin).join('<br>');
      final config = schema.configKeys.map((k) => '`$k`').join(', ');
      buffer.writeln(
        '| `${schema.type}` | ${inputs.isEmpty ? '—' : inputs} | '
        '${outputs.isEmpty ? '—' : outputs} | ${config.isEmpty ? '—' : config} | '
        '${schema.summary} |',
      );
    }
    buffer.writeln();
  }
}

String _pin(PinSchema pin) {
  final marker = pin.kind == PinKind.event ? '▷' : '●';
  final variadic = pin.variadic ? '…' : '';
  final required = pin.required && pin.kind == PinKind.data ? '*' : '';
  return '$marker `${pin.name}$variadic$required`: ${pin.type.dartName}';
}

const _widgetCategoryTitles = {
  WidgetCategory.structure: '结构',
  WidgetCategory.layout: '布局',
  WidgetCategory.content: '内容',
  WidgetCategory.input: '输入',
};

void _writeWidgets(StringBuffer buffer) {
  buffer
    ..writeln('## Widget 白名单')
    ..writeln()
    ..writeln('共 ${WidgetRegistry.all.length} 个。白名单之外的 widget 通过 ')
    ..writeln('`Dart Code` 节点接入（§7.8）。')
    ..writeln()
    ..writeln('参数标记：`*` 必填，`⚡` 可绑定到图输出，`▷` 回调（接 Event 节点），')
    ..writeln('`◻` 嵌套 widget。')
    ..writeln();

  for (final category in WidgetCategory.values) {
    final schemas = WidgetRegistry.byCategory(category).toList();
    if (schemas.isEmpty) continue;

    buffer
      ..writeln('### ${_widgetCategoryTitles[category] ?? category.name}')
      ..writeln()
      ..writeln('| Widget | children | 参数 | 说明 |')
      ..writeln('|---|---|---|---|');

    for (final schema in schemas) {
      final children = switch (schema.childArity) {
        ChildArity.none => '—',
        ChildArity.one => '1 → `${schema.childrenParam}`',
        ChildArity.many => 'n → `${schema.childrenParam}`',
      };
      final params = schema.params.map(_param).join('<br>');
      buffer.writeln(
        '| `${schema.type}`${schema.constCtor ? '' : ' †'} | $children | '
        '${params.isEmpty ? '—' : params} | ${schema.summary} |',
      );
    }
    buffer.writeln();
  }
  buffer
    ..writeln('† 该 widget 的 Flutter 构造函数不是 `const`，生成代码不会给它加 ')
    ..writeln('`const`（见 ADR-007）。')
    ..writeln();
}

String _param(ParamSchema param) {
  final marker = switch (param.kind) {
    ParamKind.callback => '▷',
    ParamKind.widget => '◻',
    ParamKind.widgetList => '◻…',
    ParamKind.value => param.bindable ? '⚡' : ' ',
  };
  final required = param.required ? '*' : '';
  final defaulted =
      param.defaultValue == null ? '' : ' = `${param.defaultValue}`';
  final type = param.kind == ParamKind.callback
      ? '(${param.type == PrimitiveType.void_ ? '' : param.type.dartName})'
      : param.type.dartName;
  return '$marker `${param.name}$required`: $type$defaulted';
}

void _writeTypes(StringBuffer buffer) {
  buffer
    ..writeln('## 类型系统')
    ..writeln()
    ..writeln('### 基础类型')
    ..writeln()
    ..writeln('| 类型 | 引脚族 | 可 JSON 序列化 |')
    ..writeln('|---|---|---|');
  for (final kind in PrimitiveKind.values) {
    buffer.writeln(
      '| `${kind.dartName}` | ${kind.family.name} | '
      '${kind.isSerializable ? '是' : '否'} |',
    );
  }

  buffer
    ..writeln()
    ..writeln('容器类型：`List<T>`、`Map<K, V>`、`T?`、`Future<T>`。')
    ..writeln('用户模型来自 `models/`，字段类型递归上述类型。')
    ..writeln()
    ..writeln('### 允许的隐式提升')
    ..writeln()
    ..writeln('只有这三条，其余一律要求类型相同：')
    ..writeln()
    ..writeln('- `int → double`')
    ..writeln('- `int → num`、`double → num`')
    ..writeln('- `T → T?`')
    ..writeln()
    ..writeln('刻意窄于 Dart 自身的规则，好让接错线在拖拽时就被拒绝，')
    ..writeln('而不是等到 `dart analyze`。')
    ..writeln()
    ..writeln('### 可用的 Flutter 枚举')
    ..writeln();
  for (final type in EnumRegistry.all) {
    buffer.writeln('- `${type.name}`: ${type.values.join(' / ')}');
  }
  buffer.writeln();
}
