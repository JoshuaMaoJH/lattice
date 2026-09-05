# weather

R13 的验收示例：一次 HTTP 请求，解码成模型，带 loading 与错误态。
数据来自 [Open-Meteo](https://open-meteo.com)，无需 API key。

## 图的形状

```
Signal<String>    city     = 'Berlin'
Signal<Forecast?> forecast
Signal<bool>      loading  = false
Signal<String?>   error

TextField.onChanged ─▶ SetSignal(city, payload)     ← city 也回写进输入框（controller 绑定）
Button.onPressed    ─▶ HttpRequest(url ← urlFor(city))
                         signal        = forecast
                         loadingSignal = loading
                         errorSignal   = error

If loading          → CircularProgressIndicator
If hasError(error)  → Text(errorText(error))
If hasForecast(f)   → 温度 + 风速
```

`urlFor` 是 `Dart Code` 节点，调用 `custom/cities.dart` 里手写的城市坐标表——
一张表就是一张表，没必要画成节点（§7.8）。

## 它要证明的事

1. **一条链里有 await，整个 handler 就是 async**，并且 loading / error 的
   开关是生成的，不是用户逐个连出来的：

   ```dart
   Future<void> _onFetchPressed() async {
     loading.value = true;
     error.value = null;
     try {
       final response = await http.get(Uri.parse(_urlFor(city.value)));
       if (response.statusCode >= 400) { throw Exception(...); }
       forecast.value = Forecast.fromJson(jsonDecode(response.body) as Map<String, Object?>);
     } catch (failure) {
       error.value = failure.toString();
     } finally {
       loading.value = false;
     }
   }
   ```

2. **解码形状由目标 Signal 的类型决定**。`Signal<Forecast?>` 就走 `Forecast.fromJson`，
   不需要再填一个「怎么解析」的下拉框。

3. **真实 API 不按 Dart 的拼法命名**。`current_weather` 通过模型的 `jsonKeys`
   映射到 `currentWeather`，生成的 `fromJson` 直接读对键。

4. **`http` 依赖按需加入**。todo 示例的 pubspec 里没有它。

5. **TextField 是双向的**。`city` 信号被写回输入框，且不会因此每按一个键
   就重建整棵子树——controller 绑定的参数不计入重建依赖（ADR-010）。

## 试一下

```bash
dart run packages/lattice_cli/bin/lattice.dart build examples/weather -t web --analyze
dart run packages/lattice_cli/bin/lattice.dart package examples/weather -t web
```

生成的 model 已经用真实响应验证过：

```
decoded: 16.4 °C, wind 15.8 km/h
round-trip equal: true
```

已知城市：Berlin / London / Paris / Madrid / New York / Tokyo / Shanghai / Sydney。
输入别的会走到错误分支——这也是错误态存在的意义。
