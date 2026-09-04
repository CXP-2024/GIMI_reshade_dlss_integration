# Pre-NR then DLSS Super Resolution architecture

## Validated frame graph

```text
Genshin DX11 low-resolution FSR2 carrier
  |  Color: R10G10B10A2_UNORM, Depth: R32_FLOAT, MV: R16G16_FLOAT
  v
Dx11FsrBridge
  |  translates the game's color/depth/motion/jitter contract
  v
Patched OptiScaler v0.2 DLSS-on-DX12 bridge
  |  uses GIMI's private native-context trampoline
  |  promotes Color to R16G16B16A16_FLOAT on the same D3D12 command list
  v
nr-before-sr Mode 2 + nrchain_nvngx
  |  signed NGX Feature 18: render resolution -> render resolution
  |  replaces only the low-resolution Color parameter
  v
Original NGX Feature 1
  |  render resolution -> output resolution
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

This is one neural-rendering pass followed by one spatial-upscaling pass. It is
not two competing upscalers and is not native-resolution post-processing.

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
5. OptiScaler's built-in post-upscale DLSSNR path is disabled. Mode 2 in
   nr-before-sr owns the only Feature 18 pass, while original DLSS Feature 1 owns
   final spatial upscaling.

## Required compatibility fixes

### 1. Cross-API Present guard

The DX11 wrapped-swapchain Present path previously passed an
`ID3D11DeviceContext` to a D3D12 feature's timing method. The vtable slot was
misread as `PSSetConstantBuffers`, producing a misleading GIMI/D3D11 crash.
Timing and interop calls are now made only when the feature API matches DX11.

### 2. GIMI native-context trampoline

Querying a newer D3D11 context interface does not bypass GIMI's process-wide
vtable detours. GIMI publishes its existing original-context trampoline through
private GUID `91ACFD68-5A6F-45EA-B8D0-71ACC32151B7`; the DLSS-on-DX12 bridge uses
that context for NGX Create/Evaluate only.

### 3. Correct FSR2 API selection

OptiScaler v0.2 defaults could select the DX12 FSR entry point. The launcher pins
`EnableFsr2Inputs`, `UseFsr2Inputs`, and `UseFsr2Dx11Inputs` to true so Genshin's
actual DX11 carrier is translated.

### 4. Shareable color format and FP16 promotion

Genshin supplies `R10G10B10A2_TYPELESS`. The DX11/DX12 shared texture uses its
typed `R10G10B10A2_UNORM` view. Reverse engineering of the pre-NR add-on showed
that its acceptance rule permits only DXGI format 10 (FP16) or 26 (R11). A
built-in `FT_Dx12` compute copy therefore promotes R10 to
`R16G16B16A16_FLOAT` before the add-on sees the Feature 1 parameters.

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

The add-on's Mode 2 path creates Feature 18 at the render extent, runs it into a
temporary low-resolution color resource, and passes that resource to the
original Feature 1. If Feature 18 creation or evaluation fails, the add-on calls
the original SR contract with the untouched game color. It never substitutes an
incomplete NR output.

## Hard success criteria

A valid run must show all of the following in one session:

- GIMI pass-through context resolved and D3D12 Feature 1 created.
- Carrier Color format is `R16G16B16A16_FLOAT` when observed by nr-before-sr.
- Signed DLSSNR runtime initialized through `nrchain_nvngx.dll`.
- Feature 18 created at render resolution with identical input/output extent.
- `NR-before-SR evaluate succeeded` grows continuously.
- Feature 1 continues from render resolution to output resolution.
- ReShade add-on registration and shader compilation succeed.
- The game remains responsive and GIMI remains the final Present owner.
