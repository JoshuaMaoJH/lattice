# ADR-014：文本形式是完整的第二种写法，不是「可读导出」

**状态**：已接受（R18）

## 背景

项目书把 R18 列为预留时给的理由是「图 JSON 已经是规范化的、与画布坐标分离的
语义模型」。做的时候要先回答一个问题：文本形式**丢不丢东西**。

「可读导出」很好写：省掉 ID、省掉画布坐标、把嵌套压平，出来一份人看着舒服的
摘要。但那样它就只能单向，而单向的文本形式几乎没有用——git diff 里看得懂，却
不能改；LLM 生成得出来，却塞不回去。

## 决定

`.lat` 是**无损**的：节点 ID、画布坐标、嵌套槽位、表达式，全都在里面。
`JSON → 文本 → JSON` 逐字段相等，五个示例的每一个 page / prefab / server
function 都有测试锁着。

格式是行导向 + 缩进的：

```
page Home #page_home route "/" home
  hierarchy
    Scaffold #w_root
      appBar: AppBar #w_appbar
        title: Text #w_title data="Counter"
      Column #w_col mainAxisAlignment="center"
        Text #w_txt data=<n_fmt.out
        ElevatedButton #w_btn onPressed=!ev_btn
  graph
    Signal #n_count dartType="int" init=0 name="count"
  wires
    n_count.value -> n_fmt.args[0]
  layout
    n_count @ 120,80
```

四个记号，各只有一种含义：`#id`、`<node.pin` 是绑定、`!node` 是事件、
反引号里是内联 Dart。

## 代价

**值用 JSON 字面量。** `data="Counter"` 而不是 `data=Counter`。多了引号，但省掉
了发明第二套字面量语法——以及它在数字、布尔、列表、嵌套 map 上会踩的每一个坑。
`data=unquoted` 是错误而不是字符串，这是故意的。

**画布坐标在文件里。** 它们是噪音，在 diff 里尤其烦人。但把它们排除出去就意味着
读回来会丢布局，那这个格式就不能作为工程的另一种写法存在，只能是导出。宁可忍
`layout` 那一段。

## 为什么不是解析器生成器

格式小，而错误信息比解析器本身更重要：这是给人改的文件，出错时要说「第 12 行：
wire 要写成 from.pin -> to.pin」，不是抛一个栈。手写递归下降 400 行，够了。
