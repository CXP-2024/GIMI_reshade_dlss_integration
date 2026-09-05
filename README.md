# GIMI + ReShade + DLSS + DLSS 5 双模式神经渲染

这是原神 DX11 下的四组件整合。新解压默认采用 Mode 2：在游戏渲染分辨率上先执行 DLSS 5 Neural Rendering，再保留原来的 DLSS Super Resolution 完成最终放大；本次兼容更新同时恢复插件原有 Mode 1，可在原始 DLSS 超分后执行输出分辨率 NR，并会保存玩家的模式选择。

验证环境为 Windows 11、RTX 5080、NVIDIA 616.56 驱动、3840×2160 输出和 0.8 渲染比例：Feature 18 持续执行 `3072×1728 -> 3072×1728`，随后原 Feature 1 执行 `3072×1728 -> 3840×2160`。GIMI Mod、最终 ReShade、HDR 与截图功能同时正常。

## 下载方式

GitHub 仓库包含启动器、经修改的兼容组件、普通 DLSS Runtime、两套 `nrchain` 后端、Shader、配置与许可证，但不包含约 165 MB 的 `nvngx_dlssnr.dll`。克隆仓库或下载 Source ZIP 后，需要先下载适合显卡的文件，再运行 `Install-DLSS5-Runtime.bat`；安装器会自动选择目录，也可用 `-NrProfile rtx30|rtx40|rtx50` 指定。

- RTX 50 Runtime：国外 [Google Drive](https://drive.google.com/file/d/1L7Pi4adSQal_OxpEzTMuT0NfeQTKIK-_/view?usp=sharing)；国内 [百度网盘](https://pan.baidu.com/s/1SAm1-QL0YvH8Kc28OGigAA?pwd=qisz)，提取码 `qisz`；SHA-256 `E16BCF15E16E13F527491CDF7845B2FE6521A738D8F7C9C721866A8496E1FC8E`。
- RTX 30/40 配套 Runtime（RankFTW 310.8.SF-v2）：可从无 GIMI v1.3 完整包提取，国外 [Google Drive](https://drive.google.com/file/d/1d-aaUEo_ftRpY7mFCO7zUTugBKg7pW-j/view?usp=sharing)，国内 [夸克网盘](https://pan.quark.cn/s/f3e0fa0a9155)，压缩包密码 `yuanshenqidong`；SHA-256 `6EB209E764F39872625DEBD6ABAF45E2BB6322F6F270F781F70C059AE30B3927`。
- 目标目录分别是 `components/DLSS5/Addons/pre-nr`（RTX 50）和 `components/DLSS5/Addons/pre-nr-rtx30`（RTX 30/40）。不要混用两套 `nrchain_nvngx.dll`；启动器会严格阻止后端错配。

玩家可以换用其他可信来源、适合自己显卡与驱动的 `nvngx_dlssnr.dll`。文件名必须保持不变；哈希不是上述已验证值时，安装器和启动器会显示黄色的“未验证版本”警告，但不会阻止安装或启动。其他版本的兼容性由玩家自行确认。

完整离线包会包含这个文件，因此不需要提前安装 ReShade、OptiScaler、普通 DLSS DLL 或 DLSS5 Add-on。

## 前置条件

- Windows 10/11。RTX 50 使用原有签名 Runtime；RTX 30 使用兼容后端与 RankFTW Runtime；RTX 40 会自动采用完整 RTX 30 配套方案并继续启动，但目前标为实验支持，可能不稳定或 NR 不生效。
- 已安装并能正常运行的原神客户端。
- 已有 GIMI / 3DMigoto 目录，其中应包含 `3DMigoto Loader.exe`、`d3dx.ini` 与用户自己的 `Mods`。
- 启动前退出原神、旧的 `unlockfps_nc.exe` 和单独运行的 `3DMigoto Loader.exe`。

不使用 GIMI 的版本由独立仓库维护，本仓库不能通过留空 GIMI 路径切换成无 GIMI 模式。

## 快速开始

1. 完整解压；不要在压缩包预览窗口中运行。
2. 如果来自 GitHub，先运行 `Install-DLSS5-Runtime.bat` 安装上述大组件。
3. 双击 `Launch-Genshin-GIMI-DLSS-ReShade.bat`。
4. 首次输入国内服 `YuanShen.exe` 或国际服 `GenshinImpact.exe` 的完整路径，以及现有 GIMI `3dmigoto` 目录。启动器会同步更新 GIMI `[Loader] target`，在国服与国际服之间切换后必须重新运行 `Configure-Again.bat`。
5. 以后始终从同一 BAT 启动；路径改变时运行 `Configure-Again.bat`。
6. `Insert` 打开 OptiScaler，`Home` 打开最终 ReShade，`F6` 开关 DLSS5 NR，`F10` 重载 GIMI Mod。插件里的“使用渲染分辨率 NR -> SR”勾选为 Mode 2，取消为 Mode 1；启动器不会再覆盖该选择、F6 状态或 ReShade 预设。

不要同时把另一个 ReShade `dxgi.dll`/`d3d11.dll` 放入游戏目录，也不要额外启动 GIMI Loader；这些做法会重新引入 SwapChain 和 Hook 所有权冲突。

## 实际渲染链

```text
原神 DX11 低分辨率 FSR2 carrier
  -> GIMI：唯一 DX11 包装器和最终 Present 所有者
  -> Dx11FsrBridge：提取颜色、深度、运动向量与抖动合同
  -> OptiScaler DLSS-on-DX12：通过 GIMI 原生 Device/Context 通道建立 NGX
  -> R8/R10/R11 packed/typeless 资源按需使用 FP16 输入/输出载体
  -> Mode 2：渲染分辨率 Feature 18 NR -> 原始 Feature 1 DLSS SR（默认）
     或 Mode 1：原始 Feature 1 DLSS SR -> 输出分辨率 Feature 18 NR
  -> GIMI Mod 与最终 Present
  -> GIMI 托管 ReShade 后处理、UI 与 HDR 截图
```

Mode 2 中 Feature 18 只替换原 DLSS 合同的低分辨率 Color；Mode 1 则在原 Feature 1 完成后使用输出分辨率载体。两种模式都保留 Depth、MotionVectors、Jitter、Exposure 合同；若 Feature 18 创建或执行失败，会回退原始 DLSS 输出，不提交半成品。

技术细节见 [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md)，前置链实验过程见 [`docs/PRE_NR_AUDIT.md`](docs/PRE_NR_AUDIT.md)，本次 GIMI 双模式实机回归见 [`docs/DUAL_MODE_VALIDATION_20260905.md`](docs/DUAL_MODE_VALIDATION_20260905.md)。

## 来源、署名与修改边界

| 组件 | 来源 | 本仓库的处理 |
| --- | --- | --- |
| 3Dmigoto / GIMI | [bo3b/3Dmigoto](https://github.com/bo3b/3Dmigoto) | **有修改**：外部对象包装、Hosted ReShade、GIMI/OptiScaler 原生 Device/Context 通道、HDR10/PQ 元数据传递等。 |
| ReShade 6.8 | [crosire/reshade](https://github.com/crosire/reshade) | **有修改**：Hosted Runtime 补发 Add-on 每帧事件；图形 Hook 在本组合中关闭，由 GIMI 托管最终 Runtime。 |
| OptiScaler DLSSNR fork | [Dagherbou/OptiScaler_DLSSNR](https://github.com/Dagherbou/OptiScaler_DLSSNR)，基于 [OptiScaler](https://github.com/optiscaler/OptiScaler) | **有修改**：GIMI 互操作、原生 NGX 参数对象、D3D12 typed/untyped 槽与 queue-affinity、R8/R10/R11 FP16 载体、双模式写回及 `nrchain_nvngx.dll` 名称冲突修复。 |
| Dx11FsrBridge | [AizawaHikaru233/genshin_fsr_brigde](https://github.com/AizawaHikaru233/genshin_fsr_brigde) | 二进制代码沿用固定上游提交；本仓库只固定当前原神的 FSR2 输入与渲染比例配置。 |
| `nr-before-sr.zh-CN.addon64` | Bilibili UP 主 **野生的装机宅** 提供的“DLSS5-AI渲染超分版-RTX50”包 | **二进制未修改**，SHA-256 `522D979CBFF335710F362B9FC2F330988673D7F8C7A1A2D93DA9980EC8DDA695`；新解压默认 Mode 2，但 Mode 1 与配置持久化均已恢复。 |
| RTX 50 `nrchain_nvngx.dll` | 同一“野生的装机宅”发布包 | **未修改**，SHA-256 `DB26E486592B252072BA5734FC2B27412863B8526826225640C837D4B4D11B60`。 |
| RTX 30/40 `nrchain_nvngx.dll` | `DLSS5_GI_Ready_v1.2_PreNR_fixRTX30.zip`，文档署名 **华晓熊** | SHA-256 `46041A5FF91AE2FD907E310D132AABC3C4A1ECD48DACE511B8672909D5D9C2FB`；本仓库完成源码差异审核、GIMI 原生 Device 合并和一键 Profile 整合。 |
| `nvngx_dlssnr.dll` | RTX 50 签名 Runtime / RTX 30、40 RankFTW 310.8.SF-v2 | **未修改且不提交 GitHub**；安装器按显卡选择目标、校验配套哈希，玩家提供的其他 Runtime 会警告但默认允许继续。 |
| NR HDR 合成方法 | [clshortfuse/RenoDX](https://github.com/clshortfuse/renodx) | 上游 Add-on 的 HDR 模型画面合成方法衍生自 RenoDX；MIT 声明保存在 `THIRD_PARTY_NOTICES.txt`。 |
| genshin-fps-unlock | [34736384/genshin-fps-unlock](https://github.com/34736384/genshin-fps-unlock) | **有修改**：支持预加载 GIMI、随后按固定顺序注入其余 DLL。 |

`nr-before-sr` 插件和私有桥并不是本仓库原创。本仓库不声称拥有其源代码或作者身份；仓库所做的是原神/GIMI 兼容集成、外围源码修改、配置、验证与分发整理。原始版本、固定提交和许可证明细见 [`third_party/UPSTREAM-COMMITS.md`](third_party/UPSTREAM-COMMITS.md)。

## 如何确认不是“只显示成功”

退出游戏后运行：

```powershell
powershell -ExecutionPolicy Bypass -File .\Verify-Installation.ps1 -LastRun
```

真正成功必须在所选 Profile 的 `nr-before-sr.log` 中看到持续增长的成功计数。Mode 2 位于 `pre-nr` 或 `pre-nr-rtx30`，应看到：

```text
signed DLSSNR D3D12 runtime initialized through nrchain_nvngx.dll
signed feature 18 create 3072x1728 -> 3072x1728 ... Success
NR-before-SR evaluate succeeded: count=...
SuperSampling ... create=3072x1728 -> 3840x2160
```

只有 Feature 1 计数、没有 `NR-before-SR evaluate succeeded`，不算 DLSS5 生效。

Mode 1 则应看到 `post-SR signed feature 18 create <输出分辨率> guides=<渲染分辨率> ... Success` 与持续增长的 `NR-after-SR evaluate succeeded`；验证脚本会按当前保存的 Mode 自动检查对应合同。

## HDR 截图

GIMI 会把最终 R10 交换链的 HDR10/PQ 色彩空间交给 Hosted ReShade。Before/After 截图保存为 16 位 RGB PNG，并带 BT.2020/PQ 标记；旧构建误按无标记 8 位 sRGB 保存时会发灰。HDR PNG 需要支持色彩管理的查看器；上传普通 SDR 平台前应做 HDR→SDR 色调映射。

## 风险与许可证

这是第三方实验性游戏修改整合，不是 HoYoverse、NVIDIA、ReShade、OptiScaler、RenoDX 或插件作者的官方产品。游戏、驱动和 NGX Runtime 更新可能改变格式、标志或 Hook 顺序；请自行确认服务条款、账号与在线使用风险。

根目录脚本和文档使用本仓库 MIT 许可证。第三方源码、补丁形成的衍生构建、Shader 与二进制继续受各自上游许可证和声明约束。
