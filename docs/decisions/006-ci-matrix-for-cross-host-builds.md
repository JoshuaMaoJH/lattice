# ADR-006 全平台构建默认走生成的 CI 工作流

## 背景

Flutter 桌面端只能在对应操作系统上构建：Linux → Linux，Windows → Windows，macOS / iOS → macOS。Android 和 Web 任意宿主均可。

一个只有 Linux 和 Mac 的开发者，仍然需要出 Windows 安装包。

## 决策

三条路，默认是第二条：

1. **本地**：Build 面板只显示当前宿主能构建的目标，其余灰显并说明原因——不让用户撞墙。
2. **远程 CI（默认）**：codegen 同时输出 `.github/workflows/build.yml`（matrix：ubuntu / windows / macos）。一台机器 + 一个 git 仓库 = 全平台产物。
3. **自建构建宿主**：SSH 到 KVM 里的 Windows 或云上的 Mac。适合不依赖 GitHub 的场景（未实现）。

## 后果

**好的**：零成本获得三种宿主；用户不需要接触任何一个平台的打包工具链。

**代价**：默认路径需要 GitHub；签名与公证仍需用户自己配置凭据（凭据绝不进工程文件）。

**具体表现**：`lattice targets` 会直接告诉你每个目标能不能在本机构建，不能的话产物从哪来：

```
 * local  linux    Can be built on this machine.
   ci     windows  windows must be built on windows. Push the repository and
                   let .github/workflows/build.yml produce it.
```

## 实现

- `packages/lattice_build/lib/src/host.dart`（`BuildTarget.buildableOn`）
- 工作流生成：`packages/lattice_codegen/lib/src/emit/support_files.dart`
