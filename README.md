# GIMI + DLSS + DLSS 5 Neural Rendering + ReShade

这是原神 DX11 下的四组件兼容整合：GIMI Mod、DLSS 空间超分、DLSS 5 Neural Rendering（RenoDX）与 ReShade 后处理可以在同一局游戏中持续工作。2026-09-04 的 r12 已完成实机验证：GIMI Mod 与 ReShade 正常，标准 DLSS 保持低分辨率到输出分辨率的超分，Native NR 成功帧数连续增长并产生可见的光影变化。

## 下载后能否直接运行

有两种发布形式：

- **Downloads 完整离线压缩包**：已经包含经验证的 `nvngx_dlssnr.dll`，解压后可直接配置并启动。
- **GitHub 仓库 / Source ZIP**：由于 `nvngx_dlssnr.dll` 约 158 MiB，不放入 GitHub。需要先下载该文件并双击 `Install-DLSS5-Runtime.bat`；脚本会校验 SHA-256 并放到正确目录。

DLSS 5 Runtime 下载：

- 国外 / Google Drive：[nvngx_dlssnr.dll](https://drive.google.com/file/d/1L7Pi4adSQal_OxpEzTMuT0NfeQTKIK-_/view?usp=sharing)
- 国内 / 百度网盘：[nvngx_dlssnr.dll](https://pan.baidu.com/s/1SAm1-QL0YvH8Kc28OGigAA?pwd=qisz)，提取码 `qisz`
- 必须匹配的 SHA-256：`4C5BD1171C7336B4B04FB394DE51DA285AB6EAD6F922D7AFDEC163F71C319D74`

除此以外，ReShade、Dx11FsrBridge、OptiScaler、普通 DLSS DLL、DLSS5 DX11 Bridge 与 RenoDX Add-on 都已随仓库提供，不需要提前单独安装。

## 前置条件

- Windows 10/11 与支持 DLSS 的 NVIDIA RTX 显卡；显卡驱动需能正常使用 NVIDIA NGX。
- 已安装并能正常启动的原神客户端。
- **已有 GIMI / 3DMigoto 目录**，其中至少有 `3DMigoto Loader.exe`、`d3dx.ini`；你的 `Mods` 继续保留在该目录。本仓库不会替你下载游戏或 Mod。
- 启动前完全退出原神、`3DMigoto Loader.exe` 和旧的 `unlockfps_nc.exe`。

## 快速开始

1. 下载完整离线包，或下载 GitHub 仓库并安装上面的 DLSS 5 Runtime。
2. 解压到普通的可写目录，不要在压缩包预览窗口内运行。
3. 双击 `Launch-Genshin-GIMI-DLSS-ReShade.bat`。
4. 首次运行时输入 `GenshinImpact.exe` 的完整路径，再输入现有 GIMI 的 `3dmigoto` 目录。
5. 以后始终通过同一个 BAT 启动；路径改变时运行 `Configure-Again.bat`。
6. `Insert` 打开 OptiScaler；`Home` 打开最终画面的 ReShade；`F6` 切换 Neural Rendering；`F10` 重载 GIMI Mod。

不要再单独启动 `3DMigoto Loader.exe`，也不要额外安装一个 ReShade `dxgi.dll` / `d3d11.dll` 到游戏目录。多一层图形 Hook 会重新引入本项目已经解决的所有权冲突。

完整步骤和恢复方式见 [`docs/INSTALLATION.md`](docs/INSTALLATION.md)。

## 实际生效的渲染链

```text
原神 DX11 / FSR2 carrier
  -> GIMI d3d11 预加载并成为唯一 DX11/SwapChain/Present 所有者
  -> 被动 ReShade Add-on Host（禁用图形 Hook）注册 DLSS5 Bridge
  -> Dx11FsrBridge 提取颜色、深度、运动向量
  -> OptiScaler + nvngx_dlss.dll 执行标准 DLSS 空间超分
  -> DLSS5 DX11 Bridge 建立私有 DX12 NGX 会话
  -> RenoDX DLSS5 在最终分辨率执行 Native NR
  -> GIMI 绘制 Mod 并提交最终 Present
  -> GIMI 托管的 ReShade 执行最终效果与 UI
```

这里的“DLSS5”不是再做一次空间超分。v1.1 控制配置会先请求低分辨率 NR；当前签名 Runtime 对原神的该颜色契约返回 `0xBAD00005`。Add-on 会保留已经完成的游戏 DLSS 输出，并自动改为输出分辨率的 Native NR。健康状态因此是：菜单可能显示 `Upscaling: requested ON | active OFF | ratio 1.00`，同时 `Successful NR frames` 持续增长。这不是假成功或退回无效果。

## r12 解决了什么

- GIMI 先于其他组件预加载，并独占真实 D3D11 Device、Context、SwapChain 与最终 Present；ReShade 图形 Hook 被显式关闭。
- GIMI 能包装外部创建的 D3D11 对象，并通过私有 ABI 向 OptiScaler 提供原始 Context，修复 NGX `BAD00007 / NotInitialized`。
- OptiScaler 的 DX11 Present 路径现在检查当前 Feature 的 API 类型，避免把 D3D11 Context 当成私有 D3D12 Command Queue。此前看似发生在 `PSSetConstantBuffers` 的崩溃，本质是跨 API 指针误用。
- DLSS5 Bridge 先建立私有 DX12 NGX 会话，再延迟加载 RenoDX，确保其能够截获对应 NGX 调用。
- 最关键的 r12 修复位于 Hosted ReShade：公共 Runtime 更新路径会补发正常 SwapChain Present 才有的 `execute_command_list` 与 `present` Add-on 事件。RenoDX 的逐帧 one-pass mask 因而会重置，成功 NR 帧不再停在三个持久输出资源。
- 最终 ReShade 仍由 GIMI 在完成的画面上托管，GIMI、DLSS、DLSS5 与 ReShade 不需要争夺注册或 Hook 顺序。

源码修改与对象所有权详见 [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md)，复现构建见 [`docs/BUILD.md`](docs/BUILD.md)。

## 如何验收

游戏正常运行一段时间后退出，再双击 `Verify-Installation.bat`，或运行：

```powershell
powershell -ExecutionPolicy Bypass -File .\Verify-Installation.ps1 -LastRun
```

真正成功需要同时满足：

- `Dx11FsrBridge.log` 持续记录 FSR2 translation dispatch；
- `OptiScaler.log` 持续执行标准 DLSS，输入分辨率小于输出分辨率；
- ReShade 日志先记录低分辨率 NR 被拒绝并切到 native，随后出现 `inline feature 18 evaluation succeeded`；
- `Successful NR frames` 不停在 `3`，而是持续增长（验证脚本要求日志里至少到 `count=60`）；
- GIMI Mod、`F10` 重载、ReShade `Home` 菜单及效果均正常。

详见 [`docs/TESTING.md`](docs/TESTING.md)。

## 风险说明

这是第三方游戏修改工具整合，不是 HoYoverse、NVIDIA、ReShade 或各上游项目的官方产品。游戏更新可能使 Bridge 的 RVA 失效；请自行确认服务条款、账号与在线使用风险。第三方二进制和源码修改保留各自许可证，来源见 [`third_party/UPSTREAM-COMMITS.md`](third_party/UPSTREAM-COMMITS.md)。
