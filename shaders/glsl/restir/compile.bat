set "GLSLANG_VALIDATOR=E:/Vulkan/VulkanSDK/Bin/glslangValidator.exe"
%GLSLANG_VALIDATOR% -V -R --target-env vulkan1.2 initialsample.rgen.glsl -o initialsample.rgen.spv
%GLSLANG_VALIDATOR% -V -R --target-env vulkan1.2 initialsample.rmiss.glsl -o initialsample.rmiss.spv
%GLSLANG_VALIDATOR% -V -R --target-env vulkan1.2 initialsample.rchit.glsl -o initialsample.rchit.spv
%GLSLANG_VALIDATOR% -V -R --target-env vulkan1.2 temporalreuse.comp.glsl -o temporalreuse.comp.spv
%GLSLANG_VALIDATOR% -V -R --target-env vulkan1.2 spatialreuse.rgen.glsl -o spatialreuse.rgen.spv
%GLSLANG_VALIDATOR% -V -R --target-env vulkan1.2 spatialreuse.rchit.glsl -o spatialreuse.rchit.spv
%GLSLANG_VALIDATOR% -V -R --target-env vulkan1.2 spatialreuse.rmiss.glsl -o spatialreuse.rmiss.spv
pause