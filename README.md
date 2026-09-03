# GIMI + DLSS + ReShade Hosted Integration

在原神 DirectX 11 渲染链中同时运行 GIMI Mod、真正的 NVIDIA DLSS 和 ReShade HDR 效果。新版不再依赖脆弱的 DLL 排序，而是明确分配每个组件对渲染对象与最终画面的所有权。

> 2026-09-03 已完成实机验证：游戏持续渲染，Bridge 连续分发 FSR2 输入，OptiScaler 逐帧调用 `NVSDK_NGX_D3D11_EvaluateFeature`，ReShade 由 GIMI 的最终 `Present` 路径执行。本次验证为 3072×1728 输入到 3840×2160 输出。

## 快速开始

要求：Windows 10/11、支持 DLSS 的 NVIDIA RTX 显卡、可正常运行的原神与 GIMI。仓库不包含游戏文件或你的 Mod。

1. 下载或克隆整个仓库，不要只下载某个 BAT。
2. 完全退出原神、旧 UnlockFPS 和 `3DMigoto Loader.exe`。
3. 双击 `Launch-Genshin-GIMI-DLSS-ReShade.bat`。
4. 首次运行输入 `GenshinImpact.exe` 的完整路径。
5. 输入现有 GIMI 的 `3dmigoto` 文件夹；它应包含 `3DMigoto Loader.exe`、`d3dx.ini` 和 `Mods`。
6. 以后继续使用同一个 BAT；路径变化时运行 `Configure-Again.bat`。

不要额外运行 `3DMigoto Loader.exe`。新版已经由 UnlockFPS 在恢复游戏主线程前预加载 GIMI，重复加载会造成 Hook 冲突。

完整安装、备份恢复和常见问题见 [`docs/INSTALLATION.md`](docs/INSTALLATION.md)。

## 新版渲染链

```text
GIMI d3d11 预加载
    ↓
Dx11FsrBridge 捕获并翻译原神 FSR2 输入
    ↓
OptiScaler 调用 NVIDIA NGX / DLSS
    ↓
GIMI 完成 Mod 操作并进入最终 Present
    ↓
GIMI 调用 ReShade 公共 C Runtime 处理最终 back buffer
    ↓
原始 DXGI Present
```

最关键的变化是：`ReShade64.dll` **不在** UnlockFPS 的 `DllList` 中，也不安装 D3D11/DXGI 图形 Hook。GIMI 在自己的最终 `Present` 中创建并更新 ReShade Runtime。ReShade 仍保留输入 Hook，因此 `Home` 菜单可用，但不会再和 GIMI、OptiScaler 争夺 Device、Context、SwapChain 或 Present。

架构、对象所有权和调用时序见 [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md)。

## 本版修复

- GIMI 遇到其他组件创建的、尚未登记的 D3D11 Device 时，不再执行致命退出，而是补建 `HackerDevice` / `HackerContext`。
- 外部 Device 同时安装 Device 与 immediate Context Hook；仅包装 SwapChain 已不足以维持 Mod 资源和 Shader 跟踪。
- OptiScaler 识别 GIMI COM 包装器，并在 NGX 初始化、创建和执行 Feature 时解析原生 D3D11 Device/Context，修复 `BAD00007 / NotInitialized`。
- ReShade 使用其公开 C Runtime API，由 GIMI 在最终画面阶段调用；图形 Hook 被显式禁用。
- `GIMIHostedReShade.ini` 提供环境变量之外的持久配置后备，直接从资源管理器启动也能找到 DLL 和配置。
- HDR SwapChain 可暴露原生 `IDXGISwapChain2/3/4`，并在 Resize 时保留 HDR 格式与合法的 back-buffer 数量。
- ReShade 配置、效果缓存、截图和预设都留在整合目录，不向游戏目录复制 ReShade 文件。
- 启动器只对所选 GIMI 做带时间戳备份后替换兼容 DLL，并保留用户现有 `Mods`、`ShaderFixes` 和其他资源。

## 快捷键

- `Insert`：OptiScaler 菜单。
- `Home`：ReShade 菜单。
- `F10`：重新加载 GIMI Mod。

默认预设包含 `FakeHDR`。若 Windows HDR 与游戏原生 HDR 已开启而画面主观上过亮，可在 `Home` 菜单中关闭它，或切换到包内 Lilium 的 HDR-aware 效果；这是预设选择，不代表兼容链路失败。

## 如何确认不是“假成功”

只有出现 ReShade 横幅或加载了 DLL 还不够。有效的 DLSS 证据是：

- `components/Bridge/Dx11FsrBridge.log` 持续出现 `fsr2_translation_dispatch_succeeded`；
- `components/OptiScaler/OptiScaler.log` 出现 `NVSDK_NGX_D3D11_EvaluateFeature`，并列出内部和目标分辨率；
- 菜单显示 DLSS 而不是 Fallback，进入大世界后仍持续调用；
- GIMI Mod 可见，`F10` 可重新加载；
- `Home` 能打开 ReShade，启停效果会改变最终画面。

详细验收记录见 [`docs/TESTING.md`](docs/TESTING.md)。

## 仓库内容

- `Configure-And-Launch.ps1`：路径向导、备份、运行时配置和启动逻辑。
- `GIMI/d3d11.dll`：带外部 Device、HDR 和 Hosted ReShade 修复的 GIMI 构建。
- `components/Bridge/`：原神 FSR2 输入桥接层。
- `components/OptiScaler/`：OptiScaler、DLSS Runtime 及其依赖和许可证。
- `components/ReShade/`：ReShade Runtime、效果文件、纹理和许可证。
- `src/patches/`：可审阅、可应用的 3Dmigoto、OptiScaler 与 UnlockFPS 补丁。
- `third_party/`：上游版本、来源与许可证说明。

构建方法见 [`docs/BUILD.md`](docs/BUILD.md)。

## 安全与兼容性说明

这是第三方游戏修改工具整合，不是 HoYoverse、NVIDIA、ReShade 或各上游项目的官方产品。游戏更新可能使 Bridge 的 RVA 失效；请不要把旧地址强行用于新版本。请自行确认账号、服务条款和在线环境风险。

本仓库的整合脚本和文档使用 MIT 许可证；第三方源码与二进制保留各自许可证，详见 [`third_party/UPSTREAM-COMMITS.md`](third_party/UPSTREAM-COMMITS.md)。
