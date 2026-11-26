//
//  ScanUniforms.swift
//  Final Challenge App
//
//  Created by Amadeus Gavriel on 24/11/26.
//
//  The Swift copy of the shader's uniform struct (Metal renderer, part 2). The field order, types and size must
//  stay the same as `ScanUniforms` in ScanShaders.metal: the GPU reads these bytes as that struct.
//

import simd

/// The numbers the scan shaders need for one frame. Same layout as `ScanUniforms` in ScanShaders.metal.
nonisolated struct ScanUniforms {
    /// The struct size in bytes. ScanShaders.metal checks the same number with a static_assert.
    static let metalSize = 144

    /// World position to clip space (`ScanProjection.viewProjection`).
    var viewProjection: simd_float4x4
    /// Camera picture coordinates of the screen corners: top-left, top-right, bottom-left, bottom-right.
    /// A tuple, because it must have the memory layout of the Metal array `float2 quadTexCoords[4]`.
    var quadTexCoords: (SIMD2<Float>, SIMD2<Float>, SIMD2<Float>, SIMD2<Float>) // swiftlint:disable:this large_tuple
    /// The camera picture size in pixels.
    var pictureSize: SIMD2<Float>
    /// The real scene must be this many metres closer than the line to hide it (`OcclusionRule.margin`).
    var occlusionMargin: Float
    /// Depth pixels below this confidence are not trusted. 32 bits, because Metal reads a `uint`.
    var minConfidence: UInt32
    /// Depth pixels farther than this many metres are not trusted (`OcclusionRule.maxRange`).
    var maxRange: Float
    /// 1 when this frame has a depth texture, 0 when not (then no line is hidden).
    var hasDepth: UInt32
    /// The outline colour, with its opacity in alpha.
    var lineColor: SIMD4<Float>
}
