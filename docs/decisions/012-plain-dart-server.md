# ADR-012 服务端生成 dart:io，不用 dart_frog

**这条改动了项目书 §9 的一个选型。** 如果理由不成立，推翻它只需要换掉一个 emitter。

## 背景

§9 选了 `dart_frog`，理由是「路由文件即接口，与 codegen 输出天然匹配」。
`shelf` 是列出的备选。

## 决策

**生成一个只依赖 `dart:io` 的普通 Dart 程序。** 既不用 dart_frog，也不用 shelf。

## 为什么

**1. dart_frog 的卖点对我们不成立。** 「路由文件即接口」是给**人**写路由用的
约定：你在 `routes/users/[id].dart` 建个文件，框架替你接上。但 Lattice 的路由
是生成的——没有人会打开那个目录。我们为一个不会被使用的约定付了依赖。

**2. 它在链条里多插一个必须全局安装的工具。** dart_frog 的工程要先
`dart_frog build` 才能跑。§7.9 的立场是「用户从头到尾不需要接触任何一个平台的
打包工具链」；后端多要一个全局 CLI，与这个立场矛盾。

**3. 零依赖意味着服务端能立刻跑起来。** 生成的工程 `dart pub get && dart run
bin/server.dart` 就起来了，`pubspec.yaml` 里一个依赖都没有。这也是为什么这次
能真的验证它，而不是只生成了代码：

```
$ curl -s -X POST localhost:8099/rpc/priceFor \
    -H 'content-type: application/json' -d '{"sku":"PRO-1","quantity":12}'
{"result":{"sku":"PRO-1","quantity":12,"unitPrice":49.0,"discount":0.1,"total":529.2}}
```

**4. 整个 HTTP 表面是一个人能读完的文件。** 约 80 行 `bin/server.dart`：
CORS 预检、`/health`、`POST /rpc/<name>` 的分发、错误到状态码的映射。
eject 之后要改它不需要先学一个框架（G5）。

shelf 没被选中是同理：它的中间件模型在只有一条路由形状时也是纯开销。

## 代价

- 没有中间件生态。加鉴权、限流、日志要自己写——但 v1 边界本来就是
  「无鉴权、无数据库；纯远程函数」（§7.7）。
- 没有 hot reload。生成的服务端要重启。M3 的范围里可接受。

真需要一个框架时（M4 之后、有中间件需求了），换掉 `ServerEmitter` 就行——
`ServerFunctionIr` 与它无关。

## 顺带确定的两件事

**模型文件两边共用同一份。** 生成的 `models.dart` 原本为了深比较引了
`package:flutter/foundation.dart`，服务端没有 Flutter。改成把两个比较 helper
直接发射进文件里（且只发射用得到的那个），于是模型零依赖，客户端和服务端
用的是逐字节相同的一份——「一个 Todo 是什么」只有一个定义。

**客户端 stub 放在 `lattice_codegen` 而不是 `lattice_server_gen`。**
§6 把「RPC 客户端」列在 server_gen 名下，但 server_gen 依赖 codegen，
反过来会成环。`lib/rpc.dart` 是客户端工程的文件，放客户端生成器里也更顺。

## 错误消息

RPC 的错误是给**调用者**看的，所以：

| | |
|---|---|
| 名字不在图里 | `404 No server function named "nope".` |
| 少了必填参数 | `400 priceFor: Missing required argument "quantity".` |
| 参数类型不对 | `400 priceFor: type 'String' is not a subtype of type 'int'` |

第一版少参数时答的是 `Null check operator used on a null value`——技术上没错，
对调用者毫无用处。生成的解码器现在按名字读参数，就是为了能说出是哪一个。

## 实现

- `packages/lattice_server_gen/lib/src/server_emitter.dart`
- `packages/lattice_codegen/lib/src/emit/rpc_client_emitter.dart`
- 示例：`examples/quote`
