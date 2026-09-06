# 参与 Lattice

## 跑起来

```bash
export PATH="$HOME/flutter/bin:$PATH"   # 如果 flutter 不在 PATH 上
./tool/bootstrap.sh
```

**根目录一句 `flutter pub get` 是不够的。** `lattice_runtime` 故意不在 pub
workspace 里——生成的工程要从 workspace 外面 path 依赖它，而 pub 不允许 path
依赖指向成员包。代价就是它得单独 resolve 一次，`bootstrap.sh` 做的就是这个。

编辑器的平台目录（`linux/`、`macos/`、`windows/`、`web/`）也不进版本控制，
它们是生成物——和 Lattice 对待它生成的工程是同一个立场（§7.9）。要构建先补上：

```bash
cd apps/lattice_editor && flutter create --platforms=linux .
```

```bash
melos run ci        # format + analyze + 全部测试
```

或者分开跑：

```bash
dart format --output=none --set-exit-if-changed packages/ tool/ apps/lattice_editor/lib
dart analyze packages/ tool/ apps/lattice_editor
(cd packages/lattice_core && dart test)
(cd apps/lattice_editor && flutter test)
```

编辑器：

```bash
cd apps/lattice_editor
flutter run -d linux examples/signup    # 桌面：真实文件 + 预览
flutter run -d chrome                   # 浏览器：内置 demo，无文件系统
```

## 三条约定

**1. 生成的代码必须像手写的。** 这不是修辞——它是 G2 和 G5 的可测形式：

- `flutter analyze` 零诊断（不只是零 error）
- `dart format` 之后与手写风格无异
- 改动生成器时，goldens 会拦住你；**重录之前先读 diff**：
  ```bash
  cd packages/lattice_codegen && UPDATE_GOLDENS=1 dart test
  ```

**2. 示例是测试。** `examples/` 下的每个工程都进 CI，断言直接写在它们上面
（`packages/lattice_codegen/test/features_test.dart`）。加功能就加个示例；
示例不绿，功能不算完。

**3. 决策进 `docs/decisions/`。** 尤其是偏离项目书的时候——
[ADR-012](docs/decisions/012-plain-dart-server.md) 换掉了 §9 选的 dart_frog，
所以它有一整页解释为什么，以及推翻它要动哪里。

## 加一个 widget

改 `packages/lattice_core/lib/src/schema/widget_registry.dart` 一处即可：
Inspector 的表单、Graph 的引脚、发射的构造函数调用都由 schema 驱动。

要留意的两个字段：
- `constCtor` —— Flutter 的这个构造函数是不是 `const`。写错会让生成工程报错，
  所以少数例外（`Image.network`、`ListView`）是显式标出来的，不是猜的。
- `controller` —— 值是不是经由 controller 到达 widget（见 `TextField.text`）。

## 加一个节点

`node_registry.dart` 声明引脚，`lowering.dart` 的 switch 里加一个 case。
引脚类型可以依赖节点配置——`Signal` 的输出类型来自它的 `dartType`。

节点参考是生成的：

```bash
dart run tool/generate_node_reference.dart
```

## 提交前

```bash
melos run ci
for ex in examples/*/; do
  dart run packages/lattice_cli/bin/lattice.dart build "$ex" -t web --analyze
done
```

## 协议

MIT。提交即表示你同意以该协议贡献你的代码。
