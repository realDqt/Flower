#ifndef COMMON_HPP
#define COMMON_HPP
#include "VulkanRaytracingSample.h"
#define VK_GLTF_MATERIAL_IDS
#include "VulkanglTFModel.h"

#include "Light.hpp"

// 强制所有 vec3 升级为 vec4，确保 100% 内存安全
struct Sample
{
    // xyzw: w 分量可以留作 padding，或者存别的（比如材质ID）
    glm::vec4 x_v;       // Offset 0
    glm::vec4 n_v;       // Offset 16
    glm::vec4 x_s;       // Offset 32
    glm::vec4 n_s;       // Offset 48
    glm::vec4 Lo;        // Offset 64 (w分量闲置，或者存Random?)
    glm::vec4 baseColor_v;
    
    uint32_t Random;     // Offset 96 (紧跟在 Lo 的 16字节之后)
    uint32_t _pad[3];    // Offset 100-112 (手动填充到 16 字节对齐)
};

// 确保 C++ 编译器对 Sample 的理解也是 16 字节对齐
static_assert(sizeof(Sample) % 16 == 0, "Sample size alignment error");

struct Reservoir
{
    Sample z;            // Offset 0, Size 112
    float w = 0.0f;             // Offset 112
    uint32_t M = 0;          // Offset 116
    float W = 0.0f;             // Offset 120
    uint32_t _pad;       // Offset 124-128 (手动填充，凑整结构体)
};

struct ShaderBindingTables {
    ShaderBindingTable raygen;
    ShaderBindingTable miss;
    ShaderBindingTable hit;
};

// Resources for the initial sample
struct InitialSampleRayTracing
{
    std::vector<VkRayTracingShaderGroupCreateInfoKHR> shaderGroups{};
    ShaderBindingTables shaderBindingTables;
    VkPipeline pipeline{ VK_NULL_HANDLE };
    VkPipelineLayout pipelineLayout{ VK_NULL_HANDLE };
    VkDescriptorSetLayout descriptorSetLayout{ VK_NULL_HANDLE };
    std::array<VkDescriptorSet, maxConcurrentFrames> descriptorSets{};
};

// Resources for the compute part of the example
struct TemporalReuseCompute {
    VkDescriptorSetLayout descriptorSetLayout{ VK_NULL_HANDLE };		// Compute shader binding layout
    VkPipelineLayout pipelineLayout{ VK_NULL_HANDLE };					// Layout of the compute pipeline
    VkPipeline pipeline{ VK_NULL_HANDLE };								// Compute raytracing pipeline
    std::array<VkDescriptorSet, maxConcurrentFrames> descriptorSets{};
};

// Resources for the spatial reuse
struct SpatialReuseRayTracing
{
    std::vector<VkRayTracingShaderGroupCreateInfoKHR> shaderGroups{};
    ShaderBindingTables shaderBindingTables;
    VkPipeline pipeline{ VK_NULL_HANDLE };
    VkPipelineLayout pipelineLayout{ VK_NULL_HANDLE };
    VkDescriptorSetLayout descriptorSetLayout{ VK_NULL_HANDLE };
    std::array<VkDescriptorSet, maxConcurrentFrames> descriptorSets{};
};

constexpr float Z_NEAR = 0.1f;
constexpr float Z_FAR = 512.0f;
#endif
