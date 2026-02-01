#pragma once
#include "utils.hpp"

class DDGIRayTracing
{
public:
    DDGIRayTracing(
        VkDevice _device,
        VkPhysicalDeviceRayTracingPipelinePropertiesKHR* _rayTracingPipelineProperties,
        vks::VulkanDevice* _vulkanDevice,
        vkglTF::Model* _model,
        VkDescriptorPool _descriptorPool,
        AccelerationStructure* _bottomLevelAS,
        AccelerationStructure* _topLevelAS,
        StorageImage* _storageImage,
        vks::Buffer* _geometryNodesBuffer)
    {
        device = _device;
        rayTracingPipelineProperties = _rayTracingPipelineProperties;
        vulkanDevice = _vulkanDevice;
        model = _model;
        descriptorPool = _descriptorPool;
        bottomLevelAS = _bottomLevelAS;
        topLevelAS = _topLevelAS;
        storageImage = _storageImage;
        geometryNodesBuffer = _geometryNodesBuffer;
        
        vkGetBufferDeviceAddressKHR = reinterpret_cast<PFN_vkGetBufferDeviceAddressKHR>(vkGetDeviceProcAddr(device, "vkGetBufferDeviceAddressKHR"));
        vkGetRayTracingShaderGroupHandlesKHR = reinterpret_cast<PFN_vkGetRayTracingShaderGroupHandlesKHR>(vkGetDeviceProcAddr(device, "vkGetRayTracingShaderGroupHandlesKHR"));
        vkCmdTraceRaysKHR = reinterpret_cast<PFN_vkCmdTraceRaysKHR>(vkGetDeviceProcAddr(device, "vkCmdTraceRaysKHR"));
        vkCreateRayTracingPipelinesKHR = reinterpret_cast<PFN_vkCreateRayTracingPipelinesKHR>(vkGetDeviceProcAddr(device, "vkCreateRayTracingPipelinesKHR"));
    }

    virtual ~DDGIRayTracing()
    {
        vkDestroyPipeline(device, pipeline, nullptr);
        vkDestroyPipelineLayout(device, pipelineLayout, nullptr);
        vkDestroyDescriptorSetLayout(device, descriptorSetLayout, nullptr);
		
        shaderBindingTables.raygen.destroy();
        shaderBindingTables.miss.destroy();
        shaderBindingTables.hit.destroy();

        for (auto& shaderModule: shaderModules)
        {
            vkDestroyShaderModule(device, shaderModule, nullptr);
        }
    }

    virtual void prepare()
    {
        createUniformBuffer();
        createRayTracingPipeline();
        createShaderBindingTables();
        createDescriptorSets();
    }

    virtual void recordCommandBuffer(VkCommandBuffer cmdBuffer, uint32_t currentBuffer) = 0;
	

protected:
    VkDevice device{VK_NULL_HANDLE};
    VkPhysicalDeviceRayTracingPipelinePropertiesKHR*  rayTracingPipelineProperties = nullptr;
    vks::VulkanDevice* vulkanDevice = nullptr;
    vkglTF::Model* model = nullptr;
    VkDescriptorPool descriptorPool{VK_NULL_HANDLE};
    AccelerationStructure* bottomLevelAS = nullptr;
    AccelerationStructure* topLevelAS = nullptr;
    StorageImage* storageImage = nullptr;
    vks::Buffer* geometryNodesBuffer = nullptr;
    
    PFN_vkGetBufferDeviceAddressKHR vkGetBufferDeviceAddressKHR{ VK_NULL_HANDLE };
    PFN_vkGetRayTracingShaderGroupHandlesKHR vkGetRayTracingShaderGroupHandlesKHR{ VK_NULL_HANDLE };
    PFN_vkCmdTraceRaysKHR vkCmdTraceRaysKHR{ VK_NULL_HANDLE };
    PFN_vkCreateRayTracingPipelinesKHR vkCreateRayTracingPipelinesKHR{ VK_NULL_HANDLE };
    
	
	std::vector<VkShaderModule> shaderModules{};
    VkPipeline pipeline{ VK_NULL_HANDLE };
    VkPipelineLayout pipelineLayout{ VK_NULL_HANDLE };
    
    VkDescriptorSetLayout descriptorSetLayout{ VK_NULL_HANDLE };
    std::array<VkDescriptorSet, maxConcurrentFrames> descriptorSets{};
    std::vector<VkRayTracingShaderGroupCreateInfoKHR> shaderGroups{};
    ShaderBindingTables shaderBindingTables;


	VkPipelineShaderStageCreateInfo loadShader(VkDevice device, std::string fileName, VkShaderStageFlagBits stage)
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
		shaderModules.push_back(shaderStage.module);
		return shaderStage;
	}
	
    uint64_t getBufferDeviceAddress(VkBuffer buffer)
    {
        VkBufferDeviceAddressInfoKHR bufferDeviceAI{
            .sType = VK_STRUCTURE_TYPE_BUFFER_DEVICE_ADDRESS_INFO,
            .buffer = buffer
        };
        return vkGetBufferDeviceAddressKHR(vulkanDevice->logicalDevice, &bufferDeviceAI);
    }
    
    VkStridedDeviceAddressRegionKHR getSbtEntryStridedDeviceAddressRegion(VkBuffer buffer, uint32_t handleCount)
    {
        const uint32_t handleSizeAligned = vks::tools::alignedSize(rayTracingPipelineProperties->shaderGroupHandleSize, rayTracingPipelineProperties->shaderGroupHandleAlignment);
        VkStridedDeviceAddressRegionKHR stridedDeviceAddressRegionKHR{
            .deviceAddress = getBufferDeviceAddress(buffer),
            .stride = handleSizeAligned
        };
        stridedDeviceAddressRegionKHR.size = handleCount * handleSizeAligned;
        return stridedDeviceAddressRegionKHR;
    }

    void createShaderBindingTable(ShaderBindingTable& shaderBindingTable, uint32_t handleCount)
    {
        // Create buffer to hold all shader handles for the SBT
        VK_CHECK_RESULT(vulkanDevice->createBuffer(
            VK_BUFFER_USAGE_SHADER_BINDING_TABLE_BIT_KHR | VK_BUFFER_USAGE_SHADER_DEVICE_ADDRESS_BIT, 
            VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | VK_MEMORY_PROPERTY_HOST_COHERENT_BIT, 
            &shaderBindingTable, 
            rayTracingPipelineProperties->shaderGroupHandleSize * handleCount));
        // Get the strided address to be used when dispatching the rays
        shaderBindingTable.stridedDeviceAddressRegion = getSbtEntryStridedDeviceAddressRegion(shaderBindingTable.buffer, handleCount);
        // Map persistent 
        shaderBindingTable.map();
    }
    
    virtual void createUniformBuffer() = 0;
    virtual void createRayTracingPipeline() = 0;
    virtual void createShaderBindingTables() = 0;
    virtual void createDescriptorSets() = 0;
};