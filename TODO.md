# TODO — Luma port (deferred)

Tracked here because GitHub Issues are disabled on this repo. Moved out of the
active development line to focus on GOG EXE support.

## 1. Wire LumaSettings cbuffer (LightingColor etc.)

**Status:** Phase 3f (ModulateLighting) is implemented and CI-green, but the
`LumaSettings` cbuffer that ModulateLighting (and other Luma passes) read is
not yet wired. Currently `LightingColor` defaults to `{1,1,1,1}` (white =
no-op), so ModulateLighting runs but produces no visible change.

**Task:** Wire the Luma global-settings constant buffer
(`cb_luma_global_settings` in Luma) so that `LightingColor`,
`BloomIntensity`, `AmbientLightingIntensity`, etc. actually take effect. These
should be ini-configurable (`[Luma] LightingColor=...`, etc.).

**Files:** `src/LumaPasses.cpp` (bind the cbuffer before injected passes),
`DeusExHRVR.ini.example` (new settings).

## 2. Phase 3e: SMAA draw passes

**Status:** Phase 3 stubs SMAA. Trigger detection is wired (MLAA-mask hash
`0x6B0219A1`, SupportedAA hashes), `Luma_SMAA_Linearize` CS compiles, but the
3 draw passes (edge detection → blending weight calculation → neighborhood
blending) are not implemented. `RunSMAA` returns false.

**Task:** Port Luma's `DrawSMAA` (main.cpp ~line 648 callsite + the helper).
Needs the SMAA area/search textures (Luma ships them as `SMAA_AreaTex.h` /
`SMAA_SearchTex.h` byte arrays in `Source/Core/texture_data/`). Requires 6
SMAA VS+PS shaders compiled from `Luma_SMAA_impl.hlsl`.

**Files:** `src/LumaPasses.cpp` (`RunSMAA`), `tools/compile_shaders.ps1`
(compile the 6 SMAA shader variants), `shaders/dxhr/Luma_SMAA_impl.hlsl`.

## 3. Phase 4: overlap dedup with DXHRVR stereo corrections

**Status:** DXHRVR already ships per-eye light/shadow/sky corrections
(F3/F4/F7 toggles in `EngineCamera.cpp`) that subsume part of Luma's mono
fixes — and do them stereo-correctly. Where Luma's mono shadow/lighting fixes
collide with DXHRVR's existing corrections, we should prefer DXHRVR's per-eye
versions and skip Luma's.

**Task:** Build a classification table (shader hash → "DXHRVR already handles
this stereo-correctly, skip Luma") so the two don't double-apply.

**Files:** `src/ShaderSwap.cpp` (skip-list check before substitution),
`src/EffectShader.h` (already has `UsesCentreViewMatrix` — extend).
