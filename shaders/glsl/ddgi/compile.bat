set "GLSLANG_VALIDATOR=E:/Vulkan/Bin/glslangValidator.exe"
%GLSLANG_VALIDATOR% -V -R --target-env vulkan1.2 SceneShading.rchit.glsl -o SceneShading.rchit.spv
%GLSLANG_VALIDATOR% -V -R --target-env vulkan1.2 Miss.rmiss.glsl -o Miss.rmiss.spv
%GLSLANG_VALIDATOR% -V -R --target-env vulkan1.2 SceneShading.rgen.glsl -o SceneShading.rgen.spv
%GLSLANG_VALIDATOR% -V -R --target-env vulkan1.2 ProbeTrace.rchit.glsl -o ProbeTrace.rchit.spv
%GLSLANG_VALIDATOR% -V -R --target-env vulkan1.2 ProbeTrace.rgen.glsl -o ProbeTrace.rgen.spv
pause