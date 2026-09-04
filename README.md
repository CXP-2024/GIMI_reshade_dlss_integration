# GIMI + ReShade + DLSS + DLSS 5 前置神经渲染

这是原神 DX11 下经过实机验证的四组件整合。当前版本不再使用旧版“DLSS 超分后再做原生分辨率 NR”的路径，而是在游戏渲染分辨率上先执行 DLSS 5 Neural Rendering，再保留原来的 DLSS Super Resolution 完成最终放大。

验证环境为 Windows 11、RTX 5080、NVIDIA 616.56 驱动、3840×2160 输出和 0.8 渲染比例：Feature 18 持续执行 `3072×1728 -> 3072×1728`，随后原 Feature 1 执行 `3072×1728 -> 3840×2160`。GIMI Mod、最终 ReShade、HDR 与截图功能同时正常。

## 下载方式

GitHub 仓库包含启动器、经修改的兼容组件、普通 DLSS Runtime、Shader、配置与许可证，但不包含约 165 MB 的 `nvngx_dlssnr.dll`。克隆仓库或下载 Source ZIP 后，需要先下载该文件，再运行 `Install-DLSS5-Runtime.bat`。

- 国外：[Google Drive](https://drive.google.com/file/d/1L7Pi4adSQal_OxpEzTMuT0NfeQTKIK-_/view?usp=sharing)
- 国内：[百度网盘](https://pan.baidu.com/s/1SAm1-QL0YvH8Kc28OGigAA?pwd=qisz)，提取码 `qisz`
- 必须匹配的 SHA-256：`E16BCF15E16E13F527491CDF7845B2FE6521A738D8F7C9C721866A8496E1FC8E`
- 安装目标：`components/DLSS5/Addons/pre-nr/nvngx_dlssnr.dll`

完整离线包会包含这个文件，因此不需要提前安装 ReShade、OptiScaler、普通 DLSS DLL 或 DLSS5 Add-on。

## 前置条件

- Windows 10/11；当前签名 NR Runtime 面向 RTX 50 系和 615+ 驱动，RTX 40 暂未宣称支持。
- 已安装并能正常运行的原神客户端。
- 已有 GIMI / 3DMigoto 目录，其中应包含 `3DMigoto Loader.exe`、`d3dx.ini` 与用户自己的 `Mods`。
- 启动前退出原神、旧的 `unlockfps_nc.exe` 和单独运行的 `3DMigoto Loader.exe`。

不使用 GIMI 的版本由独立仓库维护，本仓库不能通过留空 GIMI 路径切换成无 GIMI 模式。

## 快速开始

1. 完整解压；不要在压缩包预览窗口中运行。
2. 如果来自 GitHub，先运行 `Install-DLSS5-Runtime.bat` 安装上述大组件。
3. 双击 `Launch-Genshin-GIMI-DLSS-ReShade.bat`。
4. 首次输入 `GenshinImpact.exe` 的完整路径和现有 GIMI `3dmigoto` 目录。
5. 以后始终从同一 BAT 启动；路径改变时运行 `Configure-Again.bat`。
6. `Insert` 打开 OptiScaler，`Home` 打开最终 ReShade，`F6` 切换前置 NR，`F10` 重载 GIMI Mod。

不要同时把另一个 ReShade `dxgi.dll`/`d3d11.dll` 放入游戏目录，也不要额外启动 GIMI Loader；这些做法会重新引入 SwapChain 和 Hook 所有权冲突。

## 实际渲染链

```text
原神 DX11 低分辨率 FSR2 carrier
  -> GIMI：唯一 DX11 包装器和最终 Present 所有者
  -> Dx11FsrBridge：提取颜色、深度、运动向量与抖动合同
  -> OptiScaler DLSS-on-DX12：共享 R10 颜色并转换为 FP16
  -> nr-before-sr Mode 2：Feature 18 在渲染分辨率执行 1:1 NR
  -> 原始 DLSS Feature 1：从渲染分辨率放大到输出分辨率
  -> GIMI Mod 与最终 Present
  -> GIMI 托管 ReShade 后处理、UI 与 HDR 截图
```

Feature 18 只替换原 DLSS 合同的低分辨率 Color；Depth、MotionVectors、Jitter、Exposure 和原 Feature 1 均保留。若 Feature 18 创建或执行失败，Add-on 会把未修改的游戏 Color 交还原 Feature 1，不会提交半成品。

技术细节见 [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md)，实验过程与成功证据见 [`docs/PRE_NR_AUDIT.md`](docs/PRE_NR_AUDIT.md)。

## 来源、署名与修改边界

| 组件 | 来源 | 本仓库的处理 |
| --- | --- | --- |
| 3Dmigoto / GIMI | [bo3b/3Dmigoto](https://github.com/bo3b/3Dmigoto) | **有修改**：外部对象包装、Hosted ReShade、GIMI/OptiScaler 原生 Context 通道、HDR10/PQ 元数据传递等。 |
| ReShade 6.8 | [crosire/reshade](https://github.com/crosire/reshade) | **有修改**：Hosted Runtime 补发 Add-on 每帧事件；图形 Hook 在本组合中关闭，由 GIMI 托管最终 Runtime。 |
| OptiScaler DLSSNR fork | [Dagherbou/OptiScaler_DLSSNR](https://github.com/Dagherbou/OptiScaler_DLSSNR)，基于 [OptiScaler](https://github.com/optiscaler/OptiScaler) | **有修改**：GIMI 互操作、DX11/12 API 守卫、R10→FP16 转换以及 `nrchain_nvngx.dll` 名称冲突修复。 |
| Dx11FsrBridge | [AizawaHikaru233/genshin_fsr_brigde](https://github.com/AizawaHikaru233/genshin_fsr_brigde) | 二进制代码沿用固定上游提交；本仓库只固定当前原神的 FSR2 输入与渲染比例配置。 |
| `nr-before-sr.zh-CN.addon64` | Bilibili UP 主 **野生的装机宅** 提供的“DLSS5-AI渲染超分版-RTX50”包 | **二进制未修改**，SHA-256 `522D979CBFF335710F362B9FC2F330988673D7F8C7A1A2D93DA9980EC8DDA695`；仅把配置从默认 `Mode=1` 改为本项目验证的 `Mode=2`。 |
| `nrchain_nvngx.dll` | 同一“野生的装机宅”发布包 | **未修改**，SHA-256 `DB26E486592B252072BA5734FC2B27412863B8526826225640C837D4B4D11B60`；本仓库只修复了 OptiScaler 对其文件名的误拦截。 |
| `nvngx_dlssnr.dll` | 同一实验发布所需的签名 NVIDIA NR Runtime | **未修改且不提交 GitHub**；安装脚本只负责 SHA-256 校验和放置。 |
| NR HDR 合成方法 | [clshortfuse/RenoDX](https://github.com/clshortfuse/renodx) | 上游 Add-on 的 HDR 模型画面合成方法衍生自 RenoDX；MIT 声明保存在 `THIRD_PARTY_NOTICES.txt`。 |
| genshin-fps-unlock | [34736384/genshin-fps-unlock](https://github.com/34736384/genshin-fps-unlock) | **有修改**：支持预加载 GIMI、随后按固定顺序注入其余 DLL。 |

`nr-before-sr` 插件和私有桥并不是本仓库原创。本仓库不声称拥有其源代码或作者身份；仓库所做的是原神/GIMI 兼容集成、外围源码修改、配置、验证与分发整理。原始版本、固定提交和许可证明细见 [`third_party/UPSTREAM-COMMITS.md`](third_party/UPSTREAM-COMMITS.md)。

## 如何确认不是“只显示成功”

退出游戏后运行：

```powershell
powershell -ExecutionPolicy Bypass -File .\Verify-Installation.ps1 -LastRun
```

真正成功必须在同一轮 `components/DLSS5/Addons/pre-nr/nr-before-sr.log` 中看到：

```text
signed DLSSNR D3D12 runtime initialized through nrchain_nvngx.dll
signed feature 18 create 3072x1728 -> 3072x1728 ... Success
NR-before-SR evaluate succeeded: count=...
SuperSampling ... create=3072x1728 -> 3840x2160
```

只有 Feature 1 计数、没有 `NR-before-SR evaluate succeeded`，不算 DLSS5 生效。

## HDR 截图

GIMI 会把最终 R10 交换链的 HDR10/PQ 色彩空间交给 Hosted ReShade。Before/After 截图保存为 16 位 RGB PNG，并带 BT.2020/PQ 标记；旧构建误按无标记 8 位 sRGB 保存时会发灰。HDR PNG 需要支持色彩管理的查看器；上传普通 SDR 平台前应做 HDR→SDR 色调映射。

## 风险与许可证

这是第三方实验性游戏修改整合，不是 HoYoverse、NVIDIA、ReShade、OptiScaler、RenoDX 或插件作者的官方产品。游戏、驱动和 NGX Runtime 更新可能改变格式、标志或 Hook 顺序；请自行确认服务条款、账号与在线使用风险。

根目录脚本和文档使用本仓库 MIT 许可证。第三方源码、补丁形成的衍生构建、Shader 与二进制继续受各自上游许可证和声明约束。
