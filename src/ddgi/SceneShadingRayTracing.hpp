#pragma once
#include "utils.hpp"

class SceneShadingRayTracing
{
public:
    VkPipeline pipeline{ VK_NULL_HANDLE };
    VkPipelineLayout pipelineLayout{ VK_NULL_HANDLE };
    
    VkDescriptorSetLayout descriptorSetLayout{ VK_NULL_HANDLE };
    std::array<VkDescriptorSet, maxConcurrentFrames> descriptorSets{};

    struct UniformData {
        glm::mat4 viewInverse;
        glm::mat4 projInverse;
        uint32_t frame{ 0 };
    } uniformData;
    std::array<vks::Buffer, maxConcurrentFrames> uniformBuffers;

    std::vector<VkRayTracingShaderGroupCreateInfoKHR> shaderGroups{};
    ShaderBindingTables shaderBindingTables;
};
