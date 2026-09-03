# r12 架构与修复原理

## 对象所有权

```text
GIMI
  ├─ 唯一拥有真实 DX11 Device / Context / SwapChain / Present
  ├─ 执行 Mod
  └─ 在最终 Present 托管可见的 ReShade Runtime

被动 ReShade Add-on Host（graphics hooks disabled）
  └─ 只提供 Add-on API 与 DLSS5 Bridge 注册时机

Dx11FsrBridge
  └─ 从原神 FSR2 carrier 捕获 color / depth / motion vectors

OptiScaler + DLSS
  └─ 负责低分辨率到输出分辨率的标准空间超分

DLSS5 DX11 Bridge
  └─ 建立私有 D3D12 NGX 会话，再延迟加载 RenoDX

RenoDX DLSS5
  └─ 在输出分辨率执行 Native Neural Rendering
```

同一进程内实际上有两个 ReShade 用途。最早加载的实例禁用 D3D11/DXGI 图形 Hook，只让 Add-on 完成注册；最终可见的效果 Runtime 由 GIMI 通过 ReShade 公共 C API 创建。两者都不能夺走 GIMI 的 SwapChain 所有权。

## v1.1 路径与 r12 的关系

v1.1 的控制配置是 `NREnableUpscaling=1`，所以 RenoDX 首先构造低分辨率颜色输入。当前签名的 `nvngx_dlssnr.dll` 在原神上会拒绝这一步：

```text
1920x1080 color -> 3840x2160 output
feature 18 -> 0xBAD00005
```

这只是低分辨率 NR 探测失败。Add-on 不覆盖标准 DLSS 已生成的画面，而是重建为：

```text
3840x2160 color + 1920x1080 guides -> 3840x2160 output
feature 18 -> OK (Native NR)
```

因此菜单里的 `requested ON / active OFF / ratio 1.00` 与持续增长的 `Successful NR frames` 可以同时成立。空间超分仍由 OptiScaler/DLSS 完成，DLSS5 负责后续 Native NR。

## 已定位的两个关键故障

### r11：跨 API Feature 污染

OptiScaler 的 `State::currentFeature` 是进程级状态。DLSS5 私有会话创建 D3D12 Feature 后，DX11 SwapChain 的 Present 路径可能取到它，并把 `ID3D11DeviceContext` 传给只接受 `ID3D12CommandQueue` 的 `IFeature_Dx12::ReadUpscalerTime`。同一 vtable 偏移落到了 D3D11 的 `PSSetConstantBuffers`，所以崩溃栈看起来像 GIMI/Bridge 的常量缓冲 Hook 冲突。

r11 在两个 DX11 Present 分支增加 `currentFeature->Api() == API::DX11` 守卫。私有 D3D12 Feature 不再读取主 DX11 Context，稳定性问题随之消失。

### r12：Hosted Runtime 缷少逐帧 Add-on 事件

仅调用 `ReShadeUpdateAndPresentEffectRuntime -> runtime::on_present()` 不等价于正常 DXGI SwapChain Present。公共托管路径原先不会发送：

- `addon_event::execute_command_list`
- `addon_event::present`

RenoDX 的 one-pass-per-output 遮罩依赖 `present` 事件清除逐帧状态。没有事件时，三个持久输出资源各执行一次后全部被抑制，于是出现“NGX evaluations 数万、Successful NR frames 只有 3”的假完成状态。

r12 在 `runtime::on_present()` 前补发这两个事件，并在最后 flush immediate command list。实测日志随后出现 `count=1`、`count=60`，成功帧继续增长。

## 保持兼容的边界

- GIMI 必须通过 UnlockFPS 的 `PreloadDlls` 在恢复游戏主线程前加载。
- DllList 顺序固定为被动 `ReShade64.dll`、`Dx11FsrBridge.dll`、`OptiScaler.dll`。
- `RESHADE_DISABLE_GRAPHICS_HOOK=1` 必须保留。
- OptiScaler 的 `SkipD3D11DeviceVTableHooks=true` 必须保留。
- RenoDX 只 Hook NGX（`EnableHooks=2`），并由 Bridge 延迟加载。
- 不应在游戏目录额外放置 ReShade 的 `dxgi.dll` 或其他 D3D11 wrapper。

这些约束让四个组件各自只拥有一个明确阶段；所谓“注册冲突”不是靠碰运气调整 DLL 顺序，而是通过对象所有权与生命周期隔离解决。
