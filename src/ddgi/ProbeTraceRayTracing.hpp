#pragma once
#include "DDGIRayTracing.hpp"

class ProbeTraceRayTracing : public DDGIRayTracing
{
public:
    ProbeTraceRayTracing(
            VkDevice _device,
            VkPhysicalDeviceRayTracingPipelinePropertiesKHR* _rayTracingPipelineProperties,
            vks::VulkanDevice* _vulkanDevice,
            vkobj::Model* _model,
            AccelerationStructure* _bottomLevelAS,
            AccelerationStructure* _topLevelAS,
            StorageImage* _storageImage,
            vks::Buffer* _geometryNodesBuffer,
            vks::Buffer* _materialDataBuffer,
            vks::Texture* _pProbeIrradiance,
            vks::Texture* _pProbeDistance,
            vks::Texture* _pProbeData,
            vks::Texture* _pRayData,
            vks::Buffer* _pDDGIVolumes): DDGIRayTracing(
            _device,
            _rayTracingPipelineProperties,
            _vulkanDevice,
            _model,
            _bottomLevelAS,
            _topLevelAS,
            _storageImage,
            _geometryNodesBuffer,
            _materialDataBuffer
            )
    {
        pProbeIrradiance = _pProbeIrradiance;
        pProbeDistance = _pProbeDistance;
        pProbeData = _pProbeData;
        pRayData = _pRayData;
        pDDGIVolumes = _pDDGIVolumes;
    }

    void recordCommandBuffer(VkCommandBuffer cmdBuffer, uint32_t currentBuffer) override
    {
        vkCmdBindPipeline(cmdBuffer, VK_PIPELINE_BIND_POINT_RAY_TRACING_KHR, pipeline);
        vkCmdBindDescriptorSets(cmdBuffer, VK_PIPELINE_BIND_POINT_RAY_TRACING_KHR, pipelineLayout, 0, 1, &descriptorSets[currentBuffer], 0, 0);

        VkStridedDeviceAddressRegionKHR emptySbtEntry = {};
        auto pDDGIVolumeDescGPU = getGlobalDDGIVolumeDescGPU();
        uint32_t dispatchWidth, dispatchHeight, dispatchDepth;
        getRayDispatchDimensions(*pDDGIVolumeDescGPU, EDDGIVolumeTextureType::RayData, dispatchWidth, dispatchHeight, dispatchDepth);
        vkCmdTraceRaysKHR(
                cmdBuffer,
                &shaderBindingTables.raygen.stridedDeviceAddressRegion,
                &shaderBindingTables.miss.stridedDeviceAddressRegion,
                &shaderBindingTables.hit.stridedDeviceAddressRegion,
                &emptySbtEntry,
                dispatchWidth,
                dispatchHeight,
                dispatchDepth);



        // barriers
        VkImageSubresourceRange subresourceRange = { VK_IMAGE_ASPECT_COLOR_BIT, 0, 1, 0, pProbeIrradiance->layerCount };

        VkImageMemoryBarrier irradianceBarrier{};
        irradianceBarrier.subresourceRange = subresourceRange;
        irradianceBarrier.image = pProbeIrradiance->image;
        irradianceBarrier.srcAccessMask = VK_ACCESS_SHADER_READ_BIT;
        irradianceBarrier.dstAccessMask = VK_ACCESS_SHADER_READ_BIT | VK_ACCESS_SHADER_WRITE_BIT;
        irradianceBarrier.oldLayout = VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL;
        irradianceBarrier.newLayout = VK_IMAGE_LAYOUT_GENERAL;
        irradianceBarrier.srcQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED;
        irradianceBarrier.dstQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED;
        pProbeIrradiance->imageLayout = VK_IMAGE_LAYOUT_GENERAL;

        subresourceRange.layerCount = pProbeDistance->layerCount;
        VkImageMemoryBarrier distanceBarrier{};
        distanceBarrier.subresourceRange = subresourceRange;
        distanceBarrier.image = pProbeDistance->image;
        distanceBarrier.srcAccessMask = VK_ACCESS_SHADER_READ_BIT;
        distanceBarrier.dstAccessMask = VK_ACCESS_SHADER_READ_BIT | VK_ACCESS_SHADER_WRITE_BIT;
        distanceBarrier.oldLayout = VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL;
        distanceBarrier.newLayout = VK_IMAGE_LAYOUT_GENERAL;
        distanceBarrier.srcQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED;
        distanceBarrier.dstQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED;
        pProbeDistance->imageLayout = VK_IMAGE_LAYOUT_GENERAL;

        subresourceRange.layerCount = pProbeData->layerCount;
        VkImageMemoryBarrier dataBarrier{};
        dataBarrier.subresourceRange = subresourceRange;
        dataBarrier.image = pProbeData->image;
        dataBarrier.srcAccessMask = VK_ACCESS_SHADER_READ_BIT;
        dataBarrier.dstAccessMask = VK_ACCESS_SHADER_READ_BIT;
        dataBarrier.oldLayout = VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL;
        dataBarrier.newLayout = VK_IMAGE_LAYOUT_GENERAL;
        dataBarrier.srcQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED;
        dataBarrier.dstQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED;
        pProbeData->imageLayout = VK_IMAGE_LAYOUT_GENERAL;

        subresourceRange.layerCount = pRayData->layerCount;
        VkImageMemoryBarrier rayDataBarrier{};
        rayDataBarrier.subresourceRange = subresourceRange;
        rayDataBarrier.image = pRayData->image;
        rayDataBarrier.srcAccessMask = VK_ACCESS_SHADER_WRITE_BIT;
        rayDataBarrier.dstAccessMask = VK_ACCESS_SHADER_READ_BIT;
        rayDataBarrier.oldLayout = VK_IMAGE_LAYOUT_GENERAL;
        rayDataBarrier.newLayout = VK_IMAGE_LAYOUT_GENERAL;
        rayDataBarrier.srcQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED;
        rayDataBarrier.dstQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED;

        std::vector<VkImageMemoryBarrier> imageBarriers{irradianceBarrier, distanceBarrier, dataBarrier, rayDataBarrier};
        vkCmdPipelineBarrier(
                cmdBuffer,
                VK_PIPELINE_STAGE_RAY_TRACING_SHADER_BIT_KHR,
                VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT,
                0,
                0, nullptr,
                0, nullptr,
                imageBarriers.size(), imageBarriers.data());
    }

    ~ProbeTraceRayTracing() override
    {
    }

private:
    void createShaderBindingTables() {
        const uint32_t handleSize = rayTracingPipelineProperties->shaderGroupHandleSize;
        const uint32_t handleSizeAligned = vks::tools::alignedSize(rayTracingPipelineProperties->shaderGroupHandleSize, rayTracingPipelineProperties->shaderGroupHandleAlignment);
        const uint32_t groupCount = static_cast<uint32_t>(shaderGroups.size());
        const uint32_t sbtSize = groupCount * handleSizeAligned;

        std::vector<uint8_t> shaderHandleStorage(sbtSize);
        VK_CHECK_RESULT(vkGetRayTracingShaderGroupHandlesKHR(device, pipeline, 0, groupCount, sbtSize, shaderHandleStorage.data()));

        createShaderBindingTable(shaderBindingTables.raygen, 1);
        createShaderBindingTable(shaderBindingTables.miss, 2);
        createShaderBindingTable(shaderBindingTables.hit, 1);

        // Copy handles
        memcpy(shaderBindingTables.raygen.mapped, shaderHandleStorage.data(), handleSize);
        memcpy(shaderBindingTables.miss.mapped, shaderHandleStorage.data() + handleSizeAligned, handleSize * 2);
        memcpy(shaderBindingTables.hit.mapped, shaderHandleStorage.data() + handleSizeAligned * 3, handleSize);
    }

    void createRayTracingPipeline() override
    {

        std::vector<VkDescriptorSetLayoutBinding> setLayoutBindings = {
                // Binding 0: Acceleration structure
                vks::initializers::descriptorSetLayoutBinding(VK_DESCRIPTOR_TYPE_ACCELERATION_STRUCTURE_KHR, VK_SHADER_STAGE_RAYGEN_BIT_KHR | VK_SHADER_STAGE_CLOSEST_HIT_BIT_KHR, 0),
                // Binding 1: DDGIVolumeDescGPUPacked Buffer
                vks::initializers::descriptorSetLayoutBinding(VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, VK_SHADER_STAGE_RAYGEN_BIT_KHR, 1),
                // Binding 2: Probe Data
                vks::initializers::descriptorSetLayoutBinding(VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER, VK_SHADER_STAGE_RAYGEN_BIT_KHR, 2),
                // Binding 3: Probe Irradiance
                vks::initializers::descriptorSetLayoutBinding(VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER, VK_SHADER_STAGE_RAYGEN_BIT_KHR, 3),
                // Binding 4: Probe Distance
                vks::initializers::descriptorSetLayoutBinding(VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER, VK_SHADER_STAGE_RAYGEN_BIT_KHR, 4),
                // Binding 5: Ray Data
                vks::initializers::descriptorSetLayoutBinding(VK_DESCRIPTOR_TYPE_STORAGE_IMAGE, VK_SHADER_STAGE_RAYGEN_BIT_KHR, 5),
                // Binding 6: Geometry Nodes buffer
                vks::initializers::descriptorSetLayoutBinding(VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, VK_SHADER_STAGE_CLOSEST_HIT_BIT_KHR | VK_SHADER_STAGE_ANY_HIT_BIT_KHR | VK_SHADER_STAGE_RAYGEN_BIT_KHR, 6),
                // Binding 7: Base Colors buffer
                vks::initializers::descriptorSetLayoutBinding(VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, VK_SHADER_STAGE_RAYGEN_BIT_KHR | VK_SHADER_STAGE_CLOSEST_HIT_BIT_KHR, 7),
        };

        VkDescriptorSetLayoutCreateInfo descriptorSetLayoutCI = vks::initializers::descriptorSetLayoutCreateInfo(setLayoutBindings);
        VK_CHECK_RESULT(vkCreateDescriptorSetLayout(device, &descriptorSetLayoutCI, nullptr, &descriptorSetLayout));

        VkPipelineLayoutCreateInfo pPipelineLayoutCI = vks::initializers::pipelineLayoutCreateInfo(&descriptorSetLayout, 1);
        VK_CHECK_RESULT(vkCreatePipelineLayout(device, &pPipelineLayoutCI, nullptr, &pipelineLayout));


        std::vector<VkPipelineShaderStageCreateInfo> shaderStages;

        VkSpecializationMapEntry specializationMapEntry = vks::initializers::specializationMapEntry(0, 0, sizeof(uint32_t));
        uint32_t maxRecursion = 32;
        VkSpecializationInfo specializationInfo = vks::initializers::specializationInfo(1, &specializationMapEntry, sizeof(maxRecursion), &maxRecursion);


        // Ray generation group
        {
            shaderStages.push_back(loadShader(getShadersPath() + "ddgi/ProbeTrace.rgen.spv", VK_SHADER_STAGE_RAYGEN_BIT_KHR));
            // Pass recursion depth for reflections to ray generation shader via specialization constant
            shaderStages.back().pSpecializationInfo = &specializationInfo;
            VkRayTracingShaderGroupCreateInfoKHR shaderGroup{};
            shaderGroup.sType = VK_STRUCTURE_TYPE_RAY_TRACING_SHADER_GROUP_CREATE_INFO_KHR;
            shaderGroup.type = VK_RAY_TRACING_SHADER_GROUP_TYPE_GENERAL_KHR;
            shaderGroup.generalShader = static_cast<uint32_t>(shaderStages.size()) - 1;
            shaderGroup.closestHitShader = VK_SHADER_UNUSED_KHR;
            shaderGroup.anyHitShader = VK_SHADER_UNUSED_KHR;
            shaderGroup.intersectionShader = VK_SHADER_UNUSED_KHR;
            shaderGroups.push_back(shaderGroup);
        }

        // Miss group
        {
            shaderStages.push_back(loadShader(getShadersPath() + "ddgi/Miss.rmiss.spv", VK_SHADER_STAGE_MISS_BIT_KHR));
            VkRayTracingShaderGroupCreateInfoKHR shaderGroup{};
            shaderGroup.sType = VK_STRUCTURE_TYPE_RAY_TRACING_SHADER_GROUP_CREATE_INFO_KHR;
            shaderGroup.type = VK_RAY_TRACING_SHADER_GROUP_TYPE_GENERAL_KHR;
            shaderGroup.generalShader = static_cast<uint32_t>(shaderStages.size()) - 1;
            shaderGroup.closestHitShader = VK_SHADER_UNUSED_KHR;
            shaderGroup.anyHitShader = VK_SHADER_UNUSED_KHR;
            shaderGroup.intersectionShader = VK_SHADER_UNUSED_KHR;
            shaderGroups.push_back(shaderGroup);

            shaderStages.push_back(loadShader(getShadersPath() + "ddgi/Shadow.rmiss.spv", VK_SHADER_STAGE_MISS_BIT_KHR));
            shaderGroup.generalShader = static_cast<uint32_t>(shaderStages.size()) - 1;
            shaderGroups.push_back(shaderGroup);
        }

        // Closest hit group
        {
            shaderStages.push_back(loadShader(getShadersPath() + "ddgi/ProbeTrace.rchit.spv", VK_SHADER_STAGE_CLOSEST_HIT_BIT_KHR));
            VkRayTracingShaderGroupCreateInfoKHR shaderGroup{};
            shaderGroup.sType = VK_STRUCTURE_TYPE_RAY_TRACING_SHADER_GROUP_CREATE_INFO_KHR;
            shaderGroup.type = VK_RAY_TRACING_SHADER_GROUP_TYPE_TRIANGLES_HIT_GROUP_KHR;
            shaderGroup.generalShader = VK_SHADER_UNUSED_KHR;
            shaderGroup.closestHitShader = static_cast<uint32_t>(shaderStages.size()) - 1;
            shaderGroup.anyHitShader = VK_SHADER_UNUSED_KHR;
            shaderGroup.intersectionShader = VK_SHADER_UNUSED_KHR;
            shaderGroups.push_back(shaderGroup);
        }

        VkRayTracingPipelineCreateInfoKHR rayTracingPipelineCI = vks::initializers::rayTracingPipelineCreateInfoKHR();
        rayTracingPipelineCI.stageCount = static_cast<uint32_t>(shaderStages.size());
        rayTracingPipelineCI.pStages = shaderStages.data();
        rayTracingPipelineCI.groupCount = static_cast<uint32_t>(shaderGroups.size());
        rayTracingPipelineCI.pGroups = shaderGroups.data();
        rayTracingPipelineCI.maxPipelineRayRecursionDepth = std::min(uint32_t(4), rayTracingPipelineProperties->maxRayRecursionDepth);
        rayTracingPipelineCI.layout = pipelineLayout;
        VK_CHECK_RESULT(vkCreateRayTracingPipelinesKHR(device, VK_NULL_HANDLE, VK_NULL_HANDLE, 1, &rayTracingPipelineCI, nullptr, &pipeline));
    }

    void createDescriptorSets() override
    {

        std::vector<VkDescriptorPoolSize> poolSizes = {
                { VK_DESCRIPTOR_TYPE_ACCELERATION_STRUCTURE_KHR, maxConcurrentFrames },
                { VK_DESCRIPTOR_TYPE_STORAGE_IMAGE, maxConcurrentFrames },
                { VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER, maxConcurrentFrames * 3 },
                { VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, maxConcurrentFrames * 3 }
        };
        VkDescriptorPoolCreateInfo descriptorPoolCreateInfo = vks::initializers::descriptorPoolCreateInfo(poolSizes, maxConcurrentFrames);
        VK_CHECK_RESULT(vkCreateDescriptorPool(device, &descriptorPoolCreateInfo, nullptr, &descriptorPool));


        // Sets per frame, just like the buffers themselves
        // Acceleration structure, vertex and index buffers and images do not need to be duplicated per frame, we use the same for each descriptor to keep things simple
        VkDescriptorSetAllocateInfo allocInfo = vks::initializers::descriptorSetAllocateInfo(descriptorPool, &descriptorSetLayout, 1);
        pProbeIrradiance->updateDescriptor();
        pProbeDistance->updateDescriptor();
        pProbeData->updateDescriptor();
        pRayData->updateDescriptor();
        for (auto i = 0; i < maxConcurrentFrames; i++) {
            VK_CHECK_RESULT(vkAllocateDescriptorSets(device, &allocInfo, &descriptorSets[i]));

            // The fragment shader needs access to the ray tracing acceleration structure, so we pass it as a descriptor

            VkWriteDescriptorSetAccelerationStructureKHR descriptorAccelerationStructureInfo{};
            descriptorAccelerationStructureInfo.sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET_ACCELERATION_STRUCTURE_KHR;
            descriptorAccelerationStructureInfo.accelerationStructureCount = 1;
            descriptorAccelerationStructureInfo.pAccelerationStructures = &topLevelAS->handle;

            VkWriteDescriptorSet accelerationStructureWrite{};
            accelerationStructureWrite.sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET;
            // The specialized acceleration structure descriptor has to be chained
            accelerationStructureWrite.pNext = &descriptorAccelerationStructureInfo;
            accelerationStructureWrite.dstSet = descriptorSets[i];
            accelerationStructureWrite.dstBinding = 0;
            accelerationStructureWrite.descriptorCount = 1;
            accelerationStructureWrite.descriptorType = VK_DESCRIPTOR_TYPE_ACCELERATION_STRUCTURE_KHR;


            std::vector<VkWriteDescriptorSet> writeDescriptorSets = {
                    // Binding 0: Top level acceleration structure
                    accelerationStructureWrite,
                    // Binding 1: DDGIVolumeDescGPUPacked buffer
                    vks::initializers::writeDescriptorSet(descriptorSets[i], VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, 1, &pDDGIVolumes->descriptor),
                    // Binding 2: Probe Data
                    vks::initializers::writeDescriptorSet(descriptorSets[i], VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER, 2, &pProbeData->descriptor),
                    // Binding 3: Probe Irradiance
                    vks::initializers::writeDescriptorSet(descriptorSets[i], VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER, 3, &pProbeIrradiance->descriptor),
                    // Binding 4: Probe Distance
                    vks::initializers::writeDescriptorSet(descriptorSets[i], VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER, 4, &pProbeDistance->descriptor),
                    // Binding 5: Ray Data
                    vks::initializers::writeDescriptorSet(descriptorSets[i], VK_DESCRIPTOR_TYPE_STORAGE_IMAGE, 5, &pRayData->descriptor),
                    // Binding 6: Geometry Node
                    vks::initializers::writeDescriptorSet(descriptorSets[i], VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, 6, &geometryNodesBuffer->descriptor),
                    // Binding 7: Material
                    vks::initializers::writeDescriptorSet(descriptorSets[i], VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, 7, &materialDataBuffer->descriptor)
            };
            vkUpdateDescriptorSets(device, static_cast<uint32_t>(writeDescriptorSets.size()), writeDescriptorSets.data(), 0, VK_NULL_HANDLE);
        }
    }

    void createUniformBuffer() override{

    }

    vks::Texture* pProbeIrradiance = nullptr;
    vks::Texture* pProbeDistance = nullptr;
    vks::Texture* pProbeData = nullptr;
    vks::Texture* pRayData = nullptr;
    vks::Buffer* pDDGIVolumes = nullptr;
};