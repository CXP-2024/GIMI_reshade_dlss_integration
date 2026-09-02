# Build

构建环境：Windows 10/11、Visual Studio 2022（C++ Desktop workload）、.NET 8 SDK。

## 3Dmigoto/GIMI DLL

```powershell
git clone https://github.com/bo3b/3Dmigoto.git
Set-Location 3Dmigoto
git checkout 8f329bd94fecc9bbcb9211ffd42a95dd7fe6b43e
git apply ..\GIMI-reshade-integration\src\patches\3Dmigoto-HDR-loader.patch
```

用 Visual Studio 打开 `StereovisionHacks.sln`，选择 `Release|x64` 构建。将生成的 GIMI `d3d11.dll` 放到 `GIMI\d3d11.dll`。

## UnlockFPS

```powershell
git clone https://github.com/34736384/genshin-fps-unlock.git
Set-Location genshin-fps-unlock
git checkout 2b85d61dd06f6e11ad86fdd6bd90339f9abc58eb
git apply ..\GIMI-reshade-integration\src\patches\genshin-fps-unlock-preload.patch
dotnet publish unlockfps_nc\unlockfps_nc.csproj -c Release -r win-x64 --self-contained true /p:PublishSingleFile=true
```

将发布出的 `unlockfps_nc.exe` 放到仓库根目录。构建产物只适用于 x64 Windows；补丁依赖上面列出的上游 commit。
