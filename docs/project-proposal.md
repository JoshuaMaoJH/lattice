# Lattice 项目书

## 基于节点图的 Flutter 可视化全栈应用构建器

| 项目 | 内容 |
|---|---|
| 项目代号 | Lattice（暂定，可替换） |
| 文档版本 | v0.2 草案 |
| 日期 | 2026-09-04 |
| 作者 | Joshua |
| 状态 | 立项讨论中 |

---

## 1. 项目概述

**一句话：** 用 Unity 式的层级树描述界面结构，用 Blender 式的节点图描述数据与逻辑，一键编译成真实的 Flutter 应用（以及可选的 Dart 后端）。

**核心洞察：** Blender shader graph 是"纯数据流"——输入进来，经过节点变换，汇入 Material Output。Flutter 的声明式 UI 遵循同一公式 `UI = f(state)`：状态进来，经过变换，汇入 widget tree。两者在结构上同构，因此节点图是描述声明式 UI 逻辑的天然载体。Lattice 在这个同构之上补齐 shader graph 缺失的一块——事件与副作用——采用响应式信号模型而非 Unreal Blueprint 式的执行线，使图保持纯净、可读。

**三个支柱：**

1. **Hierarchy（层级树）**——就是 widget tree，Unity 用户零学习成本；支持 Prefab（自定义组件）
2. **Graph（节点图）**——响应式数据流：Signal → Computed → Widget 参数；事件只做一件事：写 Signal
3. **Compiler（编译器）**——图 → 中间表示 → 真实 Dart 源码 → `flutter build` → 各平台可分发产物（Linux / Windows / macOS / Android / iOS / Web）；生成的代码可读、可 eject

---

## 2. 背景与问题

### 2.1 现状

- 低代码工具（FlutterFlow 等）用表单式"action flow"表达逻辑，稍复杂就退化为一堆下拉菜单，且大多闭源、锁定平台、生成代码质量参差。
- 可视化编程工具（Unreal Blueprint、Scratch）逻辑表达力强，但和 UI 框架脱节，不能直接产出应用。
- 手写 Flutter：布局与状态管理样板代码多，初学者难以看清"状态如何流向界面"。
- 前后端分离：即使是简单应用也需要手写 API、序列化、客户端调用三份代码。

### 2.2 问题陈述

开发者（尤其是从游戏引擎 / 节点工具过来的人）缺少一种工具，能用**结构（树）+ 数据流（图）**这两种直观的空间化表示来构建真实应用，并且不被锁死在工具里。不解决的代价：要么忍受低代码的天花板，要么回到手写样板代码。

### 2.3 为什么现在做

- Flutter 桌面端已成熟，编辑器可以用 Flutter 自己写（单语言全栈 + dogfooding）
- Dart 生态有成熟的代码生成与格式化工具（`code_builder`、`dart_style`、`analyzer`）
- 响应式信号（signals）范式在前端已被验证（Solid、Vue Vapor、Angular Signals），Dart 也有对应实现
- 服务端 Dart（`dart_frog` / `shelf`）让"一种语言、一张图、前后端"成为可能

---

## 3. 目标与非目标

### 3.1 目标（v1）

| # | 目标 | 可衡量标准 |
|---|---|---|
| G1 | 完整闭环 | 在编辑器中从零构建一个 Todo 应用（增删改、列表渲染、内存持久化），30 分钟内完成并运行 |
| G2 | 生成代码质量 | 生成的 Dart 通过 `dart analyze` 零 error、零 warning；`dart format` 后与手写风格无异 |
| G3 | 快速反馈 | 编辑器内修改到预览窗口更新 ≤ 2 秒（热重载） |
| G4 | 可读性 | 50 节点以上的图通过子图 / 组折叠后，单屏可读 |
| G5 | 不锁定 | 任意时刻可导出完整 Flutter 工程，脱离 Lattice 继续手写开发 |
| G6 | 多平台产物 | 同一工程在 Build 面板一键产出本机可构建的全部目标（至少 Linux / Android / Web）的可分发包；配合生成的 CI 工作流覆盖 Windows / macOS / iOS |

### 3.2 非目标（v1 明确不做）

| 非目标 | 原因 |
|---|---|
| 像素级绝对定位（Unity Transform 式） | Flutter 布局是约束式（Row / Column / Flex / Stack），强行做绝对定位会生成不可维护的代码；编辑器直接暴露 Flutter 布局语义 |
| 运行时解释器 | 会造成"编辑器里能跑、导出后不一样"的双轨；一律走 codegen |
| 覆盖 Flutter 全部 widget | 采用白名单（约 40 个常用 widget），其余通过自定义代码节点接入 |
| 多人协作 / 云端工程 | 单机文件工程 + git 已足够，协作是独立课题 |
| 移动端编辑器 | 节点编辑需要大屏与精确指针 |
| 数据库可视化建模 | v1 后端仅做"服务端函数"，数据层留给 v2 |
| 图 ↔ 代码双向同步 | v1 只做图 → 代码单向；双向在 v2 评估（见 §15） |
| 应用商店上架自动化 | v1 只产出可上传的签名包（AAB / IPA / MSIX），不做 Play / App Store / Microsoft Store 的上传与审核流程 |

---

## 4. 目标用户与用户故事

### 4.1 用户画像

- **U1 节点工具用户**：熟悉 Unity / Blender / Unreal，想做 App 但不想学一套全新的 UI 编程范式
- **U2 Flutter 开发者**：想快速搭原型、看清状态流向，最终仍要拿到干净的 Dart 代码
- **U3 学习者**：把"状态 → 界面"的数据流看得见摸得着，作为理解声明式 UI 的教具

### 4.2 用户故事（按优先级）

1. 作为 U1，我想在层级树里拖拽 Container / Column / Text 组织界面，这样我能像搭 Unity 场景一样搭 UI。
2. 作为 U1，我想把一个 Signal 节点连到 Text 的 `data` 引脚，这样文本会随状态自动更新，我不用写任何 setState。
3. 作为 U2，我想把 Button 的 `onPressed` 事件连到"写 Signal"节点，这样点击逻辑一眼可见。
4. 作为 U2，我想点"导出工程"，拿到一个能 `flutter run` 的标准工程，这样我随时可以脱离工具。
5. 作为 U1，我想把一组 widget 打包成 Prefab 并暴露参数，这样能复用（等价于自定义 StatelessWidget）。
6. 作为 U2，我想用 ForEach 节点把 `List<Todo>` 渲染成列表，这样能处理动态数据。
7. 作为 U2，我想在图里写一个"自定义 Dart 代码节点"，这样遇到框架没覆盖的东西不会卡死。
8. 作为 U2，我想给某个子图打"服务端"标记，编译器自动生成 API 和客户端调用，这样不用手写三份代码。
9. 作为 U1，我想在 Build 面板勾选 Windows / macOS / Android，点一下就拿到能直接发给别人安装的文件，这样不用逐个研究每个平台的打包工具链。
10. 作为 U3，我想在预览里看到 Signal 当前值和哪些 widget 订阅了它，这样能理解数据流。
11. 边界：作为任意用户，当我连接了类型不匹配的引脚，编辑器应立即标红并说明原因，而不是等到编译才报错。

---

## 5. 核心概念模型

```
Project
├── pages/          Page（一个路由）
│   ├── hierarchy   widget 树（Hierarchy）
│   └── graph       该页面的节点图（Graph）
├── prefabs/        Prefab（自定义组件 = 一棵子树 + 一张图 + 暴露的参数）
├── models/         数据模型（struct，编译为 Dart class + toJson/fromJson）
├── server/         Server Function（服务端节点图）
└── assets/
```

| 概念 | 类比 | 编译产物 |
|---|---|---|
| Page | Unity Scene | 一个 `StatefulWidget` + 路由注册 |
| Hierarchy | Unity Hierarchy 面板 | `build()` 方法里的 widget 树 |
| Prefab | Unity Prefab | 自定义 `StatelessWidget`，暴露参数 = 构造函数参数 |
| Signal | 可变状态 | `signal<T>(初值)` |
| Computed | Blender 数学 / 混合节点 | `computed(() => ...)` 或内联表达式 |
| Event | `Button.onPressed` 等回调 | 闭包，内部只做 Signal 写入与 Effect 调用 |
| Effect | 副作用（HTTP、导航、弹窗） | 异步函数调用 |
| Server Function | 打了 `@server` 标记的子图 | 服务端 handler + 客户端 RPC stub |
| Binding | 图输出 → widget 参数 | `Watch(...)` 包裹的响应式表达式 |

**响应式规则（整个系统的核心约束）：**

1. 数据流方向永远是 `Signal → Computed → Widget 参数`，无环。
2. 只有 Event / Effect 节点可以写 Signal；Computed 必须是纯函数。
3. Widget 参数引脚连接了图输出时，该 widget 自动包裹在响应式重建边界内。
4. 图上没有"执行线"——因为不需要：Signal 变化即触发下游重算。

---

## 6. 系统架构

```
┌──────────────────────────────────────────────────────────────┐
│  Lattice Editor（Flutter Desktop：Linux / macOS）              │
│  ┌────────────┐ ┌────────────┐ ┌────────────┐ ┌────────────┐  │
│  │ Hierarchy  │ │ Inspector  │ │ Graph      │ │ Preview    │  │
│  │ 层级树     │ │ 属性面板   │ │ 节点画布   │ │ 热重载窗口 │  │
│  └─────┬──────┘ └─────┬──────┘ └─────┬──────┘ └─────▲──────┘  │
│        └──────────────┴──────────────┘               │         │
│                       │ 编辑                          │ SIGUSR1 │
│                       ▼                               │         │
│              lattice_core（工程模型 + 校验）            │         │
│                       │ Project JSON                  │         │
│                       ▼                               │         │
│              lattice_codegen（IR → Dart AST → 源码）   │         │
│                       │ 写入 .lattice/build/          │         │
│                       ▼                               │         │
│              flutter run（常驻子进程）─────────────────┘         │
└──────────────────────────────────────────────────────────────┘
```

**分层：**

- `lattice_core`：工程数据模型、类型系统、校验（类型检查、环检测、未连接必填引脚）、序列化。纯 Dart，无 Flutter 依赖，可单元测试。
- `lattice_codegen`：Project → IR → Dart 源码。使用 `code_builder` 构建 AST，`dart_style` 格式化。
- `lattice_runtime`：极薄运行时库（响应式原语 + 少量辅助 widget），被生成工程依赖。
- `lattice_editor`：Flutter 桌面应用，四大面板。
- `lattice_server_gen`（M3）：Server Function → `dart_frog` 工程 + RPC 客户端。
- `lattice_build`：构建与打包编排——写入平台配置、调用 `flutter build`、`flutter_distributor` 打包、生成 CI 工作流（见 §7.9）。

---

## 7. 详细设计

### 7.1 Hierarchy 与 Inspector

- 树节点 = 一个 widget 实例，携带 `type`（白名单内的 Flutter widget）、`props`（字面量或绑定引用）、`children`。
- 白名单 widget 按 Flutter 语义分组：布局（Row / Column / Stack / Expanded / Padding / SizedBox / Container）、内容（Text / Icon / Image）、输入（ElevatedButton / TextField / Checkbox / Switch）、结构（Scaffold / AppBar / ListView）。
- 每个 widget 类型有一份**参数 schema**（名称、Dart 类型、是否必填、默认值、是否可绑定）。schema 驱动 Inspector 自动生成表单，也驱动 Graph 中该 widget 节点的引脚。
- Inspector 中每个可绑定参数旁有"⚡ 绑定"按钮：点击后该参数在 Graph 上出现为一个输入引脚。
- 布局遵循 Flutter 语义：Row / Column 的 children 有序，Expanded 只能在 Flex 内——校验器强制这些约束，在树上直接标红。

### 7.2 Graph 节点系统

**节点分类：**

| 类别 | 节点示例 | 说明 |
|---|---|---|
| 状态 | `Signal<T>` | 唯一的可变状态源；有初值 |
| 计算 | `Computed`、算术 / 字符串 / 逻辑 / 列表操作、`Format` | 纯函数；由内置节点库提供 |
| 界面 | `WidgetParams(#id)` | Hierarchy 中某 widget 的绑定引脚集合（自动生成） |
| 事件 | `Event: Button#id.onPressed`、`Event: TextField#id.onChanged` | 事件源；输出事件携带的参数（如新文本） |
| 动作 | `Set Signal`、`Update Signal(fn)`、`Navigate`、`Show Dialog`、`HTTP Request`、`Call Server` | 只能接在 Event 之后；这是唯一允许副作用的地方 |
| 控制 | `ForEach`（列表 → 子 widget 模板）、`If`（条件渲染）、`Switch` | 见下 |
| 逃生舱 | `Dart Code` | 用户手写函数体，声明输入 / 输出引脚类型 |
| 组织 | `Subgraph`、`Comment`、`Reroute` | 折叠与整理 |

**引脚与边：**

- 每个引脚有 Dart 类型；边只能连接类型兼容的引脚（相同类型，或 `int → double`、`T → T?` 等有限的隐式提升）。
- 数据引脚（实心圆）与事件引脚（空心三角）严格区分：数据边构成响应式依赖图；事件边只连 Event → Action，且 Action 链是顺序执行的。
- 一个输入引脚最多一条入边；一个输出引脚可以扇出。

**ForEach 与作用域（最难的节点）：**

- `ForEach` 输入 `List<T>`，拥有一个"模板子图"，子图内可用 `item: T` 与 `index: int` 两个局部输出。
- 模板子图内的 widget 树片段作为列表项模板；编译为 `ListView.builder` / `children: list.map(...)`。
- 模板内允许引用外层 Signal（读）与触发外层 Action（写），生成为闭包捕获。

### 7.3 类型系统

- 基础：`int, double, num, bool, String, Color, EdgeInsets, TextStyle, IconData`
- 容器：`List<T>, Map<K, V>, T?`
- 用户模型：`models/` 中定义的 struct，字段类型递归上述类型；生成 `class` + `copyWith` + JSON 序列化
- 特殊：`Widget`（模板输出）、`Future<T>`（HTTP / Server 节点输出，编辑器强制接 `Await` 节点或 `AsyncValue` 展开）
- 引脚颜色按类型族固定（数值蓝、字符串黄、布尔红、列表绿、模型紫、Widget 白、事件橙）

### 7.4 工程文件格式

- 目录即工程；每个 Page / Prefab 一个 JSON 文件，git 友好（key 排序、稳定 ID、一节点一行）。
- 节点 ID 为短随机串（如 `n_7f3a`），重命名不改 ID。
- 画布坐标与语义模型分开存储（`layout` 字段），保证语义 diff 干净。

```json
{
  "id": "page_home",
  "hierarchy": {
    "id": "w_root", "type": "Scaffold",
    "props": {
      "appBar": { "type": "AppBar", "props": { "title": { "type": "Text", "props": { "data": "Counter" } } } }
    },
    "children": [
      { "id": "w_col", "type": "Column", "children": [
        { "id": "w_txt", "type": "Text", "props": { "data": { "$bind": "n_fmt.out" } } },
        { "id": "w_btn", "type": "ElevatedButton",
          "props": { "onPressed": { "$event": "ev_btn" },
                     "child": { "type": "Text", "props": { "data": "+1" } } } }
      ]}
    ]
  },
  "graph": {
    "nodes": [
      { "id": "n_count", "type": "Signal", "dartType": "int", "init": 0 },
      { "id": "n_fmt",   "type": "Format", "template": "Count: {0}" },
      { "id": "ev_btn",  "type": "Event",  "widget": "w_btn", "event": "onPressed" },
      { "id": "a_inc",   "type": "UpdateSignal", "signal": "n_count", "fn": "(x) => x + 1" }
    ],
    "edges": [
      { "from": "n_count.value", "to": "n_fmt.args[0]" },
      { "from": "ev_btn.fire",   "to": "a_inc.exec" }
    ]
  },
  "layout": { "n_count": [120, 80], "n_fmt": [340, 80], "ev_btn": [120, 260], "a_inc": [340, 260] }
}
```

### 7.5 代码生成管线

1. **Load & Validate**：解析 JSON → 内存模型；类型检查、环检测、必填引脚检查、布局约束检查。错误带节点 ID，编辑器高亮。
2. **Lower 到 IR**：把图拓扑排序；把每个绑定引脚归约为一个 Dart 表达式树；把 Event 链归约为语句序列；决定每个 widget 是否需要响应式边界（其任一参数依赖 Signal 则需要）。
3. **Emit Dart**：用 `code_builder` 构造 Library / Class / Method；每个 Page 一个文件；Signal 声明在 Page 的 State 类中；Computed 内联为表达式，被多处引用时提升为 `computed()`。
4. **Format & Write**：`dart_style` 格式化，写入 `.lattice/build/lib/`；生成 `pubspec.yaml`、`main.dart`、路由表；平台目录与应用元数据见 §7.9。
5. **Analyze**（可选门禁）：调用 `dart analyze`，把诊断映射回节点 ID。

**响应式原语选型**：目标 `signals` 系列包（`signal / computed / effect / Watch`），与图模型一一对应，生成代码最短。备选零依赖方案：`ValueNotifier + ValueListenableBuilder`，作为 runtime 的可切换后端保留。

### 7.6 预览与热重载

- 编辑器启动时以子进程运行 `flutter run -d linux`（或 `-d macos` / `-d chrome`），指定 `--pid-file`。
- 每次工程变更 → 增量 codegen（只重写受影响的 Page 文件）→ 向子进程发送 `SIGUSR1` 触发热重载；结构性变更（新增 Signal）发 `SIGUSR2` 热重启。
- Debug 面板：在生成代码中注入（仅 debug 构建）一个轻量 inspector hook，把 Signal 当前值回传编辑器，实现"看得见的数据流"（用户故事 10）。

### 7.7 前后端一体：Server Function

- 图中任意 `Subgraph` 可标记为 `@server`。约束：输入 / 输出类型必须可 JSON 序列化；内部不可引用客户端 Signal 或 widget。
- 编译器为每个 Server Function 生成：
  - 服务端：`dart_frog` 路由 `POST /rpc/<name>`，反序列化参数 → 执行子图 → 序列化返回
  - 客户端：`Future<R> <name>(Args)` stub，图上表现为一个 `Call Server` 动作节点
- 服务端工程输出到 `.lattice/build_server/`，可直接部署到任意 Linux 主机（本项目将用现有云服务器做演示部署）。
- v1 边界：无鉴权、无数据库；纯"远程函数"。数据层（v2）计划以同样方式暴露 `Collection<T>` 节点。

### 7.8 逃生舱：Dart Code 节点

- 用户声明输入引脚（名称 + 类型）与输出类型，手写函数体；编辑器提供带语法高亮的代码框，编译时原样嵌入为一个私有函数。
- 生成工程的 `lib/custom/` 目录允许用户放置任意手写 Dart 文件，codegen 不会覆盖该目录；图中可通过 `Dart Code` 节点调用其中的函数。
- 这两条保证：**Lattice 的表达力下界 = Dart 本身**。

### 7.9 多平台构建与打包（Build & Package）

目标：同一个 Lattice 工程，一键产出各平台**可直接分发**的产物，而不只是 `flutter build` 出来的裸文件。用户从头到尾不需要接触任何一个平台的打包工具链。

**目标平台与产物：**

| 平台 | 裸产物（`flutter build`） | 分发包（Lattice 打包） | 构建宿主要求 |
|---|---|---|---|
| Linux | `bundle/` 目录 | AppImage / `.deb`（Flatpak 可选） | Linux |
| Windows | `.exe` + DLL | Inno Setup 安装器 / MSIX / 便携 zip | Windows |
| macOS | `.app` | `.dmg`（可选 codesign + notarize） | macOS |
| Android | `.apk` / `.aab` | 签名 APK（直接安装）/ AAB（上架） | 任意（需 Android SDK） |
| iOS | `.app` / `.ipa` | 签名 `.ipa`（需 Apple 开发者账号） | macOS + Xcode |
| Web | `build/web/` 静态站 | 静态站 zip，可直接部署到任意静态托管 | 任意 |

**编辑器内 Build 面板：**

- 勾选目标平台、选择模式（debug / profile / release）
- 应用元数据：应用名、bundle id / package name、版本号、图标（一张 1024² PNG，自动生成各平台尺寸）、启动页
- 签名配置：Android keystore、macOS / iOS 证书与 provisioning profile、Windows 证书——凭据只存本机 keychain / 配置目录，绝不进工程文件
- 构建日志实时流式显示；产物列表可一键打开所在目录

**工作流程：**

1. codegen 阶段在 `.lattice/build/` 执行 `flutter create --platforms=<targets>` 生成平台目录（仅首次或目标变更时执行）
2. 把应用元数据写入各平台配置（`AndroidManifest.xml`、`Info.plist`、`linux/CMakeLists.txt`、`windows/runner/Runner.rc`、`pubspec.yaml`）；图标通过 `flutter_launcher_icons` 生成
3. 逐平台调用 `flutter build <target> --release`
4. 打包交给 `flutter_distributor`（一套配置覆盖 dmg / msix / exe / deb / appimage / apk / aab / ipa / zip），少数格式自写脚本兜底
5. 产物输出到 `dist/<platform>/<version>/`

**跨宿主构建（解决"我只有 Linux + Mac，却要出 Windows 包"）：**

Flutter 桌面端只能在对应操作系统上构建（Linux → Linux，Windows → Windows，macOS / iOS → macOS）；Android 与 Web 任意宿主均可。Lattice 提供三条路：

- **本地**：只显示当前宿主能构建的目标，其余灰显并说明原因——不让用户撞墙
- **远程 CI（默认全平台路径）**：codegen 同时输出 `.github/workflows/build.yml`（matrix：`ubuntu-latest / windows-latest / macos-latest`），推送到 GitHub 后自动构建全平台并上传 Artifacts / Release。一台机器 + 一个 git 仓库 = 全平台产物
- **自建构建宿主**：在设置里配置 SSH 远程宿主（例如 KVM 里的 Windows 虚拟机、云上的 Mac），Lattice 同步工程过去执行构建再拉回产物；适合不想依赖 GitHub 的场景

**CLI 对应：** `lattice build --target linux,android,web --release`、`lattice package --target macos --dmg`；编辑器 Build 面板就是这两条命令的 GUI，二者共用 `lattice_build` 包。

---

## 8. 端到端示例：计数器

**图（文本表示）：**

```
Signal<int> count = 0
Format "Count: {0}"      ← count.value
Text#w_txt.data          ← Format.out
Button#w_btn.onPressed ─▶ UpdateSignal(count, x => x + 1)
```

**生成代码（目标形态，示意）：**

```dart
// lib/pages/home_page.dart — generated by Lattice, safe to edit after eject
import 'package:flutter/material.dart';
import 'package:signals_flutter/signals_flutter.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  // n_count
  final count = signal<int>(0);

  // ev_btn -> a_inc
  void _onBtnPressed() {
    count.value = count.value + 1;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Counter')),
      body: Column(
        children: [
          // w_txt (bound to n_fmt)
          Watch((context) => Text('Count: ${count.value}')),
          // w_btn
          ElevatedButton(onPressed: _onBtnPressed, child: const Text('+1')),
        ],
      ),
    );
  }
}
```

注意点：只有依赖 Signal 的 `Text` 被 `Watch` 包裹；静态部分保持 `const`；节点 ID 以注释形式保留——这是"生成代码和手写一样好"的具体含义，也是未来做图 ↔ 代码双向同步的锚点。

---

## 9. 技术选型

| 决策点 | 选择 | 备选 | 理由 |
|---|---|---|---|
| 编辑器 | Flutter Desktop（Linux / macOS） | Web + React Flow | 单语言全栈；dogfooding；桌面文件系统 / 子进程直接可用。代价：节点画布需自研 |
| 节点画布 | `InteractiveViewer` + `CustomPainter` 自研 | 第三方 node editor 包 | 现有包成熟度不足；画布是产品核心，值得自研 |
| 工程模型 | 纯 Dart 包 `lattice_core` | — | 可被 editor / codegen / CLI 共用，可单测 |
| 代码生成 | `code_builder` + `dart_style` | 字符串模板 | AST 级生成不易出语法错，格式化后可读 |
| 响应式 runtime | `signals` / `signals_flutter` | `ValueNotifier` 零依赖 | 与图模型一一对应；runtime 抽象层保留切换可能 |
| 后端 | `dart_frog` | `shelf` | 路由文件即接口，与 codegen 输出天然匹配 |
| 序列化 | 自生成 `toJson / fromJson` | `json_serializable` | 我们已经拥有 codegen，无需再引入 build_runner |
| 工程格式 | JSON（一文件一页面） | YAML / 二进制 | git diff 友好，易被外部工具 / LLM 生成 |
| 预览 | `flutter run` 子进程 + SIGUSR1 热重载 | 内嵌解释器 | 零双轨；预览即真实产物 |
| 打包 | `flutter_distributor` + `flutter_launcher_icons` | 各平台手写脚本 | 一套配置覆盖 dmg / msix / deb / appimage / apk / aab / ipa |
| 跨平台构建 | 生成 GitHub Actions matrix 工作流 | 自建构建机 / VM | 零成本获得三种宿主；SSH 自建宿主作为可选补充 |
| Monorepo | `melos` | 手动多包 | Dart 生态标准做法 |
| 开源协议 | MIT（待定） | Apache-2.0 | 降低采用门槛 |

---

## 10. 需求清单

### P0（MVP 必须）

| ID | 需求 | 验收标准 |
|---|---|---|
| R1 | Hierarchy 增删改拖拽 | 可在树中新增白名单 widget、调整顺序 / 父子、删除；违反布局约束时标红 |
| R2 | Inspector 按 schema 编辑属性 | 字面量属性即改即预览；可切换为"绑定" |
| R3 | Graph：Signal / Computed / 内置运算 / Event / SetSignal / UpdateSignal | 可连线；类型不匹配的边被拒绝并提示 |
| R4 | 绑定：图输出 → widget 参数 | 绑定后预览随 Signal 变化实时更新 |
| R5 | Codegen → 可运行工程 | `dart analyze` 零 error / warning；`flutter run` 成功 |
| R6 | 预览热重载 | 修改后 ≤ 2s 更新（统计 P90） |
| R7 | 工程保存 / 加载 | 关闭重开后完全一致（round-trip 测试） |
| R8 | 导出工程 | 一键导出到用户指定目录，包含 README |

### P1（MVP 后快速跟进）

| ID | 需求 | 验收标准 |
|---|---|---|
| R9 | Prefab | 可从选中子树创建；暴露参数出现为节点引脚；复用 3 处以上无异常 |
| R10 | ForEach / If | Todo 列表示例可完成 |
| R11 | Dart Code 节点 + `lib/custom/` | 手写函数可被图调用，重新生成不覆盖 |
| R12 | 多页面与 Navigate | 两页互跳，传参 |
| R13 | HTTP Request + Await | 调用公开 JSON API 并渲染 |
| R14 | Subgraph 折叠、Comment、Reroute | 50 节点示例整理后单屏可读 |
| R15 | 校验诊断面板 | 所有错误可点击定位到节点 / 树节点 |
| R16 | 本地构建与打包 | Build 面板勾选目标 → `dist/` 出现可分发包；Linux 出 AppImage / deb，Android 出签名 APK，Web 出静态 zip；构建失败时日志可定位到步骤 |

### P2（架构预留，暂不实现）

| ID | 需求 | 设计预留 |
|---|---|---|
| R17 | Server Function + RPC 自动生成 | 子图已有 `tags` 字段；类型系统已区分"可序列化"类型 |
| R18 | 图 ↔ 文本 DSL 双向 | 图 JSON 已是规范化的、与画布坐标分离的语义模型；生成代码保留节点 ID 注释 |
| R19 | 数据层 `Collection<T>` | 与 Server Function 共享序列化基础 |
| R20 | 插件化节点库 | 内置节点通过同一 schema 注册，不特殊化 |
| R21 | 运行时 Signal 可视化（数据流调试） | debug hook 预留注入点 |
| R22 | 远程全平台构建矩阵 + 签名 / 公证向导 | codegen 已能输出 `.github/workflows/build.yml`；签名凭据存储与工程文件分离 |

---

## 11. 里程碑与实施计划

> 以下按业余时间估算，仅作节奏参考；每个里程碑以"能演示什么"为验收，而不是以功能列表。

| 里程碑 | 周期（估） | 交付物 / 演示 | 释放的风险 |
|---|---|---|---|
| **M0 打通管线** | 2 周 | 手写一个 Page JSON → CLI codegen → `flutter run` 出现静态界面；`lattice_core` + `lattice_codegen` 骨架与单测 | 验证 code_builder 生成质量与 flutter 子进程控制 |
| **M1 MVP** | 6–8 周 | 编辑器四面板；计数器与简单表单可在编辑器内从零构建并热重载；R1–R8 | 节点画布可用性；类型系统落地 |
| **M2 可做真实小应用** | 8 周 | Prefab / ForEach / If / 多页面 / HTTP / Dart Code；本机目标一键构建打包（Linux / Android / Web）；Todo + 天气查询两个示例；R9–R16 | ForEach 作用域；图的可读性 |
| **M3 全栈** | 6 周 | Server Function → dart_frog；示例部署到云服务器；客户端 RPC 调用 | 序列化边界；部署流程 |
| **M4 发布** | 持续 | GitHub Actions 全平台构建矩阵（Windows / macOS / iOS 产物）、签名流程文档；文档、示例仓库、个人站项目页、开源发布、收集反馈 | 跨宿主构建与签名流程 |

**每个里程碑固定的工程实践：**

- `lattice_core` 与 `lattice_codegen` 单元测试 + golden test（示例工程生成代码快照比对）
- 每个示例工程都进 CI：`dart analyze` + `flutter build` 通过才算绿
- 每个里程碑结束更新本项目书与 `docs/decisions/` 决策记录

---

## 12. 风险与对策

| 风险 | 影响 | 概率 | 对策 |
|---|---|---|---|
| 节点画布自研工作量超预期 | M1 延期 | 高 | M0 阶段先用纯文本 JSON 驱动，画布晚于 codegen 开工；先做"能用"，性能优化后置；必要时先用 React Flow 做一次性原型验证交互 |
| 图变成"意大利面" | 用户放弃 | 高 | 子图 / 组 / Reroute 放 P1 而非 P2；Computed 允许内联表达式（如 `a * 2 + b`）减少节点数；Inspector 中支持直接写简短表达式而不建节点 |
| Flutter 布局语义难以在树中表达清楚 | 新手困惑 | 中 | 白名单 + 约束校验 + 内置"布局模板"（居中 / 垂直列表 / 表单等）；不做绝对定位是刻意选择 |
| 生成代码质量不如手写 | 违背 G2 / G5 | 中 | golden test；const 分析；只在必要处包 Watch；人工审查生成结果 |
| 热重载链路不稳定（子进程崩溃、状态丢失） | 体验差 | 中 | 子进程监控与自动重启；结构变更走热重启；Signal 初值来自工程文件所以可重建 |
| 类型系统缺口（泛型、函数类型） | 表达力受限 | 中 | Dart Code 节点兜底；类型系统按需扩展，不求一步完备 |
| 范围蔓延 | 永远发不出 | 高 | 本项目书的非目标清单；新增需求必须放 P2 或替换现有 P1 |
| 桌面平台只能在对应宿主构建；签名 / 公证流程繁琐 | 出不了全平台包，或产物被系统安全机制拦截 | 高 | 全平台默认走生成的 CI 工作流；本地只暴露可构建目标；先出未签名产物跑通流程，签名做成向导并链接官方文档 |

---

## 13. 成功指标

**领先指标（M1–M2）：**

- Todo 示例从零构建耗时 ≤ 30 分钟（目标）/ ≤ 15 分钟（挑战）
- 生成代码 `dart analyze` 零诊断，100% 示例工程通过
- 预览更新延迟 P90 ≤ 2s
- 三个示例工程（计数器、Todo、天气）全部可导出并独立 `flutter run`
- 三个示例工程各自在本机产出 Linux / Android / Web 分发包，并通过生成的 CI 工作流产出 Windows / macOS 包

**滞后指标（M4 后）：**

- 至少 3 位非作者用户用 Lattice 做出并运行一个应用
- GitHub 上出现外部 issue / PR
- 生成代码被用户 eject 后继续手写的案例 ≥ 1（验证"不锁定"是真的）

---

## 14. 创新点与可行性

### 14.1 创新点

1. **响应式信号图**：以 Signal / Computed / Event 三类节点取代 Blueprint 的执行线，图与声明式 UI 的数学结构同构，天然无环、易读。
2. **树 + 图双视图**：结构用树、逻辑用图，各取所长，而不是把 widget 也画成节点（那会让图爆炸）。
3. **同一张图跨越前后端**：`@server` 标记 + 自动 RPC 边界，一种语言（Dart）贯穿编辑器、运行时、客户端、服务端。
4. **生成即正品**：无运行时解释器；生成代码可读、可 eject、可 diff——工具消失后作品仍在。
5. **从图到安装包一条龙**：平台配置、构建、打包、跨宿主 CI 全部由工具生成，用户不需要接触任何一个平台的打包工具链。

### 14.2 可行性

- **技术**：所有关键环节都有成熟依赖（Flutter Desktop、code_builder、dart_style、signals、dart_frog、flutter_distributor、GitHub Actions、flutter run 信号热重载）；最不确定的是自研画布，已在 M0 / M1 排序中前置降险。
- **资源**：单人开发；开发环境为 Ubuntu 桌面 + macOS 笔记本（覆盖两个桌面目标平台）；云服务器可用于 M3 后端演示。
- **经验基础**：已有响应式 UI 库（tuikinter）、Unity 项目与多个桌面应用的开发经验，与本项目"响应式 + 编辑器"的核心直接相关。
- **验证路径**：M0 两周即可验证"图 → 代码 → 运行"闭环是否成立，失败成本低。

---

## 15. 开放问题

| 问题 | 类型 | 需在何时决定 |
|---|---|---|
| Computed 是否允许在 Inspector 里写内联 Dart 表达式（减少节点）？表达式类型推断走 `analyzer` 还是自写子集解析器？ | 设计 / 工程 | M1 前（阻塞） |
| ForEach 模板作用域：模板内的 Signal 是"每项一份"还是只能引用外层？ | 设计 | M2 前（阻塞 R10） |
| Page 级 Signal 与全局 Signal 的边界与生命周期（页面销毁是否重置） | 设计 | M2 前 |
| `signals` 包是否足够稳定作为默认 runtime，还是先用 ValueNotifier 保守起步？ | 工程 | M0 结束时 |
| 文本 DSL（图的可读文本形式）是否值得在 M2 就做——它对 git review 与 AI 辅助生成很有价值 | 产品 | M2 中期评估 |
| 开源协议与仓库名 | 产品 | M4 前（非阻塞） |

---

## 16. 仓库结构（拟）

```
lattice/
├── packages/
│   ├── lattice_core/        # 模型、类型系统、校验、序列化（纯 Dart）
│   ├── lattice_codegen/     # IR、Dart 生成、格式化
│   ├── lattice_runtime/     # 生成工程依赖的极薄运行时
│   ├── lattice_server_gen/  # (M3) dart_frog 生成
│   ├── lattice_build/       # 平台配置写入、flutter build、打包、CI 工作流生成
│   └── lattice_cli/         # `lattice build / package / export / analyze`
├── apps/
│   └── lattice_editor/      # Flutter 桌面编辑器
├── examples/
│   ├── counter/
│   ├── todo/
│   └── weather/
├── docs/
│   ├── project-proposal.md  # 本文档
│   ├── node-reference.md    # 节点库参考
│   └── decisions/           # ADR 决策记录
└── melos.yaml
```

---

## 17. 对标与参考

| 产品 | 借鉴 | 差异 |
|---|---|---|
| FlutterFlow | widget 树 + 属性面板 + 生成 Flutter 代码 | 逻辑用表单式 action flow；闭源、云端锁定。Lattice 用节点图 + 本地开源 |
| Unreal Blueprint | 节点图表达完整程序逻辑、子图、类型化引脚 | 执行线 + 数据线双轨；Lattice 用响应式模型去掉执行线 |
| Blender Shader Nodes | 纯数据流、输出节点、引脚颜色即类型 | 无事件与状态；Lattice 补上 Signal / Event |
| Unity | Hierarchy / Prefab / Inspector 三件套 | Transform 式定位；Lattice 遵循 Flutter 约束布局 |
| Enso（前 Luna） | 图与文本双向等价的原则 | 通用语言；Lattice 专注 UI + 全栈 |
| Rive | 状态机可视化与运行时 | 动画领域；Lattice 覆盖整个应用 |

---

## 附录 A：决策记录（ADR 索引）

- ADR-001 采用响应式信号模型而非执行线（§5）
- ADR-002 不做运行时解释器，一律 codegen（§3.2）
- ADR-003 编辑器用 Flutter Desktop 自研（§9）
- ADR-004 不支持绝对定位，遵循 Flutter 约束布局（§3.2）
- ADR-005 画布坐标与语义模型分离存储（§7.4）
- ADR-006 全平台构建默认走生成的 CI 工作流，本地构建只暴露宿主可构建目标（§7.9）

## 附录 B：术语表

- **Signal**：可变的响应式状态单元；写入后所有依赖者自动更新
- **Computed**：由其他 Signal / Computed 派生的只读值，纯函数
- **Binding**：把图的某个输出连接到 widget 参数
- **Prefab**：可复用的子树 + 子图 + 暴露参数，编译为自定义 widget
- **Server Function**：标记为服务端执行的子图，自动生成 RPC
- **Eject**：导出完整 Flutter 工程并脱离 Lattice 继续手写
