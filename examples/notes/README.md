# notes

R19 的验收示例：**一个重启之后还在的列表**。

## 数据层就是一行声明

`project.json` 里：

```json
"collections": [{"name": "notes", "of": "Note"}]
```

生成出四个文件：`collections.dart`（类型化的列表，装在 signal 里）、
`store.dart`（存储的平台无关面）、`store_io.dart`（写 JSON 文件）、
`store_web.dart`（写 localStorage）。后两个之间是条件导入——Dart 里说「这件事
按平台不同」而不引入依赖的唯一办法。

## 图的形状

```
CollectionItems(notes) ──▶ ForEach ──▶ ListTile
                       └─▶ noteCount(notes) ──▶ Text

TextField.onChanged ─▶ SetSignal(draft)
Button.onPressed    ─▶ CollectionAdd(notes, newNote(draft))
                        └─▶ SetSignal(draft, '')
ListTile.onTap      ─▶ CollectionRemoveAt(notes, index)
```

## 它要证明的事

1. **读是响应式的。** `CollectionItems` 和 `Signal` 一样算作 signal 依赖，所以
   读它的 widget 自动进 `SignalBuilder`——加一条笔记，列表和计数一起更新，没有
   任何一处要手写 setState。

2. **写是 await 的。** 每个集合动作都落盘，所以每个都 await。只在内存里改、
   等下一帧再存的写法，表现出来是「它忘了我刚才输的东西」。

3. **序列化就是模型自己的那套。** 和跨网络边界用的是同一份 codec（§7.7）。
   由此得到一条校验规则：没有 JSON 形式的字段不能存——`persist: false` 的集合
   不受此限，因为它本来就只活在内存里。

4. **首帧之前数据已经在手上。** `main()` 是 async 的，先 `await
   loadCollections()` 再 `runApp`。先渲染空的再跳一下，看起来就像数据丢了。

## 它证明不了的事

**这不是数据库。** 没有索引、没有查询、没有迁移。整个列表一次读进内存、一次写
回去。几百条以内没问题，几万条就该换真的数据库了——那时候 `Note` 的 codec 还是
能用，因为它本来就不属于这一层。

**旧格式的数据会被丢掉。** 模型改了字段之后，存着的旧数据解不出来，`load()` 会
把列表清空而不是让 app 起不来。丢数据是坏事，起不来更坏。迁移没有做。
