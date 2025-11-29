//
// Created by 22473 on 2025-11-23.
//

#ifndef MISS_RMISS_VULKANOBJMODEL_H
#define MISS_RMISS_VULKANOBJMODEL_H
#pragma once

#include <stdlib.h>
#include <string>
#include <fstream>
#include <vector>

#include "vulkan/vulkan.h"
#include "VulkanDevice.h"

#define GLM_FORCE_RADIANS
#define GLM_FORCE_DEPTH_ZERO_TO_ONE
#include <glm/glm.hpp>
#include <glm/gtc/matrix_transform.hpp>
#include <glm/gtc/type_ptr.hpp>

#include <tiny_obj_loader.h>

namespace vkobj{

    enum class VertexComponent { Position, Normal, UV, Color};

    struct Vertex {
        glm::vec3 pos;
        glm::vec3 normal;
        glm::vec2 uv;
        glm::vec4 color;
        static VkVertexInputBindingDescription vertexInputBindingDescription;
        static std::vector<VkVertexInputAttributeDescription> vertexInputAttributeDescriptions;
        static VkPipelineVertexInputStateCreateInfo pipelineVertexInputStateCreateInfo;
        static VkVertexInputBindingDescription inputBindingDescription(uint32_t binding);
        static VkVertexInputAttributeDescription inputAttributeDescription(uint32_t binding, uint32_t location, VertexComponent component);
        static std::vector<VkVertexInputAttributeDescription> inputAttributeDescriptions(uint32_t binding, const std::vector<VertexComponent> components);
        /** @brief Returns the default pipeline vertex input state create info structure for the requested vertex components */
        static VkPipelineVertexInputStateCreateInfo* getPipelineVertexInputState(const std::vector<VertexComponent> components);
    };


    struct Material {
        vks::VulkanDevice* device = nullptr;
        float metallicFactor = 1.0f;
        float roughnessFactor = 1.0f;
        glm::vec4 baseColorFactor = glm::vec4(1.0f);

        VkDescriptorSet descriptorSet = VK_NULL_HANDLE;

        Material(vks::VulkanDevice* device) : device(device) {};
        void createDescriptorSet(VkDescriptorPool descriptorPool, VkDescriptorSetLayout descriptorSetLayout, uint32_t descriptorBindingFlags);
    };


    struct Primitive {
        uint32_t firstIndex;
        uint32_t indexCount;
        uint32_t firstVertex;
        uint32_t vertexCount;
        Material& material;

        struct Dimensions {
            glm::vec3 min = glm::vec3(FLT_MAX);
            glm::vec3 max = glm::vec3(-FLT_MAX);
            glm::vec3 size;
            glm::vec3 center;
            float radius;
        } dimensions;

        void setDimensions(glm::vec3 min, glm::vec3 max);
        Primitive(uint32_t firstIndex, uint32_t indexCount, Material& material) : firstIndex(firstIndex), indexCount(indexCount), material(material) {};
    };


    struct Mesh {
        vks::VulkanDevice* device;

        std::vector<Primitive*> primitives;
        std::string name;

        struct UniformBuffer {
            VkBuffer buffer;
            VkDeviceMemory memory;
            VkDescriptorBufferInfo descriptor;
            VkDescriptorSet descriptorSet = VK_NULL_HANDLE;
            void* mapped;
        } uniformBuffer;

        struct UniformBlock {
            glm::mat4 matrix;
            glm::mat4 jointMatrix[64]{};
            float jointcount{ 0 };
        } uniformBlock;

        Mesh(vks::VulkanDevice* device, glm::mat4 matrix);
        ~Mesh();
    };

    class Model{
    public:
        vks::VulkanDevice* device;

        struct Vertices {
            int count;
            VkBuffer buffer;
            VkDeviceMemory memory;
        } vertices;
        struct Indices {
            int count;
            VkBuffer buffer;
            VkDeviceMemory memory;
        } indices;

        std::vector<Mesh*> meshes;

        Model(){}

        void loadSceneFromFile(std::vector<std::string> filenames, vks::VulkanDevice* device, VkQueue transferQueue);
    };
}


#endif //MISS_RMISS_VULKANOBJMODEL_H
