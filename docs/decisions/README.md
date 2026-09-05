# 决策记录（ADR）

每条记录一个"当时为什么这样选"，以便日后推翻它的人知道要推翻的是什么。
格式：**背景 → 决策 → 后果**。已实现的决策标注对应代码位置。

| # | 决策 | 状态 |
|---|---|---|
| [001](001-reactive-signals-not-exec-lines.md) | 用响应式信号模型而非执行线 | 已实现 |
| [002](002-codegen-not-interpreter.md) | 不做运行时解释器，一律 codegen | 已实现 |
| [003](003-editor-in-flutter-desktop.md) | 编辑器用 Flutter Desktop 自研 | 待 M1 |
| [004](004-constraint-layout-not-absolute.md) | 不支持绝对定位，遵循 Flutter 约束布局 | 已实现 |
| [005](005-layout-separate-from-semantics.md) | 画布坐标与语义模型分离存储 | 已实现 |
| [006](006-ci-matrix-for-cross-host-builds.md) | 全平台构建默认走生成的 CI 工作流 | 已实现 |
| [007](007-const-decided-at-codegen.md) | const 由 codegen 结构化决定，而非交给 lint | 已实现（M0 新增） |
| [008](008-signalbuilder-as-runtime-seam.md) | `SignalBuilder` 作为两套运行时后端的唯一接缝 | 已实现（M0 新增） |
