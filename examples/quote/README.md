# quote

M3 的示例：一张图，两个产物（§7.7）。

定价规则跑在服务端——它是生意，不是界面，不该发到客户端去。页面把 SKU 和数量
送过去，拿回一个 `Quote`。

## 图的形状

```
── server/fn_price.json ─── priceFor(sku: String, quantity: int) → Quote ──┐
│  Param sku ──▶ unitPrice(sku)      PRO→49  LITE→19  其余→9              │
│  Param quantity ──▶ discountFor(q) ≥100→20%  ≥10→10%  其余→0            │
│  ─────────────────▶ buildQuote(…) ──▶ Return                            │
└──────────────────────────────────────────────────────────────────────────┘
                                    ▲
── pages/page_home.json ────────────┼──────────────────────────────────────┐
│  Signal sku / quantity ───────────┘                                      │
│  Button.onPressed ─▶ CallServer(priceFor)                                │
│                        signal        = quote                             │
│                        loadingSignal = loading                           │
│                        errorSignal   = error                             │
│  If loading → 转圈    If hasError → 红字    If hasQuote → 总价 + 明细     │
└──────────────────────────────────────────────────────────────────────────┘
```

## 它要证明的事

1. **调用点没有任何仪式**。整个 `CallServer` 编译成：

   ```dart
   Future<void> _onGoPressed() async {
     loading.value = true;
     error.value = null;
     try {
       quote.value = await priceFor(sku.value, quantity.value);
     } catch (failure) {
       error.value = failure.toString();
     } finally {
       loading.value = false;
     }
   }
   ```

   序列化在生成的 stub 里，页面看不到它。

2. **服务端是普通 Dart**，没有框架，`pubspec.yaml` 里零依赖（ADR-012）：

   ```dart
   /// `POST /rpc/priceFor` — from fn_price.
   Quote priceFor(String sku, int quantity) =>
       _buildQuote(sku, quantity, _unitPrice(sku), _discountFor(quantity));
   ```

3. **模型两边是同一份文件**。`lib/models.dart` 逐字节相同——「一个 Quote 是
   什么」只有一个定义。

4. **边界被校验**。参数或返回值放一个过不了 JSON 的类型（比如 `TextStyle`），
   得到 `unserializable_boundary`；在服务端图里放个 `Signal`，得到
   `client_node_on_server`。

## 试一下

```bash
dart run packages/lattice_cli/bin/lattice.dart build examples/quote
cd examples/quote/.lattice/build_server && dart pub get && dart run bin/server.dart 8099
```

另开一个终端：

```bash
curl -s -X POST localhost:8099/rpc/priceFor \
  -H 'content-type: application/json' -d '{"sku":"PRO-1","quantity":12}'
```

```json
{"result":{"sku":"PRO-1","quantity":12,"unitPrice":49.0,"discount":0.1,"total":529.2}}
```

客户端默认连 `http://localhost:8080`；换个地址用
`--dart-define=LATTICE_SERVER=https://…`，一次构建既能连笔记本也能连线上。

## 已知缺口

- **没有鉴权、没有数据库**，就是 §7.7 说的「纯远程函数」。
- **服务端够不到 `custom/`**：`Dart Code` 节点的 `imports` 目前只镜像进客户端
  工程。服务端要调手写代码得先补这条。
- **没部署过**。§11 的 M3 写的是「示例部署到云服务器」——这里只在本机跑通了
  往返。生成的工程是个零依赖的 Dart 程序，扔到任何装了 Dart 的主机上
  `dart run bin/server.dart` 就行，但这一步没有验证过。
