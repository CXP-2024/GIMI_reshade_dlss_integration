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

## 2026-09-05 双模式与 GIMI 原生 Device 回归

合并 RTX 30 后端修复与 GIMI 原生 Device pass-through 后，在同一 RTX 5080 / 616.56 环境完成两次独立启动：Mode 2 的 `NR-before-SR evaluate succeeded` 达到 2400 帧；Mode 1 的 `post-SR signed feature 18 create 3840x2160 guides=1920x1080` 成功，`NR-after-SR evaluate succeeded` 达到 600 帧。两次均记录 `nativeGimiDevice=true`、原生 Context 解析、Feature 1 创建成功和 Hosted ReShade Add-on 注册。完整证据见 [`DUAL_MODE_VALIDATION_20260905.md`](DUAL_MODE_VALIDATION_20260905.md)。

## 组件共存

- `Dx11FsrBridge.log` 连续增长到至少 8192 次分发；
- Feature 18 成功计数达到 9600，且 Feature 1 仍持续执行；
- GIMI Mod 和 `F10` 重载保留；
- `Home` 可打开最终 ReShade，`Insert` 可打开 OptiScaler；
- `F6` 切换前置 NR 时用户确认光影效果有实际差异；
- 游戏保持响应，未重新引入旧的 D3D11/DX12 Context 指针冲突。

## 国服目标名回归

国服可执行文件不是国际服的 `GenshinImpact.exe`，而是 `YuanShen.exe`。仅修改 UnlockFPS 的 `GamePath` 不够；GIMI `d3dx.ini` 的 `[Loader] target` 也必须同步，否则 3DMigoto、其托管的最终 ReShade 和前置 NR 资源链会失效。

修复后使用同一套组件在国服 7.0.0 实机验证：

```text
GIMI target: YuanShen.exe
Game path: <原神目录>\YuanShen.exe
Recreated runtime environment ... ReShade.ini
signed feature 18 create 960x540 -> 960x540 ... Success
NR-before-SR evaluate succeeded: count=1800 extent=960x540
```

随后在隔离配置中切回国际服，`target=GenshinImpact.exe` 与安装验证同样通过。发布验收必须覆盖两个文件名的双向切换，不能只验证路径输入框是否接受 `YuanShen.exe`。

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
2. 确认 GIMI `[Loader] target` 与当前 `YuanShen.exe` 或 `GenshinImpact.exe` 一致，再进入大世界并活动数分钟；
3. 确认 Bridge 分发、Feature 18 和 Feature 1 三类计数都持续增长；
4. Mode 2 确认 Feature 18 为渲染分辨率 1:1 且 Feature 1 输出更大；Mode 1 确认 Feature 18 等于 Feature 1 输出分辨率且 guides 等于渲染分辨率；
5. 测试 GIMI Mod、`F10`、`Home`、`Insert` 与 `F6`；
6. 截取 Before/After，确认 PNG 为 16 位且带 cICP `9,16,0,1`；
7. 退出游戏后运行 `Verify-Installation.ps1 -LastRun`。

发布维护者若要同时强制核对本项目验证过的 RTX 50 Runtime 哈希，可运行 `Verify-Installation.ps1 -LastRun -RequireValidatedDlssNrHash`。普通验证允许玩家自行替换 `nvngx_dlssnr.dll`，但会对未知哈希显示警告。

## 验证边界

- GIMI 双模式当前在 RTX 5080/616.56 实机通过；RTX 30 Profile 来自已报告 RTX 3090/581.57 通过的“华晓熊”修复并已完成源码合并与静态验证；RTX 40 自动使用 RTX 30 配套方案但仍是实验支持；
- 不宣称 AMD、Intel、Wine 或帧生成可用；
- 原神更新可能改变 Bridge RVA、资源格式或输入合同；
- HDR PNG 在不支持 PQ/BT.2020 的查看器中仍可能显示错误；
- 性能和画质偏好与链路是否正确执行是两个独立问题。
