import simd

/// Top-down plan, like a lighting diagram: subject at the centre, the phone (stand-in for the
/// photographer's camera) drawn below it. Plan units are metres; plan +x is right, plan +y is DOWN (screen).
public enum PlanLayout {
    /// Ignores world y. Plan +y points from the subject toward `viewer` (horizontal part only);
    /// plan +x is the viewer's right when facing the subject. If viewer and subject share x and z,
    /// use world +z as the "toward viewer" direction.
    public static func planPoint(_ world: SIMD3<Float>, subject: SIMD3<Float>, viewer: SIMD3<Float>) -> SIMD2<Float> {
        rotate(world - subject, subject: subject, viewer: viewer)
    }

    /// Unit plan direction of an axis's horizontal part; nil if that part is shorter than 1e-3.
    public static func planDirection(_ axis: SIMD3<Float>, subject: SIMD3<Float>, viewer: SIMD3<Float>) -> SIMD2<Float>? {
        guard simd_length(SIMD2(axis.x, axis.z)) >= 1e-3 else { return nil }
        return simd_normalize(rotate(axis, subject: subject, viewer: viewer))
    }

    /// Points per metre so every point (and the origin) fits inside `size` minus `margin` on each side,
    /// centred on the origin. At most `maxScale`; `maxScale` when there are no other points.
    public static func scale(fitting points: [SIMD2<Float>], in size: SIMD2<Float>, margin: Float,
                             maxScale: Float = 400) -> Float {
        var fit = maxScale
        let half = size / 2 - SIMD2(repeating: margin)
        for p in points {
            if abs(p.x) > 1e-6 { fit = min(fit, half.x / abs(p.x)) }
            if abs(p.y) > 1e-6 { fit = min(fit, half.y / abs(p.y)) }
        }
        return max(0, fit)
    }

    /// Horizontal part of a world-space offset in plan axes: y toward the viewer, x to the viewer's right.
    private static func rotate(_ v: SIMD3<Float>, subject: SIMD3<Float>, viewer: SIMD3<Float>) -> SIMD2<Float> {
        var toward = SIMD2(viewer.x - subject.x, viewer.z - subject.z)
        toward = simd_length(toward) > 1e-6 ? simd_normalize(toward) : SIMD2(0, 1)
        return SIMD2(v.x * toward.y - v.z * toward.x, v.x * toward.x + v.z * toward.y)
    }
}
