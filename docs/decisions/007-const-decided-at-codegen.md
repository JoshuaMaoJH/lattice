# ADR-007 const 由 codegen 结构化决定，而非交给 lint

## 背景

项目书 §8 要求生成代码"只在必要处包 Watch；静态部分保持 `const`"。有两种做法：

1. 生成不带 `const` 的代码，靠 `prefer_const_constructors` lint 提示用户/工具补上。
2. codegen 自己判断哪里能 `const`，直接发射。

做法 1 的问题：lint 无法知道一个 widget 参数是绑定到 Signal 的（那就永远不可能 const），它只能在事后抱怨，于是 `dart analyze` 输出永远不干净——直接违反 G2。

## 决策

codegen 结构化地决定 const，并在生成工程的 `analysis_options.yaml` 里**关掉** `prefer_const_constructors` 和 `prefer_const_literals_to_create_immutables`，附注释说明原因。

判定规则（`Emitted`）：
- 每个表达式携带 `isConst` 与 `signalDeps` 两个事实。
- 有 Signal 依赖 ⇒ 一定不是 const。
- 父表达式 const ⇒ 子表达式省略 `const` 关键字（由上下文隐含）；父不 const 而子可以 ⇒ `const` 落在子上。

这样 `const` 恰好落在最外层可 const 的位置，和人手写的一模一样。

Flutter 中少数 widget 的构造函数**不是** const（`AppBar`、`Container`、`ListView`、`GestureDetector`、`Image.network`），这些在 `WidgetSchema.constCtor` 里显式标注，而不是靠猜。

## 后果

**好的**：`flutter analyze` 在生成工程上零诊断（G2 达成）；`const AppBar(...)` 这类错误在 codegen 阶段就不可能产生。

**代价**：新增白名单 widget 时必须确认它的构造函数是否 const。判断方法记录在此：

```bash
grep -rhE "^  (const )?<WidgetName>\(" $FLUTTER/packages/flutter/lib/src/{material,widgets}/*.dart
```

## 实现

- `packages/lattice_codegen/lib/src/emit/emitted.dart`
- `WidgetSchema.constCtor`：`packages/lattice_core/lib/src/schema/widget_schema.dart`
- 测试：`lowering_test.dart` 中 "keeps a fully static subtree const"
