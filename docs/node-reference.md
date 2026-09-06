# 节点与 Widget 参考

> 本文件由 `dart run tool/generate_node_reference.dart` 从
> `lattice_core` 的注册表生成，请勿手工编辑。

## 节点库

引脚类型随节点配置而变，下表展示的是默认配置下的形状。
`…` 表示可变长引脚（如 `Format.args[0]`、`args[1]`）。

### 状态

| 节点 | 输入 | 输出 | 配置 | 说明 |
|---|---|---|---|---|
| `Signal` | — | ● `value`: dynamic | `dartType`, `init`, `name` | The only mutable state source. Reads are reactive. |

### 计算（纯函数）

| 节点 | 输入 | 输出 | 配置 | 说明 |
|---|---|---|---|---|
| `Const` | — | ● `value`: String | `dartType`, `value` | A literal value. |
| `Format` | ● `args…`: dynamic | ● `out`: String | `template` | Interpolates arguments into a template, e.g. "Count: {0}". |
| `Computed` | — | ● `out`: dynamic | `dartType`, `expr`, `inputs`, `imports` | A pure Dart expression over named inputs. |
| `Add` | ● `a*`: int<br>● `b*`: int | ● `out`: int | `dartType` | a + b |
| `Subtract` | ● `a*`: int<br>● `b*`: int | ● `out`: int | `dartType` | a - b |
| `Multiply` | ● `a*`: int<br>● `b*`: int | ● `out`: int | `dartType` | a * b |
| `Divide` | ● `a*`: int<br>● `b*`: int | ● `out`: double | `dartType` | a / b (always a double, as in Dart) |
| `IntegerDivide` | ● `a*`: int<br>● `b*`: int | ● `out`: int | — | a ~/ b |
| `Modulo` | ● `a*`: int<br>● `b*`: int | ● `out`: int | `dartType` | a % b |
| `Equals` | ● `a*`: int<br>● `b*`: int | ● `out`: bool | `dartType` | a == b |
| `NotEquals` | ● `a*`: int<br>● `b*`: int | ● `out`: bool | `dartType` | a != b |
| `GreaterThan` | ● `a*`: int<br>● `b*`: int | ● `out`: bool | `dartType` | a > b |
| `LessThan` | ● `a*`: int<br>● `b*`: int | ● `out`: bool | `dartType` | a < b |
| `GreaterOrEqual` | ● `a*`: int<br>● `b*`: int | ● `out`: bool | `dartType` | a >= b |
| `LessOrEqual` | ● `a*`: int<br>● `b*`: int | ● `out`: bool | `dartType` | a <= b |
| `And` | ● `a*`: bool<br>● `b*`: bool | ● `out`: bool | — | a && b |
| `Or` | ● `a*`: bool<br>● `b*`: bool | ● `out`: bool | — | a || b |
| `Not` | ● `a*`: bool | ● `out`: bool | — | !a |
| `Concat` | ● `a*`: String<br>● `b*`: String | ● `out`: String | — | a + b, for strings |
| `ToString` | ● `value*`: dynamic | ● `out`: String | — | value.toString() |
| `Conditional` | ● `condition*`: bool<br>● `ifTrue*`: String<br>● `ifFalse*`: String | ● `out`: String | `dartType` | condition ? ifTrue : ifFalse |
| `ListLength` | ● `list*`: List<dynamic> | ● `out`: int | `elementType` | list.length |
| `ListIsEmpty` | ● `list*`: List<dynamic> | ● `out`: bool | `elementType` | list.isEmpty |
| `ListAppend` | ● `list*`: List<dynamic><br>● `item*`: dynamic | ● `out`: List<dynamic> | `elementType` | A new list with one item appended. |
| `ListRemoveAt` | ● `list*`: List<dynamic><br>● `index*`: int | ● `out`: List<dynamic> | `elementType` | A new list with one index removed. |
| `ListSetAt` | ● `list*`: List<dynamic><br>● `index*`: int<br>● `item*`: dynamic | ● `out`: List<dynamic> | `elementType` | A new list with one index replaced. |
| `MapGet` | ● `map*`: Map<String, dynamic><br>● `key*`: String | ● `value`: dynamic? | `keyType`, `valueType` | map[key]. The workhorse for per-item UI state keyed by id. |
| `MapPut` | ● `map*`: Map<String, dynamic><br>● `key*`: String<br>● `value*`: dynamic | ● `out`: Map<String, dynamic> | `keyType`, `valueType` | A new map with one key set. |

### 界面

| 节点 | 输入 | 输出 | 配置 | 说明 |
|---|---|---|---|---|
| `PageParam` | — | ● `value`: dynamic | `name` | A parameter of the page or prefab this graph belongs to (R12, R9). |

### 事件

| 节点 | 输入 | 输出 | 配置 | 说明 |
|---|---|---|---|---|
| `Event` | — | ▷ `fire`: Event | `widget`, `event` | Fires when a widget callback runs. |

### 动作（唯一允许副作用的地方）

| 节点 | 输入 | 输出 | 配置 | 说明 |
|---|---|---|---|---|
| `CallServer` | ▷ `exec`: Event | ▷ `next`: Event | `function`, `signal`, `loadingSignal`, `errorSignal` | Calls a server function and writes the answer into a Signal. One input pin per parameter the function declares (§7.7). |
| `SetSignal` | ▷ `exec`: Event<br>● `value*`: dynamic | ▷ `next`: Event | `signal` | Writes a value into a Signal. |
| `UpdateSignal` | ▷ `exec`: Event | ▷ `next`: Event | `signal`, `fn` | Applies a pure function to a Signal's current value. |
| `ToggleSignal` | ▷ `exec`: Event | ▷ `next`: Event | `signal` | Inverts a bool Signal. |
| `Navigate` | ▷ `exec`: Event | ▷ `next`: Event | `route`, `replace` | Pushes or replaces a route. One input pin appears per parameter the target page declares. |
| `HttpRequest` | ▷ `exec`: Event<br>● `url*`: String | ▷ `next`: Event | `method`, `signal`, `loadingSignal`, `errorSignal`, `decode` | Fetches a URL and decodes the body into a Signal. The handler it sits in becomes async (R13). |
| `ShowSnackBar` | ▷ `exec`: Event<br>● `message*`: String | ▷ `next`: Event | — | Shows a snack bar on the current Scaffold. |
| `Print` | ▷ `exec`: Event<br>● `message*`: dynamic | ▷ `next`: Event | — | debugPrint, for tracing a graph. |
| `ShowDialog` | ▷ `exec`: Event<br>● `title*`: String<br>● `message*`: String | ▷ `next`: Event | `dismissLabel` | A modal alert with a title, a message and one dismiss button. |

### 控制

| 节点 | 输入 | 输出 | 配置 | 说明 |
|---|---|---|---|---|
| `Return` | ● `value*`: dynamic | — | — | What a server function answers with. Exactly one per function. |
| `ForEachItem` | — | ● `item`: dynamic<br>● `index`: int | `forEach` | The current item and index inside a ForEach template. Readable only by widgets inside that template. |

### 逃生舱

| 节点 | 输入 | 输出 | 配置 | 说明 |
|---|---|---|---|---|
| `DartCode` | — | ● `out`: dynamic | `inputs`, `dartType`, `body`, `name`, `imports` | A hand-written pure function body (§7.8). "imports" reaches your own files under lib/custom/, which codegen never overwrites. |

### 组织

| 节点 | 输入 | 输出 | 配置 | 说明 |
|---|---|---|---|---|
| `Subgraph` | — | — | `name`, `members`, `collapsed` | Folds a group of nodes into one box (§7.2, R14). Purely organisational: the members stay in the graph, so nothing about the generated code changes. |
| `Comment` | — | — | `text`, `width`, `height` | A note on the canvas. Ignored by codegen. |
| `Reroute` | ● `in*`: dynamic | ● `out`: dynamic | `dartType` | A pass-through, for tidying edges. |

## Widget 白名单

共 52 个。白名单之外的 widget 通过 
`Dart Code` 节点接入（§7.8）。

参数标记：`*` 必填，`⚡` 可绑定到图输出，`▷` 回调（接 Event 节点），
`◻` 嵌套 widget。

### 布局

| Widget | children | 参数 | 说明 |
|---|---|---|---|
| `Column` | n → `children` | ⚡ `mainAxisAlignment`: MainAxisAlignment = `start`<br>⚡ `crossAxisAlignment`: CrossAxisAlignment = `center`<br>⚡ `mainAxisSize`: MainAxisSize = `max` | Lays children out vertically. |
| `Row` | n → `children` | ⚡ `mainAxisAlignment`: MainAxisAlignment = `start`<br>⚡ `crossAxisAlignment`: CrossAxisAlignment = `center`<br>⚡ `mainAxisSize`: MainAxisSize = `max` | Lays children out horizontally. |
| `Stack` | n → `children` | ⚡ `alignment`: Alignment? | Overlays children. |
| `Center` | 1 → `child` | — | Centres its child. |
| `Align` | 1 → `child` | ⚡ `alignment`: Alignment | Aligns its child within itself. |
| `Padding` | 1 → `child` | ⚡ `padding*`: EdgeInsets | Insets its child. |
| `Container` † | 1 → `child` | ⚡ `width`: double?<br>⚡ `height`: double?<br>⚡ `color`: Color?<br>⚡ `padding`: EdgeInsets?<br>⚡ `margin`: EdgeInsets?<br>⚡ `alignment`: Alignment? | Painting, positioning and sizing in one box. |
| `SizedBox` | 1 → `child` | ⚡ `width`: double?<br>⚡ `height`: double? | A box of a fixed size, or plain empty space. |
| `Expanded` | 1 → `child` | ⚡ `flex`: int = `1` | Fills the remaining space along a Flex axis. |
| `Flexible` | 1 → `child` | ⚡ `flex`: int = `1` | Lets a child shrink or grow along a Flex axis. |
| `Spacer` | — | ⚡ `flex`: int = `1` | Empty flexible space between Flex children. |
| `Wrap` | n → `children` | ⚡ `spacing`: double = `0.0`<br>⚡ `runSpacing`: double = `0.0` | Lays children out in runs, wrapping as needed. |
| `Divider` | — | ⚡ `height`: double?<br>⚡ `thickness`: double?<br>⚡ `color`: Color? | A one-pixel horizontal rule. |
| `Positioned` | 1 → `child` | ⚡ `left`: double?<br>⚡ `top`: double?<br>⚡ `right`: double?<br>⚡ `bottom`: double?<br>⚡ `width`: double?<br>⚡ `height`: double? | Places a child at an offset inside a Stack. |
| `GridView` † | n → `children` | ⚡ `crossAxisCount*`: int = `2`<br>⚡ `mainAxisSpacing`: double = `0.0`<br>⚡ `crossAxisSpacing`: double = `0.0`<br>⚡ `padding`: EdgeInsets?<br>⚡ `shrinkWrap`: bool = `false` | A fixed-column grid. |
| `AspectRatio` | 1 → `child` | ⚡ `aspectRatio*`: double = `1.0` | Sizes its child to a given width/height ratio. |

### 内容

| Widget | children | 参数 | 说明 |
|---|---|---|---|
| `Text` | — | ⚡ `data*`: String<br>⚡ `style`: TextStyle?<br>⚡ `textAlign`: TextAlign?<br>⚡ `maxLines`: int?<br>⚡ `overflow`: TextOverflow? | A run of styled text. |
| `Icon` | — | ⚡ `icon*`: IconData<br>⚡ `size`: double?<br>⚡ `color`: Color? | A glyph from an icon font. |
| `Image` † | — | ⚡ `src*`: String<br>⚡ `width`: double?<br>⚡ `height`: double?<br>⚡ `fit`: BoxFit? | An image loaded over the network. |
| `CircularProgressIndicator` | — | ⚡ `color`: Color? | An indeterminate spinner. |
| `Chip` † | — | ◻ `label*`: Widget<br>◻ `avatar`: Widget<br>⚡ `backgroundColor`: Color? | A compact labelled pill. |
| `Tooltip` | 1 → `child` | ⚡ `message*`: String | Explains its child on hover or long press. |
| `CircleAvatar` † | 1 → `child` | ⚡ `radius`: double?<br>⚡ `backgroundColor`: Color? | A round avatar with a child or a background colour. |
| `LinearProgressIndicator` | — | ⚡ `value`: double?<br>⚡ `color`: Color? | A determinate or indeterminate bar. |

### 输入

| Widget | children | 参数 | 说明 |
|---|---|---|---|
| `ElevatedButton` | 1 → `child` | ▷ `onPressed*`: () | A filled button. |
| `TextButton` | 1 → `child` | ▷ `onPressed*`: () | A flat button. |
| `OutlinedButton` | 1 → `child` | ▷ `onPressed*`: () | A button with an outline. |
| `IconButton` | — | ▷ `onPressed*`: ()<br>◻ `icon*`: Widget<br>⚡ `tooltip`: String? | A tappable icon. |
| `FloatingActionButton` | 1 → `child` | ▷ `onPressed*`: ()<br>⚡ `tooltip`: String? | The primary action of a page. |
| `TextField` | — | ⚡ `text`: String<br>▷ `onChanged`: (String)<br>▷ `onSubmitted`: (String)<br>⚡ `hintText`: String?<br>⚡ `labelText`: String?<br>⚡ `obscureText`: bool = `false`<br>⚡ `keyboardType`: TextInputType? | A single-line text input. |
| `Checkbox` | — | ⚡ `value*`: bool<br>▷ `onChanged*`: (bool?) | A binary toggle box. |
| `Switch` | — | ⚡ `value*`: bool<br>▷ `onChanged*`: (bool) | A binary on/off switch. |
| `Slider` | — | ⚡ `value*`: double<br>▷ `onChanged*`: (double)<br>⚡ `min`: double = `0.0`<br>⚡ `max`: double = `1.0` | A continuous value picker. |
| `GestureDetector` † | 1 → `child` | ▷ `onTap`: ()<br>▷ `onLongPress`: () | Recognises taps on an arbitrary child. |
| `InkWell` | 1 → `child` | ▷ `onTap`: () | Tap target with a material ripple. |

### 结构

| Widget | children | 参数 | 说明 |
|---|---|---|---|
| `Scaffold` | 1 → `body` | ◻ `appBar`: Widget<br>◻ `floatingActionButton`: Widget<br>◻ `drawer`: Widget<br>◻ `bottomNavigationBar`: Widget<br>⚡ `backgroundColor`: Color? | Page shell: app bar, body, floating action button. |
| `AppBar` † | — | ◻ `title`: Widget<br>◻ `leading`: Widget<br>◻… `actions`: List<Widget><br>⚡ `backgroundColor`: Color?<br>⚡ `centerTitle`: bool?<br>⚡ `elevation`: double? | Top bar with a title and actions. |
| `ListView` † | n → `children` | ⚡ `padding`: EdgeInsets?<br>⚡ `shrinkWrap`: bool = `false`<br>⚡ `scrollDirection`: Axis = `vertical` | Scrolling list of children. |
| `ListTile` | — | ◻ `title`: Widget<br>◻ `subtitle`: Widget<br>◻ `leading`: Widget<br>◻ `trailing`: Widget<br>▷ `onTap`: () | A single fixed-height row in a list. |
| `Card` | 1 → `child` | ⚡ `elevation`: double?<br>⚡ `color`: Color?<br>⚡ `margin`: EdgeInsets? | Rounded, elevated surface. |
| `SafeArea` | 1 → `child` | — | Insets its child away from system intrusions. |
| `SingleChildScrollView` | 1 → `child` | ⚡ `padding`: EdgeInsets? | Makes an oversized child scrollable. |
| `Drawer` | 1 → `child` | ⚡ `backgroundColor`: Color? | The panel that slides in from the edge. |
| `DrawerHeader` | 1 → `child` | ⚡ `padding`: EdgeInsets? | The block at the top of a Drawer. |
| `BottomNavigationBar` † | — | ◻… `items`: List<Widget><br>⚡ `currentIndex`: int = `0`<br>▷ `onTap`: (int)<br>⚡ `backgroundColor`: Color? | The bar of destinations along the bottom. |
| `BottomNavigationBarItem` | — | ◻ `icon*`: Widget<br>⚡ `label`: String? | One destination in a BottomNavigationBar. |
| `DefaultTabController` | 1 → `child` | ⚡ `length*`: int<br>⚡ `initialIndex`: int = `0` | Supplies the tab controller TabBar and TabBarView look up. |
| `TabBar` † | — | ◻… `tabs`: List<Widget> | The row of tabs. Needs a DefaultTabController above it. |
| `Tab` | — | ⚡ `text`: String?<br>◻ `icon`: Widget | One tab label. |
| `TabBarView` † | n → `children` | — | The pages a TabBar switches between. |

### control

| Widget | children | 参数 | 说明 |
|---|---|---|---|
| `ForEach` † | 1 → `template` | ⚡ `items*`: List<dynamic><br>  `itemKey`: String? | Repeats its template once per item of a list. |
| `If` † | 1 → `then` | ⚡ `condition*`: bool<br>◻ `orElse`: Widget | Includes its child only when a condition holds. |

† 该 widget 的 Flutter 构造函数不是 `const`，生成代码不会给它加 
`const`（见 ADR-007）。

## 类型系统

### 基础类型

| 类型 | 引脚族 | 可 JSON 序列化 |
|---|---|---|
| `int` | number | 是 |
| `double` | number | 是 |
| `num` | number | 是 |
| `bool` | boolean | 是 |
| `String` | text | 是 |
| `Color` | style | 否 |
| `EdgeInsets` | style | 否 |
| `TextStyle` | style | 否 |
| `IconData` | style | 否 |
| `Alignment` | style | 否 |
| `Duration` | special | 否 |
| `dynamic` | special | 否 |
| `void` | special | 否 |

容器类型：`List<T>`、`Map<K, V>`、`T?`、`Future<T>`。
用户模型来自 `models/`，字段类型递归上述类型。

### 允许的隐式提升

只有这三条，其余一律要求类型相同：

- `int → double`
- `int → num`、`double → num`
- `T → T?`

刻意窄于 Dart 自身的规则，好让接错线在拖拽时就被拒绝，
而不是等到 `dart analyze`。

### 可用的 Flutter 枚举

- `MainAxisAlignment`: start / end / center / spaceBetween / spaceAround / spaceEvenly
- `CrossAxisAlignment`: start / end / center / stretch / baseline
- `MainAxisSize`: min / max
- `TextAlign`: left / right / center / justify / start / end
- `TextOverflow`: clip / fade / ellipsis / visible
- `Axis`: horizontal / vertical
- `BoxFit`: fill / contain / cover / fitWidth / fitHeight / none / scaleDown
- `FontWeight`: w100 / w200 / w300 / w400 / w500 / w600 / w700 / w800 / w900 / normal / bold
- `TextInputType`: text / multiline / number / phone / emailAddress / url

