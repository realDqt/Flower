#pragma once
#include "DDGICompute.hpp"

class ProbeBlendIrradianceCompute : public DDGICompute{
public:
    ProbeBlendIrradianceCompute(
            VkDevice _device,
            VkPipelineCache _pipelineCache,
            vks::Buffer* _pDDGIVolumes,
            vks::Texture* _pProbeIrradiance,
            vks::Texture* _pRayData,
            vks::Texture* _pProbeData
            ): DDGICompute(
                    _device,
                    _pipelineCache
                    ){
        pDDGIVolumes = _pDDGIVolumes;
        pProbeIrradiance = _pProbeIrradiance;
        pRayData = _pRayData;
        pProbeData = _pProbeData;
    }

    void recordCommandBuffer(VkCommandBuffer cmdBuffer, uint32_t currentBuffer) override{
        vkCmdBindPipeline(cmdBuffer, VK_PIPELINE_BIND_POINT_COMPUTE, pipeline);
        vkCmdBindDescriptorSets(cmdBuffer, VK_PIPELINE_BIND_POINT_COMPUTE, pipelineLayout, 0, 1, &descriptorSets[currentBuffer], 0, 0);


        uint32_t probeCountX, probeCountY, probeCountZ;
        getDDGIVolumeProbeCounts(*getGlobalDDGIVolumeDescGPU(), probeCountX, probeCountY, probeCountZ);

        vkCmdDispatch(cmdBuffer, probeCountX, probeCountY, probeCountZ);

        // probe irradiance
        VkImageSubresourceRange subresourceRange = { VK_IMAGE_ASPECT_COLOR_BIT, 0, 1, 0, pProbeIrradiance->layerCount };
        VkImageMemoryBarrier irradianceBarrier{};
        irradianceBarrier.subresourceRange = subresourceRange;
        irradianceBarrier.image = pProbeIrradiance->image;
        irradianceBarrier.srcAccessMask = VK_ACCESS_SHADER_READ_BIT | VK_ACCESS_SHADER_WRITE_BIT;
        irradianceBarrier.dstAccessMask = VK_ACCESS_SHADER_READ_BIT;
        irradianceBarrier.oldLayout = VK_IMAGE_LAYOUT_GENERAL;
        irradianceBarrier.newLayout = VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL;
        irradianceBarrier.srcQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED;
        irradianceBarrier.dstQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED;
        pProbeIrradiance->imageLayout = VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL;

        vkCmdPipelineBarrier(
                cmdBuffer,
                VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT,
                VK_PIPELINE_STAGE_RAY_TRACING_SHADER_BIT_KHR,
                0,
                0, nullptr,
                0, nullptr,
                1, &irradianceBarrier);
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

        pProbeIrradiance->updateDescriptor();
        pRayData->updateDescriptor();
        pProbeData->updateDescriptor();
        for (auto i = 0; i < maxConcurrentFrames; i++) {
            VkDescriptorSetAllocateInfo allocInfo = vks::initializers::descriptorSetAllocateInfo(descriptorPool, &descriptorSetLayout, 1);
            VK_CHECK_RESULT(vkAllocateDescriptorSets(device, &allocInfo, &descriptorSets[i]));
            std::vector<VkWriteDescriptorSet> computeWriteDescriptorSets = {
                    vks::initializers::writeDescriptorSet(descriptorSets[i], VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, 0, &pDDGIVolumes->descriptor),
                    vks::initializers::writeDescriptorSet(descriptorSets[i], VK_DESCRIPTOR_TYPE_STORAGE_IMAGE, 1, &pProbeIrradiance->descriptor),
                    vks::initializers::writeDescriptorSet(descriptorSets[i], VK_DESCRIPTOR_TYPE_STORAGE_IMAGE, 2, &pRayData->descriptor),
                    vks::initializers::writeDescriptorSet(descriptorSets[i], VK_DESCRIPTOR_TYPE_STORAGE_IMAGE, 3, &pProbeData->descriptor),
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
    vks::Texture* pProbeIrradiance;
    vks::Texture* pRayData;
    vks::Texture* pProbeData;
};