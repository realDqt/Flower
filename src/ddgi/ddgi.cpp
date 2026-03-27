/*
 * Vulkan Example - Rendering a glTF model using hardware accelerated ray tracing example (for proper transparency, this sample does frame accumulation)
 *
 * Copyright (C) 2023-2025 by Sascha Willems - www.saschawillems.de
 *
 * This code is licensed under the MIT license (MIT) (http://opensource.org/licenses/MIT)
 */
#pragma once
#include "ProbeTraceRayTracing.hpp"
#include "ProbeBlendIrradianceCompute.hpp"
#include "ProbeBlendDistanceCompute.hpp"
#include "ProbeRelocationCompute.hpp"
#include "ProbeClassificationCompute.hpp"
#include "SceneShadingRayTracing.hpp"

class CornellBox : public VulkanRaytracingSample
{
public:
	AccelerationStructure bottomLevelAS{};
	AccelerationStructure topLevelAS{};

	vks::Buffer vertexBuffer;
	vks::Buffer indexBuffer;
	uint32_t indexCount{ 0 };
	vks::Buffer transformBuffer;
	vks::Buffer geometryNodesBuffer;
    vks::Buffer materialDataBuffer;
    vks::Buffer ddgiVolumes;

    vks::Texture probeIrradiance;
    vks::Texture probeDistance;
    vks::Texture probeData;
    vks::Texture rayData;


    vkobj::Model cornell;
    std::vector<std::string> filenames;
    std::vector<vkobj::Material> materials;

	VkPhysicalDeviceDescriptorIndexingFeaturesEXT physicalDeviceDescriptorIndexingFeatures{};

    std::unique_ptr<ProbeTraceRayTracing> probeTraceRayTracing = nullptr;
    std::unique_ptr<ProbeBlendIrradianceCompute> probeBlendIrradianceCompute = nullptr;
    std::unique_ptr<ProbeBlendDistanceCompute> probeBlendDistanceCompute = nullptr;
    std::unique_ptr<ProbeRelocationCompute> probeRelocationCompute = nullptr;
	std::unique_ptr<ProbeClassificationCompute> probeClassificationCompute = nullptr;
	std::unique_ptr<SceneShadingRayTracing> sceneShadingRayTracing = nullptr;

    int32_t probeVisualizationMode{ 0 };
    bool probeVisualizationXRay{ false };
    float probeVisualizationRadius{ 0.15f };
    float probeVisualizationOpacity{ 0.85f };


    CornellBox() : VulkanRaytracingSample()
    {
        title = "DDGI";
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
		if (device) {
			deleteStorageImage();
			deleteAccelerationStructure(bottomLevelAS);
			deleteAccelerationStructure(topLevelAS);
			vertexBuffer.destroy();
			indexBuffer.destroy();
			transformBuffer.destroy();
			geometryNodesBuffer.destroy();
            materialDataBuffer.destroy();
		}
	}

    void createAccelerationStructureBuffer(AccelerationStructure& accelerationStructure, VkAccelerationStructureBuildSizesInfoKHR buildSizeInfo)
    {
        // create buffer
        VkBufferCreateInfo bufferCreateInfo{};
        bufferCreateInfo.sType = VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO;
        bufferCreateInfo.size = buildSizeInfo.accelerationStructureSize;
        bufferCreateInfo.usage = VK_BUFFER_USAGE_ACCELERATION_STRUCTURE_STORAGE_BIT_KHR | VK_BUFFER_USAGE_SHADER_DEVICE_ADDRESS_BIT;
        VK_CHECK_RESULT(vkCreateBuffer(device, &bufferCreateInfo, nullptr, &accelerationStructure.buffer));

        // allocate memory
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

        // bind buffer and memory
        VK_CHECK_RESULT(vkBindBufferMemory(device, accelerationStructure.buffer, accelerationStructure.memory, 0));
    }

    // done
    void createBottomLevelAccelerationStructure()
    {
        // Build
        // One geometry per obj, so we can index materials using gl_GeometryIndexEXT
        std::vector<uint32_t> maxPrimitiveCounts{};
        std::vector<VkAccelerationStructureGeometryKHR> geometries{};
        std::vector<VkAccelerationStructureBuildRangeInfoKHR> buildRangeInfos{};
        std::vector<VkAccelerationStructureBuildRangeInfoKHR*> pBuildRangeInfos{};
        std::vector<GeometryNode> geometryNodes{};
        std::vector<vkobj::MaterialData> materialDataVec{};
        int meshIndex = 0;
        for (auto mesh : cornell.meshes) {
            if (mesh->indexCount > 0) {
                VkDeviceOrHostAddressConstKHR vertexBufferDeviceAddress{};
                VkDeviceOrHostAddressConstKHR indexBufferDeviceAddress{};

                vertexBufferDeviceAddress.deviceAddress = getBufferDeviceAddress(cornell.vertices.buffer);
                indexBufferDeviceAddress.deviceAddress = getBufferDeviceAddress(cornell.indices.buffer) + mesh->firstIndex * sizeof(uint32_t);


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
            meshIndex++;
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
        VkTransformMatrixKHR transformMatrix = {};

        auto m44 = glm::mat4(1.0f);
        float scale = 0.001f;
        glm::vec3 axisX = glm::vec3(1.0f, 0.0f, 0.0f);

        m44 = glm::rotate(m44, glm::radians(180.0f), axisX);
        m44 = glm::scale(m44, glm::vec3(scale));

        // 转置以适应 Vulkan [3][4] 行主序布局
        auto m44Trans = glm::transpose(m44);
        const float* rawData = reinterpret_cast<const float*>(&m44Trans);
        for (int i = 0; i < 3; ++i) {
            for (int j = 0; j < 4; ++j) {
                transformMatrix.matrix[i][j] = rawData[i * 4 + j];
            }
        }

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
		If the window has been resized, we need to recreate the storage image and it's descriptor
	*/
	void handleResize()
	{
		/*
		// Recreate image
		createStorageImage(swapChain.colorFormat, { width, height, 1 });
		// Update descriptors
		VkDescriptorImageInfo storageImageDescriptor{ VK_NULL_HANDLE, storageImage.view, VK_IMAGE_LAYOUT_GENERAL };
		for (auto i = 0; i < maxConcurrentFrames; i++) {
			VkWriteDescriptorSet resultImageWrite = vks::initializers::writeDescriptorSet(sceneShadingRayTracing->descriptorSets[i], VK_DESCRIPTOR_TYPE_STORAGE_IMAGE, 1, &storageImageDescriptor);
			vkUpdateDescriptorSets(device, 1, &resultImageWrite, 0, VK_NULL_HANDLE);
		}
		resized = false;
		*/
	}

	void updateUniformBuffers()
	{
		sceneShadingRayTracing->uniformData.projInverse = glm::inverse(camera.matrices.perspective);
		sceneShadingRayTracing->uniformData.viewInverse = glm::inverse(camera.matrices.view);
        sceneShadingRayTracing->uniformData.position = -camera.position; // TODO
        sceneShadingRayTracing->uniformData.probeDebugFlags = glm::ivec4(
                probeVisualizationMode,
                probeVisualizationXRay ? 1 : 0,
                0,
                0);
        sceneShadingRayTracing->uniformData.probeDebugParams = glm::vec4(
                probeVisualizationRadius,
                probeVisualizationOpacity,
                0.0f,
                0.0f);
		// This value is used to accumulate multiple frames into the finale picture
		// It's required as ray tracing needs to do multiple passes for transparency
		// In this sample we use noise offset by this frame index to shoot rays for transparency into different directions
		// Once enough frames with random ray directions have been accumulated, it looks like proper transparency
		sceneShadingRayTracing->uniformData.frame++;
		memcpy(sceneShadingRayTracing->uniformBuffers[currentBuffer].mapped, &sceneShadingRayTracing->uniformData, sizeof(SceneShadingRayTracing::UniformData));
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
        vkobj::Material yellow(vulkanDevice);
        yellow.baseColor =  glm::vec4(1.f, 1.f, 0.f, 1.0f);
        //light.emission = 8.0f * glm::vec3(0.747f+0.058f, 0.747f+0.258f, 0.747f) + 15.6f * glm::vec3(0.740f+0.287f,0.740f+0.160f,0.740f) + 18.4f * glm::vec3(0.737f+0.642f,0.737f+0.159f,0.737f);
        vkobj::Material specular(vulkanDevice);
        specular.baseColor = glm::vec4(0.725f, 0.71f, 0.68f, 1.0f);
        specular.metallic = 1.0f;
        specular.roughness = 0.0f;

        materials.push_back(white);
        materials.push_back(red);
        materials.push_back(yellow);
        materials.push_back(green);
        materials.push_back(white);
        materials.push_back(white);

        // 加载obj
        cornell.loadFromFile(filenames, materials, vulkanDevice, queue);
    }

    void createDDGIVolumeTextures()
    {
        createDDGIVolumeTexture(EDDGIVolumeTextureType::Irradiance, probeIrradiance, vulkanDevice, queue);
        createDDGIVolumeTexture(EDDGIVolumeTextureType::Distance, probeDistance, vulkanDevice, queue);
        createDDGIVolumeTexture(EDDGIVolumeTextureType::Data, probeData, vulkanDevice, queue);
        createDDGIVolumeTexture(EDDGIVolumeTextureType::RayData, rayData, vulkanDevice, queue);
    }

    void createDDGIVolumes()
    {
        vks::Buffer stagingBuffer;

        VK_CHECK_RESULT(vulkanDevice->createBuffer(
                VK_BUFFER_USAGE_TRANSFER_SRC_BIT,
                VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | VK_MEMORY_PROPERTY_HOST_COHERENT_BIT,
                &stagingBuffer,
                sizeof(DDGIVolumeDescGPUPacked),
                getGlobalDDGIVolumeDescGPUPacked()));

        VK_CHECK_RESULT(vulkanDevice->createBuffer(
                VK_BUFFER_USAGE_SHADER_DEVICE_ADDRESS_BIT | VK_BUFFER_USAGE_STORAGE_BUFFER_BIT | VK_BUFFER_USAGE_TRANSFER_DST_BIT,
                VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT,
                &ddgiVolumes,
                sizeof(DDGIVolumeDescGPUPacked)));

        vulkanDevice->copyBuffer(&stagingBuffer, &ddgiVolumes, queue);

        stagingBuffer.destroy();
    }

	void prepare()
	{
		VulkanRaytracingSample::prepare();

		loadAssets();

		// Create the acceleration structures used to render the ray traced scene
		createBottomLevelAccelerationStructure();
		createTopLevelAccelerationStructure();
		createStorageImage(swapChain.colorFormat, { width, height, 1 });

        createDDGIVolumeTextures();
        createDDGIVolumes();

        probeTraceRayTracing = std::make_unique<ProbeTraceRayTracing>(device, &rayTracingPipelineProperties, vulkanDevice, &cornell, &bottomLevelAS, &topLevelAS, &storageImage, &geometryNodesBuffer, &materialDataBuffer, &probeIrradiance, &probeDistance, &probeData, &rayData, &ddgiVolumes);
        probeTraceRayTracing->prepare();

        probeBlendIrradianceCompute = std::make_unique<ProbeBlendIrradianceCompute>(device, pipelineCache, &ddgiVolumes, &probeIrradiance, &rayData, &probeData);
        probeBlendIrradianceCompute->prepare();

        probeBlendDistanceCompute = std::make_unique<ProbeBlendDistanceCompute>(device, pipelineCache, &ddgiVolumes, &probeDistance, &rayData, &probeData);
        probeBlendDistanceCompute->prepare();

        probeRelocationCompute = std::make_unique<ProbeRelocationCompute>(device, pipelineCache, &ddgiVolumes, &rayData, &probeData);
        probeRelocationCompute->prepare();

        probeClassificationCompute = std::make_unique<ProbeClassificationCompute>(device, pipelineCache, &ddgiVolumes, &rayData, &probeData);
        probeClassificationCompute->prepare();

		sceneShadingRayTracing = std::make_unique<SceneShadingRayTracing>(device, &rayTracingPipelineProperties, vulkanDevice, &cornell, &bottomLevelAS, &topLevelAS, &storageImage, &geometryNodesBuffer, &materialDataBuffer, &ddgiVolumes, &probeIrradiance, &probeDistance, &probeData);
		sceneShadingRayTracing->prepare();
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


        probeTraceRayTracing->recordCommandBuffer(cmdBuffer, currentBuffer);
        probeBlendIrradianceCompute->recordCommandBuffer(cmdBuffer, currentBuffer);
        probeBlendDistanceCompute->recordCommandBuffer(cmdBuffer, currentBuffer);
        probeRelocationCompute->recordCommandBuffer(cmdBuffer, currentBuffer);
        probeClassificationCompute->recordCommandBuffer(cmdBuffer, currentBuffer);
		sceneShadingRayTracing->recordCommandBuffer(cmdBuffer, currentBuffer);
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


	virtual void render()
	{
		if (!prepared)
			return;
		VulkanExampleBase::prepareFrame();
		if (camera.updated) {
			// If the camera's view has been updated we need to  reset the frame accumulation (which is used for transparent surfaces and anti-aliasing)
			sceneShadingRayTracing->uniformData.frame = -1;
		}
		//printVec3(camera.position);
		updateUniformBuffers();
		buildCommandBuffer();
		VulkanExampleBase::submitFrame();
	}

    void OnUpdateUIOverlay(vks::UIOverlay* overlay) override
    {
        if (!overlay->header("DDGI Debug")) {
            return;
        }

        bool changed = false;
        changed |= overlay->comboBox("Probe visualization", &probeVisualizationMode, { "Off", "State", "Irradiance", "Distance" });

        if (probeVisualizationMode > 0) {
            changed |= overlay->checkBox("Probe x-ray", &probeVisualizationXRay);
            changed |= overlay->sliderFloat("Probe radius", &probeVisualizationRadius, 0.05f, 0.45f);
            changed |= overlay->sliderFloat("Probe opacity", &probeVisualizationOpacity, 0.10f, 1.0f);
            overlay->text("State shows active/inactive and relocation.");
            overlay->text("Irradiance/Distance are sampled from the view direction.");
        }

        if (changed && sceneShadingRayTracing) {
            sceneShadingRayTracing->uniformData.frame = -1;
        }
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
