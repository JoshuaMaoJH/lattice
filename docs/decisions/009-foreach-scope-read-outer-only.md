# ADR-009 ForEach 模板先做"只读外层"，但现在就留出 key 与作用域

## 背景

项目书 §15 留了一个阻塞 R10 的问题：ForEach 模板内的 Signal 是"每项一份"还是只能引用外层？

两条路：

- **A 每项一份**：每个列表项拥有自己的状态实例，等价于 per-item `StatefulWidget`。
- **B 只读外层**：模板可以读外层 Signal、可以触发外层 Action，但不能声明自己的状态。

## 决策

**M2 做 B。** 但把 A 需要的三样东西现在就建好，使它日后是增量而非重构。

### 为什么不是 A

A 的真实成本不在作用域，在**身份**。一旦每项有自己的状态，就必须回答：列表重排或删掉第 0 项之后，第 1 项的展开状态跟着谁？Flutter 的答案是 `Key` + element 复用；没有 key，状态跟的是**下标**——删掉第一行，它的内部状态会落到第二行头上。

这是 Flutter 的经典坑。在 Lattice 里它会更糟：用户从没写过 `ListView.builder`，凭什么知道要给 key。所以 A 意味着 ForEach 必须带 key 表达式、模板必须编译成独立的 `StatefulWidget`（inline closure 拿不到 per-element state）、还要把"什么时候重置"讲清楚。§7.2 已经把 ForEach 标成"最难的节点"，这三件事会让它更难。

### 为什么 B 不是硬墙

反对 B 的理由是"展开/折叠这类瞬态 UI 状态不该塞进数据模型"。对，但有个不脏的出口：页面级 `Signal<Map<String, bool>>`，模板里用 `MapGet` 读 `map[item.id]`。为此加了 `MapGet` / `MapPut` 两个节点，没有任何新机制。

而且 R10 的验收目标 Todo 本来就不需要 per-item state：`done` / `title` 属于模型。B 顺手把正确架构变成了唯一路径，这对 U3（学习者画像）是加分项。

## 现在就留好的三条缝

### 1. `itemKey` 从第一天起就是必填（对模型列表）

`ForEach` 有 `itemKey` 参数，指明 item 的身份字段。元素是用户模型时**强制要求**，字段不存在也报错：

```
missing_item_key  ForEach over Todo needs "itemKey": the name of the field that
                  identifies an item (for example "id"). Without it, reordering
                  or deleting a row moves widget state to the wrong row.
```

这条跟 A/B 之争无关，是独立的正确性要求：只要模板里出现 `TextField` 这类自带 Flutter 内部状态的 widget，没 key 一样会串行。codegen 据此发射 `KeyedSubtree(key: ValueKey(item.id), child: …)`。

元素是基础类型时不发射 key——因为没有可用的身份字段，而 `ValueKey(item)` 遇到重复值会直接抛"duplicate key"。这一点是已知取舍，不是疏忽。

### 2. 模板是真正的作用域，不是共用命名空间

`ScopeMap` 把两件事映射出来：每个 widget 位于哪些 ForEach 模板内，每个图节点的值属于哪些模板。规则一句话：**读 `item` 的 widget 必须在定义它的模板内**。违反时：

```
item_out_of_scope  Text.data reads a value that only exists inside the ForEach
                   "w_each". Move the widget into that template, or lift the
                   value out of the loop.
```

将来加 local state，就是"这个 scope 允许声明状态"，而不是改文件格式。

### 3. `NodeContext` 带作用域解析

`ForEachItem` 节点的 `item` 引脚类型不是写死的，是从 ForEach 的 `items` 绑定反查出来的（`forEachElementType`）。嵌套 ForEach 会形成解析环，已经有 guard。

## 连带确定的两件事

**模板内可以写外层 Signal。** 删除按钮就是这么工作的。handler 仍然是 State 类上的方法，所以它读到的循环变量作为参数传进去，调用点变成闭包：

```dart
// ev_del -> a_remove
void _onDelPressed(int index) {
  todos.value = (List.of(todos.value)..removeAt(index));
}
...
IconButton(onPressed: () => _onDelPressed(index), …)
```

**依赖 `item` 的计算永远不提升为页面级 `computed()`。** 它是每次迭代一份的值，作为页面字段没有意义。`_planHoists` 显式跳过带作用域的引脚。

## 将来补 A 的时候

做成**独立节点类型**（`LocalSignal`，只在模板 scope 内合法），不要做成"Signal 放进模板里就自动变 local"。用户应该看得见自己选了个生命周期不同的东西，编辑器也才好在旁边写一句"item 的 key 变了它就重置"。隐式的行为差异是这类工具最容易埋雷的地方。

## 实现

- 作用域：`packages/lattice_core/lib/src/validation/scope.dart`
- 校验：`Validator._validateControlFlow` / `_validateScopes` / `_validateItemKey`
- 展开：`packages/lattice_codegen/lib/src/ir/lowering.dart`（`_lowerChildList` / `_forEachElement` / `_ifElement`）
- 测试：`packages/lattice_core/test/scope_test.dart`、`packages/lattice_codegen/test/control_flow_test.dart`
- 示例：`examples/todo`
