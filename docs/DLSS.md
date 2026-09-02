# DLSS Integration

This package loads the pre-existing Genshin FSR Bridge and OptiScaler runtime from a path supplied by the user. It does not redistribute `Dx11FsrBridge.dll`, `OptiScaler.dll`, or NVIDIA's `nvngx_dlss.dll`.

## Required runtime layout

Choose the FSR Bridge root folder, not one of its `payload` subfolders. The wizard requires this layout:

```text
<Bridge root>\payload\Bridge\Dx11FsrBridge.dll
<Bridge root>\payload\Bridge\Dx11FsrBridge.ini
<Bridge root>\payload\OptiScaler\OptiScaler.dll
<Bridge root>\payload\OptiScaler\OptiScaler.ini
<Bridge root>\payload\OptiScaler\nvngx_dlss.dll
```

The configured chain is:

```text
GIMI d3d11.dll -> ReShade64.dll (optional) -> Dx11FsrBridge.dll -> OptiScaler.dll
```

GIMI is loaded through `PreloadDlls`. The remaining DLLs are loaded through `DllList` while the game process is still suspended. The order of Bridge and OptiScaler is required: OptiScaler scans the game executable for FSR2 exports only during its startup, while Bridge supplies those exports.

## Backend and quality control

The wizard sets only `Dx11Upscaler = dlss` under `[Upscalers]` in the selected `OptiScaler.ini`. It makes a timestamped `OptiScaler.ini.before-dlss-*` backup before changing the file. It deliberately leaves `QualityRatioOverride*` settings alone; those overrides would compete with the Bridge's direct control of the game's internal render scale.

In Genshin, select FSR2 anti-aliasing and choose a render scale below `1`. The Bridge exposes `0.2` through `0.9` plus `0.999`. These are input-resolution scales rather than fixed DLSS preset names. As practical starting points: `0.7` is about 1.43x upscale, `0.6` about 1.67x, and `0.5` about 2x. Lower scales reduce GPU cost but may introduce temporal artifacts. `0.999` is near native resolution.

## Verification

After a fresh game start, check the logs in the selected Bridge runtime:

- `payload\Bridge\Dx11FsrBridge.log` should contain `fsr2_get_proc_address_shim_queries mask=0x3F` and `fsr2_translation_context_created`.
- `payload\OptiScaler\OptiScaler.log` should show the NVIDIA backend, including `Enabling DLSS`, and its DX11 FSR2 input hook.

If either marker is absent, close the game completely before making another test. To return to the GIMI/ReShade-only chain, run `Configure-GIMI-Paths.bat` and leave the FSR Bridge prompt blank. This removes Bridge and OptiScaler from `fps_config.json`; the saved OptiScaler backup remains available if its standalone configuration also needs to be restored.

## Scope and risk

This is third-party game-modification software. The Bridge, OptiScaler, DLSS, ReShade, GIMI, and the game can each change independently. The game build-specific render-scale hook may need an upstream Bridge update after a game patch. Evaluate game-account, platform, component-license, and NVIDIA GPU requirements before use.
