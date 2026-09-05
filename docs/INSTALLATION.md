# 安装与使用

## 前置条件

- Windows 10/11 x64；
- 支持 DLSS 的 NVIDIA RTX 显卡和正常工作的 NVIDIA 驱动；
- 已安装的原神；
- 已经能单独工作的 GIMI，其中 `3dmigoto` 目录包含 `3DMigoto Loader.exe`、`d3dx.ini` 和 `Mods`。

请先关闭游戏、其他 UnlockFPS 和 `3DMigoto Loader.exe`。整合启动器本身会预加载 GIMI，不需要 Loader 的全局 Hook。

## GitHub 版先安装 DLSS 5 Runtime

完整离线包若同时包含两套 Runtime，可以跳过本节。GitHub 因文件大小限制不包含 `nvngx_dlssnr.dll`：

- RTX 50：国外 [Google Drive](https://drive.google.com/file/d/1L7Pi4adSQal_OxpEzTMuT0NfeQTKIK-_/view?usp=sharing)，国内 [百度网盘](https://pan.baidu.com/s/1SAm1-QL0YvH8Kc28OGigAA?pwd=qisz)，提取码 `qisz`；
- RTX 30/40：从无 GIMI v1.3 完整包提取 RankFTW 310.8.SF-v2 Runtime，国外 [Google Drive](https://drive.google.com/file/d/1d-aaUEo_ftRpY7mFCO7zUTugBKg7pW-j/view?usp=sharing)，国内 [夸克网盘](https://pan.quark.cn/s/f3e0fa0a9155)，压缩包密码 `yuanshenqidong`。

下载后双击 `Install-DLSS5-Runtime.bat`，把文件拖入窗口并回车。脚本自动识别 RTX 30/40/50，也可在 PowerShell 中追加 `-NrProfile` 指定。RTX 40 自动使用完整 RTX 30 后端/Runtime 配对，会提示实验支持但不会阻止安装或启动。`nrchain` 哈希错配会被拦截；玩家替换其他可信 Runtime 时只显示黄色警告，除非维护者启用严格哈希开关。

若维护者需要执行严格的发布校验，可直接运行 `Install-DLSS5-Runtime.ps1 -RequireValidatedHash`；普通玩家不需要这个开关。

## 首次启动

1. 完整解压项目；不要在压缩包预览窗口中直接运行。
2. 双击 `Launch-Genshin-GIMI-DLSS-ReShade.bat`。
3. 输入国内服 `YuanShen.exe` 或国际服 `GenshinImpact.exe` 的完整路径。
4. 输入 GIMI 的 `3dmigoto` 文件夹路径，而不是它的上级目录。
5. 启动器完成配置后会调用包内 `unlockfps_nc.exe`。

启动器会把 GIMI `d3dx.ini` 的 `[Loader] target` 同步为所选文件名：国内服使用 `YuanShen.exe`，国际服使用 `GenshinImpact.exe`。切换服务器或游戏目录后请运行 `Configure-Again.bat`，不要只手工修改 `fps_config.json`。

启动器会执行这些动作：

- 把兼容版 `GIMI/d3d11.dll` 备份后安装到所选 GIMI 目录；
- 确保 GIMI `[System] hook=recommended`；
- 生成 Bridge、OptiScaler 和 ReShade 的运行配置；
- 在 GIMI 目录写入 UTF-16 `GIMIHostedReShade.ini`；
- 如果检测到特定旧版 `HealthBar.ini` 中当前 GIMI 不支持的 `store = $health, ps-cb0, 33`，先备份，再只注释这一行；
- 生成 `fps_config.json`，其中 `PreloadDlls` 只有 GIMI，`DllList` 依次为被动 ReShade Add-on Host、Bridge、OptiScaler；
- 通过 UnlockFPS 创建挂起的游戏进程，完成 DLL 装载后再恢复主线程。

路径和备份保存在项目的 `state` 目录。第二次启动会复用有效路径；路径发生变化时运行 `Configure-Again.bat`。

## 运行时检查

- `F10`：GIMI 重新加载。Mod 应保持可见，且不应出现致命退出或连续错误音。
- `Insert`：OptiScaler 菜单。选中的后端应为 DLSS，而不是 Fallback。
- `Home`：ReShade 菜单。启用/关闭效果应改变最终画面。
- `F6`：开关 Neural Rendering。插件中勾选“使用渲染分辨率 NR -> SR”为 Mode 2，取消为 Mode 1；模式、开关和 ReShade 预设都会保留。

日志位置：

- `components/Bridge/Dx11FsrBridge.log`
- `components/OptiScaler/OptiScaler.log`
- 所选 GIMI 目录中的 `d3d11_log.txt`
- `state/reshade-runtime/ReShade.log`
- `components/DLSS5/Addons/pre-nr/nr-before-sr.log`（RTX 50）
- `components/DLSS5/Addons/pre-nr-rtx30/nr-before-sr.log`（RTX 30/40）

Mode 2 的真正证据是 `NR-before-SR evaluate succeeded` 持续增长，且 Feature 18 为渲染分辨率 1:1、Feature 1 随后放大。Mode 1 则必须看到输出分辨率的 `post-SR signed feature 18 create` 和持续增长的 `NR-after-SR evaluate succeeded`。只有 Feature 1、只加载 DLL 或只显示菜单不算 DLSS5 生效。

## HDR 与 ReShade 效果

启动器默认设置 `UseHDR=true`，并打包 ReShade HDR 效果。`FakeHDR` 最初是为了让效果是否执行更容易观察，但它并不是所有 HDR 显示链的最佳默认值。

如果系统 HDR、游戏 HDR 与 `FakeHDR` 叠加后过亮：

1. 按 `Home`；
2. 关闭 `HDR@FakeHDR.fx`；
3. 需要时改用 Lilium 的 HDR-aware CAS、亮度或 Tone Mapping 效果；
4. 不必修改 DLL 顺序。

Before/After 截图会保存为带 BT.2020/PQ 标记的 16 位 HDR PNG。请用支持 HDR 色彩管理的查看器；普通 SDR 平台需要先做 HDR→SDR 色调映射。

## 常见问题

### 启动器提示游戏正在运行

任务管理器中关闭遗留的 `GenshinImpact.exe`、`YuanShen.exe` 和本包的 `unlockfps_nc.exe`，再重新运行。启动器不会在游戏运行时替换 GIMI DLL。

### DLSS 显示 Fallback

先检查 Bridge 和 OptiScaler 日志。游戏更新后，Bridge 配置中的版本相关 RVA 可能失效；不要把旧 RVA 强行用于新游戏版本。确认 `Dx11FsrBridge.dll`、`OptiScaler.dll` 和 `nvngx_dlss.dll` 没有被杀毒软件隔离。

### ReShade 没有出现

确认 GIMI 目录中的 `GIMIHostedReShade.ini` 为 `Enabled=1`，其中 DLL 和配置路径指向当前整合目录。`fps_config.json` 的 `DllList` 中会先加载同一 `ReShade64.dll` 作为禁用图形 Hook 的 Add-on Host；最终可见 Runtime 仍由 GIMI 托管，这是两个不同职责。

### 启动器提示缺少 nvngx_dlssnr.dll

GitHub 版需要按本文“GitHub 版先安装 DLSS 5 Runtime”完成一次安装。完整离线包若出现此提示，说明解压不完整或文件被安全软件隔离；重新解压并运行 `Verify-Installation.bat`。

### 启动器提示 DLSSNR 哈希未验证

这表示玩家替换的 `nvngx_dlssnr.dll` 与所选显卡 Profile 的已记录版本不同，不代表文件一定损坏。启动器会继续；请自行确认 Runtime 与显卡代际、驱动、`nrchain` 和 DLSS5 Add-on 接口兼容。维护者可用 `Verify-Installation.ps1 -RequireValidatedDlssNrHash` 恢复严格校验。

### GIMI Mod 不工作

确认使用的是原来的 GIMI 目录，并且 `Mods` 与 `ShaderFixes` 仍在。检查 `d3dx.ini` 的 `[System] hook=recommended`，以及 `[Loader] target` 是否与当前游戏一致（国服 `YuanShen.exe`、国际服 `GenshinImpact.exe`）。不一致时运行 `Configure-Again.bat`。不要同时启动 `3DMigoto Loader.exe`。

## 恢复原来的 GIMI

安装器只在内容不同的时候替换 GIMI DLL，并先把原文件备份到 `state/GIMI-d3d11.before-experiment.<时间>.bak`。`d3dx.ini` 或兼容性配置如果被修改，也会在 `state` 中留下对应备份。

退出游戏后，把需要的备份复制回原 GIMI 目录并恢复原文件名。确认已恢复后，可以删除 GIMI 目录中的 `GIMIHostedReShade.ini`。在完成恢复前不要删除整合目录中的 `state`。
