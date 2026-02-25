#pragma once
#include "DDGICompute.hpp"

class ProbeBlendDistanceCompute : public DDGICompute{
public:
    ProbeBlendDistanceCompute(
            VkDevice _device,
            VkPipelineCache _pipelineCache,
            vks::Buffer* _pDDGIVolumes,
            vks::Texture* _pProbeDistance,
            vks::Texture* _pRayData,
            vks::Texture* _pProbeData
    ): DDGICompute(
            _device,
            _pipelineCache
    ){
        pDDGIVolumes = _pDDGIVolumes;
        pProbeDistance = _pProbeDistance;
        pRayData = _pRayData;
        pProbeData = _pProbeData;
    }

    void recordCommandBuffer(VkCommandBuffer cmdBuffer, uint32_t currentBuffer) override{
        vkCmdBindPipeline(cmdBuffer, VK_PIPELINE_BIND_POINT_COMPUTE, pipeline);
        vkCmdBindDescriptorSets(cmdBuffer, VK_PIPELINE_BIND_POINT_COMPUTE, pipelineLayout, 0, 1, &descriptorSets[currentBuffer], 0, 0);


        uint32_t probeCountX, probeCountY, probeCountZ;
        getDDGIVolumeProbeCounts(*getGlobalDDGIVolumeDescGPU(), probeCountX, probeCountY, probeCountZ);

        vkCmdDispatch(cmdBuffer, probeCountX, probeCountY, probeCountZ);

        // probe distance
        VkImageSubresourceRange subresourceRange = { VK_IMAGE_ASPECT_COLOR_BIT, 0, 1, 0, pProbeDistance->layerCount };
        VkImageMemoryBarrier distanceBarrier{};
        distanceBarrier.subresourceRange = subresourceRange;
        distanceBarrier.image = pProbeDistance->image;
        distanceBarrier.srcAccessMask = VK_ACCESS_SHADER_READ_BIT | VK_ACCESS_SHADER_WRITE_BIT;
        distanceBarrier.dstAccessMask = VK_ACCESS_SHADER_READ_BIT;
        distanceBarrier.oldLayout = VK_IMAGE_LAYOUT_GENERAL;
        distanceBarrier.newLayout = VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL;
        distanceBarrier.srcQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED;
        distanceBarrier.dstQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED;
        pProbeDistance->imageLayout = VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL;
        vkCmdPipelineBarrier(
                cmdBuffer,
                VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT,
                VK_PIPELINE_STAGE_RAY_TRACING_SHADER_BIT_KHR,
                0,
                0, nullptr,
                0, nullptr,
                1, &distanceBarrier);

        // probe data
        subresourceRange.layerCount = pProbeData->layerCount;
        VkImageMemoryBarrier dataBarrier{};
        dataBarrier.subresourceRange = subresourceRange;
        dataBarrier.image = pProbeData->image;
        dataBarrier.srcAccessMask = VK_ACCESS_SHADER_READ_BIT;
        dataBarrier.dstAccessMask = VK_ACCESS_SHADER_READ_BIT | VK_ACCESS_SHADER_WRITE_BIT;
        dataBarrier.oldLayout = VK_IMAGE_LAYOUT_GENERAL;
        dataBarrier.newLayout = VK_IMAGE_LAYOUT_GENERAL;
        dataBarrier.srcQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED;
        dataBarrier.dstQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED;

        vkCmdPipelineBarrier(
                cmdBuffer,
                VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT,
                VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT,
                0,
                0, nullptr,
                0, nullptr,
                1, &dataBarrier);

    }

    void prepare() override{
        std::vector<VkDescriptorPoolSize> poolSizes = {
                { VK_DESCRIPTOR_TYPE_STORAGE_IMAGE, maxConcurrentFrames * 3},
                { VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, maxConcurrentFrames}
        };
        VkDescriptorPoolCreateInfo descriptorPoolCreateInfo = vks::initializers::descriptorPoolCreateInfo(poolSizes, maxConcurrentFrames);
        VK_CHECK_RESULT(vkCreateDescriptorPool(device, &descriptorPoolCreateInfo, nullptr, &descriptorPool));


        std::vector<VkDescriptorSetLayoutBinding> setLayoutBindings = {
                vks::initializers::descriptorSetLayoutBinding(VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, VK_SHADER_STAGE_COMPUTE_BIT, 0),
                vks::initializers::descriptorSetLayoutBinding(VK_DESCRIPTOR_TYPE_STORAGE_IMAGE, VK_SHADER_STAGE_COMPUTE_BIT, 1),
                vks::initializers::descriptorSetLayoutBinding(VK_DESCRIPTOR_TYPE_STORAGE_IMAGE, VK_SHADER_STAGE_COMPUTE_BIT, 2),
                vks::initializers::descriptorSetLayoutBinding(VK_DESCRIPTOR_TYPE_STORAGE_IMAGE, VK_SHADER_STAGE_COMPUTE_BIT, 3),
        };
        VkDescriptorSetLayoutCreateInfo descriptorLayout = vks::initializers::descriptorSetLayoutCreateInfo(setLayoutBindings);
        VK_CHECK_RESULT(vkCreateDescriptorSetLayout(device, &descriptorLayout, nullptr,	&descriptorSetLayout));

        pProbeDistance->updateDescriptor();
        pRayData->updateDescriptor();
        pProbeData->updateDescriptor();
        for (auto i = 0; i < maxConcurrentFrames; i++) {
            VkDescriptorSetAllocateInfo allocInfo = vks::initializers::descriptorSetAllocateInfo(descriptorPool, &descriptorSetLayout, 1);
            VK_CHECK_RESULT(vkAllocateDescriptorSets(device, &allocInfo, &descriptorSets[i]));
            std::vector<VkWriteDescriptorSet> computeWriteDescriptorSets = {
                    vks::initializers::writeDescriptorSet(descriptorSets[i], VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, 0, &pDDGIVolumes->descriptor),
                    vks::initializers::writeDescriptorSet(descriptorSets[i], VK_DESCRIPTOR_TYPE_STORAGE_IMAGE, 1, &pProbeDistance->descriptor),
                    vks::initializers::writeDescriptorSet(descriptorSets[i], VK_DESCRIPTOR_TYPE_STORAGE_IMAGE, 2, &pRayData->descriptor),
                    vks::initializers::writeDescriptorSet(descriptorSets[i], VK_DESCRIPTOR_TYPE_STORAGE_IMAGE, 3, &pProbeData->descriptor),
            };
            vkUpdateDescriptorSets(device, static_cast<uint32_t>(computeWriteDescriptorSets.size()), computeWriteDescriptorSets.data(), 0, nullptr);
        }

        // Create the compute shader pipeline
        VkPipelineLayoutCreateInfo pipelineLayoutCreateInfo = vks::initializers::pipelineLayoutCreateInfo(&descriptorSetLayout, 1);
        VK_CHECK_RESULT(vkCreatePipelineLayout(device, &pipelineLayoutCreateInfo, nullptr, &pipelineLayout));

        VkComputePipelineCreateInfo computePipelineCreateInfo = vks::initializers::computePipelineCreateInfo(pipelineLayout, 0);
        computePipelineCreateInfo.stage = loadShader(getShadersPath() + "ddgi/ProbeBlendDistance.comp.spv", VK_SHADER_STAGE_COMPUTE_BIT);
        VK_CHECK_RESULT(vkCreateComputePipelines(device, pipelineCache, 1, &computePipelineCreateInfo, nullptr, &pipeline));
    }


private:

    vks::Buffer* pDDGIVolumes;
    vks::Texture* pProbeDistance;
    vks::Texture* pRayData;
    vks::Texture* pProbeData;
};