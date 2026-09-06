# 打包

`lattice build` 产出的是**能跑的东西**，`lattice package` 产出的是**能发给别人的
东西**。这份文档讲后者需要宿主机上有什么。

```bash
lattice package examples/todo -t linux
lattice package examples/todo -t android
lattice package examples/todo -t web
```

产物落在工程目录的 `dist/<平台>/<版本>/`。`dist/` 在 `.gitignore` 里。

| 平台 | 格式 | 状态 |
|---|---|---|
| linux | `.AppImage`、`.deb` | 本机验证过 |
| android | `.apk`、`.aab` | 本机验证过 |
| web | `.zip` | 本机验证过 |
| windows | `.exe`、`.msix` | 配置写了，**没跑过** |
| macos | `.dmg` | 配置写了，**没跑过** |

只能在对应宿主上打包：Linux 打不了 macOS 的包，这是 Flutter 的限制，不是
Lattice 的。`Host.canBuild` 会直接跳过并说明原因。

## flutter_distributor

除 web 外的一切都走它。web 的 zip 由 Lattice 自己打，免得依赖宿主有 `zip`。

```bash
dart pub global activate flutter_distributor
```

**它装进 `~/.pub-cache/bin`，但不会把这个目录加进 PATH。** Lattice 因此不靠
`which` 判断，而是直接尝试运行几个候选路径——「装了但看不见」这种状态不该表现成
「没装」。

## Linux

AppImage 需要 `appimagetool`，deb 需要 `dpkg-deb`。两者都会在缺失时报出安装方式。

## Android

需要 Android SDK（platform + build-tools）和 **NDK**。NDK 不是可选的：Flutter 的
Gradle 插件设了 `ndkVersion`，AGP 在配置阶段就会去校验它。

```bash
# cmdline-tools 必须解到 <sdk>/cmdline-tools/latest/，sdkmanager 不认别的布局
yes | sdkmanager --licenses
sdkmanager --install "platform-tools" "platforms;android-36" "build-tools;36.0.0"
flutter config --android-sdk "$HOME/Android/Sdk"
flutter doctor          # Android toolchain 必须是 ✓
```

`flutter doctor` 会告诉你缺哪个版本——照它说的装，别猜。

> **下载被截断时**：网络不好的话 `sdkmanager` 会失败在
> `Error on ZipFile unknown archive`，或者 Gradle wrapper 报
> `Unexpected end of file from server`。这两个都是下到一半的文件，不是配置错误。
> 包的真实大小和 SHA-1 在
> [`repository2-3.xml`](https://dl.google.com/android/repository/repository2-3.xml)
> 里，可以用 `curl -C - --retry` 自己下、`sha1sum` 核对，再解到
> `<sdk>/ndk/<版本号>/`（目录名要和 `source.properties` 里的 `Pkg.Revision` 一致）。

Gradle 首次构建要拉 wrapper 发行包和依赖，十分钟起步；之后是几十秒。

签名见 [签名与公证](signing.md)。**不设签名环境变量也能出包**，只是签的是
Flutter 的 debug key。

## 编辑器自己

编辑器是普通 Flutter 工程，不是 Lattice 工程，所以没有哪一步会给它生成打包配置。
`tool/package_editor.dart` 把它交给同一份代码处理，而不是另抄一套配置文件：

```bash
dart run tool/package_editor.dart      # -> apps/lattice_editor/dist/linux/<版本>/
sudo dpkg -i apps/lattice_editor/dist/linux/*/lattice_editor-*-linux.deb
lattice_editor /path/to/工程目录       # 不给参数则打开内置的计数器示例
```

装到 `/opt/lattice_editor/`，`postinst` 往 `/usr/bin/lattice_editor` 建软链，
桌面项进 `/usr/share/applications/`。AppImage 不用装，`chmod +x` 直接跑。

## 应用身份

三个字段决定产物长什么样，都在 `project.json` 的 `config` 里：

| 字段 | 去处 |
|---|---|
| `appName` | 窗口标题、桌面项、`android:label`、web `<title>` |
| `packageName` | 可执行文件名、产物文件名 |
| `bundleId` | Linux `APPLICATION_ID`、macOS `PRODUCT_BUNDLE_IDENTIFIER`、Android `applicationId` |

Android 的 `namespace` **不跟着 `bundleId` 走**：它是 Kotlin 源码声明的包名，
manifest 里的 `.MainActivity` 按它解析，改了就编译不过。
