#pragma once
#include "Utils.hpp"

class DDGICompute{
public:
    DDGICompute(
            VkDevice _device,
            VkPipelineCache _pipelineCache
            ){
        device = _device;
        pipelineCache = _pipelineCache;
    }

    virtual ~DDGICompute(){
        vkDestroyPipeline(device, pipeline, nullptr);
        vkDestroyPipelineLayout(device, pipelineLayout, nullptr);
        vkDestroyDescriptorSetLayout(device, descriptorSetLayout, nullptr);
        vkDestroyDescriptorPool(device, descriptorPool, nullptr);
    }

    virtual void recordCommandBuffer(VkCommandBuffer cmdBuffer, uint32_t currentBuffer) = 0;
    virtual void prepare() = 0;

    VkPipelineShaderStageCreateInfo loadShader(std::string fileName, VkShaderStageFlagBits stage)
    {
        VkPipelineShaderStageCreateInfo shaderStage{
                .sType = VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
                .stage = stage,
                .pName = "main"
        };
#if defined(VK_USE_PLATFORM_ANDROID_KHR)
        shaderStage.module = vks::tools::loadShader(androidApp->activity->assetManager, fileName.c_str(), device);
#else
        shaderStage.module = vks::tools::loadShader(fileName.c_str(), device);
#endif
        assert(shaderStage.module != VK_NULL_HANDLE);
        return shaderStage;
    }

    VkDescriptorPool descriptorPool{VK_NULL_HANDLE};
    VkDescriptorSetLayout descriptorSetLayout{ VK_NULL_HANDLE };		// Compute shader binding layout
    VkPipelineLayout pipelineLayout{ VK_NULL_HANDLE };					// Layout of the compute pipeline
    VkPipeline pipeline{ VK_NULL_HANDLE };								// Compute raytracing pipeline
    std::array<VkDescriptorSet, maxConcurrentFrames> descriptorSets{};


    VkDevice device{VK_NULL_HANDLE};
    VkPipelineCache pipelineCache{VK_NULL_HANDLE};
};