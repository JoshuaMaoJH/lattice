# ADR-003 编辑器用 Flutter Desktop 自研

## 背景

编辑器可以是 Web（React Flow 等成熟节点库）或桌面原生。节点画布是产品核心交互，现有 Flutter 节点编辑包成熟度不足。

## 决策

编辑器用 Flutter Desktop 写，节点画布基于 `InteractiveViewer` + `CustomPainter` 自研。

## 后果

**好的**：单语言全栈；dogfooding——我们自己就是 Lattice 目标用户的极端情形；桌面文件系统与子进程（`flutter run` 预览）直接可用。

**代价**：画布要自己写，这是 §12 中概率最高的风险项。缓解办法是排序：M0 先把 codegen 打通（已完成），画布晚于 codegen 开工，因此即使画布延期，管线的价值已经落地——CLI 已经可用。

## 状态

未开始。`apps/lattice_editor/` 目前只有说明文件。
