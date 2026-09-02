# GIMI + ReShade + UnlockFPS Integration

一个面向 Windows 的原神启动整合方案：由修改后的 `unlockfps_nc.exe` 创建挂起的游戏进程，先注入 GIMI/3Dmigoto，再按配置注入 ReShade，最后恢复游戏线程。仓库还包含 3Dmigoto 的 HDR 兼容修改，用于避免 HDR swap chain 与 ReShade 同时启用时的黑屏。

## 快速使用

1. 将仓库完整下载到一个没有中文或特殊权限限制的目录。
2. 双击根目录的 `Launch-Genshin-GIMI-UnlockFPS.bat`。
3. 首次运行按终端提示依次输入原神 `GenshinImpact.exe`/`YuanShen.exe` 的完整路径，以及 GIMI 的 `3dmigoto` 文件夹。该文件夹必须包含 `d3dx.ini` 和 `Mods`。
4. 第三个提示可输入 `ReShade64.dll` 的完整路径；直接回车则跳过 ReShade。配置会保存到根目录的 `fps_config.json`。
5. 后续直接双击同一个 BAT 即可启动。路径改变时运行 `Configure-GIMI-Paths.bat` 重新选择。

不要同时运行 `3DMigoto Loader.exe`。本方案已经通过 UnlockFPS 的挂起进程注入 GIMI，不需要全局 CBT hook；额外启动 Loader 会造成重复注入或 `Error installing hook`。

## 工作原理

`unlockfps_nc.exe` 读取 `fps_config.json`，调用 `CreateProcess(..., CREATE_SUSPENDED)` 创建游戏，使用远程线程按顺序加载 `PreloadDlls`（整合后的 GIMI `d3d11.dll`）和 `DllList`（可选 ReShade），再恢复主线程。GIMI 从被加载 DLL 所在目录读取 `d3dx.ini` 和 `Mods`，因此向导会把补丁 DLL 复制到用户选择的 3dmigoto 目录。

HDR 修改位于 `src/3dmigoto-patches/HackerDXGI.cpp`：原生 `R10G10B10A2_UNORM` swap chain 对 `IDXGISwapChain2/3/4` 返回原始 DXGI 接口，使游戏可以调用 HDR 色彩空间 API；`ResizeBuffers` 保留 HDR 格式和至少两个 back buffer，避免 ReShade 请求导致 `E_INVALIDARG`、黑屏和鼠标轨迹异常。

## 仓库构成

- `Launch-Genshin-GIMI-UnlockFPS.bat`：日常启动入口。
- `Configure-GIMI-Paths.ps1` / `.bat`：终端路径向导、补丁 DLL 安装和配置保存。
- `Install-HDR-Integration.ps1`：只向指定 GIMI 目录备份并安装补丁 DLL。
- `fps_config.json`：不含个人路径的便携模板。
- `GIMI/d3d11.dll`、`unlockfps_nc.exe`：已验证的可运行构建产物；`release/` 中保留同样的发布副本。
- `src/patches/`：可应用到上游源码的完整 Git 补丁。
- `src/3dmigoto-patches/`、`src/unlockfps-patches/`：修改后的关键源码文件，便于审阅。
- `docs/BUILD.md`、`docs/TESTING.md`：构建和验证记录。
- `third_party/`：上游 commit、许可证和归属信息。

## ReShade/HDR 注意事项

ReShade 本体、效果文件和预设没有打包进仓库。向导只接受本机已有的 `ReShade64.dll`，因为 ReShade 版本和效果目录通常由用户自行管理。首次建议先跳过 ReShade，确认 GIMI/HDR 画面正常后再输入 DLL 并逐个启用 HDR 效果。

这是第三方游戏修改工具的整合项目，不包含原神文件或 Mod。请自行确认相关软件、账号和服务条款风险。

## 开源来源

精确版本、源码地址和许可证见 [`third_party/UPSTREAM-COMMITS.md`](third_party/UPSTREAM-COMMITS.md)。本仓库新增的整合脚本和文档使用 MIT 许可证；3Dmigoto、UnlockFPS 和 ReShade 保留各自许可证。
