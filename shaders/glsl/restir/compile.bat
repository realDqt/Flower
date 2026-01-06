set "GLSLANG_VALIDATOR=E:/Vulkan/VulkanSDK/Bin/glslangValidator.exe"
%GLSLANG_VALIDATOR% -V -R --target-env vulkan1.2 spraygen.rgen.glsl -o spraygen.rgen.spv
%GLSLANG_VALIDATOR% -V -R --target-env vulkan1.2 spmiss.rmiss.glsl -o spmiss.rmiss.spv
%GLSLANG_VALIDATOR% -V -R --target-env vulkan1.2 spclosesthit.rchit.glsl -o spclosesthit.rchit.spv
%GLSLANG_VALIDATOR% -V -R --target-env vulkan1.2 temporalreuse.comp.glsl -o temporalreuse.comp.spv
%GLSLANG_VALIDATOR% -V -R --target-env vulkan1.2 temporalreuse.rgen.glsl -o temporalreuse.rgen.spv
pause