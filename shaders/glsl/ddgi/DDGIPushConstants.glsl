// GLSL 实现
layout(push_constant) uniform DDGIRootConstants {
    uint volumeIndex;
    uint volumeConstantsIndex;
    uint volumeResourceIndicesIndex;

    // 对应 HLSL 中的三个 uint，保持 flat 布局以避免 padding 差异
    uint reductionInputSizeX;
    uint reductionInputSizeY;
    uint reductionInputSizeZ;
} DDGI;


uint GetDDGIVolumeIndex() { return DDGI.volumeIndex; }
uint GetDDGIVolumeConstantsIndex() { return DDGI.volumeConstantsIndex; }
uint GetDDGIVolumeResourceIndicesIndex() { return DDGI.volumeResourceIndicesIndex; }
uvec3 GetReductionInputSize() { return uvec3(DDGI.reductionInputSizeX, DDGI.reductionInputSizeY, DDGI.reductionInputSizeZ); }
