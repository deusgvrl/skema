# B: own Metal renderer — Implementation Plan (part 1: the testable maths)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

- **Made:** 24 Nov 2026 by Claude. Direction and decisions are Amadeus's. No Jira ticket; this plan lives only in the B branch (decision, 24 Nov).
- **Status:** cases M1–M26 + M13a **approved** (Amadeus, 24 Nov; M4 as written: the switch ignores upper and lower case; M7 as fixed). Part 1 = Tasks 1–4. The renderer (part 2) and the switch (part 3) need their own approval first.

**Goal:** Build the pure, unit-testable parts of B: the renderer switch, the occlusion rule, the projection maths and the outline GPU buffers.

**Architecture:** Only new files (decision: no old file changes until A10-117 is merged). Pure maths lives in small `nonisolated enum`s; the occlusion rule lives in MeasureKit next to `DepthSampler`. The projection is the same formula as `ScanOverlay` (see the artifact "Scan Projection Maths", https://claude.ai/artifact/5omiruCsb8nR34GRHTBA2K, engineer section).

**Tech Stack:** Swift 6, Swift Testing, simd, Metal (Task 4 only). Default actor isolation is MainActor.

**Spec:** `docs/scan-metal-renderer-design.md` (this branch), sections 0, 5 and 7.

## Global Constraints

- Work in the worktree `/Users/itsdeus/Documents/Apple Developer Academy/Challenge 5/skema-metal-renderer` (branch `perf/scan-metal-renderer`). New files only.
- Amadeus runs every `git` command and makes every commit. No Claude attribution.
- TDD: red, green, mutation checks, SwiftLint, the focused suite. The full suite one time at the end of part 1.
- App tests: xcodebuild test -project "Skema Photo.xcodeproj" -scheme "Final Challenge App" -destination id=AA6C7DC9-83BF-4CB9-9880-8BB6DB6A23A5 CODE_SIGNING_ALLOWED=NO -skipPackagePluginValidation -skipMacroValidation -configuration Debug -only-testing:"Skema Tests/<Suite>"  (run from the worktree root; count ' passed on ' / ' failed on ')
- MeasureKit tests: `swift test --filter <Suite>` in `Packages/MeasureKit`.
- Lint: "/Users/itsdeus/Documents/Apple Developer Academy/Challenge 5/Final Challenge App/.tools/swiftlint" lint --quiet --force-exclude <files>  (run from the worktree root, so its .swiftlint.yml is used; the worktree has no .tools folder). MeasureKit is excluded by `.swiftlint.yml`.
- New files: header "Created by Amadeus Gavriel on 24/11/26." Plain short comments.
- Decisions D1–D4 (design §0): room mesh off in Metal mode only; after-save target 300 MB; our own projection maths; occlusion margin 3 cm, minimum confidence 1.

## Review Focus

1. **Launch-argument text:** `-scanRenderer Metal` arrives as a String; any case of "metal" gives `.metal`; anything else, or a missing key, gives `.arView` (M1–M4).
2. **Points behind the camera** must never produce a screen point (M6): `clip.w <= 0` → nil.
3. **No depth / NaN / low confidence / beyond 5 m** must always show the line (M12, M13, M13a): the safe default is "visible".
4. **The right and bottom screen edges** for the picture quad (M7 fix): the reverse formula must work at x = width and y = height.
5. **A principal point off the middle** (real phones): the matrix must use px and py, not assume the centre. Pin it with the artifact's example 2 numbers in Task 3.

---

### Task 1: `ScanRendererChoice` (cases M1–M4)

**Files:** Create `Final Challenge App/Services/Scan/ScanRendererChoice.swift`; Test `Skema Tests/ScanRendererChoiceTests.swift`.

**Interfaces — Produces:** `nonisolated enum ScanRendererChoice: Equatable, Sendable { case arView, metal }`; `static let key = "scanRenderer"`; `init(defaults: UserDefaults)`.

- [ ] Tests (fresh `UserDefaults(suiteName:)` per test, removed after): M1 no key → `.arView`; M2 `"metal"` → `.metal`; M3 `"metl"` → `.arView`; M4 `"METAL"` → `.metal`.
- [ ] RED (does not compile), GREEN, mutations: compare without lowercasing → M4 fails; default `.metal` → M1 fails.
- [ ] Amadeus commits `feat(scan): add the renderer switch for the Metal camera view`.

### Task 2: `OcclusionRule` (cases M9–M13a)

**Files:** Create `Packages/MeasureKit/Sources/MeasureKit/OcclusionRule.swift`; Test `Packages/MeasureKit/Tests/MeasureKitTests/OcclusionRuleTests.swift`.

**Interfaces — Produces:** `public enum OcclusionRule` with `public static let margin: Float = 0.03`, `public static let minConfidence: UInt8 = 1`, `public static let maxRange: Float = DepthSampler.maxRange`, `public static func isHidden(lineDepth: Float, sceneDepth: Float, confidence: UInt8) -> Bool`. True only when: sceneDepth is finite and > 0; confidence ≥ minConfidence; sceneDepth ≤ maxRange; sceneDepth < lineDepth − margin (design §5.4).

- [ ] Tests: M9 (2.0, 1.5, 2) hidden; M10 (2.0, 2.5, 2) shows; M11 (2.0, 1.99, 2) shows; M12 depth 0 and NaN show; M13 (2.0, 1.0, 0) shows; M13a (6.0, 5.5, 2) shows. Add one boundary pair: (2.0, 1.969, 2) hidden and (2.0, 1.971, 2) shows (the 3 cm edge).
- [ ] RED, GREEN, mutations: drop the confidence check → M13 fails; drop the range check → M13a fails; margin 0 → M11 fails.
- [ ] Amadeus commits `feat(measure): add the occlusion rule for the Metal camera view`.

### Task 3: `ScanProjection` (cases M5–M8, plus the off-centre example)

**Files:** Create `Final Challenge App/Features/Scan/Metal/ScanProjection.swift`; Test `Skema Tests/ScanProjectionTests.swift`.

**Interfaces — Produces** (`nonisolated enum ScanProjection`, portrait only):
- `static func projectionMatrix(camera: CameraModel, viewSize: CGSize, near: Float = 0.01, far: Float = 20) -> simd_float4x4` — rows exactly as the artifact's step 6: [0, a, −b, 0], [−e, 0, −g, 0], [0, 0, −f/(f−n), −f·n/(f−n)], [0, 0, −1, 0], with s = max(w/H, h/W), o_x = (w − H·s)/2, o_y = (h − W·s)/2, a = 2·s·fy/w, b = 2(s(H − py) + o_x)/w − 1, e = 2·s·fx/h, g = 1 − 2(s·px + o_y)/h. (fx = intrinsics[0][0], fy = intrinsics[1][1], px = intrinsics[2][0], py = intrinsics[2][1]; W, H = imageResolution.)
- `static func viewProjection(camera: CameraModel, viewSize: CGSize) -> simd_float4x4` = projectionMatrix · cameraToWorld.inverse.
- `static func screenPoint(of world: SIMD3<Float>, camera: CameraModel, viewSize: CGSize) -> CGPoint?` — through viewProjection; nil when clip.w ≤ 0.
- `static func pictureQuadTexCoords(camera: CameraModel, viewSize: CGSize) -> [SIMD2<Float>]` — [top-left, top-right, bottom-left, bottom-right], each = (v′/W, (H − u′)/H) with u′ = (x − o_x)/s, v′ = (y − o_y)/s, NO screen-bounds check.
- `static func pictureFraction(of world: SIMD3<Float>, camera: CameraModel) -> SIMD2<Float>?` and `static func lineDepth(of world: SIMD3<Float>, camera: CameraModel) -> Float` (= −z in camera space).

- [ ] Tests (shared camera fx = fy = 1500, px = 960, py = 720, 1920×1440, identity, view 390×844): M5 (0.1, 0.2, −2) → (260.9375, 454.96875) ± 0.01 and equal to `ScanOverlay.screenPoint`; M6 (0.1, 0.2, +1) → nil (and clip.w ≤ 0); M7 corners (0, 0.808), (0, 0.192), (1, 0.808), (1, 0.192) ± 0.001, and the top-left equals `ScanOverlay.picturePoint(fromScreen: .zero, …)`; M8 picture fraction (1035/1920, 570/1440) ± 1e-4 and line depth 2.0. **Off-centre (Review Focus 5):** fx = fy = 1340.3, px = 957.6, py = 723.1, camera at (0.5, 1.4, 1.0) turned 30° about world y, view 402×874: point (−0.3, 1.1, −1.5) → (128.2321, 568.4360) ± 0.01 and equal to `ScanOverlay.screenPoint`.
- [ ] RED, GREEN, mutations: drop the o_x term in b → the off-centre test fails; use min instead of max for s → M5 fails; drop the w ≤ 0 check → M6 fails.
- [ ] Amadeus commits `feat(scan): add the projection maths for the Metal camera view`.

### Task 4: `OutlineBuffers` (cases M14–M16)

**Files:** Create `Final Challenge App/Features/Scan/Metal/OutlineBuffers.swift`; Test `Skema Tests/OutlineBuffersTests.swift`.

**Interfaces — Produces:** `@MainActor final class OutlineBuffers`; `init?(device: any MTLDevice)`; `func update(_ boxes: [UUID: WorldBox], radius: (WorldBox) -> Float)`; `private(set) var entries: [UUID: Entry]` with `struct Entry { let box: WorldBox; let vertexBuffer: any MTLBuffer; let indexBuffer: any MTLBuffer; let vertexCount: Int; let indexCount: Int }`. Rebuild rule: a box whose min and max moved less than `ScanOutlines.rebuildStep` (1 cm) on every side keeps its entry (the same buffer objects); a missing box is removed. Vertex data = `OutlineMesh.geometry(of:radius:).positions` packed as 3 floats each; indices as UInt32.

- [ ] Tests (device = `MTLCreateSystemDefaultDevice()`; skip with a clear message if nil): M14 a 1 m cube (0,0,0)–(1,1,1), radius 0.005 → vertexCount and indexCount equal `OutlineMesh.geometry`'s counts, and the buffer contents equal its positions and indices (the design expects 4,080 and 23,040: assert the equality with OutlineMesh, and report the actual counts); M15 moved 0.5 cm → `===` the same buffer; moved 1 cm → a new buffer; M16 two boxes, update with one → the other is gone.
- [ ] RED, GREEN, mutations: always rebuild → M15 fails; never remove → M16 fails.
- [ ] Amadeus commits `feat(scan): add GPU buffers for the outline boxes`.

### Part 1 finish

- [ ] SwiftLint on the new app files; MeasureKit `swift test` (all); the full app suite one time; the final review.

### Not in part 1 (needs Amadeus's approval first)

- **Shader notes from the part 1 final review (24 Nov, inferred):** send the picture fraction with `[[center_no_perspective]]` (it is affine in screen space); read the 12-byte packed vertices as `packed_float3` (or a vertex descriptor with stride 12); the project sets `MTL_FAST_MATH = YES`, so write the occlusion test so that NaN fails each comparison (or turn fast math off for the shader file); store `minConfidence` as a 32-bit value in the uniform buffer.
- **Part 2 — the renderer:** `CameraTextures`, `ScanShaders.metal`, `ScanMetalRenderer`, `MetalScanView`. Their approved cases are phone checks (M17–M24). Unit tests for them are not yet approved: Claude proposes them before building.
- **Part 3 — the switch** (`ScanView` `if`, room mesh off in Metal mode, M26): after A10-117 is merged and B is rebased on it.
- **CentreDotBuffers** (M25): after Richie's branch is merged.


---

# Part 2 and part 3 (approved 24 Nov: R1–R7; "do part 2 and 3, don't wait for A")

**Decision (Amadeus, 24 Nov):** B does not wait for A10-117. Parts 2 and 3 are built now in this local branch. Where B and A change the same old file (`ScanSession.swift`, `ScanView.swift`), the conflict is solved when the branches meet; nothing is pushed until then.

**Global constraints for part 2–3** (in addition to part 1's): only the files each task lists; the shader notes above are binding; the camera picture and the lines are drawn in ONE render pass of ONE command buffer per frame; the `ARView` path stays exactly as today when no launch argument is set (M26).

### Task 5: `CameraTextures` (cases R1–R3)

**Files:** Create `Final Challenge App/Features/Scan/Metal/CameraTextures.swift`; Test `Skema Tests/CameraTexturesTests.swift`.

**Interfaces — Produces:** `final class CameraTextures`; `init?(device: any MTLDevice)` (nil only when `CVMetalTextureCacheCreate` fails); `func cameraTextures(from pixelBuffer: CVPixelBuffer) -> (y: CVMetalTexture, cbcr: CVMetalTexture)?` (Y = plane 0 `r8Unorm`, CbCr = plane 1 `rg8Unorm`; nil unless the format is `kCVPixelFormatType_420YpCbCr8BiPlanarFullRange`); `func depthTextures(depth: CVPixelBuffer, confidence: CVPixelBuffer?) -> (depth: CVMetalTexture, confidence: CVMetalTexture?)?` (depth `r32Float` only for `kCVPixelFormatType_DepthFloat32`; confidence `r8Uint` only for `kCVPixelFormatType_OneComponent8`). The caller keeps the `CVMetalTexture`s alive until its command buffer completes (Apple's rule; doc comment). Test buffers: `CVPixelBufferCreate` with `kCVPixelBufferMetalCompatibilityKey` and `kCVPixelBufferIOSurfacePropertiesKey`.

- [ ] R1 a `kCVPixelFormatType_32BGRA` buffer → `cameraTextures` is nil. R2 a 16×12 420f buffer → Y 16×12 `r8Unorm`, CbCr 8×6 `rg8Unorm`. R3 a 256×192 DepthFloat32 + OneComponent8 → `r32Float` and `r8Uint`, both 256×192; a wrong depth format → nil.
- [ ] RED, GREEN, mutations: drop the format check → R1 fails; swap the plane index → R2 fails.

### Task 6: `ScanShaders.metal` (cases R5, R6)

**Files:** Create `Final Challenge App/Features/Scan/Metal/ScanShaders.metal` and `Final Challenge App/Features/Scan/Metal/ScanUniforms.swift` (the Swift mirror of the shader's uniform struct); Test `Skema Tests/ScanShadersTests.swift`.

**Interfaces — Produces:**
- Metal: `struct ScanUniforms { float4x4 viewProjection; float2 quadTexCoords[4]; float2 pictureSize; float occlusionMargin; uint minConfidence; float maxRange; uint hasDepth; float4 lineColor; }` (exact order; Swift mirror with the same layout and a test that `MemoryLayout<ScanUniforms>.stride` equals the Metal size the test reads back, or equals a fixed number written in both files).
- Metal functions: `cameraVertex` / `cameraFragment` (full-screen quad, 4 vertices, texture coordinates from `quadTexCoords`; YCbCr → RGB with Apple's `ycbcrToRGBTransform` from `ARFrame.h`); `outlineVertex` / `outlineFragment` (positions are `packed_float3`, stride 12; clip = viewProjection × position; the line depth = clip.w; the picture fraction for the depth lookup is affine in screen space: pass it `[[center_no_perspective]]` or compute it from `[[position]]`); one inline `bool occlusionIsHidden(float lineDepth, float sceneDepth, uint confidence, constant ScanUniforms&)` with the same 4 conditions as `OcclusionRule.isHidden`, written so that NaN fails every comparison (the project has `MTL_FAST_MATH = YES`); the depth texture is read with nearest sampling; `hasDepth == 0` → never hidden.
- A small compute kernel `occlusionRuleKernel` (inputs: arrays of lineDepth, sceneDepth, confidence → output 0/1) that calls the same inline function, for test R5. Doc comment: "used by tests".

- [ ] R5: for the M9–M13a inputs plus the 3 cm edge pair, the kernel's output equals `OcclusionRule.isHidden` for every input. R6: render `cameraFragment` into a 1×1 `rgba8Unorm` target with Y = 0.5, Cb = 0.25, Cr = 0.75 (as texture values) → the pixel equals Apple's matrix result within 1/255 (compute the expected value in the test with the same matrix).
- [ ] RED, GREEN, mutations: drop the confidence condition in the Metal function → R5 fails; swap Cb and Cr → R6 fails.

### Task 7: `ScanMetalRenderer` (case R4)

**Files:** Create `Final Challenge App/Features/Scan/Metal/ScanMetalRenderer.swift`; Test `Skema Tests/ScanMetalRendererTests.swift`.

**Interfaces — Consumes:** `CameraTextures` (T5), `ScanUniforms` + shaders (T6), `ScanProjection` (T3, incl. `focalLength(camera:viewSize:)`), `OutlineBuffers` (T4), `OcclusionRule` (T2), `CameraModel(_ camera: ARCamera)` (`ScanFrame+ARKit.swift`), `OutlineMesh.radius(for:cameraPosition:focalLength:)`.
**Produces:** `@MainActor final class ScanMetalRenderer: NSObject, MTKViewDelegate`; `init?(device: any MTLDevice, session: ARSession)` (nil when the library or a pipeline cannot be made); `var outlines: [UUID: WorldBox]`; `static func uniforms(camera: CameraModel, viewSize: CGSize, hasDepth: Bool) -> ScanUniforms` (pure, for R4); `draw(in:)`: read `session.currentFrame`; no frame → clear only; make the textures; update `OutlineBuffers` with the radius from `OutlineMesh.radius` and `ScanProjection.focalLength`; one command buffer, one render pass: camera quad first, then the outlines (alpha blending, opacity `OutlineLayout.opacity`, white); keep the frame's `CVMetalTexture`s alive in `addCompletedHandler` (a `@Sendable` closure that only holds them).

- [ ] R4: `uniforms(…)` for the shared camera (fx = fy = 1500, 1920×1440, identity, 390×844) → `viewProjection` equals `ScanProjection.viewProjection`; `quadTexCoords` equal `ScanProjection.pictureQuadTexCoords`; `occlusionMargin` 0.03, `minConfidence` 1, `maxRange` 5 (from `OcclusionRule`); `pictureSize` (1920, 1440); `hasDepth` follows the argument.
- [ ] Also: `init?(device:session:)` returns non-nil with the simulator's device (the shaders compile and the pipelines build).
- [ ] RED, GREEN, mutations: hard-code the margin → R4 fails.

### Task 8: `MetalScanView` (case R7)

**Files:** Create `Final Challenge App/Features/Scan/Metal/MetalScanView.swift`; Test `Skema Tests/MetalScanViewTests.swift`.

**Interfaces — Produces:** `struct MetalScanView: UIViewRepresentable` with the same inputs as `RoomScanView` (`session: ARSession`, `outlines: [UUID: WorldBox]`); `static func makeMetalView(session: ARSession) -> MTKView?` (device, `colorPixelFormat = .bgra8Unorm`, no depth attachment, `framebufferOnly = true`, `preferredFramesPerSecond = 60`, the renderer as delegate kept by the coordinator) and `static func makeCoachingView(session: ARSession, in bounds: CGRect) -> ARCoachingOverlayView` (goal `.horizontalPlane`, `activatesAutomatically = true`, flexible width and height; same settings as Richie's branch). `updateUIView` passes `outlines` to the renderer.

- [ ] R7: the coaching view from `makeCoachingView` has the session, goal `.horizontalPlane` and `activatesAutomatically`; `makeMetalView` gives a view whose delegate is a `ScanMetalRenderer` and whose `preferredFramesPerSecond` is 60.
- [ ] RED, GREEN, mutations: wrong goal → R7 fails.

### Task 9 (part 3): the room mesh is off in Metal mode (decision D1)

**Files:** Modify `Final Challenge App/Services/ScanSession.swift`; Test `Skema Tests/ScanSessionTests.swift`.

**Interfaces — Produces:** `ScanSession.init(…, renderer: ScanRendererChoice = ScanRendererChoice(defaults: .standard))` (last parameter); `start()` asks for the mesh only when `supportsMesh() && renderer == .arView`. (When A10-117 meets B, the condition becomes `supportsMesh() && renderSettings.roomMesh && renderer == .arView`.)

- [ ] P1 (from D1): mesh supported, `renderer: .metal` → `sceneReconstruction == []`. Case 20 (existing) must still pass with `renderer: .arView`; pass `.arView` explicitly in the test helper so tests do not read `UserDefaults.standard`.
- [ ] RED, GREEN, mutation: ignore the renderer → P1 fails.

### Task 10 (part 3): the switch in `ScanView` (case M26)

**Files:** Modify `Final Challenge App/Features/Scan/ScanView.swift` (the camera block only); Test: the existing suites (M26 = "all old tests pass") plus one small test.

**Interfaces — Produces:** in `ScanView`, one `let rendererChoice = ScanRendererChoice(defaults: .standard)` read once; the camera block shows `MetalScanView(session:outlines:)` when `.metal`, else `RoomScanView` exactly as today. The tap gesture, the accessibility modifiers and `ScanTagsView` stay the same for both. `ScanViewModel` makes `ScanSession` with the same choice (so the mesh rule of Task 9 and the view agree).

- [ ] Test: `ScanViewModel`'s default `makeScan` passes the choice through (or a factory function that a test can call) — one assertion that with `.metal` the session asks for no mesh.
- [ ] The full suite one time (M26).

### Part 2–3 finish

- [ ] SwiftLint on the changed app files; MeasureKit `swift test`; the full app suite one time; the final review.
- [ ] Phone checks for Amadeus (M17–M24), with `-scanRenderer metal`: the same 8 moments as "Part 1" (note §2e), plus look, lag and occlusion.
