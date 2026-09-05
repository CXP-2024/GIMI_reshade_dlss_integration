# GIMI-hosted dual-mode DLSS5 architecture

## Validated frame graph

```text
Genshin DX11 low-resolution FSR2 carrier
  |  Color: R10G10B10A2_UNORM, Depth: R32_FLOAT, MV: R16G16_FLOAT
  v
Dx11FsrBridge
  |  translates the game's color/depth/motion/jitter contract
  v
Patched OptiScaler v0.2 DLSS-on-DX12 bridge
  |  uses GIMI's private native-device and native-context trampolines
  |  exposes typed/untyped resource slots and queue-affinity metadata
  v
nr-before-sr + profile-matched nrchain_nvngx
  |  Mode 2: Feature 18 render-resolution NR -> original Feature 1 DLSS SR
  |  Mode 1: original Feature 1 DLSS SR -> output-resolution Feature 18 NR
  |  packed/typeless output uses an FP16 carrier and is copied back after completion
  v
GIMI Mods and sole final Present owner
  v
GIMI-hosted ReShade effects and overlay
```

The validated 4K/0.8-scale contract was:

```text
Feature 18: 3072x1728 -> 3072x1728
Feature 1 : 3072x1728 -> 3840x2160
```

Mode 2 is one neural-rendering pass followed by one spatial-upscaling pass, not
two competing upscalers. Mode 1 deliberately reverses those two passes to restore
the add-on's original output-resolution NR comparison path.

## Ownership rules

1. GIMI is the only D3D11 device/context wrapper and the only owner of the real
   final Present.
2. ReShade graphics hooks are disabled. GIMI creates the visible ReShade effect
   runtime through ReShade's public C Runtime API at final Present.
3. The pre-NR add-on is loaded by that hosted ReShade runtime for its Add-on API,
   but observes the private D3D12 NGX calls generated inside OptiScaler.
4. OptiScaler's D3D11 device vtable hooks remain disabled. Only the NGX work uses
   GIMI's private pass-through context; normal game rendering and Mods retain the
   wrapped GIMI context.
5. OptiScaler's built-in DLSSNR path is disabled. The external add-on owns the
   only Feature 18 pass and selects Mode 1 or Mode 2; both cannot run at once.

## Required compatibility fixes

### 1. Cross-API Present guard

The DX11 wrapped-swapchain Present path previously passed an
`ID3D11DeviceContext` to a D3D12 feature's timing method. The vtable slot was
misread as `PSSetConstantBuffers`, producing a misleading GIMI/D3D11 crash.
Timing and interop calls are now made only when the feature API matches DX11.

### 2. GIMI native-device and native-context trampolines

Querying a newer D3D11 context interface does not bypass GIMI's process-wide
vtable detours. GIMI publishes its existing original-context trampoline through
private GUID `91ACFD68-5A6F-45EA-B8D0-71ACC32151B7`; the DLSS-on-DX12 bridge uses
that context for NGX Create/Evaluate only.

The RTX 30 backend must allocate capability parameters and establish native NGX
before the first feature creation. A second private GUID,
`DB17DC9A-5A5A-4AC7-A4CE-EF41F7C51D5C`, exposes GIMI's original D3D11 Device.
OptiScaler uses it only for native NGX initialization/parameter objects; the game
and Mods continue through GIMI's wrapped Device and Context.

### 3. Correct FSR2 API selection

OptiScaler v0.2 defaults could select the DX12 FSR entry point. The launcher pins
`EnableFsr2Inputs`, `UseFsr2Inputs`, and `UseFsr2Dx11Inputs` to true so Genshin's
actual DX11 carrier is translated.

### 4. Shareable color format and FP16 promotion

Genshin may supply R8/R10/R11 packed or typeless resources. The compatibility
build maintains both typed and untyped D3D12 parameter slots and promotes these
formats to `R16G16B16A16_FLOAT` when the add-on/NGX contract requires it. Mode 2
uses the FP16 carrier before Feature 1; Mode 1 uses an FP16 output carrier after
Feature 1, then copies the completed NR result back to the game's output resource.

The conversion, Feature 18, and Feature 1 are submitted on the same D3D12
command list, so their order is guaranteed before the DX12-to-DX11 copyback.

### 5. Private bridge name collision

OptiScaler's generic NGX DLL check intentionally uses suffix matching.
`nrchain_nvngx.dll` therefore matched `_nvngx.dll` and was replaced with the
OptiScaler module handle; all four `NRChain_*` lookups then failed. The patched
loader excludes the exact filename `nrchain_nvngx.dll`, while retaining normal
`nvngx.dll` and `_nvngx.dll` interception.

### 6. Hosted ReShade HDR color-space handoff

Disabling ReShade's own graphics hooks also disables its normal interception of
`IDXGISwapChain3::SetColorSpace1`. Without an explicit handoff, the hosted
runtime treated GIMI's `R10G10B10A2_UNORM` HDR10/PQ back buffer as sRGB and
saved washed-out, untagged 8-bit screenshots. Before the hosted runtime is
created, GIMI now attaches `DXGI_COLOR_SPACE_RGB_FULL_G2084_NONE_P2020` through
ReShade's swap-chain private-data contract. Effects and Before/After capture
therefore see the same color space they would under ReShade's normal DXGI hook;
HDR PNG output is 16-bit and carries BT.2020/PQ metadata.

## Failure behavior

Mode 2 creates Feature 18 at the render extent, runs it into a temporary
low-resolution color resource, and passes that resource to original Feature 1.
Mode 1 first completes original Feature 1 and then runs output-resolution Feature
18. If Feature 18 creation or evaluation fails, the add-on preserves the original
DLSS result. It never substitutes an incomplete NR output.

## Hard success criteria

A valid run must show all of the following in one session:

- GIMI pass-through Device/Context resolved, native NGX parameters allocated, and D3D12 Feature 1 created.
- The selected RTX profile's `nrchain` and `nvngx_dlssnr.dll` form the intended pair.
- Signed DLSSNR runtime initialized through `nrchain_nvngx.dll`.
- Mode 2: Feature 18 is 1:1 at render resolution and `NR-before-SR evaluate succeeded` grows continuously.
- Mode 1: Feature 1 reaches output resolution, Feature 18 is created at that output extent, and `NR-after-SR evaluate succeeded` grows continuously.
- ReShade add-on registration and shader compilation succeed.
- The game remains responsive and GIMI remains the final Present owner.
