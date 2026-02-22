#pragma once
#include "VulkanRaytracingSample.h"
#define VK_GLTF_MATERIAL_IDS
#include "VulkanglTFModel.h"
#include "VulkanObjModel.h"

constexpr uint32_t width = 1280;
constexpr uint32_t height = 720;

struct ShaderBindingTables {
    ShaderBindingTable raygen;
    ShaderBindingTable miss;
    ShaderBindingTable hit;
};

struct GeometryNode {
    uint64_t vertexBufferDeviceAddress;
    uint64_t indexBufferDeviceAddress;
};


enum class EDDGIVolumeTextureType
{
    RayData = 0,
    Irradiance,
    Distance,
    Data,
    Variability,
    VariabilityAverage,
    Count
};

#define DDGI_PROBE_DEPTH_WITH_BORDER_SIDE 18
#define DDGI_PROBE_DEPTH_SIDE 16
#define DDGI_PROBE_IRRADIANCE_WITH_BORDER_SIDE 10
#define DDGI_PROBE_IRRADIANCE_SIDE 8
