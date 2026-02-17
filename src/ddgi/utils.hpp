#pragma once
#include "VulkanRaytracingSample.h"
#define VK_GLTF_MATERIAL_IDS
#include "VulkanglTFModel.h"
#include "VulkanObjModel.h"


constexpr uint32_t width = 1280;
constexpr uint32_t height = 720;

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
};

inline std::string getShadersPath()
{
    std::string shaderDir = "glsl";
    return getShaderBasePath() + shaderDir + "/";
}

