# 安装与使用

## 前置条件

- Windows 10/11 x64；
- 支持 DLSS 的 NVIDIA RTX 显卡和正常工作的 NVIDIA 驱动；
- 已安装的原神；
- 已经能单独工作的 GIMI，其中 `3dmigoto` 目录包含 `3DMigoto Loader.exe`、`d3dx.ini` 和 `Mods`。

请先关闭游戏、其他 UnlockFPS 和 `3DMigoto Loader.exe`。整合启动器本身会预加载 GIMI，不需要 Loader 的全局 Hook。

## 首次启动

1. 完整解压项目；不要在压缩包预览窗口中直接运行。
2. 双击 `Launch-Genshin-GIMI-DLSS-ReShade.bat`。
3. 输入游戏本体 `GenshinImpact.exe` 的完整路径。
4. 输入 GIMI 的 `3dmigoto` 文件夹路径，而不是它的上级目录。
5. 启动器完成配置后会调用包内 `unlockfps_nc.exe`。

启动器会执行这些动作：

- 把兼容版 `GIMI/d3d11.dll` 备份后安装到所选 GIMI 目录；
- 确保 GIMI `[System] hook=recommended`；
- 生成 Bridge、OptiScaler 和 ReShade 的运行配置；
- 在 GIMI 目录写入 UTF-16 `GIMIHostedReShade.ini`；
- 如果检测到特定旧版 `HealthBar.ini` 中当前 GIMI 不支持的 `store = $health, ps-cb0, 33`，先备份，再只注释这一行；
- 生成 `fps_config.json`，其中 `PreloadDlls` 只有 GIMI，`DllList` 依次为 Bridge、OptiScaler；
- 通过 UnlockFPS 创建挂起的游戏进程，完成 DLL 装载后再恢复主线程。

路径和备份保存在项目的 `state` 目录。第二次启动会复用有效路径；路径发生变化时运行 `Configure-Again.bat`。

## 运行时检查

- `F10`：GIMI 重新加载。Mod 应保持可见，且不应出现致命退出或连续错误音。
- `Insert`：OptiScaler 菜单。选中的后端应为 DLSS，而不是 Fallback。
- `Home`：ReShade 菜单。启用/关闭效果应改变最终画面。

日志位置：

- `components/Bridge/Dx11FsrBridge.log`
- `components/OptiScaler/OptiScaler.log`
- 所选 GIMI 目录中的 `d3d11_log.txt`
- 游戏目录中的 `ReShade.log`（部分构建会延迟到退出时刷新）

真正的 DLSS 运行证据是 OptiScaler 日志内持续出现 `NVSDK_NGX_D3D11_EvaluateFeature`，并同时显示内部渲染分辨率和目标分辨率。只看到 DLL 被加载或 ReShade 横幅不能证明 DLSS 已经工作。

## HDR 与 ReShade 效果

启动器默认设置 `UseHDR=true`，并打包 ReShade HDR 效果。`FakeHDR` 最初是为了让效果是否执行更容易观察，但它并不是所有 HDR 显示链的最佳默认值。

如果系统 HDR、游戏 HDR 与 `FakeHDR` 叠加后过亮：

1. 按 `Home`；
2. 关闭 `HDR@FakeHDR.fx`；
3. 需要时改用 Lilium 的 HDR-aware CAS、亮度或 Tone Mapping 效果；
4. 不必修改 DLL 顺序。

HDR 截图在普通 SDR 查看器中也可能显得发白，优先以 HDR 显示器上的实际观感和 ReShade 菜单为准。

## 常见问题

### 启动器提示游戏正在运行

任务管理器中关闭遗留的 `GenshinImpact.exe`、`YuanShen.exe` 和本包的 `unlockfps_nc.exe`，再重新运行。启动器不会在游戏运行时替换 GIMI DLL。

### DLSS 显示 Fallback

先检查 Bridge 和 OptiScaler 日志。游戏更新后，Bridge 配置中的版本相关 RVA 可能失效；不要把旧 RVA 强行用于新游戏版本。确认 `Dx11FsrBridge.dll`、`OptiScaler.dll` 和 `nvngx_dlss.dll` 没有被杀毒软件隔离。

### ReShade 没有出现

确认 GIMI 目录中的 `GIMIHostedReShade.ini` 为 `Enabled=1`，其中 DLL 和配置路径指向当前整合目录。`fps_config.json` 的 `DllList` 不应包含 `ReShade64.dll`；Hosted 模式下这正是预期行为。

### GIMI Mod 不工作

确认使用的是原来的 GIMI 目录，并且 `Mods` 与 `ShaderFixes` 仍在。检查 `d3dx.ini` 的 `[System] hook=recommended`。不要同时启动 `3DMigoto Loader.exe`。

## 恢复原来的 GIMI

安装器只在内容不同的时候替换 GIMI DLL，并先把原文件备份到 `state/GIMI-d3d11.before-experiment.<时间>.bak`。`d3dx.ini` 或兼容性配置如果被修改，也会在 `state` 中留下对应备份。

退出游戏后，把需要的备份复制回原 GIMI 目录并恢复原文件名。确认已恢复后，可以删除 GIMI 目录中的 `GIMIHostedReShade.ini`。在完成恢复前不要删除整合目录中的 `state`。
