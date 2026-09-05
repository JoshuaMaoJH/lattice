# 示例工程

每个示例都是一个 Lattice 工程目录（`project.json` + `pages/`），
可以直接编译成 Flutter 应用。

```bash
export PATH="$HOME/flutter/bin:$PATH"
dart run packages/lattice_cli/bin/lattice.dart build examples/counter -t web --analyze
dart run packages/lattice_cli/bin/lattice.dart build examples/counter -t web --compile
```

| 示例 | 覆盖到什么 | 状态 |
|---|---|---|
| [`counter/`](counter) | Signal、Format、绑定、Event → UpdateSignal、响应式边界、const 折叠 | ✅ |
| [`todo/`](todo) | ForEach、If、作用域、itemKey、Prefab ×3、多页面传参、Dart Code、controller 绑定 | ✅ |
| [`weather/`](weather) | HTTP 异步链、loading/error、JSON→模型、jsonKey、Dart Code | ✅ |
| [`signup/`](signup) | 51 个节点的表单校验；Subgraph 折叠、Comment、Reroute（R14） | ✅ |

`counter/` 与 `todo/` 生成的代码都被 `packages/lattice_codegen/test/goldens/` 快照锁定，
任何输出变化都必须显式重录并审阅 diff。

`todo/`、`weather/` 与 `signup/` 的工程 JSON 由 `tool/make_*_example.dart` 生成（这样 fixture 有类型检查），生成出来的 JSON 才是交付物。
