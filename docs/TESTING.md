# Testing

已完成的检查：

- PowerShell 5.1 可解析并执行终端向导；首次配置会写入游戏路径、GIMI `PreloadDlls`、`UseHDR=true`，并可选择 ReShade DLL。
- 在隔离目录中验证了 DLSS 配置：向导会生成 `GIMI -> ReShade（可选）-> Bridge -> OptiScaler` 顺序，将 `Dx11Upscaler` 设为 `dlss`，并创建 `OptiScaler.ini.before-dlss-*` 备份；同时验证了跳过 ReShade/DLSS 的回退路径。
- 向导会验证游戏文件名、GIMI `d3dx.ini` 和 `Mods`，并在替换 DLL 前创建带时间戳的备份。
- UnlockFPS 构建为 x64 单文件 Release，源码补丁可由 `git apply` 应用。
- 运行时曾验证 GIMI overlay、HDR swap chain、ReShade `SetColorSpace1` 和正常进入游戏画面。

仓库不自动启动真实游戏进行 CI 测试，因为这需要本机安装的原神、GIMI Mod、显卡驱动、ReShade、FSR Bridge 和 NVIDIA DLSS 运行时。出现黑屏时，先清空 `DllList` 验证 GIMI/HDR 基线，再逐个恢复 ReShade、Bridge 和 OptiScaler。
