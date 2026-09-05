# ADR-010 M2 的四个形状：controller、prefab、异步链、打包边界

M2 补齐 R9 / R11 / R12 / R13 / R16 时定下的四件事。它们各自不大，但都决定了以后加东西的形状。

## 1. 值经由 controller 到达 widget 时，由 codegen 拥有那个 controller

`TextField` 不能像 `Text` 那样"给它一个字符串就跟着变"——widget 自己拥有编辑状态。于是 `ParamSchema` 多了一个 `ControllerBinding`：

```dart
ParamSchema(
  name: 'text',
  type: _string,
  controller: ControllerBinding(
    type: 'TextEditingController',
    argument: 'controller',
    property: 'text',
  ),
)
```

codegen 据此在 `initState` 里创建、用 `effect` 保持同步、在 `dispose` 里销毁：

```dart
_inputController = TextEditingController(text: draft.value);
_inputControllerSync = effect(() {
  final next = draft.value;
  if (_inputController.text != next) {
    _inputController.text = next;
  }
});
```

那个 `if` 是关键：无条件写回会在每次重建时把光标弹回开头。

**连带的一条规则**：controller 绑定的参数**不计入** widget 的重建依赖。controller 自己把新值推进去，再包一层 `SignalBuilder` 只会让每次按键都重建整棵子树。这条写在 `_ownSignalDeps` 里。

将来加 `ScrollController` / `TabController` 走同一条路，不需要新机制。

## 2. Prefab v1 只收值，不收 children 和回调

`Prefab` 与 `Page` 都实现 `WidgetUnit`——同一套校验、同一套 lowering、同一个发射器。两者只在"怎么被抵达"上不同：页面靠路由，prefab 靠被放进另一棵树。

**v1 的边界**：prefab 参数只能是值。不支持 children 槽位，也不支持回调参数（prefab 里的按钮回调不出去）。

**为什么**：回调参数意味着 prefab 要往外发事件，而事件在本系统里是"widget 回调 → Action 链"，不是"组件对外接口"。这需要先想清楚 prefab 的事件出口是什么形状，不该顺手做。R9 的验收是"复用 3 处以上无异常"，值参数已经满足。

**留好的性质**：prefab 没有自己的 Signal / Event / controller 时编译成带 const 构造函数的 `StatelessWidget`，所以放三次不比写三遍贵。这个判断由 `WidgetUnit.isStateful` 给出，prefab schema 和 lowering 共用同一个定义——两处各写一遍迟早会分叉。

**校验**：名字必须是合法类名、不能撞内置 widget、不能重名、不能自己包自己（`prefab_recursion` 用染色法查环）。

## 3. 一条动作链里只要有 await，整个 handler 就是 async

`HttpRequest` 是**动作节点**，不是产出 `Future<T>` 的计算节点。理由是它有副作用，而本系统里只有动作能有副作用（ADR-001）。它把结果写进 Signal，把 loading / error 写进另外两个 Signal：

```dart
Future<void> _onFetchPressed() async {
  loading.value = true;
  error.value = null;
  try {
    final response = await http.get(Uri.parse(_urlFor(city.value)));
    if (response.statusCode >= 400) {
      throw Exception('Request failed: ${response.statusCode}');
    }
    forecast.value = Forecast.fromJson(jsonDecode(response.body) as Map<String, Object?>);
  } catch (failure) {
    error.value = failure.toString();
  } finally {
    loading.value = false;
  }
}
```

调用点不变——Dart 允许把 `Future<void> Function()` 传给 `VoidCallback`。

**解码由目标 Signal 的类型决定**，不是由节点配置决定：`String` 取原始 body，模型走 `fromJson`，`List<模型>` 走 map。少一个要填的下拉框。

**真实 API 不按 Dart 的拼法命名**，所以模型字段多了 `jsonKey`：

```json
{ "fields": {"currentWeather": "CurrentWeather"},
  "jsonKeys": {"currentWeather": "current_weather"} }
```

`http` 依赖只在真的有页面用到时才进生成的 pubspec。

## 4. 打包只做本机真能做的，其余说清楚从哪来

`lattice package` 的分工：

- **Web** 直接在 Dart 里打 zip（`package:archive`）。静态站点就是个 zip，为此依赖宿主装了 `zip` 没道理。
- **其余格式**交给 `flutter_distributor`，并生成它读的 `distribute_options.yaml`——一份配置覆盖 dmg / msix / deb / appimage / apk / aab / ipa。
- **宿主构建不了的目标**（ADR-006）在动手前就报出来，并指向生成的 CI 工作流。
- **`flutter_distributor` 没装**时，给出的是"下一步做什么"，不是一个失败：

  ```
  ! linux: flutter_distributor is not installed. Run
    `dart pub global activate flutter_distributor`, then
    `lattice package --target linux` again. The generated
    distribute_options.yaml already describes this target.
  ```

一个打不了的包应该说清楚缺什么，而不是只报错。

## 实现

- controller：`ControllerBinding`（`widget_schema.dart`）、`ControllerIr`、`PageEmitter._initState/_dispose`
- prefab：`Prefab`、`WidgetUnit`、`WidgetLookup`、`Validator._validatePrefabDeclarations`
- 异步：`Lowering._lowerHttpRequest`、`HandlerIr.isAsync`
- 打包：`packages/lattice_build/lib/src/packager.dart`、`SupportFiles.distributeOptions`
- 测试：`packages/lattice_codegen/test/features_test.dart`（断言跑在 `examples/` 上）
