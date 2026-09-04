# RC2 pre-NR integration audit

Validated on 2026-09-04 with Genshin Impact DX11, RTX 5080, NVIDIA driver
616.56, 3840x2160 output and 0.8 render scale.

## Goal

Preserve the already-working GIMI + hosted ReShade + DLSS integration, while
moving DLSS5 Neural Rendering from a native-resolution post-pass to a true
render-resolution pass before the original DLSS Super Resolution operation.

## Experiments

| Run | Result | Decisive finding |
| --- | --- | --- |
| 01 | Failed before usable dispatch | OptiScaler v0.2 selected the FSR2 DX12 input path; Genshin exposes the DX11 contract. |
| 02 | Stable DLSS-on-DX12, NR rejected | D3D12 Feature 1 and GIMI pass-through worked, but add-on received typeless color format 23. |
| 03 | Stable DLSS-on-DX12, NR rejected | Typed R10 format 24 was shareable but still outside the add-on's accepted format rule. |
| 04 | Stable SR, NR disabled | FP16 promotion worked; the add-on reported incomplete NR runtime exports. |
| 05 | Same failure | Adding a DLL search path did not help because the add-on already loads companions by absolute path. |
| 06 | Success | Exact exclusion for `nrchain_nvngx.dll` fixed the OptiScaler suffix-name collision; Feature 18 and Feature 1 then ran continuously in the intended order. |

## Reverse-engineered format rule

The add-on's pre-SR acceptance logic masks bit 4 of the DXGI format and compares
the result to 10. In practice it accepts format 10 (`R16G16B16A16_FLOAT`) and
format 26 (`R11G11B10_FLOAT`). Genshin's shared R10 carrier is therefore promoted
to FP16 with OptiScaler's existing `FT_Dx12` compute transfer before Feature 18.

## Loader collision

The add-on successfully loaded the signed runtime and private bridge paths, but
OptiScaler's generic suffix check interpreted `nrchain_nvngx.dll` as
`_nvngx.dll` and returned OptiScaler's own module. The non-null module handle
made this look like an export failure. An exact private-bridge exclusion restored
the expected `NRChain_Init`, `NRChain_Create`, `NRChain_Evaluate`, and
`NRChain_Release` exports without changing normal NGX interception.

## Successful evidence

The successful development run was archived as
`run-06-success-pre-nr-then-dlss-sr`. Raw multi-megabyte logs are intentionally
excluded from the clean distribution; the decisive excerpts are retained here.

Decisive log sequence:

```text
Color ... physical=3072x1728 format=10(R16G16B16A16_FLOAT)
signed DLSSNR D3D12 runtime initialized through nrchain_nvngx.dll
signed feature 18 create 3072x1728 -> 3072x1728 ... Success
NR-before-SR evaluate succeeded: count=1 extent=3072x1728
...
[stats] all NGX evaluations=3600 ... feature=1(SuperSampling)
NR-before-SR evaluate succeeded: count=3600 extent=3072x1728
```

OptiScaler simultaneously recorded Feature 1 as:

```text
Render Size: 3072x1728, Target Size: 3840x2160, Display Size: 3840x2160
```

`Verify-Installation.ps1 -LastRun` returned:

```text
Last-run diagnostic: render-resolution NR succeeded before the original DLSS SR pass.
```

ReShade registered the Chinese pre-NR add-on and compiled FakeHDR; the game was
still responsive after more than 3600 successful NR frames. No GIMI ownership,
final Present, or original DLSS fallback behavior was changed.

## Hosted ReShade HDR screenshot correction

The hosted runtime disables ReShade's normal DXGI graphics hooks so GIMI can
remain the sole swap-chain owner. That also bypassed ReShade's usual
`SetColorSpace1` observation: an R10 HDR10/PQ back buffer was misclassified as
sRGB, and Before/After screenshots were written as untagged 8-bit PNG files.

GIMI now publishes the final swap chain's HDR10/PQ color space through the same
private-data contract used by ReShade's normal DXGI path before creating the
hosted runtime. The isolated validation run preserved continuous pre-NR and
Feature 1 execution and changed both screenshot stages from 8-bit/no-cICP to
16-bit RGB PNG with cICP `9,16,0,1` (BT.2020 primaries, PQ transfer, RGB matrix,
full range) at 3840x2160.

## Remaining scope

- The bundled signed DLSSNR runtime is currently intended for RTX 50 and 615+
  drivers; RTX 40 is not claimed.
- The exact contract is validated for the current Genshin/driver/component
  versions. Updates can change resource formats, NGX flags, or hook order.
- Performance and image preference are separate from functional correctness.
  F6 provides an immediate in-game comparison between original SR and pre-NR.
