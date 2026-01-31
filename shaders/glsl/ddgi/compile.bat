set "GLSLANG_VALIDATOR=E:/Vulkan/VulkanSDK/Bin/glslangValidator.exe"
%GLSLANG_VALIDATOR% -V -R --target-env vulkan1.2 depthpass.vert.glsl -o depthpass.vert.spv
%GLSLANG_VALIDATOR% -V -R --target-env vulkan1.2 depthpass.frag.glsl -o depthpass.frag.spv
%GLSLANG_VALIDATOR% -V -R --target-env vulkan1.2 anyhit.rahit.glsl -o anyhit.rahit.spv
%GLSLANG_VALIDATOR% -V -R --target-env vulkan1.2 closesthit.rahit.glsl -o closesthit.rahit.spv
%GLSLANG_VALIDATOR% -V -R --target-env vulkan1.2 shadow.rmiss.glsl -o shadow.rmiss.spv
%GLSLANG_VALIDATOR% -V -R --target-env vulkan1.2 miss.rmiss.glsl -o miss.rmiss.spv
%GLSLANG_VALIDATOR% -V -R --target-env vulkan1.2 raygen.rgen.glsl -o raygen.rgen.spv
pause