//
// Created by 22473 on 2025-11-23.
//
#include "VulkanObjModel.h"
#define TINYOBJLOADER_IMPLEMENTATION
#include <tiny_obj_loader.h>

#include "VulkanglTFModel.h"

VkVertexInputBindingDescription vkobj::Vertex::vertexInputBindingDescription;
std::vector<VkVertexInputAttributeDescription> vkobj::Vertex::vertexInputAttributeDescriptions;
VkPipelineVertexInputStateCreateInfo vkobj::Vertex::pipelineVertexInputStateCreateInfo;

VkMemoryPropertyFlags vkobj::memoryPropertyFlags = 0;

VkVertexInputBindingDescription vkobj::Vertex::inputBindingDescription(uint32_t binding) {
    return VkVertexInputBindingDescription({ binding, sizeof(Vertex), VK_VERTEX_INPUT_RATE_VERTEX });
}

VkVertexInputAttributeDescription vkobj::Vertex::inputAttributeDescription(uint32_t binding, uint32_t location, VertexComponent component) {
    switch (component) {
        case VertexComponent::Position:
            return VkVertexInputAttributeDescription({ location, binding, VK_FORMAT_R32G32B32_SFLOAT, offsetof(Vertex, pos) });
        case VertexComponent::Normal:
            return VkVertexInputAttributeDescription({ location, binding, VK_FORMAT_R32G32B32_SFLOAT, offsetof(Vertex, normal) });
        case VertexComponent::UV:
            return VkVertexInputAttributeDescription({ location, binding, VK_FORMAT_R32G32_SFLOAT, offsetof(Vertex, uv) });
        case VertexComponent::Color:
            return VkVertexInputAttributeDescription({ location, binding, VK_FORMAT_R32G32B32A32_SFLOAT, offsetof(Vertex, color) });
        default:
            return VkVertexInputAttributeDescription({});
    }
}

std::vector<VkVertexInputAttributeDescription> vkobj::Vertex::inputAttributeDescriptions(uint32_t binding, const std::vector<VertexComponent> components) {
    std::vector<VkVertexInputAttributeDescription> result;
    uint32_t location = 0;
    for (VertexComponent component : components) {
        result.push_back(Vertex::inputAttributeDescription(binding, location, component));
        location++;
    }
    return result;
}

/** @brief Returns the default pipeline vertex input state create info structure for the requested vertex components */
VkPipelineVertexInputStateCreateInfo* vkobj::Vertex::getPipelineVertexInputState(const std::vector<VertexComponent> components) {
    vertexInputBindingDescription = inputBindingDescription(0);
    vertexInputAttributeDescriptions = inputAttributeDescriptions(0, components);
    pipelineVertexInputStateCreateInfo.sType = VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO;
    pipelineVertexInputStateCreateInfo.vertexBindingDescriptionCount = 1;
    pipelineVertexInputStateCreateInfo.pVertexBindingDescriptions = &vertexInputBindingDescription;
    pipelineVertexInputStateCreateInfo.vertexAttributeDescriptionCount = static_cast<uint32_t>(Vertex::vertexInputAttributeDescriptions.size());
    pipelineVertexInputStateCreateInfo.pVertexAttributeDescriptions = vertexInputAttributeDescriptions.data();
    return &pipelineVertexInputStateCreateInfo;
}

void vkobj::Material::createDescriptorSet(VkDescriptorPool descriptorPool, VkDescriptorSetLayout descriptorSetLayout,
                                          uint32_t descriptorBindingFlags) {
    // TODO: 考虑纹理
}


vkobj::Material::Material(const Material& rhs)
{
    device = rhs.device;
    metallic = rhs.metallic;
    roughness = rhs.roughness;
    baseColor = rhs.baseColor;
    descriptorSet = rhs.descriptorSet;
}


vkobj::Mesh::~Mesh(){
}


static void loadFromFileIntern(const std::string& filename,
                               vkobj::Material& material,
                               std::vector<vkobj::Vertex>& outVertices,
                               std::vector<uint32_t>& outIndices,
                               std::vector<vkobj::Mesh*>& outMeshes)
{
    size_t firstIndex = outIndices.size();
    tinyobj::attrib_t attrib;
    std::vector<tinyobj::shape_t> shapes;
    std::vector<tinyobj::material_t> materials;
    std::string warn, err;

    // 1. 加载 OBJ
    // base_dir 设置为 nullptr 或文件所在路径，用于加载 .mtl
    bool ret = tinyobj::LoadObj(&attrib, &shapes, &materials, &warn, &err, filename.c_str());

    if (!warn.empty()) std::cout << "TinyObj Warning (" << filename << "): " << warn << std::endl;
    if (!err.empty()) std::cerr << "TinyObj Error (" << filename << "): " << err << std::endl;
    if (!ret) throw std::runtime_error("Failed to load OBJ file: " + filename);

    std::cout << "loading " << filename << std::endl;
    // 2. 局部去重 Map
    // 这个 map 只负责当前文件的去重。
    // 注意：如果你希望不同 OBJ 文件之间共享顶点（通常不需要），需要把这个 map 传进来。
    std::unordered_map<vkobj::Vertex, uint32_t> uniqueVertices{};

    // 3. 遍历所有形状
    for (const auto& shape : shapes) {
        for (const auto& index : shape.mesh.indices) {
            vkobj::Vertex vertex{};

            // --- 提取位置 ---
            vertex.pos = {
                    attrib.vertices[3 * index.vertex_index + 0],
                    attrib.vertices[3 * index.vertex_index + 1],
                    attrib.vertices[3 * index.vertex_index + 2]
            };

            // --- 提取法线 (如果有) ---
            if (index.normal_index >= 0) {
                vertex.normal = {
                        attrib.normals[3 * index.normal_index + 0],
                        attrib.normals[3 * index.normal_index + 1],
                        attrib.normals[3 * index.normal_index + 2]
                };
            }

            // --- 提取 UV (如果有) ---
            if (index.texcoord_index >= 0) {
                vertex.uv = {
                        attrib.texcoords[2 * index.texcoord_index + 0],
                        1.0f - attrib.texcoords[2 * index.texcoord_index + 1] // Vulkan Y轴翻转
                };
            }

            vertex.color = {1.0f, 1.0f, 1.0f, 1.0f};

            // --- 核心逻辑：处理多文件偏移与去重 ---

            // 检查这个顶点在“当前文件”的加载过程中是否已经出现过
            if (uniqueVertices.count(vertex) == 0) {

                // 【关键点】：使用当前全局 vertices 的大小作为新索引。
                // 假设 outVertices 之前已经有 1000 个点 (来自上一个 obj)。
                // 那么当前这个新点的索引就是 1000。
                uint32_t globalIndex = static_cast<uint32_t>(outVertices.size());

                uniqueVertices[vertex] = globalIndex;
                outVertices.push_back(vertex);
            }

            // 将找到的（或新创建的）全局索引加入索引列表
            outIndices.push_back(uniqueVertices[vertex]);
        }
    }
    vkobj::Mesh* pMesh = new vkobj::Mesh(firstIndex, outIndices.size() - firstIndex, material);
    outMeshes.push_back(pMesh);
}

void vkobj::Model::loadFromFile(const std::vector<std::string>& filenames, const std::vector<Material>& _materials, vks::VulkanDevice *device, VkQueue transferQueue) {
    assert(filenames.size() == _materials.size());
    
    materials = _materials;
    this->device = device;

    std::vector<Vertex> vertexBuffer{};
    std::vector<uint32_t> indexBuffer{};

    for (size_t i = 0; i < filenames.size(); ++i)
    {
        loadFromFileIntern(filenames[i], materials[i], vertexBuffer, indexBuffer, meshes);
    }

    size_t vertexBufferSize = vertexBuffer.size() * sizeof(Vertex);
    size_t indexBufferSize = indexBuffer.size() * sizeof(uint32_t);
    indices.count = static_cast<uint32_t>(indexBuffer.size());
    vertices.count = static_cast<uint32_t>(vertexBuffer.size());

    assert((vertexBufferSize > 0) && (indexBufferSize > 0));

    struct StagingBuffer {
        VkBuffer buffer;
        VkDeviceMemory memory;
    } vertexStaging{}, indexStaging{};

    // Create staging buffers
    // Vertex data
    VK_CHECK_RESULT(device->createBuffer(
            VK_BUFFER_USAGE_TRANSFER_SRC_BIT,
            VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | VK_MEMORY_PROPERTY_HOST_COHERENT_BIT,
            vertexBufferSize,
            &vertexStaging.buffer,
            &vertexStaging.memory,
            vertexBuffer.data()));
    // Index data
    VK_CHECK_RESULT(device->createBuffer(
            VK_BUFFER_USAGE_TRANSFER_SRC_BIT,
            VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | VK_MEMORY_PROPERTY_HOST_COHERENT_BIT,
            indexBufferSize,
            &indexStaging.buffer,
            &indexStaging.memory,
            indexBuffer.data()));

    // Create device local buffers
    // Vertex buffer
    VK_CHECK_RESULT(device->createBuffer(
            VK_BUFFER_USAGE_VERTEX_BUFFER_BIT | VK_BUFFER_USAGE_TRANSFER_DST_BIT | memoryPropertyFlags,
            VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT,
            vertexBufferSize,
            &vertices.buffer,
            &vertices.memory));
    // Index buffer
    VK_CHECK_RESULT(device->createBuffer(
            VK_BUFFER_USAGE_INDEX_BUFFER_BIT | VK_BUFFER_USAGE_TRANSFER_DST_BIT | memoryPropertyFlags,
            VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT,
            indexBufferSize,
            &indices.buffer,
            &indices.memory));

    // Copy from staging buffers
    VkCommandBuffer copyCmd = device->createCommandBuffer(VK_COMMAND_BUFFER_LEVEL_PRIMARY, true);

    VkBufferCopy copyRegion = {};

    copyRegion.size = vertexBufferSize;
    vkCmdCopyBuffer(copyCmd, vertexStaging.buffer, vertices.buffer, 1, &copyRegion);

    copyRegion.size = indexBufferSize;
    vkCmdCopyBuffer(copyCmd, indexStaging.buffer, indices.buffer, 1, &copyRegion);

    device->flushCommandBuffer(copyCmd, transferQueue, true);

    vkDestroyBuffer(device->logicalDevice, vertexStaging.buffer, nullptr);
    vkFreeMemory(device->logicalDevice, vertexStaging.memory, nullptr);
    vkDestroyBuffer(device->logicalDevice, indexStaging.buffer, nullptr);
    vkFreeMemory(device->logicalDevice, indexStaging.memory, nullptr);
}


vkobj::Model::~Model()
{
    vkDestroyBuffer(device->logicalDevice, vertices.buffer, nullptr);
    vkFreeMemory(device->logicalDevice, vertices.memory, nullptr);
    vkDestroyBuffer(device->logicalDevice, indices.buffer, nullptr);
    vkFreeMemory(device->logicalDevice, indices.memory, nullptr);

    for(auto& mesh : meshes){
        delete mesh;
    }
}