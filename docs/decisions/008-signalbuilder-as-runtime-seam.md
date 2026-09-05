# ADR-008 `SignalBuilder` 作为两套运行时后端的唯一接缝

## 背景

§15 留了一个开放问题：`signals` 包是否足够稳定作为默认 runtime，还是先用 `ValueNotifier` 保守起步？该在 M0 结束时决定。

要能真的比较，就得两套都能跑，而不是二选一后再也换不回来。

## 决策

生成代码对响应式原语只用三个名字：`signal<T>()`、`computed<T>()`、`SignalBuilder(builder: ...)`。两套后端都提供这三个名字：

- `signals` 后端：`import 'package:signals_flutter/signals_flutter.dart'`
- 零依赖后端：`import 'package:lattice_runtime/lattice_runtime.dart'`

切换后端**只改一行 import**，其余源码逐字节相同。这一点由测试锁死（`lowering_test.dart` 中 "signals and the zero-dependency runtime differ only in the import"）：它把两份输出各自的 import 行替换成同一个占位符后断言完全相等。

注意名字选的是 `SignalBuilder` 而不是项目书 §8 里的 `Watch`——`signals_flutter` 7.x 已把 `Watch` 标记为 deprecated，继续用会在生成工程里留下 `deprecated_member_use` 提示，违反 G2。`lattice_runtime` 因此同时提供 `Watch` 和 `SignalBuilder`，后者是 codegen 实际发射的那个。

## 现状与建议

两套后端都已跑通完整闭环（生成 → `flutter analyze` 零诊断 → `flutter build web` 出产物）。

- **默认仍是 `signals`**，符合项目书 §9 的选型。
- **零依赖后端不是备胎，是真实现**：`Signal` / `Computed` / `effect` / `batch` / `SignalBuilder` 均有测试覆盖，包括自动依赖追踪、依赖丢弃（不再读的信号会被取消订阅）、批量写合并为一次通知、以及 widget 销毁后取消监听。

因此 §15 的这个问题可以关掉了：不必赌某一个包的长期稳定性，接缝已经足够窄。

## 实现

- `packages/lattice_runtime/lib/src/reactive.dart`、`watch.dart`
- 发射点：`packages/lattice_codegen/lib/src/ir/lowering.dart`（`_lowerWidget` 末尾）
- 后端选择：`ProjectConfig.runtime`
