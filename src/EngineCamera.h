#pragma once
#include <cstdint>
#include "SharedPair.h"
struct ID3D11Device;
namespace EngineCamera {
Transport::RenderInfo OnPresent(uint64_t frame, bool capture);
void SetChannel(Transport::Header* header);
// Luma port: forward the engine's D3D11 device to ShaderSwap so it can build
// replacement shaders and issue PSSetShader overrides. Called from
// NativeTransport::Producer::Init once the device is first available.
void SetShaderSwapDevice(ID3D11Device* device);
// Toggle live shader substitution (F12). Returns the new state.
bool ToggleShaderSubstitution();
}
