# 构建与复现

构建环境：Windows 10/11 x64、Visual Studio 2022 C++ Desktop workload、Windows SDK 10.0.26100.0、.NET 8 SDK。上游提交固定在 [`third_party/UPSTREAM-COMMITS.md`](../third_party/UPSTREAM-COMMITS.md)。

## 3Dmigoto / GIMI

```powershell
git clone https://github.com/bo3b/3Dmigoto.git
Set-Location 3Dmigoto
git checkout 8f329bd94fecc9bbcb9211ffd42a95dd7fe6b43e
git apply ..\GIMI_reshade_integration\src\patches\3Dmigoto-GIMI-hosted-reshade.patch
```

本次实机构建命令：

```powershell
$msbuild = 'C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\MSBuild\Current\Bin\MSBuild.exe'
& $msbuild .\DirectX11\DirectX11.vcxproj /t:Build /m `
  /p:Configuration=Release /p:Platform=x64 /p:BuildProjectReferences=false `
  "/p:SolutionDir=$((Get-Location).Path)\" /p:WindowsTargetPlatformVersion=10.0.26100.0
```

输出 `builds/x64/Release/d3d11.dll`。当前已验证构建包含 Hosted ReShade HDR10/PQ 色彩空间传递，SHA-256：

```text
B85512DEE19BFBA65978F9011C6551E0DDD6F52FAEC6F6DDA1714F948CF79A80
```

## OptiScaler

```powershell
git clone --recursive https://github.com/Dagherbou/OptiScaler_DLSSNR.git
Set-Location OptiScaler_DLSSNR
git checkout 973761621353b99bee3dc7d4bb27b117fef2644f
git apply ..\GIMI_reshade_integration\src\patches\OptiScaler-DLSSOn12-GIMI-pre-NR.patch
```

用 Visual Studio 2022 打开 `OptiScaler.sln` 并构建 x64 Release。补丁包含 GIMI 原生 Device/Context 解析、跨 API 守卫、原神 R10 共享颜色的 FP16 转换和 `nrchain_nvngx.dll` 名称冲突修复；最终配置保持 `Plugins.LoadReShade=false`、`DlssNr.Enabled=false`，因为 ReShade 和唯一的 Feature 18 pass 分别由 GIMI 与外部 pre-NR Add-on 管理。

已验证 `OptiScaler.dll` SHA-256：

```text
B9E6D5D79D9DDF6FE7170C0DC783F3D40825CAC8338CE4CD1D24E7EFE9A84760
```

## Dx11FsrBridge

Bridge 使用 `AizawaHikaru233/genshin_fsr_brigde` 的提交 `620f47ca3f6959bc27b7866e4f8db813df8bbcc4`，按上游解决方案直接构建 x64 Release。DLL 代码未做本地修改；当前原神的 FSR2 输入翻译、渲染比例档位和版本相关 RVA 固定在 `components/Bridge/Dx11FsrBridge.ini`。

已验证 DLL SHA-256：

```text
1AB7FBD90B69D8F57851FDFC039AA3890AEE46AEA2DCB4DB72C8049282140310
```

## UnlockFPS

```powershell
git clone https://github.com/34736384/genshin-fps-unlock.git
Set-Location genshin-fps-unlock
git checkout 2b85d61dd06f6e11ad86fdd6bd90339f9abc58eb
git apply ..\GIMI_reshade_integration\src\patches\genshin-fps-unlock-preload.patch
dotnet publish unlockfps_nc\unlockfps_nc.csproj -c Release -r win-x64 `
  --self-contained true /p:PublishSingleFile=true
```

补丁使 UnlockFPS 在主线程恢复前区分 `PreloadDlls` 和普通 `DllList`。GIMI 必须位于前者，Bridge、OptiScaler 位于后者。

## ReShade

发行文件使用 ReShade 6.8.0 的 x64 DLL，并通过公开 C Runtime API 加载。在提交 `ec0346e035b7d1c267103ea0d7c231b3945fc2b1` 上应用：

```powershell
git apply ..\GIMI_reshade_integration\src\patches\ReShade-hosted-addon-present-events.patch
```

该补丁让公共 Hosted Runtime 每帧发送 Add-on 的 `execute_command_list` 与 `present` 事件。GIMI 只在运行时解析 API 导出，不静态链接 ReShade；`RESHADE_DISABLE_GRAPHICS_HOOK=1` 仍是架构要求。

已验证 `ReShade64.dll` SHA-256：

```text
084FA6B41AC9FC0CF66055E95C91C69A5BEF153612DDA15E18EACB21C9F52C54
```

## DLSS5 前置 NR Add-on 与私有桥

`nr-before-sr.zh-CN.addon64` 与 `nrchain_nvngx.dll` 来自 Bilibili UP 主“野生的装机宅”提供的 `DLSS5-AI渲染超分版-RTX50` 包，本仓库没有修改这两个二进制。唯一配置变化是把 `nr_before_sr.ini` 的默认 `Mode=1` 改为已验证的 `Mode=2`。约 165 MB 的 `nvngx_dlssnr.dll` 不提交到 GitHub；完整离线包加入后必须核对：

```text
E16BCF15E16E13F527491CDF7845B2FE6521A738D8F7C9C721866A8496E1FC8E
```

## 发布布局

```text
GIMI/d3d11.dll
components/Bridge/Dx11FsrBridge.dll
components/Bridge/Dx11FsrBridge.ini
components/OptiScaler/OptiScaler.dll
components/OptiScaler/nvngx_dlss.dll
components/ReShade/ReShade64.dll
components/DLSS5/Addons/pre-nr/nr-before-sr.zh-CN.addon64
components/DLSS5/Addons/pre-nr/nrchain_nvngx.dll
components/DLSS5/Addons/pre-nr/nr_before_sr.ini
# Full offline archive only:
components/DLSS5/Addons/pre-nr/nvngx_dlssnr.dll
Configure-And-Launch.ps1
Install-DLSS5-Runtime.ps1
Launch-Genshin-GIMI-DLSS-ReShade.bat
unlockfps_nc.exe
UnlockerStub.dll
```

不要把本机生成的 `state`、`fps_config.json`、`*.log`、效果缓存或 GIMI Mod 放入发布物。发布前应扫描绝对路径，并重新计算所有运行时 SHA-256。
