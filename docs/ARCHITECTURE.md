# 新版架构与修复原理

## 为什么直接串联会失败

旧实验把 ReShade、Bridge 和 OptiScaler都作为普通注入 DLL 排进 `DllList`。这三个组件连同 GIMI 都可能拦截 D3D11/DXGI 创建函数，包装 Device、Context 或 SwapChain，并接管 `Present`。结果依赖加载时序：

- ReShade 先包装 SwapChain 时，GIMI 可能拿到一个从未登记的原生 Device 并执行致命退出；
- GIMI 只补包装 SwapChain、没有同时 Hook 外部 Device/Context 时，覆盖层存在但 Mod 资源和 Shader 跟踪失效；
- OptiScaler 把 GIMI 的 COM 包装对象交给 NVIDIA NGX 时，Device 与 Context 身份不一致，DLSS 创建失败并回退；
- 绕开 GIMI SwapChain 包装虽然能让 ReShade 出图，却会跳过 GIMI 的最终 Present 行为；
- 多层 `ResizeBuffers` 和 HDR 色彩空间协商还会造成黑屏、错误格式或非法 back-buffer 数量。

因此问题不是简单的“哪一个 DLL 放前面”，而是四个组件对同一批图形对象缺少明确所有权。

## 最终所有权

| 对象或阶段 | 所有者 | 说明 |
| --- | --- | --- |
| 游戏进程创建与暂停 | UnlockFPS | 在恢复主线程前完成预加载和依赖注入 |
| D3D11 代理入口与 Mod Hook | GIMI | `d3d11.dll` 是唯一预加载代理 |
| 原神 FSR2 输入捕获 | Dx11FsrBridge | 把游戏数据转换成 OptiScaler 可消费的 FSR2 接口 |
| NGX/DLSS Feature | OptiScaler | 使用解包后的原生 Device/Context 调用 NVIDIA NGX |
| GIMI Mod 绘制与 Frame Actions | GIMI | 保持原有纹理、Shader、快捷键和 F10 重载语义 |
| ReShade 效果 Runtime | GIMI 托管 | 在最终 GIMI Present 中调用 ReShade 公共 C API |
| 原始 SwapChain Present | DXGI | ReShade Runtime 更新完成后提交 |

## 启动时序

`fps_config.json` 的结构是：

```json
{
  "PreloadDlls": ["<GIMI>/d3d11.dll"],
  "DllList": [
    "<package>/components/Bridge/Dx11FsrBridge.dll",
    "<package>/components/OptiScaler/OptiScaler.dll"
  ]
}
```

ReShade 刻意不在 `DllList` 中。启动器通过环境变量和 GIMI 目录旁路文件提供：

```ini
[HostedReShade]
Enabled=1
Dll=<package>\components\ReShade\ReShade64.dll
Config=<package>\state\reshade-runtime\ReShade.ini
```

GIMI 第一次走到最终 `Present` 时加载 ReShade DLL，设置 `RESHADE_DISABLE_GRAPHICS_HOOK=1`，解析以下公共导出并创建 D3D11 Runtime：

- `ReShadeCreateEffectRuntime`
- `ReShadeUpdateAndPresentEffectRuntime`
- `ReShadeDestroyEffectRuntime`

创建 Runtime 时使用与目标 SwapChain 完全一致的原生 Device，并把 GIMI 的 passthrough immediate Context 交给 ReShade。SwapChain 改变或 `ResizeBuffers` 前销毁 Runtime，下一帧再惰性重建。

## GIMI 外部 Device 修复

正常 GIMI 路径假定 D3D11 Device 是由它自己的创建 Hook 返回的。Bridge/OptiScaler参与后，DXGI 创建 SwapChain 时可能带入尚未登记的原生 Device。

新版在 `sort_out_swap_chain_device_mess` 中识别这种对象并：

1. 获取 `ID3D11Device1` 与 `ID3D11DeviceContext1`；
2. 创建配对的 `HackerDevice` / `HackerContext`；
3. 按 `hook=recommended` 同时安装 Device 和 immediate Context vtable Hook；
4. 写入 GIMI 私有 Device 标记；
5. 创建并绑定 GIMI 资源、初始化 INI 常量；
6. 回到正常的 SwapChain 包装和最终 Present 路径。

这取代了原先的 `DoubleBeepExit()`，同时避免“覆盖层出现但 Mod 不工作”的半兼容状态。

## OptiScaler / NGX 解包修复

NVIDIA NGX 会校验创建 Feature 的 Context 是否属于初始化时的 Device。GIMI 包装器对基础 D3D11 接口保留代理身份，因此直接传递会导致 `NVSDK_NGX_Result_FAIL_NotInitialized (BAD00007)`。

修复路径通过更高版本的 `ID3D11DeviceContext4` QueryInterface 取得 passthrough 原生 Context，再从该 Context 获取配对的原生 Device。NGX 初始化、`CreateFeature`、后端切换和 `EvaluateFeature` 都使用这对原生对象；游戏其余 D3D11 调用仍经过 GIMI。

## HDR SwapChain 修复

对于 `DXGI_FORMAT_R10G10B10A2_UNORM`：

- GIMI 向游戏暴露原生 `IDXGISwapChain2/3/4`，让 `SetColorSpace1` 和 HDR 元数据协商使用正确 ABI；
- `ResizeBuffers` 请求不兼容格式时改用 `DXGI_FORMAT_UNKNOWN` 保留现有 HDR 格式；
- flip-model SwapChain 保持至少两个 back buffer；
- Hosted ReShade Runtime 在 Resize 前释放旧 back-buffer 视图。

## 故障隔离

Hosted ReShade 初始化失败只会在 GIMI 日志记录原因，不会改变 Bridge → OptiScaler 的 DLL 顺序。反之，ReShade 的图形 Hook 被禁用，也不会因为独立包装 SwapChain 而破坏 GIMI。这个隔离是新版相较于旧 DLL 排序实验最重要的稳定性改进。
