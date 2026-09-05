# todo

M2 的主示例：一个能增、能勾、能删、能进详情页的列表。
它把 R9 / R10 / R11 / R12 和 controller 绑定都串在一处。

## 图的形状

```
Signal<List<Todo>> todos = []      Signal<String> draft = ''      Signal<int> seq = 0

ListLength(todos) → total ─┐
countDone(todos)  → done  ─┼─▶ 三张 StatCard（同一个 Prefab 放三次）
total - done      → left  ─┘

ListIsEmpty(todos) → If.condition（空状态提示）

TextField.text      ← draft                （双向：controller 绑定）
TextField.onChanged ─▶ SetSignal(draft, payload)
Button.onPressed    ─▶ UpdateSignal(seq, x => x + 1)
                    ─▶ SetSignal(todos, ListAppend(todos, buildTodo(seq, draft)))
                    ─▶ SetSignal(draft, '')

── ForEach(w_each) over todos, itemKey = "id" ──────────────────
   ForEachItem ─▶ item / index                （只在模板内可读）
   titleOf(item) → Text.data                  （走 custom/labels.dart）
   doneOf(item)  → Checkbox.value
   ListTile.onTap       ─▶ Navigate('/detail', title: …, done: …)
   Checkbox.onChanged   ─▶ SetSignal(todos, ListSetAt(todos, index, toggle(item)))
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

4. **模板里的按钮能写外层状态、也能导航**。handler 仍是 State 上的方法，
   循环变量作为参数传进去，调用点是闭包：

   ```dart
   void _onDelPressed(int index) { todos.value = (List.of(todos.value)..removeAt(index)); }
   ...
   IconButton(onPressed: () => _onDelPressed(index), ...)
   ```

5. **重建边界不嵌套**。Column 因为 If 和 ForEach 都读 `todos` 而成为边界，
   它底下的 ListView 就不会再包一层——整页只有一个 `SignalBuilder`。

6. **Prefab 放三次只有一份定义**。`StatCard` 没有自己的状态，
   编译成带 const 构造函数的 `StatelessWidget`（R9）。

7. **双向 TextField**。`text` 绑定到 `draft`，点 Add 之后输入框真的会清空。
   codegen 拥有那个 `TextEditingController`（创建、同步、销毁），
   并且 controller 绑定的参数不计入重建依赖，所以打字不会重建整棵子树。

8. **第二个页面拿到路由参数**。点一行进 `/detail`，标题和完成状态在目标页
   变成构造函数参数；`detail_page.dart` 是 `StatelessWidget`，
   所以读的是 `title` 而不是 `widget.title`（R12）。

9. **手写 Dart 能被图调用**。`custom/labels.dart` 里的 `decorate` 和 `countDone`
   通过 `Dart Code` 节点接入，codegen 把 `custom/` 镜像进生成工程的
   `lib/custom/` 且从不覆盖（§7.8、R11）。

顺带能看到提升规则在真实图上生效：`total` 和 `doneCount` 各被用两次，
提升成了 `computed()` 字段；只用一次的 `left` 内联成
`total.value - doneCount.value`。

## 试一下

```bash
dart run packages/lattice_cli/bin/lattice.dart build examples/todo -t web --analyze
cat examples/todo/.lattice/build/lib/pages/home_page.dart
```

工程 JSON 由 `dart run tool/make_todo_example.dart` 生成（这样 fixture 有类型检查），
生成的 JSON 才是交付物。手写代码在 `custom/`，它随工程一起进版本控制。
