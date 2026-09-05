# counter

项目书 §8 的端到端示例，也是整条管线的验收用例。

## 图

```
Signal<int> count = 0
Format "Count: {0}"      ← count.value
Text#w_txt.data          ← Format.out
Button#w_btn.onPressed ─▶ UpdateSignal(count, x => x + 1)
```

四个节点、两条边。`pages/page_home.json` 里能逐字读到这四个节点。

## 它要证明的事

1. **绑定成立**：`Text.data` 接到图输出后，文本随 Signal 自动更新，没有一行 `setState`。
2. **边界最小**：只有那一个 `Text` 被包进 `SignalBuilder`，`AppBar` 里的标题、按钮标签
   仍是 `const`。
3. **代码可读**：生成的 `_onBtnPressed` 是 `count.value = count.value + 1;`，
   而不是 `count.value = ((x) => x + 1)(count.value);`——lambda 在安全时会被 beta 归约。
4. **零诊断**：`flutter analyze` 在生成工程上没有任何输出（G2）。
5. **能出产物**：`flutter build web` 成功（G6 的本机部分）。

## 试一下

```bash
dart run packages/lattice_cli/bin/lattice.dart build examples/counter -t web --analyze
cat examples/counter/.lattice/build/lib/pages/home_page.dart
```

改 `pages/page_home.json` 里的 `template`（比如改成 `"点了 {0} 次"`），
重新 build，看生成代码里的插值字符串跟着变。
