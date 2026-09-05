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
| [`todo/`](todo) | ForEach、If、作用域、itemKey、List 操作、模板内写外层状态 | ✅ |
| `weather/` | HTTP Request + Await、Dart Code 节点 | 待 M2（R13 / R11） |

`counter/` 与 `todo/` 生成的代码都被 `packages/lattice_codegen/test/goldens/` 快照锁定，
任何输出变化都必须显式重录并审阅 diff。

`todo/` 的工程 JSON 由 `dart run tool/make_todo_example.dart` 生成。
