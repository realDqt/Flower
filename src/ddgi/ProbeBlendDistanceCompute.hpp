#pragma once
#include "DDGICompute.hpp"

class ProbeBlendDistanceCompute : public DDGICompute{
public:
    ProbeBlendDistanceCompute(
            VkDevice _device,
            VkPipelineCache _pipelineCache,
            vks::Buffer* _pDDGIVolumes,
            vks::Texture* _pProbeDistance,
            vks::Texture* _pRayData
    ): DDGICompute(
            _device,
            _pipelineCache
    ){
        pDDGIVolumes = _pDDGIVolumes;
        pProbeDistance = _pProbeDistance;
        pRayData = _pRayData;
    }

    void recordCommandBuffer(VkCommandBuffer cmdBuffer, uint32_t currentBuffer) override{
        vkCmdBindPipeline(cmdBuffer, VK_PIPELINE_BIND_POINT_COMPUTE, pipeline);
        vkCmdBindDescriptorSets(cmdBuffer, VK_PIPELINE_BIND_POINT_COMPUTE, pipelineLayout, 0, 1, &descriptorSets[currentBuffer], 0, 0);


        uint32_t probeCountX, probeCountY, probeCountZ;
        getDDGIVolumeProbeCounts(*getGlobalDDGIVolumeDescGPU(), probeCountX, probeCountY, probeCountZ);

        vkCmdDispatch(cmdBuffer, probeCountX, probeCountY, probeCountZ);

        // probe distance
        VkImageSubresourceRange subresourceRange = { VK_IMAGE_ASPECT_COLOR_BIT, 0, 1, 0, pProbeDistance->layerCount };
        vks::tools::setImageLayout(
                cmdBuffer,
                pProbeDistance->image,
                VK_IMAGE_LAYOUT_GENERAL,
                VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL,

                subresourceRange,
                VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT,
                VK_PIPELINE_STAGE_RAY_TRACING_SHADER_BIT_KHR
        );
        pProbeDistance->imageLayout = VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL;


        // ray data
        subresourceRange.layerCount = pRayData->layerCount;
        VkImageMemoryBarrier rayDataBarrier{};
        rayDataBarrier.subresourceRange = subresourceRange;
        rayDataBarrier.image = pRayData->image;
        rayDataBarrier.srcAccessMask = VK_ACCESS_SHADER_READ_BIT;
        rayDataBarrier.dstAccessMask = VK_ACCESS_SHADER_WRITE_BIT;
        rayDataBarrier.oldLayout = VK_IMAGE_LAYOUT_GENERAL;
        rayDataBarrier.newLayout = VK_IMAGE_LAYOUT_GENERAL;
        rayDataBarrier.srcQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED;
        rayDataBarrier.dstQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED;

        vkCmdPipelineBarrier(
                cmdBuffer,
                VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT,
                VK_PIPELINE_STAGE_RAY_TRACING_SHADER_BIT_KHR,
                0,
                0, nullptr,
                0, nullptr,
                1, &rayDataBarrier);

    }

    void prepare() override{
        std::vector<VkDescriptorPoolSize> poolSizes = {
                { VK_DESCRIPTOR_TYPE_STORAGE_IMAGE, maxConcurrentFrames * 2},
                { VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, maxConcurrentFrames}
        };
        VkDescriptorPoolCreateInfo descriptorPoolCreateInfo = vks::initializers::descriptorPoolCreateInfo(poolSizes, maxConcurrentFrames);
        VK_CHECK_RESULT(vkCreateDescriptorPool(device, &descriptorPoolCreateInfo, nullptr, &descriptorPool));


        std::vector<VkDescriptorSetLayoutBinding> setLayoutBindings = {
                vks::initializers::descriptorSetLayoutBinding(VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, VK_SHADER_STAGE_COMPUTE_BIT, 0),
                vks::initializers::descriptorSetLayoutBinding(VK_DESCRIPTOR_TYPE_STORAGE_IMAGE, VK_SHADER_STAGE_COMPUTE_BIT, 1),
                vks::initializers::descriptorSetLayoutBinding(VK_DESCRIPTOR_TYPE_STORAGE_IMAGE, VK_SHADER_STAGE_COMPUTE_BIT, 2),
        };
        VkDescriptorSetLayoutCreateInfo descriptorLayout = vks::initializers::descriptorSetLayoutCreateInfo(setLayoutBindings);
        VK_CHECK_RESULT(vkCreateDescriptorSetLayout(device, &descriptorLayout, nullptr,	&descriptorSetLayout));

        pProbeDistance->updateDescriptor();
        pRayData->updateDescriptor();
        for (auto i = 0; i < maxConcurrentFrames; i++) {
            VkDescriptorSetAllocateInfo allocInfo = vks::initializers::descriptorSetAllocateInfo(descriptorPool, &descriptorSetLayout, 1);
            VK_CHECK_RESULT(vkAllocateDescriptorSets(device, &allocInfo, &descriptorSets[i]));
            std::vector<VkWriteDescriptorSet> computeWriteDescriptorSets = {
                    vks::initializers::writeDescriptorSet(descriptorSets[i], VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, 0, &pDDGIVolumes->descriptor),
                    vks::initializers::writeDescriptorSet(descriptorSets[i], VK_DESCRIPTOR_TYPE_STORAGE_IMAGE, 1, &pProbeDistance->descriptor),
                    vks::initializers::writeDescriptorSet(descriptorSets[i], VK_DESCRIPTOR_TYPE_STORAGE_IMAGE, 2, &pRayData->descriptor),
            };
            vkUpdateDescriptorSets(device, static_cast<uint32_t>(computeWriteDescriptorSets.size()), computeWriteDescriptorSets.data(), 0, nullptr);
        }

        // Create the compute shader pipeline
        VkPipelineLayoutCreateInfo pipelineLayoutCreateInfo = vks::initializers::pipelineLayoutCreateInfo(&descriptorSetLayout, 1);
        VK_CHECK_RESULT(vkCreatePipelineLayout(device, &pipelineLayoutCreateInfo, nullptr, &pipelineLayout));

        VkComputePipelineCreateInfo computePipelineCreateInfo = vks::initializers::computePipelineCreateInfo(pipelineLayout, 0);
        computePipelineCreateInfo.stage = loadShader(getShadersPath() + "ddgi/ProbeBlendIrradiance.comp.spv", VK_SHADER_STAGE_COMPUTE_BIT);
        VK_CHECK_RESULT(vkCreateComputePipelines(device, pipelineCache, 1, &computePipelineCreateInfo, nullptr, &pipeline));
    }


private:

    vks::Buffer* pDDGIVolumes;
    vks::Texture* pProbeDistance;
    vks::Texture* pRayData;
};