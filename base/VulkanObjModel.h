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

        Model(){}

        void loadSceneFromFile(std::vector<std::string> filenames, vks::VulkanDevice* device, VkQueue transferQueue);
    };
}


#endif //MISS_RMISS_VULKANOBJMODEL_H
