# Lattice 文档

| | |
|---|---|
| [项目书](project-proposal.md) | 立项文档：目标、设计、里程碑。**其余一切的出处** |
| [节点参考](node-reference.md) | 内置节点库。由 `tool/generate_node_reference.dart` 生成 |
| [签名与公证](signing.md) | 让产物**能装上**，不只是能构建 |
| [决策记录](decisions/) | 做过的选择与代价，尤其是偏离项目书的那些 |

## 从哪读起

想知道**这东西是什么**：项目书 §1、§5、§8。三页读完就明白了。

想**改它**：[CONTRIBUTING](../CONTRIBUTING.md)，然后是
[ADR-007](decisions/007-const-decided-by-codegen.md)（为什么 const 由 codegen
决定而不是交给 lint）——它最能说明这个项目对生成代码质量的标准。

想知道**它有多少是真的**：`examples/` 下五个工程，全部生成、全部 `flutter
analyze` 零诊断、全部进 CI。每个的 README 都写了它要证明什么，以及它证明不了什么。

## 已知偏离项目书之处

| | 项目书 | 实际 | 理由 |
|---|---|---|---|
| 服务端框架 | dart_frog（§9） | 只依赖 `dart:io` | [ADR-012](decisions/012-plain-dart-server.md) |
| Subgraph | 「可标记为 @server」（§7.7） | 纯折叠；服务端边界另立 `ServerFunction` | [ADR-011](decisions/011-folding-not-subfunctions.md) |
| RPC 客户端归属 | `lattice_server_gen`（§6） | `lattice_codegen` | 反向会成环；`lib/rpc.dart` 是客户端工程的文件 |
