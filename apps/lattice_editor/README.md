# lattice_editor（M1，尚未开始）

四面板 Flutter 桌面编辑器：Hierarchy / Inspector / Graph / Preview。

暂时空着是刻意的。项目书 §12 把"节点画布自研工作量超预期"列为最高风险，
对策是**让 codegen 先于画布落地**——这样即使画布延期，管线的价值已经兑现：
`lattice_cli` 现在就能把一份工程 JSON 编译成可运行、可分发的 Flutter 应用。

## 动工时它要接的东西已经就位

| 面板 | 依赖 | 现状 |
|---|---|---|
| Hierarchy | `WidgetRegistry`（白名单 + `childArity` + `mustBeInside`） | ✅ |
| Inspector | `WidgetSchema.params`（类型、必填、默认值、是否可绑定） | ✅ |
| Graph | `NodeRegistry` + `NodeSchema.inputs/outputs`（按实例解析引脚） | ✅ |
| 诊断标红 | `Validator` → 带 `nodeId` / `widgetId` 的 `Diagnostic`（R15） | ✅ |
| 引脚配色 | `LatticeType.family` | ✅ |
| 画布坐标 | `Page.layout`，与语义分离（ADR-005） | ✅ |
| Preview | `lattice build` 的增量写盘（内容未变不落盘） | ✅ |
| Build 面板 | `lattice_build`（`Host` / `PlatformScaffolder` / `FlutterBuild`） | ✅ |

也就是说，编辑器要写的是交互，不是模型——模型、校验、编译、构建都已在 `packages/` 下，
并有测试覆盖。

## 唯一还没定的设计问题

§15 中「ForEach 模板作用域：模板内的 Signal 是"每项一份"还是只能引用外层」
仍未决定，它阻塞 R10。这个问题应该在画布开工前想清楚，因为答案会影响
`NodeContext` 要不要携带作用域链。
