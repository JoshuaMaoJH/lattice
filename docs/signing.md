# 签名与公证

产物能构建，和产物**能装上**，是两回事。这份文档讲后半段。

Lattice 的立场（§7.9）：**凭据永远不进工程文件。** 它们放在本机的 keychain 或
配置目录里，由环境变量喂给构建。工程目录可以放心进 git、可以分享、可以被 LLM
读——里面没有任何东西能签出一个冒充你的包。

> 编辑器工具栏上的盾牌图标是这一页的**清单版**（R22）：按目标列出要哪些环境变量、
> 哪些已经设了、路径指向的文件在不在。它只读「有没有」，不读值，所以那一屏可以
> 随便截图。这一页讲的是每个值**从哪来**。
>
> 下面每一节都链到官方文档，因为签名要求变化的速度比这份文件更新的速度快。

---

## Android

需要一个 keystore 和四个值。

```bash
keytool -genkey -v -keystore ~/.lattice/android.jks \
  -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```

Lattice 生成的 `android/` 目录里没有 `key.properties`，也不该有。构建时通过环境
变量传：

```bash
export LATTICE_ANDROID_KEYSTORE=$HOME/.lattice/android.jks
export LATTICE_ANDROID_KEY_ALIAS=upload
export LATTICE_ANDROID_STORE_PASSWORD=…
export LATTICE_ANDROID_KEY_PASSWORD=…

lattice package examples/todo --target android
```

这四个变量由 `AppMetadata` 注入进 `android/app/build.gradle.kts` 的 release
签名配置读取。**没设这些变量时，release 构建落回 Flutter 的 debug key**——包能装
上、能测，但不能上架，`apksigner verify --print-certs` 会看到
`CN=Android Debug`。

- `.apk` 直接发给别人装；`.aab` 上架 Play。
- **备份 keystore。** 弄丢了就再也无法更新已上架的应用——Play 不接受换 key。
- 官方：[Signing the app](https://docs.flutter.dev/deployment/android#signing-the-app)

## macOS

分两步：签名（本机能跑）和公证（**别人**的机器能跑）。

没公证的 `.app`，对方双击会看到「无法打开，因为无法验证开发者」。这不是可选项。

```bash
# 需要 Apple Developer Program 会员（每年 99 美元）
xcrun notarytool store-credentials lattice \
  --apple-id you@example.com --team-id TEAMID --password APP_SPECIFIC_PASSWORD

lattice package examples/todo --target macos
xcrun notarytool submit dist/macos/1.0.0/*.dmg --keychain-profile lattice --wait
xcrun stapler staple dist/macos/1.0.0/*.dmg
```

`stapler` 那步别省：不装订的话，用户断网时仍然会被拦。

- 官方：[macOS deployment](https://docs.flutter.dev/deployment/macos)、
  [Notarizing macOS software](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)

## iOS

只能在 macOS 上、用 Xcode 构建，并且需要 provisioning profile。

Lattice 生成 `ios/` 目录并写入 bundle id 与版本号，剩下的证书与 profile 由 Xcode
的自动签名处理最省事。CI 上则需要把证书与 profile 作为 secret 注入。

- 官方：[iOS deployment](https://docs.flutter.dev/deployment/ios)

## Windows

没有签名的 `.exe`，SmartScreen 会拦一道「Windows 已保护你的电脑」。

需要一张代码签名证书（OV 或 EV）。EV 的好处是立刻有信誉，OV 要靠下载量慢慢积累。

```powershell
signtool sign /fd SHA256 /td SHA256 /tr http://timestamp.digicert.com `
  /f cert.pfx /p $env:CERT_PASSWORD dist\windows\1.0.0\*.exe
```

`/tr`（时间戳）别省：不打时间戳的签名会随证书过期而失效。

- 官方：[Windows deployment](https://docs.flutter.dev/deployment/windows)

## Linux

AppImage 与 `.deb` 通常不签名，靠分发渠道背书。要签的话：

- AppImage 支持内嵌 GPG 签名
- `.deb` 进 apt 仓库时由仓库的 `Release` 文件签名

## Web 与服务端

都不签名。Web 是静态文件，服务端是一个二进制。它们的信任来自 TLS 和你把它们放
在哪儿，不是来自代码签名。

---

## 在 CI 上

生成的 `.github/workflows/build.yml` 出的是**未签名**产物——这是刻意的：跑通流程
不该先要一堆 secret。

要在 CI 上签名，把凭据放进仓库 secrets，然后在对应 job 里加一步。原则不变：
凭据来自 secret，不来自仓库里的文件。

```yaml
      - name: Sign
        env:
          LATTICE_ANDROID_STORE_PASSWORD: ${{ secrets.ANDROID_STORE_PASSWORD }}
        run: …
```

## 现状

`lattice package` 产出**未签名**的包。上面这些步骤要手动跑。把它们接进
`lattice package` 是 M4 之后的活；先有文档，是因为一个签不了名的包，用户装不上，
而「装不上」比「没自动化」严重得多。

Linux 的两种格式已经验证过：`lattice package <工程> -t linux` 出 AppImage 与
`.deb`，两者都不需要签名。前置条件是：

```bash
dart pub global activate flutter_distributor
export PATH="$PATH:$HOME/.pub-cache/bin"        # activate 不会替你加

# AppImage 还需要 appimagetool（单文件，不需要 sudo）
curl -L -o ~/.local/bin/appimagetool \
  https://github.com/AppImage/appimagetool/releases/download/continuous/appimagetool-x86_64.AppImage
chmod +x ~/.local/bin/appimagetool
```

`.deb` 只要 `dpkg-deb` 与 `fakeroot`，Ubuntu 上本来就有。`rpm` 需要 `rpmbuild`
（`sudo apt install rpm`），Lattice 目前不为它生成配置。

---

## CI 上怎么给

生成的工程里有两个 workflow：`build.yml` 回答「main 还编得过吗」，`release.yml`
在打 `v*` tag 时出**可分发产物**并挂到 GitHub Release 上。

签名凭据走仓库 secrets，由 workflow 塞进同样那几个环境变量。Android 的
keystore 是二进制，所以以 base64 存进 `ANDROID_KEYSTORE_BASE64`，构建时解回一个
文件——仓库里始终没有它。

```bash
base64 -w0 ~/.lattice/android.jks | gh secret set ANDROID_KEYSTORE_BASE64
gh secret set ANDROID_KEY_ALIAS
gh secret set ANDROID_STORE_PASSWORD
gh secret set ANDROID_KEY_PASSWORD
```
