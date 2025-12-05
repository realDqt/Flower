/*
* Vulkan Example - Hardware accelerated ray tracing example for doing reflections
*
* Renders a complex scene doing recursion inside the shaders for creating reflections
*
* Copyright (C) 2019-2025 by Sascha Willems - www.saschawillems.de
*
* This code is licensed under the MIT license (MIT) (http://opensource.org/licenses/MIT)
*/

#include "VulkanRaytracingSample.h"
#include "VulkanObjModel.h"

class CornellBox : public VulkanRaytracingSample
{
public:
    AccelerationStructure bottomLevelAS{};
    AccelerationStructure topLevelAS{};

    std::vector<VkRayTracingShaderGroupCreateInfoKHR> shaderGroups{};
    struct ShaderBindingTables {
        ShaderBindingTable raygen;
        ShaderBindingTable miss;
        ShaderBindingTable hit;
    } shaderBindingTables;

    struct UniformData {
        glm::mat4 viewInverse;
        glm::mat4 projInverse;
    	uint32_t frame = 0;
    } uniformData;

	struct GeometryNode {
		uint64_t vertexBufferDeviceAddress;
		uint64_t indexBufferDeviceAddress;
	};
	vks::Buffer geometryNodesBuffer;
	
	vks::Buffer materialDataBuffer;
	
	vks::Buffer transformBuffer;
	
    std::array<vks::Buffer, maxConcurrentFrames> uniformBuffers;

    VkPipeline pipeline{ VK_NULL_HANDLE };
    VkPipelineLayout pipelineLayout{ VK_NULL_HANDLE };
    VkDescriptorSetLayout descriptorSetLayout{ VK_NULL_HANDLE };
    std::array<VkDescriptorSet, maxConcurrentFrames> descriptorSets{};
    
    vkobj::Model cornell;
    std::vector<std::string> filenames;
    std::vector<vkobj::Material> materials;

	VkPhysicalDeviceDescriptorIndexingFeaturesEXT physicalDeviceDescriptorIndexingFeatures{};
    
    // This sample is derived from an extended base class that saves most of the ray tracing setup boiler plate
    CornellBox() : VulkanRaytracingSample()
    {
        title = "Ray tracing reflections";
        timerSpeed *= 100.0f;
        camera.rotationSpeed *= 0.25f;
        camera.type = Camera::CameraType::firstperson;
        camera.setPerspective(60.0f, (float)width / (float)height, 0.1f, 512.0f);
        camera.setRotation(glm::vec3(0.0f, 0.0f, 0.0f));
        camera.setTranslation(glm::vec3(0.0f, 0.5f, -2.0f));
        enableExtensions();
    }

    ~CornellBox()
    {
        vkDestroyPipeline(device, pipeline, nullptr);
        vkDestroyPipelineLayout(device, pipelineLayout, nullptr);
        vkDestroyDescriptorSetLayout(device, descriptorSetLayout, nullptr);
        deleteStorageImage();
        deleteAccelerationStructure(bottomLevelAS);
        deleteAccelerationStructure(topLevelAS);
    	transformBuffer.destroy();
    	shaderBindingTables.raygen.destroy();
    	shaderBindingTables.miss.destroy();
    	shaderBindingTables.hit.destroy();
    	geometryNodesBuffer.destroy();
    	materialDataBuffer.destroy();
        for (auto& buffer : uniformBuffers) {
            buffer.destroy();
        }
    }

	// done
    void loadAssets()
    {
        filenames.clear();
        materials.clear();
        
        // 准备路径与材质
        std::string assetPath = getAssetPath();
        filenames.push_back(assetPath + "models/cornellbox/floor.obj");
        filenames.push_back(assetPath + "models/cornellbox/left.obj");
        filenames.push_back(assetPath + "models/cornellbox/light.obj");
        filenames.push_back(assetPath + "models/cornellbox/right.obj");
        filenames.push_back(assetPath + "models/cornellbox/shortbox.obj");
        filenames.push_back(assetPath + "models/cornellbox/tallbox.obj");

        vkobj::Material red(vulkanDevice);
        red.baseColor =  glm::vec4(0.63f, 0.065f, 0.05f, 1.0f);
        vkobj::Material green(vulkanDevice);
        green.baseColor =  glm::vec4(0.14f, 0.45f, 0.091f, 1.0f);
        vkobj::Material white(vulkanDevice);
        white.baseColor =  glm::vec4(0.725f, 0.71f, 0.68f, 1.0f);
        vkobj::Material light(vulkanDevice);
        light.baseColor =  glm::vec4(0.65f, 0.65f, 0.65f, 1.0f);
    	light.emission = 8.0f * glm::vec3(0.747f+0.058f, 0.747f+0.258f, 0.747f) + 15.6f * glm::vec3(0.740f+0.287f,0.740f+0.160f,0.740f) + 18.4f * glm::vec3(0.737f+0.642f,0.737f+0.159f,0.737f);

        materials.push_back(white);
        materials.push_back(red);
        materials.push_back(light);
        materials.push_back(green);
        materials.push_back(white);
        materials.push_back(white);
        
        // 加载obj
        cornell.loadFromFile(filenames, materials, vulkanDevice, queue);
    }

	// done
	void createAccelerationStructureBuffer(AccelerationStructure& accelerationStructure, VkAccelerationStructureBuildSizesInfoKHR buildSizeInfo)
    {
    	VkBufferCreateInfo bufferCreateInfo{};
    	bufferCreateInfo.sType = VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO;
    	bufferCreateInfo.size = buildSizeInfo.accelerationStructureSize;
    	bufferCreateInfo.usage = VK_BUFFER_USAGE_ACCELERATION_STRUCTURE_STORAGE_BIT_KHR | VK_BUFFER_USAGE_SHADER_DEVICE_ADDRESS_BIT;
    	VK_CHECK_RESULT(vkCreateBuffer(device, &bufferCreateInfo, nullptr, &accelerationStructure.buffer));
    	VkMemoryRequirements memoryRequirements{};
    	vkGetBufferMemoryRequirements(device, accelerationStructure.buffer, &memoryRequirements);
    	VkMemoryAllocateFlagsInfo memoryAllocateFlagsInfo{};
    	memoryAllocateFlagsInfo.sType = VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_FLAGS_INFO;
    	memoryAllocateFlagsInfo.flags = VK_MEMORY_ALLOCATE_DEVICE_ADDRESS_BIT_KHR;
    	VkMemoryAllocateInfo memoryAllocateInfo{};
    	memoryAllocateInfo.sType = VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO;
    	memoryAllocateInfo.pNext = &memoryAllocateFlagsInfo;
    	memoryAllocateInfo.allocationSize = memoryRequirements.size;
    	memoryAllocateInfo.memoryTypeIndex = vulkanDevice->getMemoryType(memoryRequirements.memoryTypeBits, VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT);
    	VK_CHECK_RESULT(vkAllocateMemory(device, &memoryAllocateInfo, nullptr, &accelerationStructure.memory));
    	VK_CHECK_RESULT(vkBindBufferMemory(device, accelerationStructure.buffer, accelerationStructure.memory, 0));
    }
	
    /*
        Create the bottom level acceleration structure contains the scene's actual geometry (vertices, triangles)
    */
	// done
    void createBottomLevelAccelerationStructure()
    {
    	std::vector<VkTransformMatrixKHR> transformMatrices{};
    	for (auto mesh : cornell.meshes) {
    		if (mesh->indexCount > 0) {
    			VkTransformMatrixKHR transformMatrix{};
    			auto m44 = glm::mat4(1.0f);
    			float scale = 0.001f;
    			glm::vec3 axisX = glm::vec3(1.0f, 0.0f, 0.0f);

    			m44 = glm::rotate(m44, glm::radians(180.0f), axisX);
    			m44 = glm::scale(m44, glm::vec3(scale));

    			auto m44Trans = glm::transpose(m44);
    			
    			const float* rawData = reinterpret_cast<const float*>(&m44Trans);
    			for (int i = 0; i < 3; ++i)
    			{
    				for (int j = 0; j < 4; ++j)
    					transformMatrix.matrix[i][j] = rawData[i * 4 + j];
    			}
    			transformMatrices.push_back(transformMatrix);
    		}
    	}

    	// Transform buffer
    	VK_CHECK_RESULT(vulkanDevice->createBuffer(
			VK_BUFFER_USAGE_SHADER_DEVICE_ADDRESS_BIT | VK_BUFFER_USAGE_ACCELERATION_STRUCTURE_BUILD_INPUT_READ_ONLY_BIT_KHR,
			VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | VK_MEMORY_PROPERTY_HOST_COHERENT_BIT,
			&transformBuffer,
			static_cast<uint32_t>(transformMatrices.size()) * sizeof(VkTransformMatrixKHR),
			transformMatrices.data()));
    	
        // Build
		// One geometry per obj, so we can index materials using gl_GeometryIndexEXT
		std::vector<uint32_t> maxPrimitiveCounts{};
		std::vector<VkAccelerationStructureGeometryKHR> geometries{};
		std::vector<VkAccelerationStructureBuildRangeInfoKHR> buildRangeInfos{};
		std::vector<VkAccelerationStructureBuildRangeInfoKHR*> pBuildRangeInfos{};
		std::vector<GeometryNode> geometryNodes{};
    	std::vector<vkobj::MaterialData> materialDataVec{};
		for (auto mesh : cornell.meshes) {
			if (mesh->indexCount > 0) {
				VkDeviceOrHostAddressConstKHR vertexBufferDeviceAddress{};
				VkDeviceOrHostAddressConstKHR indexBufferDeviceAddress{};
				VkDeviceOrHostAddressConstKHR transformBufferDeviceAddress{};

				vertexBufferDeviceAddress.deviceAddress = getBufferDeviceAddress(cornell.vertices.buffer);
				indexBufferDeviceAddress.deviceAddress = getBufferDeviceAddress(cornell.indices.buffer) + mesh->firstIndex * sizeof(uint32_t);
				transformBufferDeviceAddress.deviceAddress = getBufferDeviceAddress(transformBuffer.buffer) + static_cast<uint32_t>(geometryNodes.size()) * sizeof(VkTransformMatrixKHR);

				VkAccelerationStructureGeometryKHR geometry{};
				geometry.sType = VK_STRUCTURE_TYPE_ACCELERATION_STRUCTURE_GEOMETRY_KHR;
				geometry.geometryType = VK_GEOMETRY_TYPE_TRIANGLES_KHR;
				geometry.geometry.triangles.sType = VK_STRUCTURE_TYPE_ACCELERATION_STRUCTURE_GEOMETRY_TRIANGLES_DATA_KHR;
				geometry.geometry.triangles.vertexFormat = VK_FORMAT_R32G32B32_SFLOAT;
				geometry.geometry.triangles.vertexData = vertexBufferDeviceAddress;
				geometry.geometry.triangles.maxVertex = cornell.vertices.count;
				geometry.geometry.triangles.vertexStride = sizeof(vkobj::Vertex);
				geometry.geometry.triangles.indexType = VK_INDEX_TYPE_UINT32;
				geometry.geometry.triangles.indexData = indexBufferDeviceAddress;
				geometry.geometry.triangles.transformData = transformBufferDeviceAddress;
				geometries.push_back(geometry);
				maxPrimitiveCounts.push_back(mesh->indexCount / 3);

				VkAccelerationStructureBuildRangeInfoKHR buildRangeInfo{};
				buildRangeInfo.firstVertex = 0;
				buildRangeInfo.primitiveOffset = 0;
				buildRangeInfo.primitiveCount = mesh->indexCount / 3;
				buildRangeInfo.transformOffset = 0;
				buildRangeInfos.push_back(buildRangeInfo);

				GeometryNode geometryNode{};
				geometryNode.vertexBufferDeviceAddress = vertexBufferDeviceAddress.deviceAddress;
				geometryNode.indexBufferDeviceAddress = indexBufferDeviceAddress.deviceAddress;
				geometryNodes.push_back(geometryNode);
				
				materialDataVec.push_back(mesh->material.GetData());
			}
		}
		for (auto& rangeInfo : buildRangeInfos) {
			pBuildRangeInfos.push_back(&rangeInfo);
		}

    	// geometry node buffer
		vks::Buffer stagingBuffer;

		VK_CHECK_RESULT(vulkanDevice->createBuffer(
			VK_BUFFER_USAGE_TRANSFER_SRC_BIT,
			VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | VK_MEMORY_PROPERTY_HOST_COHERENT_BIT,
			&stagingBuffer,
			static_cast<uint32_t>(geometryNodes.size()) * sizeof(GeometryNode),
			geometryNodes.data()));

		VK_CHECK_RESULT(vulkanDevice->createBuffer(
			VK_BUFFER_USAGE_SHADER_DEVICE_ADDRESS_BIT | VK_BUFFER_USAGE_STORAGE_BUFFER_BIT | VK_BUFFER_USAGE_TRANSFER_DST_BIT,
			VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT,
			&geometryNodesBuffer,
			static_cast<uint32_t>(geometryNodes.size()) * sizeof(GeometryNode)));

		vulkanDevice->copyBuffer(&stagingBuffer, &geometryNodesBuffer, queue);

		stagingBuffer.destroy();

    	// base color buffer
    	vks::Buffer stagingBuffer2;

    	VK_CHECK_RESULT(vulkanDevice->createBuffer(
			VK_BUFFER_USAGE_TRANSFER_SRC_BIT,
			VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | VK_MEMORY_PROPERTY_HOST_COHERENT_BIT,
			&stagingBuffer2,
			static_cast<uint32_t>(materialDataVec.size()) * sizeof(vkobj::MaterialData),
			materialDataVec.data()));

    	VK_CHECK_RESULT(vulkanDevice->createBuffer(
			VK_BUFFER_USAGE_SHADER_DEVICE_ADDRESS_BIT | VK_BUFFER_USAGE_STORAGE_BUFFER_BIT | VK_BUFFER_USAGE_TRANSFER_DST_BIT,
			VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT,
			&materialDataBuffer,
			static_cast<uint32_t>(materialDataVec.size()) * sizeof(vkobj::MaterialData)));

    	vulkanDevice->copyBuffer(&stagingBuffer2, &materialDataBuffer, queue);

    	stagingBuffer2.destroy();

		// Get size info
		VkAccelerationStructureBuildGeometryInfoKHR accelerationStructureBuildGeometryInfo{};
		accelerationStructureBuildGeometryInfo.sType = VK_STRUCTURE_TYPE_ACCELERATION_STRUCTURE_BUILD_GEOMETRY_INFO_KHR;
		accelerationStructureBuildGeometryInfo.type = VK_ACCELERATION_STRUCTURE_TYPE_BOTTOM_LEVEL_KHR;
		accelerationStructureBuildGeometryInfo.flags = VK_BUILD_ACCELERATION_STRUCTURE_PREFER_FAST_TRACE_BIT_KHR;
		accelerationStructureBuildGeometryInfo.geometryCount = static_cast<uint32_t>(geometries.size());
		accelerationStructureBuildGeometryInfo.pGeometries = geometries.data();

		VkAccelerationStructureBuildSizesInfoKHR accelerationStructureBuildSizesInfo{};
		accelerationStructureBuildSizesInfo.sType = VK_STRUCTURE_TYPE_ACCELERATION_STRUCTURE_BUILD_SIZES_INFO_KHR;
		vkGetAccelerationStructureBuildSizesKHR(
			device,
			VK_ACCELERATION_STRUCTURE_BUILD_TYPE_DEVICE_KHR,
			&accelerationStructureBuildGeometryInfo,
			maxPrimitiveCounts.data(),
			&accelerationStructureBuildSizesInfo);

		createAccelerationStructureBuffer(bottomLevelAS, accelerationStructureBuildSizesInfo);

		VkAccelerationStructureCreateInfoKHR accelerationStructureCreateInfo{};
		accelerationStructureCreateInfo.sType = VK_STRUCTURE_TYPE_ACCELERATION_STRUCTURE_CREATE_INFO_KHR;
		accelerationStructureCreateInfo.buffer = bottomLevelAS.buffer;
		accelerationStructureCreateInfo.size = accelerationStructureBuildSizesInfo.accelerationStructureSize;
		accelerationStructureCreateInfo.type = VK_ACCELERATION_STRUCTURE_TYPE_BOTTOM_LEVEL_KHR;
		vkCreateAccelerationStructureKHR(device, &accelerationStructureCreateInfo, nullptr, &bottomLevelAS.handle);

		// Create a small scratch buffer used during build of the bottom level acceleration structure
		ScratchBuffer scratchBuffer = createScratchBuffer(accelerationStructureBuildSizesInfo.buildScratchSize);

		accelerationStructureBuildGeometryInfo.mode = VK_BUILD_ACCELERATION_STRUCTURE_MODE_BUILD_KHR;
		accelerationStructureBuildGeometryInfo.dstAccelerationStructure = bottomLevelAS.handle;
		accelerationStructureBuildGeometryInfo.scratchData.deviceAddress = scratchBuffer.deviceAddress;

		const VkAccelerationStructureBuildRangeInfoKHR* buildOffsetInfo = buildRangeInfos.data();

		// Build the acceleration structure on the device via a one-time command buffer submission
		// Some implementations may support acceleration structure building on the host (VkPhysicalDeviceAccelerationStructureFeaturesKHR->accelerationStructureHostCommands), but we prefer device builds
		VkCommandBuffer commandBuffer = vulkanDevice->createCommandBuffer(VK_COMMAND_BUFFER_LEVEL_PRIMARY, true);
		vkCmdBuildAccelerationStructuresKHR(
			commandBuffer,
			1,
			&accelerationStructureBuildGeometryInfo,
			pBuildRangeInfos.data());
		vulkanDevice->flushCommandBuffer(commandBuffer, queue);

		VkAccelerationStructureDeviceAddressInfoKHR accelerationDeviceAddressInfo{};
		accelerationDeviceAddressInfo.sType = VK_STRUCTURE_TYPE_ACCELERATION_STRUCTURE_DEVICE_ADDRESS_INFO_KHR;
		accelerationDeviceAddressInfo.accelerationStructure = bottomLevelAS.handle;
		bottomLevelAS.deviceAddress = vkGetAccelerationStructureDeviceAddressKHR(device, &accelerationDeviceAddressInfo);

		deleteScratchBuffer(scratchBuffer);
    }

    /*
        The top level acceleration structure contains the scene's object instances
    */
	// done
    void createTopLevelAccelerationStructure()
    {
        VkTransformMatrixKHR transformMatrix = {
                1.0f, 0.0f, 0.0f, 0.0f,
                0.0f, 1.0f, 0.0f, 0.0f,
                0.0f, 0.0f, 1.0f, 0.0f };

        VkAccelerationStructureInstanceKHR instance{};
        instance.transform = transformMatrix;
        instance.instanceCustomIndex = 0;
        instance.mask = 0xFF;
        instance.instanceShaderBindingTableRecordOffset = 0;
        instance.flags = VK_GEOMETRY_INSTANCE_TRIANGLE_FACING_CULL_DISABLE_BIT_KHR;
        instance.accelerationStructureReference = bottomLevelAS.deviceAddress;

        // Buffer for instance data
        vks::Buffer instancesBuffer;
        VK_CHECK_RESULT(vulkanDevice->createBuffer(
                VK_BUFFER_USAGE_SHADER_DEVICE_ADDRESS_BIT | VK_BUFFER_USAGE_ACCELERATION_STRUCTURE_BUILD_INPUT_READ_ONLY_BIT_KHR,
                VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | VK_MEMORY_PROPERTY_HOST_COHERENT_BIT,
                &instancesBuffer,
                sizeof(VkAccelerationStructureInstanceKHR),
                &instance));

        VkDeviceOrHostAddressConstKHR instanceDataDeviceAddress{};
        instanceDataDeviceAddress.deviceAddress = getBufferDeviceAddress(instancesBuffer.buffer);

        VkAccelerationStructureGeometryKHR accelerationStructureGeometry = vks::initializers::accelerationStructureGeometryKHR();
        accelerationStructureGeometry.geometryType = VK_GEOMETRY_TYPE_INSTANCES_KHR;
        accelerationStructureGeometry.flags = VK_GEOMETRY_OPAQUE_BIT_KHR;
        accelerationStructureGeometry.geometry.instances.sType = VK_STRUCTURE_TYPE_ACCELERATION_STRUCTURE_GEOMETRY_INSTANCES_DATA_KHR;
        accelerationStructureGeometry.geometry.instances.arrayOfPointers = VK_FALSE;
        accelerationStructureGeometry.geometry.instances.data = instanceDataDeviceAddress;

        // Get size info
        VkAccelerationStructureBuildGeometryInfoKHR accelerationStructureBuildGeometryInfo = vks::initializers::accelerationStructureBuildGeometryInfoKHR();
        accelerationStructureBuildGeometryInfo.type = VK_ACCELERATION_STRUCTURE_TYPE_TOP_LEVEL_KHR;
        accelerationStructureBuildGeometryInfo.flags = VK_BUILD_ACCELERATION_STRUCTURE_PREFER_FAST_TRACE_BIT_KHR;
        accelerationStructureBuildGeometryInfo.geometryCount = 1;
        accelerationStructureBuildGeometryInfo.pGeometries = &accelerationStructureGeometry;

        uint32_t primitive_count = 1;

        VkAccelerationStructureBuildSizesInfoKHR accelerationStructureBuildSizesInfo = vks::initializers::accelerationStructureBuildSizesInfoKHR();
        vkGetAccelerationStructureBuildSizesKHR(
                device,
                VK_ACCELERATION_STRUCTURE_BUILD_TYPE_DEVICE_KHR,
                &accelerationStructureBuildGeometryInfo,
                &primitive_count,
                &accelerationStructureBuildSizesInfo);

        createAccelerationStructure(topLevelAS, VK_ACCELERATION_STRUCTURE_TYPE_TOP_LEVEL_KHR, accelerationStructureBuildSizesInfo);

        // Create a small scratch buffer used during build of the top level acceleration structure
        ScratchBuffer scratchBuffer = createScratchBuffer(accelerationStructureBuildSizesInfo.buildScratchSize);

        VkAccelerationStructureBuildGeometryInfoKHR accelerationBuildGeometryInfo = vks::initializers::accelerationStructureBuildGeometryInfoKHR();
        accelerationBuildGeometryInfo.type = VK_ACCELERATION_STRUCTURE_TYPE_TOP_LEVEL_KHR;
        accelerationBuildGeometryInfo.flags = VK_BUILD_ACCELERATION_STRUCTURE_PREFER_FAST_TRACE_BIT_KHR;
        accelerationBuildGeometryInfo.mode = VK_BUILD_ACCELERATION_STRUCTURE_MODE_BUILD_KHR;
        accelerationBuildGeometryInfo.dstAccelerationStructure = topLevelAS.handle;
        accelerationBuildGeometryInfo.geometryCount = 1;
        accelerationBuildGeometryInfo.pGeometries = &accelerationStructureGeometry;
        accelerationBuildGeometryInfo.scratchData.deviceAddress = scratchBuffer.deviceAddress;

        VkAccelerationStructureBuildRangeInfoKHR accelerationStructureBuildRangeInfo{};
        accelerationStructureBuildRangeInfo.primitiveCount = 1;
        accelerationStructureBuildRangeInfo.primitiveOffset = 0;
        accelerationStructureBuildRangeInfo.firstVertex = 0;
        accelerationStructureBuildRangeInfo.transformOffset = 0;
        std::vector<VkAccelerationStructureBuildRangeInfoKHR*> accelerationBuildStructureRangeInfos = { &accelerationStructureBuildRangeInfo };

        // Build the acceleration structure on the device via a one-time command buffer submission
        // Some implementations may support acceleration structure building on the host (VkPhysicalDeviceAccelerationStructureFeaturesKHR->accelerationStructureHostCommands), but we prefer device builds
        VkCommandBuffer commandBuffer = vulkanDevice->createCommandBuffer(VK_COMMAND_BUFFER_LEVEL_PRIMARY, true);
        vkCmdBuildAccelerationStructuresKHR(
                commandBuffer,
                1,
                &accelerationBuildGeometryInfo,
                accelerationBuildStructureRangeInfos.data());
        vulkanDevice->flushCommandBuffer(commandBuffer, queue);

        deleteScratchBuffer(scratchBuffer);
        instancesBuffer.destroy();
    }

    /*
        Create the Shader Binding Tables that binds the programs and top-level acceleration structure

        SBT Layout used in this sample:

            /-----------\
            | raygen    |
            |-----------|
            | miss      |
            |-----------|
            | hit       |
            \-----------/

    */
	// done
    void createShaderBindingTables() {
        const uint32_t handleSize = rayTracingPipelineProperties.shaderGroupHandleSize;
        const uint32_t handleSizeAligned = vks::tools::alignedSize(rayTracingPipelineProperties.shaderGroupHandleSize, rayTracingPipelineProperties.shaderGroupHandleAlignment);
        const uint32_t groupCount = static_cast<uint32_t>(shaderGroups.size());
        const uint32_t sbtSize = groupCount * handleSizeAligned;

        std::vector<uint8_t> shaderHandleStorage(sbtSize);
        VK_CHECK_RESULT(vkGetRayTracingShaderGroupHandlesKHR(device, pipeline, 0, groupCount, sbtSize, shaderHandleStorage.data()));

        createShaderBindingTable(shaderBindingTables.raygen, 1);
        createShaderBindingTable(shaderBindingTables.miss, 1);
        createShaderBindingTable(shaderBindingTables.hit, 1);

        // Copy handles
        memcpy(shaderBindingTables.raygen.mapped, shaderHandleStorage.data(), handleSize);
        memcpy(shaderBindingTables.miss.mapped, shaderHandleStorage.data() + handleSizeAligned, handleSize);
        memcpy(shaderBindingTables.hit.mapped, shaderHandleStorage.data() + handleSizeAligned * 2, handleSize);
    }

    /*
        Create the descriptor sets used for the ray tracing dispatch
    */
	// done
    void createDescriptorSets()
    {
        std::vector<VkDescriptorPoolSize> poolSizes = {
                { VK_DESCRIPTOR_TYPE_ACCELERATION_STRUCTURE_KHR, maxConcurrentFrames },
                { VK_DESCRIPTOR_TYPE_STORAGE_IMAGE, maxConcurrentFrames },
                { VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER, maxConcurrentFrames },
                { VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, maxConcurrentFrames * 2 }
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
            descriptorAccelerationStructureInfo.pAccelerationStructures = &topLevelAS.handle;

            VkWriteDescriptorSet accelerationStructureWrite{};
            accelerationStructureWrite.sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET;
            // The specialized acceleration structure descriptor has to be chained
            accelerationStructureWrite.pNext = &descriptorAccelerationStructureInfo;
            accelerationStructureWrite.dstSet = descriptorSets[i];
            accelerationStructureWrite.dstBinding = 0;
            accelerationStructureWrite.descriptorCount = 1;
            accelerationStructureWrite.descriptorType = VK_DESCRIPTOR_TYPE_ACCELERATION_STRUCTURE_KHR;

            VkDescriptorImageInfo storageImageDescriptor{ VK_NULL_HANDLE, storageImage.view, VK_IMAGE_LAYOUT_GENERAL };
        	

            std::vector<VkWriteDescriptorSet> writeDescriptorSets = {
                    // Binding 0: Top level acceleration structure
                    accelerationStructureWrite,
                    // Binding 1: Ray tracing result image
                    vks::initializers::writeDescriptorSet(descriptorSets[i], VK_DESCRIPTOR_TYPE_STORAGE_IMAGE, 1, &storageImageDescriptor),
                    // Binding 2: Uniform data
                    vks::initializers::writeDescriptorSet(descriptorSets[i], VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER, 2, &uniformBuffers[i].descriptor),
            		// Binding 3: Geometry Nodes
            		vks::initializers::writeDescriptorSet(descriptorSets[i], VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, 3, &geometryNodesBuffer.descriptor),
            		// Binding 4: Material Data
            		vks::initializers::writeDescriptorSet(descriptorSets[i], VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, 4, &materialDataBuffer.descriptor)
            };
            vkUpdateDescriptorSets(device, static_cast<uint32_t>(writeDescriptorSets.size()), writeDescriptorSets.data(), 0, VK_NULL_HANDLE);
        }
    }

    /*
        Create our ray tracing pipeline
    */
	// done
    void createRayTracingPipeline()
    {
        std::vector<VkDescriptorSetLayoutBinding> setLayoutBindings = {
                // Binding 0: Acceleration structure
                vks::initializers::descriptorSetLayoutBinding(VK_DESCRIPTOR_TYPE_ACCELERATION_STRUCTURE_KHR, VK_SHADER_STAGE_RAYGEN_BIT_KHR | VK_SHADER_STAGE_CLOSEST_HIT_BIT_KHR, 0),
                // Binding 1: Storage image
                vks::initializers::descriptorSetLayoutBinding(VK_DESCRIPTOR_TYPE_STORAGE_IMAGE, VK_SHADER_STAGE_RAYGEN_BIT_KHR, 1),
                // Binding 2: Uniform buffer
                vks::initializers::descriptorSetLayoutBinding(VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER, VK_SHADER_STAGE_RAYGEN_BIT_KHR | VK_SHADER_STAGE_CLOSEST_HIT_BIT_KHR | VK_SHADER_STAGE_MISS_BIT_KHR, 2),
        		// Binding 3: Geometry Nodes buffer
        		vks::initializers::descriptorSetLayoutBinding(VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, VK_SHADER_STAGE_CLOSEST_HIT_BIT_KHR | VK_SHADER_STAGE_ANY_HIT_BIT_KHR, 3),
        		// Binding 4: Base Colors buffer
        		vks::initializers::descriptorSetLayoutBinding(VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, VK_SHADER_STAGE_RAYGEN_BIT_KHR | VK_SHADER_STAGE_CLOSEST_HIT_BIT_KHR, 4)
        };

        VkDescriptorSetLayoutCreateInfo descriptorSetLayoutCI = vks::initializers::descriptorSetLayoutCreateInfo(setLayoutBindings);
        VK_CHECK_RESULT(vkCreateDescriptorSetLayout(device, &descriptorSetLayoutCI, nullptr, &descriptorSetLayout));

        VkPipelineLayoutCreateInfo pPipelineLayoutCI = vks::initializers::pipelineLayoutCreateInfo(&descriptorSetLayout, 1);
        VK_CHECK_RESULT(vkCreatePipelineLayout(device, &pPipelineLayoutCI, nullptr, &pipelineLayout));

        /*
            Setup ray tracing shader groups
        */
        std::vector<VkPipelineShaderStageCreateInfo> shaderStages;

        VkSpecializationMapEntry specializationMapEntry = vks::initializers::specializationMapEntry(0, 0, sizeof(uint32_t));
        uint32_t maxRecursion = 4;
        VkSpecializationInfo specializationInfo = vks::initializers::specializationInfo(1, &specializationMapEntry, sizeof(maxRecursion), &maxRecursion);

        // Ray generation group
        {
            shaderStages.push_back(loadShader(getShadersPath() + "pathtracing/cbraygen.rgen.spv", VK_SHADER_STAGE_RAYGEN_BIT_KHR));
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
            shaderStages.push_back(loadShader(getShadersPath() + "pathtracing/cbmiss.rmiss.spv", VK_SHADER_STAGE_MISS_BIT_KHR));
            VkRayTracingShaderGroupCreateInfoKHR shaderGroup{};
            shaderGroup.sType = VK_STRUCTURE_TYPE_RAY_TRACING_SHADER_GROUP_CREATE_INFO_KHR;
            shaderGroup.type = VK_RAY_TRACING_SHADER_GROUP_TYPE_GENERAL_KHR;
            shaderGroup.generalShader = static_cast<uint32_t>(shaderStages.size()) - 1;
            shaderGroup.closestHitShader = VK_SHADER_UNUSED_KHR;
            shaderGroup.anyHitShader = VK_SHADER_UNUSED_KHR;
            shaderGroup.intersectionShader = VK_SHADER_UNUSED_KHR;
            shaderGroups.push_back(shaderGroup);
        }

        // Closest hit group
        {
            shaderStages.push_back(loadShader(getShadersPath() + "pathtracing/cbclosesthit.rchit.spv", VK_SHADER_STAGE_CLOSEST_HIT_BIT_KHR));
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
        rayTracingPipelineCI.maxPipelineRayRecursionDepth = std::min(uint32_t(4), rayTracingPipelineProperties.maxRayRecursionDepth);
        rayTracingPipelineCI.layout = pipelineLayout;
        VK_CHECK_RESULT(vkCreateRayTracingPipelinesKHR(device, VK_NULL_HANDLE, VK_NULL_HANDLE, 1, &rayTracingPipelineCI, nullptr, &pipeline));
    }

    /*
        Create the uniform buffer used to pass matrices to the ray tracing ray generation shader
    */
    void createUniformBuffer()
    {
        for (auto& buffer : uniformBuffers) {
            VK_CHECK_RESULT(vulkanDevice->createBuffer(VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT, VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | VK_MEMORY_PROPERTY_HOST_COHERENT_BIT, &buffer, sizeof(UniformData), &uniformData));
            VK_CHECK_RESULT(buffer.map());
        }
    }

    /*
        If the window has been resized, we need to recreate the storage image and it's descriptor
    */
    void handleResize()
    {
        // Recreate image
        createStorageImage(swapChain.colorFormat, { width, height, 1 });
        // Update descriptors
        VkDescriptorImageInfo storageImageDescriptor{ VK_NULL_HANDLE, storageImage.view, VK_IMAGE_LAYOUT_GENERAL };
        for (auto i = 0; i < maxConcurrentFrames; i++) {
            VkWriteDescriptorSet resultImageWrite = vks::initializers::writeDescriptorSet(descriptorSets[i], VK_DESCRIPTOR_TYPE_STORAGE_IMAGE, 1, &storageImageDescriptor);
            vkUpdateDescriptorSets(device, 1, &resultImageWrite, 0, VK_NULL_HANDLE);
        }
        resized = false;
    }

	// done
    void updateUniformBuffers()
    {
        uniformData.projInverse = glm::inverse(camera.matrices.perspective);
        uniformData.viewInverse = glm::inverse(camera.matrices.view);
    	uniformData.frame++;
        memcpy(uniformBuffers[currentBuffer].mapped, &uniformData, sizeof(uniformData));
    }

	// done
    void getEnabledFeatures()
    {
        // Enable features required for ray tracing using feature chaining via pNext
        enabledBufferDeviceAddresFeatures.sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_BUFFER_DEVICE_ADDRESS_FEATURES;
        enabledBufferDeviceAddresFeatures.bufferDeviceAddress = VK_TRUE;

        enabledRayTracingPipelineFeatures.sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_RAY_TRACING_PIPELINE_FEATURES_KHR;
        enabledRayTracingPipelineFeatures.rayTracingPipeline = VK_TRUE;
        enabledRayTracingPipelineFeatures.pNext = &enabledBufferDeviceAddresFeatures;

        enabledAccelerationStructureFeatures.sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_ACCELERATION_STRUCTURE_FEATURES_KHR;
        enabledAccelerationStructureFeatures.accelerationStructure = VK_TRUE;
        enabledAccelerationStructureFeatures.pNext = &enabledRayTracingPipelineFeatures;

    	physicalDeviceDescriptorIndexingFeatures.sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_DESCRIPTOR_INDEXING_FEATURES_EXT;
    	physicalDeviceDescriptorIndexingFeatures.shaderSampledImageArrayNonUniformIndexing = VK_TRUE;
    	physicalDeviceDescriptorIndexingFeatures.runtimeDescriptorArray = VK_TRUE;
    	physicalDeviceDescriptorIndexingFeatures.descriptorBindingVariableDescriptorCount = VK_TRUE;
    	physicalDeviceDescriptorIndexingFeatures.pNext = &enabledAccelerationStructureFeatures;
    	
        deviceCreatepNextChain = &physicalDeviceDescriptorIndexingFeatures;

    	enabledFeatures.samplerAnisotropy = VK_TRUE;
    }


	// done
    void prepare()
    {
        VulkanRaytracingSample::prepare();
        
        loadAssets();
        // Create the acceleration structures used to render the ray traced scene
        createBottomLevelAccelerationStructure();
        createTopLevelAccelerationStructure();

        createStorageImage(swapChain.colorFormat, { width, height, 1 });
        createUniformBuffer();
        createRayTracingPipeline();
        createShaderBindingTables();
        createDescriptorSets();
        prepared = true;
    }

	
    void buildCommandBuffer()
    {
        if (resized)
        {
            handleResize();
        }

        VkCommandBuffer cmdBuffer = drawCmdBuffers[currentBuffer];

        VkCommandBufferBeginInfo cmdBufInfo = vks::initializers::commandBufferBeginInfo();

        VkImageSubresourceRange subresourceRange = { VK_IMAGE_ASPECT_COLOR_BIT, 0, 1, 0, 1 };

        VK_CHECK_RESULT(vkBeginCommandBuffer(cmdBuffer, &cmdBufInfo));

        vkCmdBindPipeline(cmdBuffer, VK_PIPELINE_BIND_POINT_RAY_TRACING_KHR, pipeline);
        vkCmdBindDescriptorSets(cmdBuffer, VK_PIPELINE_BIND_POINT_RAY_TRACING_KHR, pipelineLayout, 0, 1, &descriptorSets[currentBuffer], 0, 0);

        /*
            Dispatch the ray tracing commands
        */
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

        /*
            Copy ray tracing output to swap chain image
        */

        // Prepare current swap chain image as transfer destination
        vks::tools::setImageLayout(
                cmdBuffer,
                swapChain.images[currentImageIndex],
                VK_IMAGE_LAYOUT_UNDEFINED,
                VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
                subresourceRange);

        // Prepare ray tracing output image as transfer source
        vks::tools::setImageLayout(
                cmdBuffer,
                storageImage.image,
                VK_IMAGE_LAYOUT_GENERAL,
                VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL,
                subresourceRange);

        VkImageCopy copyRegion{};
        copyRegion.srcSubresource = { VK_IMAGE_ASPECT_COLOR_BIT, 0, 0, 1 };
        copyRegion.srcOffset = { 0, 0, 0 };
        copyRegion.dstSubresource = { VK_IMAGE_ASPECT_COLOR_BIT, 0, 0, 1 };
        copyRegion.dstOffset = { 0, 0, 0 };
        copyRegion.extent = { width, height, 1 };
        vkCmdCopyImage(cmdBuffer, storageImage.image, VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL, swapChain.images[currentImageIndex], VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, 1, &copyRegion);

        // Transition swap chain image back for presentation
        vks::tools::setImageLayout(
                cmdBuffer,
                swapChain.images[currentImageIndex],
                VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
                VK_IMAGE_LAYOUT_PRESENT_SRC_KHR,
                subresourceRange);

        // Transition ray tracing output image back to general layout
        vks::tools::setImageLayout(
                cmdBuffer,
                storageImage.image,
                VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL,
                VK_IMAGE_LAYOUT_GENERAL,
                subresourceRange);

        drawUI(cmdBuffer, frameBuffers[currentImageIndex]);

        VK_CHECK_RESULT(vkEndCommandBuffer(cmdBuffer));
    }

	// done
    virtual void render()
    {
        if (!prepared)
            return;
        VulkanExampleBase::prepareFrame();
    	if (camera.updated) {
    		// If the camera's view has been updated we need to  reset the frame accumulation (which is used for transparent surfaces and anti-aliasing)
    		uniformData.frame = -1;
    	}
        updateUniformBuffers();
        buildCommandBuffer();
        VulkanExampleBase::submitFrame();
    }
};


CornellBox *cornellBox;																		
LRESULT CALLBACK WndProc(HWND hWnd, UINT uMsg, WPARAM wParam, LPARAM lParam)						
{																									
    if (cornellBox != NULL)																		
    {																								
        cornellBox->handleMessages(hWnd, uMsg, wParam, lParam);									
    }																								
    return (DefWindowProc(hWnd, uMsg, wParam, lParam));												
}																									
int APIENTRY WinMain(_In_ HINSTANCE hInstance, _In_opt_  HINSTANCE hPrevInstance, _In_ LPSTR, _In_ int) 
{																									
    for (int32_t i = 0; i < __argc; i++) { CornellBox::args.push_back(__argv[i]); }			
    cornellBox = new CornellBox();															
    cornellBox->initVulkan();																	
    cornellBox->setupWindow(hInstance, WndProc);													
    cornellBox->prepare();																		
    cornellBox->renderLoop();																	
    delete(cornellBox);																			
    return 0;																						
}
