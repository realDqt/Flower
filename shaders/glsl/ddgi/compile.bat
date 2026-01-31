set "GLSLANG_VALIDATOR=E:/Vulkan/VulkanSDK/Bin/glslangValidator.exe"
%GLSLANG_VALIDATOR% -V -R --target-env vulkan1.2 depthpass.vert.glsl -o depthpass.vert.spv
%GLSLANG_VALIDATOR% -V -R --target-env vulkan1.2 depthpass.frag.glsl -o depthpass.frag.spv
pause