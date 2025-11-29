//
// Created by 22473 on 2025-11-23.
//
#include "VulkanObjModel.h"

VkVertexInputBindingDescription vkobj::Vertex::vertexInputBindingDescription;
std::vector<VkVertexInputAttributeDescription> vkobj::Vertex::vertexInputAttributeDescriptions;
VkPipelineVertexInputStateCreateInfo vkobj::Vertex::pipelineVertexInputStateCreateInfo;

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


void vkobj::Primitive::setDimensions(glm::vec3 min, glm::vec3 max) {
    dimensions.min = min;
    dimensions.max = max;
    dimensions.size = max - min;
    dimensions.center = (min + max) / 2.0f;
    dimensions.radius = glm::distance(min, max) / 2.0f;
}


vkobj::Mesh::Mesh(vks::VulkanDevice *device, glm::mat4 matrix) {
    this->device = device;
    this->uniformBlock.matrix = matrix;
    VK_CHECK_RESULT(device->createBuffer(
            VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT,
            VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | VK_MEMORY_PROPERTY_HOST_COHERENT_BIT,
            sizeof(uniformBlock),
            &uniformBuffer.buffer,
            &uniformBuffer.memory,
            &uniformBlock));
    VK_CHECK_RESULT(vkMapMemory(device->logicalDevice, uniformBuffer.memory, 0, sizeof(uniformBlock), 0, &uniformBuffer.mapped));
    uniformBuffer.descriptor = { uniformBuffer.buffer, 0, sizeof(uniformBlock) };
}

vkobj::Mesh::~Mesh(){
    vkDestroyBuffer(device->logicalDevice, uniformBuffer.buffer, nullptr);
    vkFreeMemory(device->logicalDevice, uniformBuffer.memory, nullptr);
    for(auto primitive : primitives)
    {
        delete primitive;
    }
}