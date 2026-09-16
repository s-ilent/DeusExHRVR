# TODO — Luma port (deferred)

Tracked here because GitHub Issues are disabled on this repo.

## 1. Phase 3e: SMAA draw passes — WON'T DO (incompatible with VR config)

**Status:** Not implementable under DXHRVR's required configuration.

**Rationale:** The VR mod requires `AntiAliasingMode=0` (set by the installer,
confirmed in README) because the game's built-in AA conflicts with the native
stereo renderer's double-height buffer. Luma's SMAA replaces the game's MLAA,
which is itself an AA pass — so when `AntiAliasingMode=0`, the MLAA-mask draw
(`0x6B0219A1`, the SMAA trigger) doesn't fire. Even if it did, running SMAA on
the double-height stereo buffer would AA across the eye seam. The same applies
to Luma's FXAA replacement (`0xFF6E347A`).

Luma's SMAA was designed for the mono desktop pipeline (one eye, AA on).
Neither holds in DXHRVR.

**Alternative paths for VR AA** (not Luma ports, separate DXHRVR features):
- Engine-level MSAA on the stereo render targets (would need DXHRVR support)
- Post-composition AA on the final OpenXR swapchain in the 64-bit host

**Action:** `RunSMAA` stays a stub returning false. The SMAA trigger detection
in `LumaPasses::OnDraw` is left in place (harmless — it logs but does nothing).
The `Luma_SMAA_Linearize` CS and `Luma_SMAA_impl.hlsl` are kept in the shader
tree in case a future DXHRVR config allows AA.

## 2. Phase 4: overlap dedup with DXHRVR stereo corrections — DONE

**Status:** Implemented. `ShaderSwap::TrySubstitutePS` now accepts a
`dxhrvrCorrected` flag (computed in `RenderStateHook` via
`EffectShader::UsesCentreViewMatrix`) and skips substitution when
`DedupWithDXHRVR=1` (default). Also auto-skips SSAO generation hashes when
XeGTAO is enabled. Manual skip-list via `AddSkipHash()`. Skips logged to
`DeusExHRVR-shaderswap.log`.

**Needs in-headset verification:** The auto-skip covers projected light/shadow
(`UsesCentreViewMatrix`) + SSAO gen. Other shaders (sky, additive transparent
geom) may also need skipping — test with `DedupWithDXHRVR=0` vs `=1` and
add to `skipHashes` if stereo breaks.

## Done

- ~~Wire LumaSettings cbuffer (LightingColor etc.)~~ — Done. `src/LumaSettingsCB.h`
  mirrors the HLSL cbuffer layout (global settings + DXHR GameSettings at b13).
  Created as a dynamic cbuffer, updated via Map(DISCARD), bound before Phase 2
  substitution (PS) and Phase 3 injected passes (CS for XeGTAO, PS for
  ModulateLighting). Ini-configurable intensities with Luma's defaults.
