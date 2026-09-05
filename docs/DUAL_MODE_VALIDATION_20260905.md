# GIMI dual-mode validation — 2026-09-05

## Environment

- Windows 11
- NVIDIA GeForce RTX 5080, driver 616.56
- Output 3840×2160, render extent 1920×1080
- GIMI Mods present (three INI files), GIMI `hook=recommended`
- GIMI tested build SHA-256: `365E1A008CE1833ED5B3C0DF6B6C9FE8CB661CB59C6204A192EB6FB6EB94A2C8`
- Release GIMI SHA-256: `50B0AAB76C8ED74ACDEE031437E34873C6C451DDE214992A8D39065B6D7F8066` (same source, relinked without the local PDB debug-directory record and separately rerun to 600 successful Mode 2 frames)
- OptiScaler SHA-256: `2D86C3E6728F018F259AABC052F78E53A039A1B0D6BBBC3AEB7571BB67D61F44`

## Shared interop evidence

Both launches reported:

```text
D3D11 init policy: gimiMarker=true bridge=true nativeGimiDevice=true deferNativeInit=false customParams=true
GIMI pass-through context resolved
DLSSFeatureDx12::InitDLSS _CreateFeature result: NVSDK_NGX_Result_Success
signed DLSSNR D3D12 runtime initialized through nrchain_nvngx.dll
```

Hosted ReShade registered the unmodified `nr-before-sr.zh-CN.addon64`, detected
the RTX 5080/616.56 driver and compiled the configured effect successfully.

## Mode 2

```text
signed feature 18 create 1920x1080 -> 1920x1080 ... Success
NR-before-SR evaluate succeeded: count=2400 extent=1920x1080
SuperSampling Evaluate ... create=1920x1080 -> 3840x2160
```

This confirms render-resolution NR followed by original DLSS Super Resolution.

## Mode 1

```text
SuperSampling Evaluate ... create=1920x1080 -> 3840x2160
post-SR signed feature 18 create 3840x2160 guides=1920x1080 ... Success
NR-after-SR evaluate succeeded: count=600 extent=3840x2160 guides=1920x1080
```

This confirms the restored output-resolution NR path. `Verify-Installation.ps1
-LastRun` accepted both saved modes and their respective extent contracts.

## Scope

The RTX 30 backend/resource pair and automatic RTX 40 fallback passed package,
profile, hash and launcher tests. This machine cannot provide RTX 30/40 hardware
validation: RTX 30 support is based on the supplied RTX 3090-tested fix and the
reviewed source delta; RTX 40 remains explicitly experimental and is not blocked.
