#pragma once
#include "Common.hpp"
#include "DDGIVolumeDescGPU.hpp"

inline void printVec3(const glm::vec3& rhs)
{
    std::cout << rhs.x << " " << rhs.y << " " << rhs.z << "\n";
}

inline std::string getShadersPath()
{
    std::string shaderDir = "glsl";
    return getShaderBasePath() + shaderDir + "/";
}

inline DDGIVolumeDescGPU* getGlobalDDGIVolumeDescGPU()
{
    static DDGIVolumeDescGPU ddgiVolumeDescGPU{};
    static bool initialized = false;
    if(!initialized){
        ddgiVolumeDescGPU.origin = -glm::vec3(-0.25, 0.25, 0.25);
        ddgiVolumeDescGPU.rotation = glm::vec4(0, 0, 0, 1);
        ddgiVolumeDescGPU.probeRayRotation = glm::vec4(0, 0, 0, 1);
        ddgiVolumeDescGPU.movementType = 0;

        ddgiVolumeDescGPU.probeSpacing = glm::vec3(0.08);
        ddgiVolumeDescGPU.probeCounts = glm::ivec3(9);

        ddgiVolumeDescGPU.probeNumRays = 256;
        ddgiVolumeDescGPU.probeNumIrradianceInteriorTexels = DDGI_PROBE_IRRADIANCE_SIDE;
        ddgiVolumeDescGPU.probeNumDistanceInteriorTexels = DDGI_PROBE_DEPTH_SIDE;

        ddgiVolumeDescGPU.probeHysteresis = 0.97f;
        ddgiVolumeDescGPU.probeMaxRayDistance = 10.f;
        ddgiVolumeDescGPU.probeNormalBias = 0.03f;
        ddgiVolumeDescGPU.probeViewBias = 0.01f;
        ddgiVolumeDescGPU.probeDistanceExponent = 50.f;
        ddgiVolumeDescGPU.probeIrradianceEncodingGamma = 5.f;

        ddgiVolumeDescGPU.probeIrradianceThreshold = 0.2f;
        ddgiVolumeDescGPU.probeBrightnessThreshold = 1.0f;
        ddgiVolumeDescGPU.probeRandomRayBackfaceThreshold = 0.1f;

        ddgiVolumeDescGPU.probeFixedRayBackfaceThreshold = 0.25f;
        ddgiVolumeDescGPU.probeMinFrontfaceDistance = 0.025f;

        ddgiVolumeDescGPU.probeScrollOffsets = glm::ivec3(0, 0, 0);
        for(int i = 0; i < 3; ++i)
        {
            ddgiVolumeDescGPU.probeScrollClear[i] = false;
            ddgiVolumeDescGPU.probeScrollDirections[i] = false;
        }

        ddgiVolumeDescGPU.probeRayDataFormat = 6;
        ddgiVolumeDescGPU.probeIrradianceFormat = 6;

        ddgiVolumeDescGPU.probeRelocationEnabled = true;
        ddgiVolumeDescGPU.probeClassificationEnabled = true;
        ddgiVolumeDescGPU.probeVariabilityEnabled = false;

        initialized = true;
    }
    return &ddgiVolumeDescGPU;
}

inline DDGIVolumeDescGPUPacked* getGlobalDDGIVolumeDescGPUPacked()
{
    static DDGIVolumeDescGPUPacked ddgiVolumeDescGPUPacked{};
    auto pDDGIVolumeDescGPU = getGlobalDDGIVolumeDescGPU();
    ddgiVolumeDescGPUPacked = packDDGIVolumeDescGPU(*pDDGIVolumeDescGPU);
    return &ddgiVolumeDescGPUPacked;
}

inline void getDDGIVolumeProbeCounts(const DDGIVolumeDescGPU& desc, uint32_t& probeCountX, uint32_t& probeCountY, uint32_t& probeCountZ)
{
    probeCountX = (uint32_t)desc.probeCounts.x;
    probeCountY = (uint32_t)desc.probeCounts.z;
    probeCountZ = (uint32_t)desc.probeCounts.y;
}

inline uint32_t getDDGIVolumeProbeCounts(const DDGIVolumeDescGPU& desc)
{
    uint32_t numProbes = desc.probeCounts.x * desc.probeCounts.y * desc.probeCounts.z;
    return numProbes;
}

inline void getDDGIVolumeTextureDimensions(const DDGIVolumeDescGPU& desc, EDDGIVolumeTextureType type, uint32_t& width, uint32_t& height, uint32_t& arraySize)
{
    getDDGIVolumeProbeCounts(desc, width, height, arraySize);
    if (type == EDDGIVolumeTextureType::RayData)
    {
        height = (uint32_t)(width * height);
        width = (uint32_t)desc.probeNumRays;
    }
    else
    {
        if (type == EDDGIVolumeTextureType::Irradiance)
        {
            width *= (uint32_t)(desc.probeNumIrradianceInteriorTexels + 2);
            height *= (uint32_t)(desc.probeNumIrradianceInteriorTexels + 2);
        }
        else if (type == EDDGIVolumeTextureType::Distance)
        {
            width *= (uint32_t)(desc.probeNumDistanceInteriorTexels + 2);
            height *= (uint32_t)(desc.probeNumDistanceInteriorTexels + 2);
        }
        else if (type == EDDGIVolumeTextureType::Variability)
        {
            width *= (uint32_t)(desc.probeNumIrradianceInteriorTexels);
            height *= (uint32_t)(desc.probeNumIrradianceInteriorTexels);
        }
        else if (type == EDDGIVolumeTextureType::VariabilityAverage)
        {
            // Start with Probe variability texture dimensions
            width *= (uint32_t)(desc.probeNumIrradianceInteriorTexels);
            height *= (uint32_t)(desc.probeNumIrradianceInteriorTexels);
            // Divide into thread groups, should match NUM_THREADS_XYZ in ReductionCS.hlsl
            const glm::uvec3 NumThreadsInGroup = { 4, 8, 4 };
            // Also divide by sample footprint per-thread, should match ThreadSampleFootprint in ReductionCS.hlsl
            const glm::uvec3 DimensionScale = { NumThreadsInGroup.x * 4, NumThreadsInGroup.y * 2, NumThreadsInGroup.z };
            // Size of diff total texture is just diff divided by thread group dimensions, rounded up
            width = (width + DimensionScale.x - 1) / DimensionScale.x;
            height = (height + DimensionScale.y - 1) / DimensionScale.y;
            arraySize = (arraySize + DimensionScale.z - 1) / DimensionScale.z;
        }
    }
}

inline void getRayDispatchDimensions(const DDGIVolumeDescGPU& desc, const EDDGIVolumeTextureType& textureType, uint32_t& width, uint32_t& height, uint32_t& depth)
{
    getDDGIVolumeTextureDimensions(desc, textureType, width, height, depth);
}

inline VkImageLayout getInitialLayoutByType(const EDDGIVolumeTextureType& textureType)
{
    switch(textureType){
        case EDDGIVolumeTextureType::RayData:
            return VK_IMAGE_LAYOUT_GENERAL;
        case EDDGIVolumeTextureType::Irradiance:
        case EDDGIVolumeTextureType::Distance:
        case EDDGIVolumeTextureType::Data:
            return VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL;
        default:
            return VK_IMAGE_LAYOUT_GENERAL;
    }
}

inline VkFormat getFormatByType(const EDDGIVolumeTextureType& textureType)
{
    switch(textureType){
        case EDDGIVolumeTextureType::Irradiance:
            return VK_FORMAT_R32G32B32A32_SFLOAT;
        case EDDGIVolumeTextureType::Distance:
            return VK_FORMAT_R32G32_SFLOAT;
        default:
            return VK_FORMAT_R32G32B32A32_SFLOAT;
    }
}

inline glm::vec4 getInitialValueByType(const EDDGIVolumeTextureType& textureType)
{
    switch (textureType) {
        case EDDGIVolumeTextureType::Irradiance:
        case EDDGIVolumeTextureType::Distance:
            return glm::vec4(0.f);
        case EDDGIVolumeTextureType::Data:
            return glm::vec4(0.f, 0.f, 0.f, DDGI_PROBE_STATE_ACTIVE);
        default:
            return glm::vec4(0.f);
    }
}

inline void clearAndTransitionImage(
        vks::VulkanDevice* device,
        VkQueue queue,
        vks::Texture& texture,
        VkImageLayout targetLayout,
        glm::vec4 clearValues = glm::vec4(0.f))
{
    // 1. 创建一次性命令缓冲
    VkCommandBuffer cmd = device->createCommandBuffer(VK_COMMAND_BUFFER_LEVEL_PRIMARY, true);

    VkImageSubresourceRange range = {VK_IMAGE_ASPECT_COLOR_BIT, 0, 1, 0, texture.layerCount};

    // --- 步骤 1: UNDEFINED -> TRANSFER_DST_OPTIMAL ---
    vks::tools::setImageLayout(cmd, texture.image, VK_IMAGE_LAYOUT_UNDEFINED, VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, range, VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT, VK_PIPELINE_STAGE_TRANSFER_BIT);

    // --- 步骤 2: 执行清除 (Clear) ---
    VkClearColorValue cv = { {clearValues[0], clearValues[1], clearValues[2], clearValues[3]} };
    vkCmdClearColorImage(cmd, texture.image, VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, &cv, 1, &range);

    // --- 步骤 3: TRANSFER_DST_OPTIMAL -> 目标布局 (如 SHADER_READ_ONLY 或 GENERAL) ---
    vks::tools::setImageLayout(cmd, texture.image, VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, targetLayout, range, VK_PIPELINE_STAGE_TRANSFER_BIT, VK_PIPELINE_STAGE_RAY_TRACING_SHADER_BIT_KHR);

    // 提交并销毁临时命令缓冲
    device->flushCommandBuffer(cmd, queue);
}

inline void createDDGIVolumeTexture(const EDDGIVolumeTextureType& textureType, vks::Texture& outVolumeTexture, vks::VulkanDevice* device, VkQueue queue)
{
    auto pDDGIVolumeDescGPU = getGlobalDDGIVolumeDescGPU();
    uint32_t volumeTextureWidth, volumeTextureHeight, volumeTextureDepth;

    // 获取计算出的维度信息
    getDDGIVolumeTextureDimensions(*pDDGIVolumeDescGPU, textureType, volumeTextureWidth, volumeTextureHeight, volumeTextureDepth);

    // 设置基础属性
    outVolumeTexture.device = device;
    outVolumeTexture.width = volumeTextureWidth;
    outVolumeTexture.height = volumeTextureHeight;
    outVolumeTexture.layerCount = volumeTextureDepth;
    outVolumeTexture.mipLevels = 1;

    // 1. 确定格式 (根据 DDGI 常见的格式需求)
    VkFormat format = getFormatByType(textureType);

    // 2. 创建 Image
    VkImageCreateInfo imageCI = vks::initializers::imageCreateInfo();
    imageCI.imageType = VK_IMAGE_TYPE_2D;
    imageCI.format = format;
    imageCI.extent = { outVolumeTexture.width, outVolumeTexture.height, 1 };
    imageCI.mipLevels = outVolumeTexture.mipLevels;
    imageCI.arrayLayers = outVolumeTexture.layerCount;
    imageCI.samples = VK_SAMPLE_COUNT_1_BIT;
    imageCI.tiling = VK_IMAGE_TILING_OPTIMAL;
    // 注意：必须包含 STORAGE 位以便计算着色器写入，包含 SAMPLED 位以便后续采样
    imageCI.usage = VK_IMAGE_USAGE_STORAGE_BIT | VK_IMAGE_USAGE_SAMPLED_BIT | VK_IMAGE_USAGE_TRANSFER_DST_BIT;
    imageCI.initialLayout = VK_IMAGE_LAYOUT_UNDEFINED;

    VK_CHECK_RESULT(vkCreateImage(device->logicalDevice, &imageCI, nullptr, &outVolumeTexture.image));

    // 3. 分配显存并绑定
    VkMemoryRequirements memReqs;
    vkGetImageMemoryRequirements(device->logicalDevice, outVolumeTexture.image, &memReqs);
    VkMemoryAllocateInfo memAlloc = vks::initializers::memoryAllocateInfo();
    memAlloc.allocationSize = memReqs.size;
    memAlloc.memoryTypeIndex = device->getMemoryType(memReqs.memoryTypeBits, VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT);

    VK_CHECK_RESULT(vkAllocateMemory(device->logicalDevice, &memAlloc, nullptr, &outVolumeTexture.deviceMemory));
    VK_CHECK_RESULT(vkBindImageMemory(device->logicalDevice, outVolumeTexture.image, outVolumeTexture.deviceMemory, 0));

    // 4. 创建 Image View (注意是 2D_ARRAY)
    VkImageViewCreateInfo viewCI = vks::initializers::imageViewCreateInfo();
    viewCI.viewType = VK_IMAGE_VIEW_TYPE_2D_ARRAY;
    viewCI.format = format;
    viewCI.subresourceRange = { VK_IMAGE_ASPECT_COLOR_BIT, 0, 1, 0, outVolumeTexture.layerCount };
    viewCI.image = outVolumeTexture.image;

    VK_CHECK_RESULT(vkCreateImageView(device->logicalDevice, &viewCI, nullptr, &outVolumeTexture.view));

    // 5. 创建采样器
    VkSamplerCreateInfo samplerCI = vks::initializers::samplerCreateInfo();
    samplerCI.magFilter = (textureType == EDDGIVolumeTextureType::Data ? VK_FILTER_NEAREST : VK_FILTER_LINEAR);
    samplerCI.minFilter = (textureType == EDDGIVolumeTextureType::Data ? VK_FILTER_NEAREST : VK_FILTER_LINEAR);
    samplerCI.mipmapMode = VK_SAMPLER_MIPMAP_MODE_NEAREST;
    samplerCI.addressModeU = VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE;
    samplerCI.addressModeV = VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE;
    samplerCI.addressModeW = VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE;
    samplerCI.minLod = 0.0f;
    samplerCI.maxLod = 0.0f;

    VK_CHECK_RESULT(vkCreateSampler(device->logicalDevice, &samplerCI, nullptr, &outVolumeTexture.sampler));

    clearAndTransitionImage(device, queue, outVolumeTexture, getInitialLayoutByType(textureType), getInitialValueByType(textureType));
}


