//
//  ScanShaders.metal
//  Final Challenge App
//
//  Created by Amadeus Gavriel on 24/11/26.
//
//  The shaders of the Metal camera view (Metal renderer, part 2): the camera picture as a full-screen quad, the box
//  outlines on top, and the LiDAR occlusion test that hides a line behind a real thing.
//

#include <metal_stdlib>
using namespace metal;

/// Same layout as ScanUniforms.swift. Change both files together.
struct ScanUniforms {
    float4x4 viewProjection;  // world position to clip space
    float2 quadTexCoords[4];  // picture coordinates of the screen corners: top-left, top-right, bottom-left, bottom-right
    float2 pictureSize;       // the camera picture size in pixels
    float occlusionMargin;    // metres; smaller depth gaps are noise
    uint minConfidence;       // lower LiDAR confidence is not trusted
    float maxRange;           // metres; farther depth is not trusted
    uint hasDepth;            // 0 = no depth texture this frame
    float4 lineColor;         // outline colour and opacity
};

// The Swift side checks the same number (ScanUniforms.metalSize).
static_assert(sizeof(ScanUniforms) == 144, "ScanUniforms must stay 144 bytes, like ScanUniforms.swift");

/// True when the real scene is clearly in front of the line, so the line must be hidden.
/// The same 4 conditions as OcclusionRule.isHidden, plus "no depth texture = never hidden".
/// The project uses fast math, so the code does not ask "is it NaN?". Instead every test is a plain comparison,
/// and a comparison with NaN is false: NaN depth never hides the line.
inline bool occlusionIsHidden(float lineDepth, float sceneDepth, uint confidence, constant ScanUniforms &uniforms) {
    bool hasSceneDepth = sceneDepth > 0.0f && sceneDepth <= uniforms.maxRange;   // not missing, not too far
    bool isTrusted = confidence >= uniforms.minConfidence;
    bool isInFront = sceneDepth < lineDepth - uniforms.occlusionMargin;
    return uniforms.hasDepth != 0 && hasSceneDepth && isTrusted && isInFront;
}

// MARK: - Camera picture

struct CameraOut {
    float4 position [[position]];
    float2 texCoord;
};

/// A full-screen quad as a triangle strip of 4 vertices. No vertex buffer: the corner comes from the vertex id.
/// Buffer 0: the uniforms.
vertex CameraOut cameraVertex(uint vertexID [[vertex_id]], constant ScanUniforms &uniforms [[buffer(0)]]) {
    // Same corner order as quadTexCoords: top-left, top-right, bottom-left, bottom-right.
    const float2 corners[4] = { float2(-1, 1), float2(1, 1), float2(-1, -1), float2(1, -1) };
    CameraOut out;
    out.position = float4(corners[vertexID], 0, 1);
    out.texCoord = uniforms.quadTexCoords[vertexID];
    return out;
}

/// The camera colour. Texture 0: Y (brightness), texture 1: CbCr (colour, half size).
fragment float4 cameraFragment(CameraOut in [[stage_in]],
                               texture2d<float> lumaTexture [[texture(0)]],
                               texture2d<float> chromaTexture [[texture(1)]]) {
    constexpr sampler pictureSampler(filter::linear, address::clamp_to_edge);
    float luma = lumaTexture.sample(pictureSampler, in.texCoord).r;
    float2 chroma = chromaTexture.sample(pictureSampler, in.texCoord).rg;
    // Apple's ycbcrToRGBTransform (ARKit, ARFrame.h).
    const float4x4 ycbcrToRGBTransform = float4x4(
        float4(+1.0000f, +1.0000f, +1.0000f, +0.0000f),
        float4(+0.0000f, -0.3441f, +1.7720f, +0.0000f),
        float4(+1.4020f, -0.7141f, +0.0000f, +0.0000f),
        float4(-0.7010f, +0.5291f, -0.8860f, +1.0000f)
    );
    return ycbcrToRGBTransform * float4(luma, chroma.x, chroma.y, 1.0f);
}

// MARK: - Box outlines

struct OutlineOut {
    float4 position [[position]];
    float lineDepth;                                  // metres in front of the camera (clip.w)
    float2 pictureFraction [[center_no_perspective]]; // where this pixel is in the depth picture (0...1)
};

/// One outline vertex. Buffer 0: positions as 3 packed floats (12 bytes each). Buffer 1: the uniforms.
vertex OutlineOut outlineVertex(uint vertexID [[vertex_id]],
                                const device packed_float3 *positions [[buffer(0)]],
                                constant ScanUniforms &uniforms [[buffer(1)]]) {
    float4 clip = uniforms.viewProjection * float4(float3(positions[vertexID]), 1.0f);
    // The screen point (0...1 from the top-left), then the picture point between the 4 corners. This map is
    // straight (affine) on the screen, so the value is spread over the triangle without perspective.
    float2 screen = float2(clip.x / clip.w + 1.0f, 1.0f - clip.y / clip.w) * 0.5f;
    float2 top = mix(uniforms.quadTexCoords[0], uniforms.quadTexCoords[1], screen.x);
    float2 bottom = mix(uniforms.quadTexCoords[2], uniforms.quadTexCoords[3], screen.x);
    OutlineOut out;
    out.position = clip;
    out.lineDepth = clip.w;
    out.pictureFraction = mix(top, bottom, screen.y);
    return out;
}

/// The outline colour, or no pixel when a real thing is in front. Buffer 0: the uniforms.
/// Texture 0: LiDAR depth (metres), texture 1: its confidence (0, 1, 2). Read with nearest sampling: depth values
/// must not be blended.
fragment float4 outlineFragment(OutlineOut in [[stage_in]],
                                constant ScanUniforms &uniforms [[buffer(0)]],
                                texture2d<float> depthTexture [[texture(0)]],
                                texture2d<uint> confidenceTexture [[texture(1)]]) {
    if (uniforms.hasDepth != 0) {
        constexpr sampler depthSampler(filter::nearest, address::clamp_to_edge);
        float sceneDepth = depthTexture.sample(depthSampler, in.pictureFraction).r;
        uint confidence = confidenceTexture.sample(depthSampler, in.pictureFraction).r;
        if (occlusionIsHidden(in.lineDepth, sceneDepth, confidence, uniforms)) {
            discard_fragment();
        }
    }
    return uniforms.lineColor;
}

// MARK: - Test kernel

/// Used by tests: runs occlusionIsHidden on arrays of inputs and writes 1 (hidden) or 0 (shows) for each.
kernel void occlusionRuleKernel(const device float *lineDepths [[buffer(0)]],
                                const device float *sceneDepths [[buffer(1)]],
                                const device uint *confidences [[buffer(2)]],
                                device uint *hidden [[buffer(3)]],
                                constant ScanUniforms &uniforms [[buffer(4)]],
                                uint index [[thread_position_in_grid]]) {
    hidden[index] = occlusionIsHidden(lineDepths[index], sceneDepths[index], confidences[index], uniforms) ? 1 : 0;
}
