# todo

R10 的验收示例：一个能增、能勾、能删的列表。它存在的意义是把 ForEach 的
作用域规则（ADR-009）跑通并展示出来。

## 图的形状

```
Signal<List<Todo>> todos = []
Signal<String>     draft = ''
Signal<int>        seq   = 0

ListIsEmpty  ← todos                    → If.condition（空状态提示）

TextField.onChanged ─▶ SetSignal(draft, payload)
Button.onPressed    ─▶ UpdateSignal(seq, x => x + 1)
                    ─▶ SetSignal(todos, ListAppend(todos, buildTodo(seq, draft)))
                    ─▶ SetSignal(draft, '')

── ForEach(w_each) over todos, itemKey = "id" ──────────────────
   ForEachItem ─▶ item / index                （只在模板内可读）
   titleOf(item) → Text.data
   doneOf(item)  → Checkbox.value
   Checkbox.onChanged ─▶ SetSignal(todos, ListSetAt(todos, index, toggle(item)))
   IconButton.onPressed ─▶ SetSignal(todos, ListRemoveAt(todos, index))
────────────────────────────────────────────────────────────────
```

## 它要证明的事

1. **ForEach 展开成 collection-for**，不是某种运行时列表构件：

   ```dart
   for (final (index, item) in todos.value.indexed)
     KeyedSubtree(key: ValueKey(item.id), child: ListTile(...))
   ```

   带下标的形式只在真的有人读 `index` 时才发射。

2. **身份是强制的**。`itemKey: "id"` 不是可选项——元素是模型时不写会被校验器拒绝，
   因为没有它，删掉第一行会把它的 widget 状态交给第二行（ADR-009）。

3. **`item` 出不了模板**。把绑定 `titleOf` 的 `Text` 挪到 ForEach 外面，
   立刻得到 `item_out_of_scope`，而不是等到生成的 Dart 报未定义变量。

4. **模板里的按钮能写外层状态**。handler 仍是 State 上的方法，循环变量作为参数
   传进去，调用点是闭包：

   ```dart
   void _onDelPressed(int index) { todos.value = (List.of(todos.value)..removeAt(index)); }
   ...
   IconButton(onPressed: () => _onDelPressed(index), ...)
   ```

5. **重建边界不嵌套**。Column 因为 If 和 ForEach 都读 `todos` 而成为边界，
   它底下的 ListView 就不会再包一层——整页只有一个 `SignalBuilder`。

6. **If 有两种形态**。在 children 列表里是 collection-`if`；在单 child 槽位里
   会变成三元表达式，缺失分支补 `const SizedBox.shrink()`。

## 已知缺口

`TextField` 目前是单向的（widget → signal）。`a_clear` 会把 `draft` 置空，
状态是对的，但输入框里的文字不会跟着清掉——把 signal 写回输入框需要
controller 绑定，还没实现。这是 M2 剩下的活，不是这个示例的 bug。

## 试一下

```bash
dart run packages/lattice_cli/bin/lattice.dart build examples/todo -t web --analyze
cat examples/todo/.lattice/build/lib/pages/home_page.dart
```

工程 JSON 由 `tool/make_todo_example.dart` 生成（这样 fixture 有类型检查），
生成的 JSON 才是交付物。
