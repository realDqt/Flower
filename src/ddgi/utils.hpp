#pragma once
#include "VulkanRaytracingSample.h"
#define VK_GLTF_MATERIAL_IDS
#include "VulkanglTFModel.h"

inline void printVec3(const glm::vec3& rhs)
{
    std::cout << rhs.x << " " << rhs.y << " " << rhs.z << "\n";
}

constexpr VkFormat shadowMapDepthFormat{ VK_FORMAT_D16_UNORM };
constexpr uint32_t shadowMapSize{ 2048 };
// Keep depth range as small as possible
// for better shadow map precision
constexpr float zNear = 1.0f;
constexpr float zFar = 96.0f;

// Depth bias (and slope) are used to avoid shadowing artifacts
// Constant depth bias factor (always applied)
constexpr float depthBiasConstant = 1.25f;
// Slope depth bias factor, applied depending on polygon's slope
constexpr float depthBiasSlope = 1.75f;

// Depth Pass
struct FrameBufferAttachment {
    VkImage image;
    VkDeviceMemory mem;
    VkImageView view;
};

struct DepthPassRaster
{
    int32_t width, height;
    VkFramebuffer frameBuffer;
    FrameBufferAttachment depth;
    VkRenderPass renderPass;
    VkSampler depthSampler;
    VkDescriptorImageInfo descriptor;
    
    VkPipeline pipeline{VK_NULL_HANDLE};
    VkPipelineLayout pipelineLayout{ VK_NULL_HANDLE };
    
    std::array<VkDescriptorSet, maxConcurrentFrames> descriptorSets;

    struct UniformData {
        glm::mat4 depthMVP;
    } uniformData;
    std::array<vks::Buffer, maxConcurrentFrames> uniformBuffer;
};