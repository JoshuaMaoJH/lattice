# ADR-001 用响应式信号模型而非执行线

## 背景

Unreal Blueprint 用"执行线 + 数据线"双轨表达程序：白线决定语句顺序，彩线传值。这套模型能表达任意命令式程序，代价是图上永远有两种不同语义的边，读者必须同时跟踪两条线。

Blender shader graph 只有数据线，图因此干净得多，但它没有状态、没有事件——纯函数没法做应用。

## 决策

采用**响应式信号**作为唯一的状态模型：

- 数据流方向永远是 `Signal → Computed → Widget 参数`，无环。
- 只有 Event / Action 节点可以写 Signal；Computed 必须是纯函数。
- 图上**没有执行线**。Signal 变化即触发下游重算，顺序由依赖关系决定而非由用户画出。
- 唯一保留顺序语义的地方是 Action 链（`exec → next`），因为副作用确实有先后。

## 后果

**好的**：图与 `UI = f(state)` 同构，天然无环；环检测只需在数据边上做（`Validator._detectCycles`）；用户点一次按钮写一次 Signal，不需要想"这条白线接哪"。

**代价**：无法直接表达 `while` / 提前 return 这类控制流。逃生舱是 `Dart Code` 节点——表达力下界等于 Dart 本身（§7.8）。

**验证**：`packages/lattice_core/test/validator_test.dart` 中 "accepts an event edge looping back to the signal it reads" ——按钮写 count、count 驱动 Text，画出来是个环，但数据流无环，必须不被拒绝。这条测试正是这个模型的分界线。

## 实现

- 模型：`packages/lattice_core/lib/src/schema/node_registry.dart`（`NodeCategory.state / compute / event / action`）
- 校验：`packages/lattice_core/lib/src/validation/validator.dart`
