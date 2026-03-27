#pragma once
#include "DDGIRayTracing.hpp"

class SceneShadingRayTracing : public DDGIRayTracing
{
public:
	struct UniformData {
		glm::mat4 viewInverse;
		glm::mat4 projInverse;
        glm::vec3 position;
		uint32_t frame{ 0 };
        glm::ivec4 probeDebugFlags{ 0, 0, 0, 0 };
        glm::vec4 probeDebugParams{ 0.15f, 0.85f, 0.0f, 0.0f };
	} uniformData;
	std::array<vks::Buffer, maxConcurrentFrames> uniformBuffers;

	SceneShadingRayTracing(
		VkDevice _device,
		VkPhysicalDeviceRayTracingPipelinePropertiesKHR* _rayTracingPipelineProperties,
		vks::VulkanDevice* _vulkanDevice,
		vkobj::Model* _model,
		AccelerationStructure* _bottomLevelAS,
		AccelerationStructure* _topLevelAS,
		StorageImage* _storageImage,
		vks::Buffer* _geometryNodesBuffer,
        vks::Buffer* _materialDataBuffer,
        vks::Buffer* _pDDGIVolumes,
        vks::Texture* _pProbeIrradiance,
        vks::Texture* _pProbeDistance,
        vks::Texture* _pProbeData): DDGIRayTracing(
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
        pDDGIVolumes = _pDDGIVolumes;
        pProbeIrradiance = _pProbeIrradiance;
        pProbeDistance = _pProbeDistance;
        pProbeData = _pProbeData;
	}

	void recordCommandBuffer(VkCommandBuffer cmdBuffer, uint32_t currentBuffer) override
	{
		vkCmdBindPipeline(cmdBuffer, VK_PIPELINE_BIND_POINT_RAY_TRACING_KHR, pipeline);
		vkCmdBindDescriptorSets(cmdBuffer, VK_PIPELINE_BIND_POINT_RAY_TRACING_KHR, pipelineLayout, 0, 1, &descriptorSets[currentBuffer], 0, 0);

		VkStridedDeviceAddressRegionKHR emptySbtEntry = {};
		vkCmdTraceRaysKHR(
			cmdBuffer,
			&shaderBindingTables.raygen.stridedDeviceAddressRegion,
			&shaderBindingTables.miss.stridedDeviceAddressRegion,
			&shaderBindingTables.hit.stridedDeviceAddressRegion,
			&emptySbtEntry,
			width,
			height,
			1);

	}
	
	~SceneShadingRayTracing() override
	{
		for (auto& buffer : uniformBuffers) {
			buffer.destroy();
		}
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
                // Binding 1: Storage image
                vks::initializers::descriptorSetLayoutBinding(VK_DESCRIPTOR_TYPE_STORAGE_IMAGE, VK_SHADER_STAGE_RAYGEN_BIT_KHR, 1),
                // Binding 2: Uniform buffer
                vks::initializers::descriptorSetLayoutBinding(VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER, VK_SHADER_STAGE_RAYGEN_BIT_KHR | VK_SHADER_STAGE_CLOSEST_HIT_BIT_KHR | VK_SHADER_STAGE_MISS_BIT_KHR, 2),
                // Binding 3: Geometry Nodes buffer
                vks::initializers::descriptorSetLayoutBinding(VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, VK_SHADER_STAGE_CLOSEST_HIT_BIT_KHR | VK_SHADER_STAGE_ANY_HIT_BIT_KHR | VK_SHADER_STAGE_RAYGEN_BIT_KHR, 3),
                // Binding 4: Base Colors buffer
                vks::initializers::descriptorSetLayoutBinding(VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, VK_SHADER_STAGE_RAYGEN_BIT_KHR | VK_SHADER_STAGE_CLOSEST_HIT_BIT_KHR, 4),
                // Binding 5: DDGI Volume
                vks::initializers::descriptorSetLayoutBinding(VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, VK_SHADER_STAGE_RAYGEN_BIT_KHR, 5),
                // Binding 6: Probe Irradiance
                vks::initializers::descriptorSetLayoutBinding(VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER, VK_SHADER_STAGE_RAYGEN_BIT_KHR , 6),
                // Binding 7: Probe Distance
                vks::initializers::descriptorSetLayoutBinding(VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER, VK_SHADER_STAGE_RAYGEN_BIT_KHR, 7),
                // Binding 8: Probe Data
                vks::initializers::descriptorSetLayoutBinding(VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER, VK_SHADER_STAGE_RAYGEN_BIT_KHR, 8),
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
            shaderStages.push_back(loadShader(getShadersPath() + "ddgi/SceneShading.rgen.spv", VK_SHADER_STAGE_RAYGEN_BIT_KHR));
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
            shaderStages.push_back(loadShader(getShadersPath() + "ddgi/SceneShading.rchit.spv", VK_SHADER_STAGE_CLOSEST_HIT_BIT_KHR));
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
                { VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER, maxConcurrentFrames },
                { VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, maxConcurrentFrames * 4 },
                { VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER, maxConcurrentFrames * 3 }
        };
        VkDescriptorPoolCreateInfo descriptorPoolCreateInfo = vks::initializers::descriptorPoolCreateInfo(poolSizes, maxConcurrentFrames);
        VK_CHECK_RESULT(vkCreateDescriptorPool(device, &descriptorPoolCreateInfo, nullptr, &descriptorPool));


        // Sets per frame, just like the buffers themselves
        // Acceleration structure, vertex and index buffers and images do not need to be duplicated per frame, we use the same for each descriptor to keep things simple
        VkDescriptorSetAllocateInfo allocInfo = vks::initializers::descriptorSetAllocateInfo(descriptorPool, &descriptorSetLayout, 1);
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

            VkDescriptorImageInfo storageImageDescriptor{ VK_NULL_HANDLE, storageImage->view, VK_IMAGE_LAYOUT_GENERAL };


            pProbeIrradiance->updateDescriptor();
            pProbeDistance->updateDescriptor();
            pProbeData->updateDescriptor();
            std::vector<VkWriteDescriptorSet> writeDescriptorSets = {
                    // Binding 0: Top level acceleration structure
                    accelerationStructureWrite,
                    // Binding 1: Ray tracing result image
                    vks::initializers::writeDescriptorSet(descriptorSets[i], VK_DESCRIPTOR_TYPE_STORAGE_IMAGE, 1, &storageImageDescriptor),
                    // Binding 2: Uniform data
                    vks::initializers::writeDescriptorSet(descriptorSets[i], VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER, 2, &uniformBuffers[i].descriptor),
                    // Binding 3: Geometry Nodes
                    vks::initializers::writeDescriptorSet(descriptorSets[i], VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, 3, &geometryNodesBuffer->descriptor),
                    // Binding 4: Material Data
                    vks::initializers::writeDescriptorSet(descriptorSets[i], VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, 4, &materialDataBuffer->descriptor),
                    // Binding 5: DDGI Volumes
                    vks::initializers::writeDescriptorSet(descriptorSets[i], VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, 5, &pDDGIVolumes->descriptor),
                    // Binding 6: Probe Irradiance
                    vks::initializers::writeDescriptorSet(descriptorSets[i], VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER, 6, &pProbeIrradiance->descriptor),
                    // Binding 7: Probe Distance
                    vks::initializers::writeDescriptorSet(descriptorSets[i], VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER, 7, &pProbeDistance->descriptor),
                    // Binding 8: Probe Data
                    vks::initializers::writeDescriptorSet(descriptorSets[i], VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER, 8, &pProbeData->descriptor),
            };
            vkUpdateDescriptorSets(device, static_cast<uint32_t>(writeDescriptorSets.size()), writeDescriptorSets.data(), 0, VK_NULL_HANDLE);
        }
    }

	void createUniformBuffer() override
	{
		for (auto& buffer : uniformBuffers) {
			VK_CHECK_RESULT(vulkanDevice->createBuffer(VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT, VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | VK_MEMORY_PROPERTY_HOST_COHERENT_BIT, &buffer, sizeof(UniformData), &uniformData));
			VK_CHECK_RESULT(buffer.map());
		}
	}

    vks::Buffer* pDDGIVolumes = nullptr;
    vks::Texture* pProbeIrradiance = nullptr;
    vks::Texture* pProbeDistance = nullptr;
    vks::Texture* pProbeData = nullptr;
};
