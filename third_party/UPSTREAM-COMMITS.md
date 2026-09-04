# 上游来源与版本

## 3Dmigoto / GIMI Runtime 基础

- Source: https://github.com/bo3b/3Dmigoto.git
- Base commit: `8f329bd94fecc9bbcb9211ffd42a95dd7fe6b43e`
- License: GPL-3.0-only，见 `LICENSES/3Dmigoto-GPL-3.0.txt`
- Local changes: 外部 D3D11 Device/Context 包装、HDR SwapChain、Hosted ReShade Runtime、UnlockFPS 注入兼容、OptiScaler 原生 Context 通道、Hosted ReShade HDR10/PQ 色彩空间传递
- Patch: `src/patches/3Dmigoto-GIMI-hosted-reshade.patch`

## OptiScaler DLSSNR fork

- Source: https://github.com/Dagherbou/OptiScaler_DLSSNR.git
- Base commit: `973761621353b99bee3dc7d4bb27b117fef2644f`
- Runtime family: OptiScaler v0.2 DLSS-on-DX12 / DLSSNR experimental fork
- License: GPL-3.0，见 `LICENSES/OptiScaler-GPL-3.0.txt`
- Local changes: GIMI Device/Context 原生接口解析；DX11 Present API 类型守卫；原神 R10 共享颜色的 FP16 提升；`nrchain_nvngx.dll` 私有桥名称排除；发行配置不使用 OptiScaler Hosted ReShade 或内置 post-NR
- Patch: `src/patches/OptiScaler-DLSSOn12-GIMI-pre-NR.patch`

## Dx11FsrBridge

- Source: https://github.com/AizawaHikaru233/genshin_fsr_brigde.git
- Commit: `620f47ca3f6959bc27b7866e4f8db813df8bbcc4`
- Runtime version: `1.2.3.0`
- License: GPL-3.0，见 `LICENSES/Dx11FsrBridge-GPL-3.0.txt`
- Role: 捕获原神 DX11 FSR2 输入、提供渲染比例档位并通过 Mode 2 路径交给 OptiScaler
- Local changes: DLL 代码未修改；发行包只固定 `Dx11FsrBridge.ini` 中当前原神版本的输入翻译和渲染比例配置

## genshin-fps-unlock

- Source: https://github.com/34736384/genshin-fps-unlock.git
- Base commit: `2b85d61dd06f6e11ad86fdd6bd90339f9abc58eb`
- License: MIT，见 `LICENSES/genshin-fps-unlock-MIT.txt`
- Local changes: `PreloadDlls`、普通 `DllList` 与挂起进程恢复顺序
- Patch: `src/patches/genshin-fps-unlock-preload.patch`

## ReShade

- Source: https://github.com/crosire/reshade.git
- Inspected source commit: `ec0346e035b7d1c267103ea0d7c231b3945fc2b1`
- Packaged runtime version: `6.8.0`
- License: BSD 3-Clause，见 `LICENSES/ReShade-BSD-3-Clause.md`
- Integration: 动态解析公开 C Runtime API；不静态链接，不启用图形 Hook；Hosted 更新路径补发逐帧 Add-on 事件
- Patch: `src/patches/ReShade-hosted-addon-present-events.patch`

## DLSS5 前置 NR Add-on / 私有桥

- Binary package attribution: Bilibili UP 主 **野生的装机宅**，用户提供的发布包名为 `B站野生的装机宅 DLSS5-AI渲染超分版-RTX50.zip`
- `nr-before-sr.zh-CN.addon64`: 原包二进制未修改，SHA-256 `522D979CBFF335710F362B9FC2F330988673D7F8C7A1A2D93DA9980EC8DDA695`
- `nrchain_nvngx.dll`: 原包二进制未修改，SHA-256 `DB26E486592B252072BA5734FC2B27412863B8526826225640C837D4B4D11B60`
- Configuration-only change: `nr_before_sr.ini` 从上游默认 `Mode=1` 改为本项目验证的 `Mode=2`；Add-on 与私有桥本体未反编译修改
- The Add-on's HDR composition method is derived from clshortfuse/RenoDX under MIT; full notice is kept beside the Add-on in `components/DLSS5/Addons/pre-nr/THIRD_PARTY_NOTICES.txt`
- `nvngx_dlssnr.dll` 原样使用但不提交 GitHub；README 与安装脚本提供下载位置、目标路径和固定 SHA-256

## Lilium ReShade HDR Shaders

- Source: https://github.com/EndlesslyFlowering/ReShade_HDR_shaders
- License: GPL-3.0，见 `LICENSES/Lilium-ReShade-HDR-Shaders-GPL-3.0.txt`
- Role: HDR 分析、亮度、锐化与 Tone Mapping 效果；默认包同时保留 `FakeHDR` 作为易观察的测试预设

## GI-Model-Importer

- Source: https://github.com/SilentNightSound/GI-Model-Importer.git
- Inspected commit: `4232c26`
- Role: GIMI 生态与目录结构参考
- 本仓库不包含其 Mod 内容

## NVIDIA DLSS Runtime 与其他 OptiScaler 依赖

`components/OptiScaler` 中的供应商 Runtime 来自上述 OptiScaler 分发结构；对应许可证随文件保存在同目录 `Licenses` 和 `nvngx_dlss.license.txt`。这些文件未由本仓库修改。

本仓库新增的启动脚本和文档使用根目录 MIT `LICENSE`；第三方源代码、补丁所形成的衍生构建、Shader 和二进制继续受各自上游许可与声明约束。
