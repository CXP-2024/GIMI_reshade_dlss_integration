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

输出 `builds/x64/Release/d3d11.dll`。已验证构建的 SHA-256：

```text
75D8D79D4A25FAA1E57105076A41C9EEF6E60561F752C39878064A7EB6B917EB
```

## OptiScaler

```powershell
git clone --recursive https://github.com/optiscaler/OptiScaler.git
Set-Location OptiScaler
git checkout c983a500335134ecff512bfcdadcf912d1286547
git apply ..\GIMI_reshade_integration\src\patches\OptiScaler-GIMI-DX11-interop.patch
```

用 Visual Studio 2022 打开 `OptiScaler.sln` 并构建 x64 Release。补丁包含 GIMI 原生 Device/Context 解析和本次二进制中的兼容开关；最终发行配置保持 `Plugins.LoadReShade=false`，因为 ReShade 由 GIMI 托管。

已验证 `OptiScaler.dll` SHA-256：

```text
2C17413A6C9DD881439643EC8E48961BB225982E74961CA932EE8882309468E4
```

## Dx11FsrBridge

Bridge 使用 `AizawaHikaru233/genshin_fsr_brigde` 的提交 `620f47ca3f6959bc27b7866e4f8db813df8bbcc4`，运行时版本为 1.2.3.0。按上游解决方案构建 x64 Release；游戏版本相关 RVA 位于 `components/Bridge/Dx11FsrBridge.ini`。

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

发行文件使用 ReShade 6.8.0 的 x64 DLL，并通过公开 C Runtime API 加载。GIMI 构建只在运行时解析 API 导出，不静态链接 ReShade。配置中的 `RESHADE_DISABLE_GRAPHICS_HOOK=1` 是架构要求，不能为 Hosted 模式关闭。

## 发布布局

```text
GIMI/d3d11.dll
components/Bridge/Dx11FsrBridge.dll
components/Bridge/Dx11FsrBridge.ini
components/OptiScaler/OptiScaler.dll
components/OptiScaler/nvngx_dlss.dll
components/ReShade/ReShade64.dll
Configure-And-Launch.ps1
Launch-Genshin-GIMI-DLSS-ReShade.bat
unlockfps_nc.exe
UnlockerStub.dll
```

不要把本机生成的 `state`、`fps_config.json`、`*.log`、效果缓存或 GIMI Mod 放入发布物。发布前应扫描绝对路径，并重新计算所有运行时 SHA-256。
