# Lattice

[![ci](https://github.com/JoshuaMaoJH/lattice/actions/workflows/ci.yml/badge.svg)](https://github.com/JoshuaMaoJH/lattice/actions/workflows/ci.yml)

**用 Unity 式的层级树描述界面结构，用 Blender 式的节点图描述数据与逻辑，一键编译成真实的 Flutter 应用。**

Lattice 把声明式 UI 的 `UI = f(state)` 公式画成一张图：Signal 进来，经过 Computed 变换，汇入 widget 参数；事件只做一件事——写 Signal。图里没有执行线，因为不需要。图编译成可读、可 `dart analyze` 零诊断、可随时 eject 的 Dart 源码。

完整设计见 [`docs/project-proposal.md`](docs/project-proposal.md)。

---

## 现在能做什么（M0 已打通）

```bash
# 一次性：把 Flutter SDK 放进 PATH
export PATH="$HOME/flutter/bin:$PATH"

dart pub get                                   # 解析 workspace
dart run packages/lattice_cli/bin/lattice.dart new my_app
dart run packages/lattice_cli/bin/lattice.dart build my_app -t web --analyze
dart run packages/lattice_cli/bin/lattice.dart build my_app -t web --compile
```

`lattice new` 生成的就是项目书 §8 的计数器。它编译出的 `lib/pages/home_page.dart`：

```dart
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
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SignalBuilder(builder: (context) => Text('Count: ${count.value}')),
            const SizedBox(height: 12),
            ElevatedButton(onPressed: _onBtnPressed, child: const Text('+1')),
          ],
        ),
      ),
    );
  }
}
```

注意只有依赖 Signal 的那一个 `Text` 被包进了重建边界，其余保持 `const`；节点 ID 以注释形式保留。这就是 G2「生成代码和手写一样好」的具体含义。

## CLI

| 命令 | 作用 |
|---|---|
| `lattice new <dir>` | 创建工程，附带计数器起始页 |
| `lattice build <dir>` | 校验 → 生成 → 平台目录 → 元数据 → `flutter pub get` |
| `lattice build -t linux,web --compile` | 顺带调用 `flutter build` |
| `lattice run <dir>` | 生成后直接 `flutter run` |
| `lattice export <dir> -o <out>` | 导出脱离 Lattice 的独立工程（G5） |
| `lattice analyze <dir>` | 只跑校验器，输出带节点 ID 的诊断 |
| `lattice targets <dir>` | 本机能构建哪些平台，不能的为什么（ADR-006） |
| `lattice package <dir> -t linux` | 出可分发产物到 `dist/`（见[打包](docs/packaging.md)） |
| `lattice text <dir> --out text` | 把工程写成可读的 `.lat` 文本（R18） |
| `lattice text <dir> --read` | 把改过的 `.lat` 读回工程 JSON |

## 工程里有什么

一个 Lattice 工程是一个目录，每样东西一个文件，便于 diff：

| | |
|---|---|
| `project.json` | 应用名、包名、目标平台、以及 `collections` 声明 |
| `pages/*.json` | 每页一个：Hierarchy + Graph + 画布坐标 |
| `prefabs/*.json` | 可复用组件。参数类型写 `Widget` 就是子树槽位，写 `Event` 就是回调（R9） |
| `server/*.json` | 跑在服务端的子图，客户端拿到类型化的调用桩（R17） |
| `models/*.json` | 数据模型。序列化两边共用一份 |
| `nodes/*.json` | 这个工程自己定义的节点：引脚 + 一段带 `{引脚名}` 占位符的模板（R20，[ADR-013](docs/decisions/013-project-defined-nodes.md)） |
| `custom/*.dart` | 手写 Dart，图通过 `Dart Code` 节点调用，重新生成不覆盖 |

**数据层**是 `project.json` 里的一行（R19）：

```json
"collections": [{"name": "notes", "of": "Note"}]
```

生成一个装在 signal 里的类型化列表，读是响应式的、写会落盘（原生写 JSON 文件，
web 写 localStorage）。它**不是数据库**——没有索引、查询和迁移，整个列表一次读
进内存一次写回去。见 [`examples/notes`](examples/notes/)。

**文本形式**是无损的第二种写法（R18，[ADR-014](docs/decisions/014-text-form.md)）：

```
page Home #page_home route "/" home
  hierarchy
    Scaffold #w_root
      Text #w_txt data=<n_fmt.out
      ElevatedButton #w_btn onPressed=!ev_btn
  graph
    Signal #n_count dartType="int" init=0 name="count"
  wires
    n_count.value -> n_fmt.args[0]
```

`JSON → 文本 → JSON` 逐字段相等，所以它可以拿来做 code review、手改、或者让
LLM 生成之后读回去。

## 仓库结构

```
packages/
  lattice_core/      模型、类型系统、schema 注册表、校验（纯 Dart）
  lattice_codegen/   Lower → IR → code_builder → dart_style
  lattice_runtime/   零依赖响应式运行时（signals 的可切换后端）
  lattice_build/     平台目录、应用元数据、flutter build 编排
  lattice_cli/       lattice new / build / run / export / analyze / targets
apps/
  lattice_editor/    四面板编辑器：Hierarchy / Inspector / Graph / Preview
examples/
  counter/           §8 计数器
  todo/              ForEach / If / 作用域（R10）
docs/
  project-proposal.md
  node-reference.md
  decisions/         ADR
```

## 编辑器

```bash
cd apps/lattice_editor
flutter run -d linux      # 桌面：真实文件 + flutter run 预览热重载
flutter run -d chrome     # 浏览器：内存工程，看得见但存不下
```

开工程用工具栏的打开按钮或 `Ctrl+O`（不给命令行参数时是一屏选择，不会闷头打开
内置示例）。画布上 Ctrl/Shift 点击加减选中、空白处拖拽框选、`Ctrl+C/V/D` 复制
粘贴、选中两个以上可以折叠成 Subgraph。底部 **Data flow** 页签显示运行中的预览
每次状态变化（R21）——画布上对应的节点同时显示当前值。工具栏的盾牌是签名清单
（R22）：按目标列出要哪些环境变量、哪些还空着，只读有没有、不读值。

一条视觉规则贯穿全局：**颜色只表示类型**。中性色阶之外唯一饱和的像素是引脚、
连线和类型徽章，色值来自 §7.3；选中用抬升与亮边表达，不用颜色；诊断是刻意的
例外，所以它无法被忽略。详见 [`apps/lattice_editor/README.md`](apps/lattice_editor/README.md)。

## 开发

```bash
dart pub get
dart analyze packages/                       # 全部零诊断
(cd packages/lattice_core && dart test)      # 类型系统 / 序列化 / 校验器
(cd packages/lattice_codegen && dart test)   # lowering + golden
(cd packages/lattice_runtime && flutter test)
(cd apps/lattice_editor && flutter test)     # 领域层 + 四面板 widget 测试
```

Golden 变更需显式重录并审阅 diff：

```bash
UPDATE_GOLDENS=1 dart test packages/lattice_codegen
```

## 里程碑状态

| 里程碑 | 状态 |
|---|---|
| **M0 打通管线** | ✅ 工程 JSON → 校验 → codegen → `flutter analyze` 零诊断 → `flutter build web` 出产物 |
| **M1 MVP 编辑器** | ✅ 四面板 + 自研节点画布；R1–R8、R14、R15 |
| **M2 真实小应用** | ✅ R9–R16 全部完成；Linux / Android / Web 三个宿主目标都真出过包 |
| **M3 全栈** | ✅ Server Function → 可运行的服务端 + 类型化 RPC；真实往返已验证。未部署 |
| **M4 发布** | ✅ R17–R22 全部完成；打包与签名通路已验证（见[打包](docs/packaging.md)）。Windows / macOS 缺宿主机没跑 |

## 协议

MIT，见 [LICENSE](LICENSE)。
