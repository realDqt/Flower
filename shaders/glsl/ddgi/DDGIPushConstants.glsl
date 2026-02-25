/*
layout(push_constant) uniform DDGIRootConstants {
    uint volumeIndex;
    uint volumeConstantsIndex;
    uint volumeResourceIndicesIndex;

    uint reductionInputSizeX;
    uint reductionInputSizeY;
    uint reductionInputSizeZ;
} DDGI;

uint GetDDGIVolumeIndex() { return DDGI.volumeIndex; }
uint GetDDGIVolumeConstantsIndex() { return DDGI.volumeConstantsIndex; }
uint GetDDGIVolumeResourceIndicesIndex() { return DDGI.volumeResourceIndicesIndex; }
uvec3 GetReductionInputSize() { return uvec3(DDGI.reductionInputSizeX, DDGI.reductionInputSizeY, DDGI.reductionInputSizeZ); }
*/

uint GetDDGIVolumeIndex() { return 0; }