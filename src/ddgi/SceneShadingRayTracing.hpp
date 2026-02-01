#pragma once
#include "DDGIRayTracing.hpp"

class SceneShadingRayTracing : public DDGIRayTracing
{
public:
	struct UniformData {
		glm::mat4 viewInverse;
		glm::mat4 projInverse;
		uint32_t frame{ 0 };
	} uniformData;
	std::array<vks::Buffer, maxConcurrentFrames> uniformBuffers;

	SceneShadingRayTracing(
		VkDevice _device,
		VkPhysicalDeviceRayTracingPipelinePropertiesKHR* _rayTracingPipelineProperties,
		vks::VulkanDevice* _vulkanDevice,
		vkglTF::Model* _model,
		VkDescriptorPool _descriptorPool,
		AccelerationStructure* _bottomLevelAS,
		AccelerationStructure* _topLevelAS,
		StorageImage* _storageImage,
		vks::Buffer* _geometryNodesBuffer): DDGIRayTracing(
			_device,
			_rayTracingPipelineProperties,
			_vulkanDevice,
			_model,
			_descriptorPool,
			_bottomLevelAS,
			_topLevelAS,
			_storageImage,
			_geometryNodesBuffer
			)
	{
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
    
    void createShaderBindingTables() override {
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
        // We are using two miss shaders, so we need to get two handles for the miss shader binding table
        memcpy(shaderBindingTables.miss.mapped, shaderHandleStorage.data() + handleSizeAligned, handleSize * 2);
        memcpy(shaderBindingTables.hit.mapped, shaderHandleStorage.data() + handleSizeAligned * 3, handleSize);
    }


	void createRayTracingPipeline() override
	{
		const uint32_t imageCount = static_cast<uint32_t>(model->textures.size());

		std::vector<VkDescriptorSetLayoutBinding> setLayoutBindings = {
			// Binding 0: Top level acceleration structure
			vks::initializers::descriptorSetLayoutBinding(VK_DESCRIPTOR_TYPE_ACCELERATION_STRUCTURE_KHR, VK_SHADER_STAGE_RAYGEN_BIT_KHR | VK_SHADER_STAGE_CLOSEST_HIT_BIT_KHR, 0),
			// Binding 1: Ray tracing result image
			vks::initializers::descriptorSetLayoutBinding(VK_DESCRIPTOR_TYPE_STORAGE_IMAGE, VK_SHADER_STAGE_RAYGEN_BIT_KHR, 1),
			// Binding 2: Uniform buffer
			vks::initializers::descriptorSetLayoutBinding(VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER, VK_SHADER_STAGE_RAYGEN_BIT_KHR | VK_SHADER_STAGE_CLOSEST_HIT_BIT_KHR | VK_SHADER_STAGE_MISS_BIT_KHR, 2),
			// Binding 3: Texture image
			vks::initializers::descriptorSetLayoutBinding(VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER, VK_SHADER_STAGE_CLOSEST_HIT_BIT_KHR | VK_SHADER_STAGE_ANY_HIT_BIT_KHR, 3),
			// Binding 4: Geometry node information SSBO
			vks::initializers::descriptorSetLayoutBinding(VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, VK_SHADER_STAGE_CLOSEST_HIT_BIT_KHR | VK_SHADER_STAGE_ANY_HIT_BIT_KHR, 4),
			// Binding 5: All images used by the glTF model
			vks::initializers::descriptorSetLayoutBinding(VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER, VK_SHADER_STAGE_CLOSEST_HIT_BIT_KHR | VK_SHADER_STAGE_ANY_HIT_BIT_KHR, 5, imageCount)
		};

		// Unbound set
		VkDescriptorSetLayoutBindingFlagsCreateInfoEXT setLayoutBindingFlags{};
		setLayoutBindingFlags.sType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_BINDING_FLAGS_CREATE_INFO_EXT;
		setLayoutBindingFlags.bindingCount = 6;
		std::vector<VkDescriptorBindingFlagsEXT> descriptorBindingFlags = {
			0,
			0,
			0,
			0,
			0,
			VK_DESCRIPTOR_BINDING_VARIABLE_DESCRIPTOR_COUNT_BIT_EXT
		};
		setLayoutBindingFlags.pBindingFlags = descriptorBindingFlags.data();

		VkDescriptorSetLayoutCreateInfo descriptorSetLayoutCI = vks::initializers::descriptorSetLayoutCreateInfo(setLayoutBindings);
		descriptorSetLayoutCI.pNext = &setLayoutBindingFlags;
		VK_CHECK_RESULT(vkCreateDescriptorSetLayout(device, &descriptorSetLayoutCI, nullptr, &descriptorSetLayout));

		VkPipelineLayoutCreateInfo pipelineLayoutCI = vks::initializers::pipelineLayoutCreateInfo(&descriptorSetLayout, 1);
		VK_CHECK_RESULT(vkCreatePipelineLayout(device, &pipelineLayoutCI, nullptr, &pipelineLayout));


		std::vector<VkPipelineShaderStageCreateInfo> shaderStages;

		// Ray generation group
		{
			shaderStages.push_back(loadShader(device, getShadersPath() + "ddgi/raygen.rgen.spv", VK_SHADER_STAGE_RAYGEN_BIT_KHR));
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
			shaderStages.push_back(loadShader(device, getShadersPath() + "ddgi/miss.rmiss.spv", VK_SHADER_STAGE_MISS_BIT_KHR));
			VkRayTracingShaderGroupCreateInfoKHR shaderGroup{};
			shaderGroup.sType = VK_STRUCTURE_TYPE_RAY_TRACING_SHADER_GROUP_CREATE_INFO_KHR;
			shaderGroup.type = VK_RAY_TRACING_SHADER_GROUP_TYPE_GENERAL_KHR;
			shaderGroup.generalShader = static_cast<uint32_t>(shaderStages.size()) - 1;
			shaderGroup.closestHitShader = VK_SHADER_UNUSED_KHR;
			shaderGroup.anyHitShader = VK_SHADER_UNUSED_KHR;
			shaderGroup.intersectionShader = VK_SHADER_UNUSED_KHR;
			shaderGroups.push_back(shaderGroup);
			// Second shader for shadows
			shaderStages.push_back(loadShader(device, getShadersPath() + "ddgi/shadow.rmiss.spv", VK_SHADER_STAGE_MISS_BIT_KHR));
			shaderGroup.generalShader = static_cast<uint32_t>(shaderStages.size()) - 1;
			shaderGroups.push_back(shaderGroup);
		}

		// Closest hit group for doing texture lookups
		{
			shaderStages.push_back(loadShader(device, getShadersPath() + "ddgi/closesthit.rchit.spv", VK_SHADER_STAGE_CLOSEST_HIT_BIT_KHR));
			VkRayTracingShaderGroupCreateInfoKHR shaderGroup{};
			shaderGroup.sType = VK_STRUCTURE_TYPE_RAY_TRACING_SHADER_GROUP_CREATE_INFO_KHR;
			shaderGroup.type = VK_RAY_TRACING_SHADER_GROUP_TYPE_TRIANGLES_HIT_GROUP_KHR;
			shaderGroup.generalShader = VK_SHADER_UNUSED_KHR;
			shaderGroup.closestHitShader = static_cast<uint32_t>(shaderStages.size()) - 1;
			shaderGroup.intersectionShader = VK_SHADER_UNUSED_KHR;
			// This group also uses an anyhit shader for doing transparency (see anyhit.rahit for details)
			shaderStages.push_back(loadShader(device, getShadersPath() + "ddgi/anyhit.rahit.spv", VK_SHADER_STAGE_ANY_HIT_BIT_KHR));
			shaderGroup.anyHitShader = static_cast<uint32_t>(shaderStages.size()) - 1;
			shaderGroups.push_back(shaderGroup);
		}

		VkRayTracingPipelineCreateInfoKHR rayTracingPipelineCI{};
		rayTracingPipelineCI.sType = VK_STRUCTURE_TYPE_RAY_TRACING_PIPELINE_CREATE_INFO_KHR;
		rayTracingPipelineCI.stageCount = static_cast<uint32_t>(shaderStages.size());
		rayTracingPipelineCI.pStages = shaderStages.data();
		rayTracingPipelineCI.groupCount = static_cast<uint32_t>(shaderGroups.size());
		rayTracingPipelineCI.pGroups = shaderGroups.data();
		rayTracingPipelineCI.maxPipelineRayRecursionDepth = 1;
		rayTracingPipelineCI.layout = pipelineLayout;
		VK_CHECK_RESULT(vkCreateRayTracingPipelinesKHR(device, VK_NULL_HANDLE, VK_NULL_HANDLE, 1, &rayTracingPipelineCI, nullptr, &pipeline));
	}

	void createDescriptorSets() override
	{
		uint32_t imageCount = static_cast<uint32_t>(model->textures.size());
		std::vector<VkDescriptorPoolSize> poolSizes = {
			{ VK_DESCRIPTOR_TYPE_ACCELERATION_STRUCTURE_KHR, maxConcurrentFrames },
			{ VK_DESCRIPTOR_TYPE_STORAGE_IMAGE, maxConcurrentFrames },
			{ VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER, maxConcurrentFrames },
			{ VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER, maxConcurrentFrames },
			{ VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, maxConcurrentFrames },
			{ VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER, static_cast<uint32_t>(model->textures.size()) * maxConcurrentFrames }
		};
		VkDescriptorPoolCreateInfo descriptorPoolCreateInfo = vks::initializers::descriptorPoolCreateInfo(poolSizes, maxConcurrentFrames);
		VK_CHECK_RESULT(vkCreateDescriptorPool(device, &descriptorPoolCreateInfo, nullptr, &descriptorPool));

		VkDescriptorSetVariableDescriptorCountAllocateInfoEXT variableDescriptorCountAllocInfo{};
		uint32_t variableDescCounts[] = { imageCount };
		variableDescriptorCountAllocInfo.sType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_VARIABLE_DESCRIPTOR_COUNT_ALLOCATE_INFO_EXT;
		variableDescriptorCountAllocInfo.descriptorSetCount = 1;
		variableDescriptorCountAllocInfo.pDescriptorCounts = variableDescCounts;

		// Sets per frame, just like the buffers themselves
		// Acceleration structure and images do not need to be duplicated per frame, we use the same for each descriptor to keep things simple
		VkDescriptorSetAllocateInfo descriptorSetAllocateInfo = vks::initializers::descriptorSetAllocateInfo(descriptorPool, &descriptorSetLayout, 1);
		// Required for the variable no. of images used by the glTF model
		descriptorSetAllocateInfo.pNext = &variableDescriptorCountAllocInfo;
		for (auto i = 0; i < maxConcurrentFrames; i++) {
			VK_CHECK_RESULT(vkAllocateDescriptorSets(device, &descriptorSetAllocateInfo, &descriptorSets[i]));

			VkWriteDescriptorSetAccelerationStructureKHR descriptorAccelerationStructureInfo = vks::initializers::writeDescriptorSetAccelerationStructureKHR();
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

			std::vector<VkWriteDescriptorSet> writeDescriptorSets = {
				// Binding 0: Top level acceleration structure
				accelerationStructureWrite,
				// Binding 1: Ray tracing result image
				vks::initializers::writeDescriptorSet(descriptorSets[i], VK_DESCRIPTOR_TYPE_STORAGE_IMAGE, 1, &storageImageDescriptor),
				// Binding 2: Uniform data
				vks::initializers::writeDescriptorSet(descriptorSets[i], VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER, 2, &uniformBuffers[i].descriptor),
				// Binding 4: Geometry node information SSBO
				vks::initializers::writeDescriptorSet(descriptorSets[i], VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, 4, &geometryNodesBuffer->descriptor),
			};

			// Image descriptors for the variable no. of images of the glTF model
			std::vector<VkDescriptorImageInfo> textureDescriptors{};
			for (auto& texture : model->textures) {
				VkDescriptorImageInfo descriptor{};
				descriptor.imageLayout = VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL;
				descriptor.sampler = texture.sampler;
				descriptor.imageView = texture.view;
				textureDescriptors.push_back(descriptor);
			}

			VkWriteDescriptorSet writeDescriptorImgArray{};
			writeDescriptorImgArray.sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET;
			writeDescriptorImgArray.dstBinding = 5;
			writeDescriptorImgArray.descriptorType = VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER;
			writeDescriptorImgArray.descriptorCount = imageCount;
			writeDescriptorImgArray.dstSet = descriptorSets[i];
			writeDescriptorImgArray.pImageInfo = textureDescriptors.data();
			writeDescriptorSets.push_back(writeDescriptorImgArray);

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
};
