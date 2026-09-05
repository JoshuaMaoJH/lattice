# ADR-011 Subgraph v1 是折叠，不是子函数

## 背景

R14 要求「Subgraph 折叠、Comment、Reroute」，验收是「50 节点示例整理后单屏可读」。

`Subgraph` 有两种合理读法：

- **A 可复用的子函数**：有自己的输入输出类型和嵌套图，能在多处实例化。
- **B 折叠**：一组节点被记住是一组，可以收起来。成员仍在原图里。

## 决策

**做 B。**

§7.2 把 `Subgraph` 和 `Comment` / `Reroute` 一起归在**组织**类，§10 R14 写的也是
「Subgraph **折叠**」。三者并列在一起时，它们的共同点很清楚：都不改变语义。
整理不该是重构。

A 需要的东西 B 都没有：边界类型、嵌套作用域、lowering 时的图栈、递归校验。
而 R17（服务端函数）真正需要的正是那个边界——**它是 M3 的设计题**。现在顺手做一个
形状不对的版本占位，比不做更糟：M3 时要么将就一个错的抽象，要么推翻重来。

## B 是什么

`Subgraph` 节点的配置是 `{name, members: [nodeId…], collapsed: bool}`。

- 展开时：画成成员所在的一块带标题区域，拖标题栏会带着成员一起移动
- 折叠时：画成一个盒子，**每条跨越边界的边得到一个端口**；完全在内部的边不画
- 生成代码：**完全不受影响**。成员本来就在图里，Subgraph 自己没有引脚，
  没有任何东西引用它

同一条规则适用于 `Comment`（背景上的带标题区域）和 `Reroute`（两个引脚都在
中心线上的小圆点，编译成直接传递）。三者都是零语义的。

## 校验

折叠只有三种出错方式，都报出来：

- `unknown_subgraph_member` — 成员不在图里
- `subgraph_self_member` — 包含自己
- `subgraph_overlap` — 一个节点被两个折叠同时认领

## 验收

`examples/signup` 是一张 51 个节点的表单校验图：三个字段各有长度规则和形状规则，
汇成一个「表单是否有效」。三个字段的规则各折成一组之后，整张图连同事件链一起
落在一屏内——而生成的 Dart 里看不到任何组织痕迹：

```dart
// n_email_ok
late final emailOk = computed(
  () => (_emailLength(email.value) >= 5) && _emailShape(email.value),
);
```

Reroute 也消失了：`n_bend_a` 直接传递。

## 已知缺口

编辑器没有多选，所以成员是在 Inspector 里以逗号分隔的 id 列表编辑的。
够用，但「框选一堆节点然后折起来」才是这个功能该有的样子。

## 实现

- schema：`packages/lattice_core/lib/src/schema/node_registry.dart`
- 校验：`Validator._validateSubgraph`
- 折叠映射：`apps/lattice_editor/lib/src/graph/folding.dart`
- 渲染：`_FoldRegion` / `_CollapsedFold` / `_CommentRegion` / `_RerouteDot`
- 示例：`examples/signup`
