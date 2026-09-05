# ADR-004 不支持绝对定位，遵循 Flutter 约束布局

## 背景

Unity 用户习惯 Transform 式的绝对定位（拖到哪就在哪）。Flutter 的布局是约束式的：`Row` / `Column` / `Flex` / `Stack` 各有语义，父约束子。

## 决策

编辑器直接暴露 Flutter 的布局语义，**不提供**像素级绝对定位。Hierarchy 里的父子关系就是 widget 树的父子关系。

## 后果

**好的**：生成代码就是正常人写的 Flutter；响应式布局、不同屏幕尺寸自动成立。

**代价**：Unity 用户有一段学习曲线。缓解办法是白名单 + 约束校验 + 内置布局模板：把非法结构在树上直接标红，而不是让用户对着 Flutter 的红屏猜。

`Expanded` 只能出现在 Flex 内是这条决策最具体的体现——校验器会给出 `illegal_parent`，并说明它的父节点实际是什么。

## 实现

- `WidgetSchema.mustBeInside` / `childArity`：`packages/lattice_core/lib/src/schema/widget_schema.dart`
- 校验：`Validator._validateHierarchy`
