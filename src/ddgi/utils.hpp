#pragma once
#include "VulkanRaytracingSample.h"
#define VK_GLTF_MATERIAL_IDS
#include "VulkanglTFModel.h"

inline void printVec3(const glm::vec3& rhs)
{
    std::cout << rhs.x << " " << rhs.y << " " << rhs.z << "\n";
}

struct ShaderBindingTables {
    ShaderBindingTable raygen;
    ShaderBindingTable miss;
    ShaderBindingTable hit;
};

struct GeometryNode {
    uint64_t vertexBufferDeviceAddress;
    uint64_t indexBufferDeviceAddress;
    int32_t textureIndexBaseColor;
    int32_t textureIndexOcclusion;
};
