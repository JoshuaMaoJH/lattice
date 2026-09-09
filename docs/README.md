# Lattice 文档

| | |
|---|---|
| [项目书](project-proposal.md) | 立项文档：目标、设计、里程碑。**其余一切的出处** |
| [节点参考](node-reference.md) | 内置节点库。由 `tool/generate_node_reference.dart` 生成 |
| [打包](packaging.md) | `lattice package` 需要宿主机上有什么 |
| [签名与公证](signing.md) | 让产物**能装上**，不只是能构建 |
| [决策记录](decisions/) | 做过的选择与代价，尤其是偏离项目书的那些 |
| [项目页](site/) | 自包含的单页介绍，可直接部署 |

## 按需求找实现

| | |
|---|---|
| R18 图 ↔ 文本 | `lattice text`；[ADR-014](decisions/014-text-form.md) |
| R19 数据层 | `project.json` 的 `collections`；[examples/notes](../examples/notes/) |
| R20 自定义节点 | 工程里的 `nodes/*.json`；[ADR-013](decisions/013-project-defined-nodes.md) |
| R21 数据流调试 | 编辑器底部 Data flow 页签，数据来自预览进程的输出 |
| R22 远程构建与签名 | 生成工程里的 `.github/workflows/release.yml`；[签名](signing.md) |

## 从哪读起

想知道**这东西是什么**：项目书 §1、§5、§8。三页读完就明白了。

想**改它**：[CONTRIBUTING](../CONTRIBUTING.md)，然后是
[ADR-007](decisions/007-const-decided-by-codegen.md)（为什么 const 由 codegen
决定而不是交给 lint）——它最能说明这个项目对生成代码质量的标准。

想知道**它有多少是真的**：`examples/` 下六个工程，全部生成、全部 `flutter
analyze` 零诊断、全部进 CI。每个的 README 都写了它要证明什么，以及它证明不了什么。

## 已知偏离项目书之处

| | 项目书 | 实际 | 理由 |
|---|---|---|---|
| 服务端框架 | dart_frog（§9） | 只依赖 `dart:io` | [ADR-012](decisions/012-plain-dart-server.md) |
| 文本形式 | 「图 ↔ 文本 DSL 双向」（R18） | 无损、含画布坐标，不是可读导出 | [ADR-014](decisions/014-text-form.md) |
| 工程自定义节点 | 「插件化节点库」（R20） | 模板替换，不是动态加载的 Dart | [ADR-013](decisions/013-project-defined-nodes.md) |
| Subgraph | 「可标记为 @server」（§7.7） | 纯折叠；服务端边界另立 `ServerFunction` | [ADR-011](decisions/011-folding-not-subfunctions.md) |
| RPC 客户端归属 | `lattice_server_gen`（§6） | `lattice_codegen` | 反向会成环；`lib/rpc.dart` 是客户端工程的文件 |
