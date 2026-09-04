# 实机验证记录

验证日期：2026-09-04。本页只把“逐帧实际执行”视为成功，单纯加载 DLL、创建菜单或显示 `ACTIVE` 不算通过。

## 环境

- Windows 11 x64
- NVIDIA GeForce RTX 5080，驱动 616.56
- 原神 DX11，HDR10，3840×2160 输出
- 渲染比例 0.8，即 3072×1728 内部渲染
- GIMI 为唯一 D3D11 包装器与最终 Present 所有者
- ReShade 6.8 Hosted Runtime，图形 Hook 关闭
- OptiScaler v0.2 DLSS-on-DX12 路径
- 前置 NR Add-on Mode 2，内置 OptiScaler post-NR 关闭

## 最终成功合同

同一帧的有效顺序为：

```text
Feature 18: 3072x1728 -> 3072x1728
Feature 1 : 3072x1728 -> 3840x2160
```

`nr-before-sr.log` 持续记录：

```text
Color ... physical=3072x1728 format=10(R16G16B16A16_FLOAT)
signed DLSSNR D3D12 runtime initialized through nrchain_nvngx.dll
signed feature 18 create 3072x1728 -> 3072x1728 ... Success
NR-before-SR evaluate succeeded: count=1 extent=3072x1728
...
NR-before-SR evaluate succeeded: count=9600 extent=3072x1728
SuperSampling ... create=3072x1728 -> 3840x2160
```

这证明 Feature 18 不是在最终 4K 图像上做后处理，也没有取代原来的空间超分；它先改善低分辨率颜色，原 Feature 1 随后完成放大。

## 组件共存

- `Dx11FsrBridge.log` 连续增长到至少 8192 次分发；
- Feature 18 成功计数达到 9600，且 Feature 1 仍持续执行；
- GIMI Mod 和 `F10` 重载保留；
- `Home` 可打开最终 ReShade，`Insert` 可打开 OptiScaler；
- `F6` 切换前置 NR 时用户确认光影效果有实际差异；
- 游戏保持响应，未重新引入旧的 D3D11/DX12 Context 指针冲突。

## HDR 截图验证

旧 Hosted Runtime 未收到 `SetColorSpace1` 信息，会把 R10/PQ 背景误存为无标记 8 位 sRGB PNG，画面呈灰白。修复后 GIMI 在创建 Hosted Runtime 前传递 HDR10/PQ 元数据。

自动 Before/After 测试结果：

```text
旧：3840x2160, RGB 8-bit, cICP absent
新：3840x2160, RGB 16-bit, cICP 9,16,0,1 (BT.2020, PQ, RGB, full range)
```

截图修复轮次中，前置 NR 同时持续成功到 9600 帧，因此该修复没有破坏 DLSS5、原 DLSS 或 GIMI 所有权。

## 发布验收

每次更新后至少完成：

1. 从全新解压目录运行 `Verify-Installation.ps1`，所有 manifest 项必须通过；
2. 进入大世界并活动数分钟；
3. 确认 Bridge 分发、Feature 18 和 Feature 1 三类计数都持续增长；
4. 确认 Feature 18 输入输出尺寸相同，Feature 1 输出尺寸更大；
5. 测试 GIMI Mod、`F10`、`Home`、`Insert` 与 `F6`；
6. 截取 Before/After，确认 PNG 为 16 位且带 cICP `9,16,0,1`；
7. 退出游戏后运行 `Verify-Installation.ps1 -LastRun`。

## 验证边界

- 当前只验证 RTX 5080/615+ 驱动，不宣称 RTX 40、AMD、Intel、Wine 或帧生成可用；
- 原神更新可能改变 Bridge RVA、资源格式或输入合同；
- HDR PNG 在不支持 PQ/BT.2020 的查看器中仍可能显示错误；
- 性能和画质偏好与链路是否正确执行是两个独立问题。
