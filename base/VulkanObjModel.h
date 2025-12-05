//
// Created by 22473 on 2025-11-23.
//

#ifndef VULKANOBJMODEL_H
#define VULKANOBJMODEL_H
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

#define GLM_ENABLE_EXPERIMENTAL
#include <glm/gtx/hash.hpp>

#include <unordered_map>

namespace vkobj{

    enum class VertexComponent { Position, Normal, UV, Color};

    extern VkMemoryPropertyFlags memoryPropertyFlags;

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

        bool operator==(const Vertex& other) const {
            return pos == other.pos && normal == other.normal && uv == other.uv;
        }
    };

    // 强制按 16 字节对齐
    struct alignas(16) MaterialData {
        glm::vec4 baseColor = glm::vec4(1.0f);
        glm::vec3 emission = glm::vec3(0.0f);
        float metallic = 0.0f;     
        float roughness = 1.0f;     
        float _padding[3] = {0.0f, 0.0f, 0.0f}; // 注释掉也ok，因为struct已经强制对齐   
    };

    struct Material {
        vks::VulkanDevice* device = nullptr;
        glm::vec4 baseColor = glm::vec4(1.0f);
        glm::vec3 emission = glm::vec3(0.0);
        float metallic = 0.0f;
        float roughness = 1.0f;

        VkDescriptorSet descriptorSet = VK_NULL_HANDLE;

        Material(){}
        Material(const Material& rhs);
        Material(vks::VulkanDevice* device) : device(device) {}
        ~Material(){}
        void createDescriptorSet(VkDescriptorPool descriptorPool, VkDescriptorSetLayout descriptorSetLayout, uint32_t descriptorBindingFlags);
        MaterialData GetData();
    };


    struct Mesh {

        vks::VulkanDevice* device;
        uint32_t firstIndex;
        uint32_t indexCount;
        uint32_t firstVertex; // 需要?
        uint32_t vertexCount; // 需要?
        Material& material;
        std::string name;

        Mesh(uint32_t firstIndex, uint32_t indexCount, Material& material) : firstIndex(firstIndex), indexCount(indexCount), material(material){} ;
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
        std::vector<Material> materials;
        
        Model(){
            meshes.clear();
            materials.clear();
        }

        ~Model();
        void loadFromFile(const std::vector<std::string>& filenames, const std::vector<Material>& _materials, vks::VulkanDevice* device, VkQueue transferQueue);
    };
}

namespace std {
    template<> struct hash<vkobj::Vertex> {
        size_t operator()(vkobj::Vertex const& vertex) const {
            return ((hash<glm::vec3>()(vertex.pos) ^
                     (hash<glm::vec3>()(vertex.normal) << 1)) >> 1) ^
                   (hash<glm::vec2>()(vertex.uv) << 1);
        }
    };
}

#endif //VULKANOBJMODEL_H
