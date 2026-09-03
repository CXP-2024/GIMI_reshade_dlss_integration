# 上游来源与版本

## 3Dmigoto / GIMI Runtime 基础

- Source: https://github.com/bo3b/3Dmigoto.git
- Base commit: `8f329bd94fecc9bbcb9211ffd42a95dd7fe6b43e`
- License: GPL-3.0-only，见 `LICENSES/3Dmigoto-GPL-3.0.txt`
- Local changes: 外部 D3D11 Device/Context 包装、HDR SwapChain、Hosted ReShade Runtime、UnlockFPS 注入兼容
- Patch: `src/patches/3Dmigoto-GIMI-hosted-reshade.patch`

## OptiScaler

- Source: https://github.com/optiscaler/OptiScaler.git
- Base commit: `c983a500335134ecff512bfcdadcf912d1286547`
- Runtime version: `10.0.0-dev (c983a50)`
- License: GPL-3.0，见 `LICENSES/OptiScaler-GPL-3.0.txt`
- Local changes: GIMI Device/Context 原生接口解析、NGX 初始化/Create/Evaluate 兼容；DX11 Present API 类型守卫；发行配置不使用 OptiScaler Hosted ReShade
- Patches: `src/patches/OptiScaler-GIMI-DX11-interop.patch`、`src/patches/OptiScaler-DX11-Present-API-guard.patch`

## Dx11FsrBridge

- Source: https://github.com/AizawaHikaru233/genshin_fsr_brigde.git
- Commit: `620f47ca3f6959bc27b7866e4f8db813df8bbcc4`
- Runtime version: `1.2.3.0`
- License: GPL-3.0，见 `LICENSES/Dx11FsrBridge-GPL-3.0.txt`
- Role: 捕获原神 DX11 FSR2 输入并通过正式 Mode 2 路径交给 OptiScaler

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

## DLSS5 DX11 Bridge / RenoDX Add-on

- Reference package: https://github.com/CXP-2024/dlss5_for_genshinimpact/
- Role: 私有 D3D12 NGX 会话、DX11/DX12 资源运输、延迟加载 RenoDX DLSS5 Add-on
- `nvngx_dlssnr.dll` 不提交到本仓库；README 提供国内外下载位置与固定 SHA-256

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
