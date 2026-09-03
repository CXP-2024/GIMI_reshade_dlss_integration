# 实机验证记录

验证日期：2026-09-04。此页区分“DLL 成功加载”和“功能实际逐帧运行”；后者才算通过。

## 验证环境

- Windows 11 x64
- NVIDIA GeForce RTX 5080
- DirectX 11 HDR10 SwapChain，3840×2160 输出
- GIMI `[System] hook=recommended`、`skip_swapchain_wrap=0`
- Bridge `Fsr2TranslationMode=2`、渲染精度 0.8
- OptiScaler `Dx11Upscaler=dlss`、`LoadReShade=false`
- ReShade 6.8.0，由 GIMI Hosted Runtime 执行
- DLSS5 Bridge 私有 D3D12 NGX 会话；RenoDX DLSSNR v310.8.0

## 已通过项目

### 进程与呈现稳定性

- 通过 `Launch-Genshin-GIMI-DLSS-ReShade.bat` 创建游戏进程；
- 游戏通过登录/资源加载阶段并持续响应；
- 4K HDR10 SwapChain 创建、Resize 和 Present 均成功；
- ReShade 顶部启动横幅出现在真实游戏画面中，证明 Runtime 已进入最终呈现链，而不是只有 DLL 映射。

### Bridge 真实分发

Bridge 日志依次出现：

```text
fsr2_get_proc_address_shim_ready exports=6
fsr2_translation_context_created render=3072x1728 output=3840x2160
fsr2_translation_dispatch_succeeded count=1 render=3072x1728 output=3840x2160
fsr2_translation_dispatch_succeeded count=16384 render=3072x1728 output=3840x2160
```

测试中把渲染精度从 0.8 改到 0.2，再改回 0.8，Bridge 能销毁/重建上下文，并分别识别 768×432 和 3072×1728 输入。

### NVIDIA DLSS 真实执行

OptiScaler 日志不是只报告“DLSS Enabled”，而是逐帧出现：

```text
ffxFsr2ContextDispatch_Dx11 handle: F4242, internalResolution: 3072x1728
NVSDK_NGX_D3D11_EvaluateFeature Handle: 1000002
DLSSFeature::ProcessEvaluateParams Render Size: 3072x1728,
Target Size: 3840x2160, Display Size: 3840x2160
```

这排除了 FSR Fallback 和只加载 `nvngx_dlss.dll` 的假阳性。

### DLSS5 Native NR 真实执行

v1.1 配置的低分辨率探测先返回 `0xBAD00005`，随后保留标准 DLSS 输出并切换到输出分辨率：

```text
created inline NR resources 1920x1080 -> 3840x2160 (upscaling)
feature 18 evaluate failed with 0xbad00005; the game DLSS output was retained
NR upscaling fell back to native
created inline NR resources 3840x2160 -> 3840x2160 (native)
inline feature 18 evaluation succeeded (count=1, ... [native])
inline feature 18 evaluation succeeded (count=60, ... [native])
```

用户同时确认 `F6` 切换对光影有实际影响。`count=60` 证明 r12 已跨过旧版本只处理三个持久输出资源的状态。

### 四组件共存

- Bridge 和 OptiScaler 持续分发时，GIMI 没有触发旧的 unwrapped-device 致命退出；
- GIMI 保持最终 Present 所有权，并在其后半段执行 ReShade Runtime；
- `DllList` 中的 ReShade 只作为被动 Add-on Host，`RESHADE_DISABLE_GRAPHICS_HOOK=1`；最终可见 Runtime 仍由 GIMI 托管；
- `Home` 使用 ReShade 输入路径，`Insert` 使用 OptiScaler 菜单路径；
- 用户在共享实机画面中确认组合已经正常工作。

## 发布验收步骤

每次游戏、Bridge、OptiScaler、ReShade 或 GIMI 更新后，应重新完成：

1. 进入登录界面，确认无黑屏和致命退出；
2. 进入大世界并活动至少数分钟；
3. `Insert` 确认 DLSS 后端不是 Fallback；
4. 日志确认 `NVSDK_NGX_D3D11_EvaluateFeature` 持续递增；
5. 确认 GIMI Mod 可见，并执行一次 `F10`；
6. `Home` 打开 ReShade，启停一种效果确认最终画面发生变化；
7. `F6` 切换 NR，确认画面变化，且 `Successful NR frames` 持续增长；
8. 修改分辨率或窗口模式，确认 Resize 后四者仍恢复；
9. 正常退出，运行 `Verify-Installation.bat` 的最后运行诊断。

## 当前验证边界

- 此次验证只覆盖上述 NVIDIA/Windows/DX11 环境，没有声称 AMD、Intel、Linux/Wine 或帧生成可用；
- Frame Generation 在默认配置中关闭；
- Bridge 的多个 RVA 与游戏版本相关，原神更新后必须重新验证；
- `FakeHDR` 的主观亮度不作为兼容性判断标准；HDR 截图在 SDR 查看器中也可能失真；
- 上述日志摘录来自本地实机运行，不是 CI 模拟。
