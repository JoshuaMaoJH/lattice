# signup

R14 的验收示例：一张 51 个节点的图，整理之后单屏可读。

表单校验是最小的、**诚实地需要五十个节点**的东西：三个字段，每个有自己的长度
规则和形状规则，汇成一个"表单是否有效"的答案。折起来能一眼看完，展开后每条
规则都看得见——这就是 R14 的全部主张。

## 图的形状

```
┌ State ──────────┐   ┌ Email rules      ⊟ ┐   ┌ Is the form valid? ─────┐
│ email           │──▶│ len ≥ 5            │   │                          │
│ password        │   │ 有 @ 且域名有 .    │──▶│ And ─┐                   │
│ confirm         │   └────────────────────┘   │      ├─ And ─┐           │
│ accepted        │   ┌ Password rules   ⊟ ┐   │ ⟲ ───┘       ├─ And ──▶ │
└─────────────────┘──▶│ len ≥ 8, 含数字     │──▶│              │  status  │
                      └────────────────────┘   │ accepted ────┘           │
                      ┌ Repeat password  ⊟ ┐   │                          │
                      │ 与 password 相同    │──▶│ ⟲                        │
                      └────────────────────┘   └──────────────────────────┘
```

`⊟` 是折叠的 Subgraph，`⟲` 是 Reroute，两个带标题的方框是 Comment。

## 三种整理手段各自做什么

| | 做什么 | 对生成代码的影响 |
|---|---|---|
| **Subgraph** | 把一组节点折成一个盒子；跨边界的边接到盒子的端口上 | 无。成员本来就在图里 |
| **Comment** | 画在所有东西背后的带标题区域 | 无 |
| **Reroute** | 把一条长边折一下，两个引脚都在它的中心线上 | 无。它编译成直接传递 |

三者都不改变语义——这是刻意的。整理不该是重构。

## 折叠是折叠，不是子函数

§7.2 把 Subgraph 和 Comment / Reroute 一起归在**组织**类，§10 R14 写的也是
"Subgraph **折叠**"。所以 v1 就是折叠：成员留在图里，Subgraph 只是记住它们是
一组，并能收起来。

**它不是可复用的函数。** 没有自己的输入输出类型，不能在别处再实例化一份。
R17（服务端函数）需要的是真正的边界——那是 M3 的设计题，不该在这里顺手做一个
形状不对的版本占位。

## 试一下

```bash
dart run packages/lattice_cli/bin/lattice.dart build examples/signup -t web --analyze
```

生成的代码里看不到任何组织痕迹——只有校验逻辑本身：

```dart
// n_email_ok
late final emailOk = computed(
  () => (_emailLength(email.value) >= 5) && _emailShape(email.value),
);
```

Reroute 也消失了：`n_bend_a` 直接传递，生成代码里 `passOk` 就接在 `And` 上。

## 已知缺口

编辑器还没有多选，所以一个 Subgraph 的成员是在 Inspector 里以逗号分隔的
节点 id 列表编辑的。够用，但"框选一堆节点然后折起来"才是这个功能该有的样子。
