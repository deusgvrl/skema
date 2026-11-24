# Design: our own Metal renderer for the scan camera (Option B, 24 Nov 2026)

- **Made:** 24 Nov 2026 by Claude. The direction and the decisions are Amadeus's.
- **Credit:** `RoomScanView` and the scan session (`ScanSession`, `ScanFrame+ARKit`, `DepthCopier`): Dzakki. Centre dots (`UsedPointsEntities`) and Apple's coaching view: Richie (branch `origin/feat/scan-instruction-overlay`, not merged yet). 3D dashed outline and grown box (`ScanOutlines`, `OutlineMesh`, `OutlineLayout`): A10-106, Amadeus.
- **Status:** design approved with D1–D4 (Amadeus, 24 Nov); cases M1–M26 + M13a **approved** (24 Nov; M4: the switch ignores case; M7 as fixed). Plan: `docs/scan-metal-renderer-plan.md`.
- **Branch:** `perf/scan-metal-renderer` (worktree, from `origin/dev`). No Jira ticket (decision, Amadeus, 24 Nov). This note lives only in this branch.
- **Related:** Change A: `investigate/docs/scan-memory-lighter-realitykit-design_2026-11-24.md` and `plan_scan-lighter-realitykit_2026-11-24.md` (A10-117, approved).
- **Checked against:** the worktree code (24 Nov), Richie's branch (read with `git show`), the iOS 27.2 SDK headers on this Mac, and developer.apple.com.

**Labels**

| Label | Meaning |
|---|---|
| **verified** | Claude read it in the code, the SDK headers or an official source in this session. "verified, memgraph" = from the 21 Nov memgraphs. |
| **inferred** | Claude's reading or estimate. Not measured on a phone. |
| **decision** | Amadeus decided. |
| **open** | Not decided. Every recommendation from Claude in this note is open until Amadeus approves it. |

---

## 0. Decisions (Amadeus, 24 Nov 2026)

- **D1. Room mesh: off in Metal mode only.** Occlusion in Metal mode comes from the LiDAR depth (§5.3–5.4). The `ARView` path keeps the room mesh (A10-117: "room mesh off: no").
- **D2. Targets:** after the save, **300 MB**. "During" is compared later: the same walk with `ARView` and with Metal, then pick the better one.
- **D3. Projection: our own maths** (`ScanProjection`), with ARKit's iOS 27 API only as a phone check (M23). The full calculation, its sources and its checks are in the artifact "Scan Projection Maths": https://claude.ai/artifact/5omiruCsb8nR34GRHTBA2K (matrix verified against `ScanOverlay` in code to 0.00004 pt; Metal NDC rules verified on an Apple GPU).
- **D4. Occlusion numbers:** margin **3 cm**, minimum confidence **1** (medium). Tune on the phone (M21).
- Approach 1 (`MTKView` + `CVMetalTextureCache`) stays the recommendation.

## 1. Intent

Draw the scan camera without RealityKit. RealityKit stays in memory after the scan (verified, memgraph). Our own small renderer draws only what the scan needs: the camera picture, the dashed boxes, the centre dots. Then RealityKit does not load at all.

B is the second step. It continues only when A does not reach the targets (decision rule in section 5).

## 2. Goals, non-goals, anti-goals

**Goals**

- G1. After the scan: no RealityKit engine in memory (no `re::Engine`, `RenderManager`, `AssetManager`, `ImageBasedLightSystem`).
- G2. During the scan: no RealityKit work and no room mesh (`Recon3D`). Occlusion comes from the LiDAR depth.
- G3. The same look as today (decision, Amadeus, 24 Nov): 3D dashed boxes in perspective, occlusion, Richie's centre dots, Apple's coaching view.
- G4. The camera picture and the outlines are drawn in the same render pass, from the same `ARFrame`. So the outlines cannot lag behind the picture (decision, Amadeus, 24 Nov).
- G5. The "hidden or visible" rule is a pure Swift function with unit tests. The shader uses the same rule and the same numbers.
- G6. A launch argument selects the renderer. The default is `ARView` (today's view).

**Non-goals**

- CPU work in the scan engine (A10-115).
- UI changes (Richie's revamp).
- A lower render resolution or a different camera format. These change the look or the tracking.
- Line thickness that is updated every frame. Today the thickness is set when the mesh is built (T1). B keeps T1.

**Anti-goals**

- The presentation on 30 Nov must depend on B (decision, Amadeus: it must not).
- Any change to existing files before A is merged (decision, Amadeus: B uses only new files until then).
- Outlines that lag behind the picture (this is why option C in A's design was rejected, verified in A's design §5).
- Taking the `ARSession` delegate away from `ScanSession`. `ScanSession` is the delegate and must stay so (verified, `RoomScanView.makeCameraView` comment and `ScanSession.init`).

## 3. What we know (facts)

### 3.1 Memory and CPU (verified, memgraph, 21 Nov, Debug build run from Xcode, Metal API validation on)

- After the scan: footprint **509.5 MB**; peak **901 MB** (4 lights). No `ARSession`, `ARView` or `ScanSession` stays.
- After the scan, RealityKit's engine stays: `re::Engine`, `RenderManager`, `AssetManager`, `ImageBasedLightSystem` pools. About **185 MB** of picture pools are in Apple's engines (4 of the 5 pools are RealityKit's, 1 is `Recon3D`). RealityKit GPU memory is about **136 MB**.
- During the scan: `AppleCV3D` (ARKit tracking) **116–125 MB**; `IOSurface` pools about **188 MB**; `Recon3D` (room mesh) **33–40 MB** and growing; RealityKit per-frame **36–43 MB**, physics **9–13 MB**; **124** `AREnvironmentProbeAnchor`; our own data about **5.5 MB**.
- Time Profiler, 22 Nov: RealityKit **22%** and the room mesh **14%** of the app CPU.

### 3.2 Targets and decision rule (decision, Amadeus)

| When | Target | Last number |
|---|---|---|
| During a 9-item scan | about **500 MB** | peak 901 MB (4 lights) |
| After the save | about **300 MB** | 509.5 MB |

If A gives during ≤ 550 MB **and** after ≤ 350 MB, B stops. Else B continues.

### 3.3 Today's code (verified, read in the worktree)

- `RoomScanView` makes an `ARView(cameraMode: .ar, automaticallyConfigureSession: false)`, sets `view.session = session`, turns on `.occlusion` from the room mesh, and adds `.disableGroundingShadows`.
- `ScanOutlines` makes **one** `ModelEntity` per box from `OutlineMesh.geometry(of:radius:)`. Material: `UnlitMaterial`, white, opacity `OutlineLayout.opacity` (0.7), `faceCulling = .none`. A box that moved less than 1 cm (`rebuildStep = 0.01`) keeps its mesh. The radius comes from `OutlineMesh.radius(for:cameraPosition:focalLength:)` (4 pt, T1).
- `OutlineLayout`: dash 6 cm, gap 4 cm, thickness 4 pt, opacity 0.7. `OutlineMesh`: 8 sides, 2 cap rings per end.
- `ScanOverlay` projects a 3D spot to the screen: camera space → picture pixel (fx, fy, cx, cy) → upright picture (pixel (u, v) becomes (H − v, u)) → aspect fill from the centre. `picturePoint(fromScreen:)` is the exact reverse. The tags and the taps use these functions.
- `CameraModel`: `intrinsics`, `imageResolution`, `cameraToWorld`. `DepthFrame.depth` is "Metres from the camera plane"; `confidence` is the `ARConfidenceLevel` raw value (0 low, 1 medium, 2 high).
- `DepthSampler.maxRange = 5.0` m. `DepthSampler.minProjectDepth = 0.01` m. The measuring code uses `minConfidence = 2` (`DepthGrouping`, `TapSampling`, `DepthPreview`), and `1` for the nearest tap pixel (`TapSampling`, line 39).
- `ScanSession` accepts frames at most 15 per second (`frameInterval = 1/15`) and copies the depth each accepted frame (`DepthCopier`). `ScanViewModel.collect` runs 5 times per second (`collectInterval = 0.2`). `outlineBoxes` gives the world box of each item and the subject.
- The iPhone app is **portrait only** (`INFOPLIST_KEY_UISupportedInterfaceOrientations = UIInterfaceOrientationPortrait`, `project.pbxproj`). The deployment target is **iOS 27.0**.
- Richie's branch (verified, `git show`): `UsedPointsEntities` draws per item a 1.5 cm dot at the top centre (item colour), a white dot at the base centre, and a 4 mm white line between them. Material: `UnlitMaterial`, `readsDepth = false` (drawn over everything). `RoomScanView.makeCoachingView` adds an `ARCoachingOverlayView` (goal `.horizontalPlane`, `activatesAutomatically = true`) as a subview, and the coordinator is its delegate (`onCoachingChange`).

### 3.4 Apple APIs (verified, official sources)

| Fact | Exact quote | Where |
|---|---|---|
| The camera picture has two planes | "The pixel buffer's contents are encoded in a biplanar YCbCr (also called YUV) data format; to render the image you'll need to convert this pixel data to a drawable RGB format." | "Displaying an AR Experience with Metal", Overview. https://developer.apple.com/documentation/arkit/displaying-an-ar-experience-with-metal |
| Zero-copy textures | "Use CVMetalTextureCache APIs to create two Metal textures from the pixel buffer—one each for the buffer's luma (Y) and chroma (CbCr) planes" | same page |
| Pull each frame | "use the session's currentFrame property to get the current frame image and tracking information each time you redraw your view's contents." | same page |
| Full range, colour matrix | "ARKit captures full-range color space values, not video-range values." The page gives the matrix `ycbcrToRGBTransform` in Metal syntax. | `ARFrame.capturedImage`, Discussion. https://developer.apple.com/documentation/arkit/arframe/capturedimage |
| Depth texture format | "if at runtime the depthMap format is kCVPixelFormatType_DepthFloat32 (OSType `fdep`), use MTLPixelFormat.r32Float." | `ARDepthData.depthMap`, Discussion. https://developer.apple.com/documentation/arkit/ardepthdata/depthmap |
| Confidence texture format | "If, for example, the confidenceMap format is kCVPixelFormatType_OneComponent8 (OSType `L008`), create a Metal texture with format MTLPixelFormat.r8Uint" | `ARDepthData.confidenceMap`, Discussion. https://developer.apple.com/documentation/arkit/ardepthdata/confidencemap |
| Depth is low resolution | "ARKit’s depth map contains precise, low-resolution depth values for objects in the camera feed." | "Displaying a point cloud using scene depth". https://developer.apple.com/documentation/arkit/displaying-a-point-cloud-using-scene-depth |
| Picture fit (iOS 27) | "The transform provides the correct rotation and aspect-fill for presenting the captured image in the given view angle and size." | `ARFrame.displayTransform(viewRotationAngle:viewportSize:)`, Discussion, iOS 27.0+. https://developer.apple.com/documentation/arkit/arframe/displaytransform(viewrotationangle:viewportsize:) |
| Old fit API is deprecated | `displayTransformForOrientation:viewportSize:`: introduced 11.0, deprecated 27.0. | https://developer.apple.com/documentation/arkit/arframe/displaytransformfororientation:viewportsize: |
| Projection (iOS 27) | "The projection matrix returned provides an aspect fill for the provided viewport size and view angle." | `ARCamera.projectionMatrix(viewRotationAngle:viewportSize:zNear:zFar:)`. https://developer.apple.com/documentation/arkit/arcamera/projectionmatrix(viewrotationangle:viewportsize:znear:zfar:) ; also `ARCamera.h` in the iOS 27.2 SDK |
| View angle | "(0 LandscapeRight, 90 Portrait, 180 LandscapeLeft, 270 PortraitUpsideDown). Obtain it from ARSession.viewRotationAngle." | same pages |
| The angle needs a layer | `viewLayer`: "The layer that displays the `ARFrame`, required before `viewRotationAngle` becomes available." The angle is "`NaN` until the angle is available". | `ARSession.h`, iOS 27.2 SDK (on this Mac). Claude did not find this text on developer.apple.com. |
| Coaching view works with a session | `session`: "The session this view uses to provide coaching." | `ARCoachingOverlayView`. https://developer.apple.com/documentation/arkit/arcoachingoverlayview |
| Memoryless depth | "You can significantly reduce your memory usage by creating these attachments as memoryless resources." | `MTLStorageMode.memoryless`. https://developer.apple.com/documentation/metal/mtlstoragemode/memoryless |

> [!NOTE]
> Inferred: Apple's point-cloud sample maps "every entry in the depth map" to "the corresponding pixel in the camera image". So the depth map and the camera picture show the same view, at a lower resolution (256×192 against the picture). B samples the depth at the same picture fraction (0…1) as the colour. Claude found no sentence that says this directly.

> [!NOTE]
> Not found: an official sentence that says how long an app may keep an `ARFrame` before ARKit drops frames. Inferred: keep each frame only until its GPU work ends, as Apple's Metal sample keeps its textures.

## 4. Approaches for drawing the camera

| | 1. `MTKView` + `CVMetalTextureCache` (Y and CbCr planes) | 2. Core Image (`CIImage` from the pixel buffer) into the Metal drawable | 3. Two layers: picture layer + Metal layer for the lines | 4. `ARSCNView` (SceneKit) |
|---|---|---|---|---|
| Same pass as the lines (G4) | yes: one render pass, one frame | possible, but a second encoder per frame (inferred) | **no**: Core Animation joins the layers, they can show different frames (inferred) | yes |
| Memory | textures point at ARKit's own buffers, no copy (verified, Apple sample) | `CIContext` keeps its own caches (inferred, not measured) | small | a full engine again (inferred, not measured) |
| Occlusion from LiDAR | our shader | our shader | our shader | needs custom shader work |
| Work | medium: one Metal file, about 5 Swift files | medium | small | medium; A10-106 left SceneKit for RealityKit (verified, `RoomScanView` header) |
| Apple pattern | yes: Apple's sample and the Xcode "Metal" AR template (verified, `capturedImage` page) | no AR sample | no | yes, but an engine |

**Recommendation (open): approach 1.** It is Apple's own pattern. It copies no picture. It is the only option that is both light and drawn in one pass. Approach 3 is rejected for the same reason as option C in A's design: lag.

## 5. The design

### 5.1 New files and their one job each

All files are new (decision: no changes to old files until A is merged).

| File | Target | One job |
|---|---|---|
| `Final Challenge App/Features/Scan/Metal/MetalScanView.swift` | app | A `UIViewRepresentable` with the same inputs as `RoomScanView` (`session`, `outlines`, later `usedPoints` and `onCoachingChange`). It holds the `MTKView` and the coaching view. |
| `.../Metal/ScanMetalRenderer.swift` | app | The `MTKViewDelegate`. Each draw: read `session.currentFrame`, make the textures, encode one render pass, keep the textures until the GPU is done. |
| `.../Metal/CameraTextures.swift` | app | Wraps one `CVMetalTextureCache`. Makes 4 textures from one `ARFrame`: Y (`r8Unorm`, plane 0), CbCr (`rg8Unorm`, plane 1), depth (`r32Float`), confidence (`r8Uint`). |
| `.../Metal/OutlineBuffers.swift` | app | One vertex buffer and one index buffer per box, from `OutlineMesh.geometry(of:radius:)`. The same rebuild rule (1 cm) and the same radius rule (T1) as `ScanOutlines`. |
| `.../Metal/CentreDotBuffers.swift` | app | Richie's dots and lines as GPU data. Only after his branch is merged (it needs `UsedPoints`). |
| `.../Metal/ScanProjection.swift` | app | Pure maths, `nonisolated enum`: (a) the view-projection matrix from `CameraModel` and the view size, portrait; (b) the texture coordinates of the 4 screen corners (picture fit). It uses the same fit as `ScanOverlay`. |
| `.../Metal/ScanShaders.metal` | app | 3 shader pairs: camera quad (YCbCr → RGB), outlines (with the occlusion rule), centre dots (no depth test). |
| `Final Challenge App/Services/Scan/ScanRendererChoice.swift` | app | Reads the launch argument `scanRenderer`. `metal` gives `.metal`; a missing key or any other value gives `.arView`. |
| `Packages/MeasureKit/Sources/MeasureKit/OcclusionRule.swift` | MeasureKit | Pure function `isHidden(lineDepth:sceneDepth:confidence:)` and its numbers (margin, minimum confidence, 5 m). Next to `DepthSampler`, because it is depth maths. |
| Tests: `Skema Tests/ScanRendererChoiceTests.swift`, `Skema Tests/ScanProjectionTests.swift`, `Skema Tests/OutlineBuffersTests.swift`, `Packages/MeasureKit/Tests/MeasureKitTests/OcclusionRuleTests.swift` | tests | Cases M1–M16 (section 7). |

**The switch comes last** (decision, Amadeus). After the rebase on A, these old files change:

- `ScanView.swift`: one `if`: `MetalScanView` when the choice is `.metal`, else `RoomScanView`. The tap gesture and `ScanTagsView` stay the same.
- `ScanSession`: with the Metal renderer, ask for no room mesh. A already adds the switch `scanRoomMesh` (verified, A's plan, Task 3). So B can test with these launch arguments: `-scanRenderer metal -scanRoomMesh NO`.

> [!WARNING]
> Open: after the rebase, should `scanRenderer` become a 4th field of A's `ScanRenderSettings`, or stay its own small file? Claude's view: a 4th field. One place reads all the scan launch arguments.

### 5.2 One render pass

Each `draw(in:)` call uses **one** `ARFrame` (`session.currentFrame`). One command buffer. One render pass. Three steps inside it:

1. **Camera picture.** A full-screen quad (2 triangles). Texture coordinates from `ScanProjection` (5.6). The fragment shader reads Y and CbCr and multiplies by Apple's `ycbcrToRGBTransform` (verified, `capturedImage` page). No depth write.
2. **Outlines.** For each box: its buffers from `OutlineBuffers`. Vertex shader: `viewProjection × world position`. It also sends 2 values to the fragment shader: the **picture fraction** of the vertex (u/W, v/H, the same maths as `DepthSampler.project`) and the **line depth** (−z in camera space, in metres; the same measure as `DepthFrame.depth`, "Metres from the camera plane", verified). Fragment shader: apply the occlusion rule (5.4). Hidden: `discard_fragment()`. Visible: white, alpha 0.7, normal blending.
3. **Centre dots.** No depth test and no occlusion, drawn last (the same as `readsDepth = false` today, verified on Richie's branch).

The lines and the picture come from the same frame, so the lines cannot lag (G4). This is the main gain against option C.

**Double blending (inferred).** Today the tubes have `faceCulling = .none` (verified). With alpha 0.7, the front and back of a tube can blend two times, which makes a brighter line. Claude does not know how RealityKit handles this now. Proposal (open): a depth-only pre-pass of the tubes, then the colour pass with depth test `equal`. So each pixel gets the colour one time. The depth attachment is `memoryless`, so it costs no memory (verified, `MTLStorageMode.memoryless` page).

> [!WARNING]
> Open: is the brighter double line visible in today's ARView? Compare a screenshot from both renderers (case M22). If the old look has it, the new view must not "fix" it without Amadeus's OK.

### 5.3 From LiDAR depth to a depth texture

- B does **not** use `DepthCopier`. `DepthCopier` copies the depth into Swift arrays 15 times per second for the measuring code (verified). The renderer needs the depth of **this** frame, 60 times per second.
- `CameraTextures` makes the depth and confidence textures from `currentFrame.sceneDepth?.depthMap` and `.confidenceMap` through the same `CVMetalTextureCache`. No copy. Formats: `r32Float` and `r8Uint` (verified, Apple quotes in 3.4). `CameraTextures` checks the pixel format at runtime, as Apple tells; a wrong format gives no depth texture, and then all lines show.
- The shader reads the depth with **nearest** sampling. A bilinear mix of a near wall and a far wall gives a depth that is not real (inferred).
- When `sceneDepth` is nil on a frame, the renderer binds no depth texture and sets a flag `hasDepth = false`. All lines show (rule: "no depth shows").

> [!NOTE]
> Inferred: 256×192 depth pixels on a screen of about 390×844 points make each depth pixel about 3–4 points wide (after the aspect fill). So the edge where a line goes behind a wall is blocky. A's design calls this "softer edges" (verified, A's design §5). It is the main visible risk of B.

### 5.4 The rule "hidden or visible"

One rule, written two times: in Swift (to test) and in the shader (to run). The numbers come from Swift only: the renderer copies `OcclusionRule`'s constants into the shader's uniform buffer each frame. So a changed number changes both.

`OcclusionRule.isHidden(lineDepth: Float, sceneDepth: Float, confidence: UInt8) -> Bool` is **true** only when all of these are true:

1. `sceneDepth` is finite and greater than 0 (there is a depth).
2. `confidence >= OcclusionRule.minConfidence`.
3. `sceneDepth <= OcclusionRule.maxRange` (5 m, the same as `DepthSampler.maxRange`).
4. `sceneDepth < lineDepth - OcclusionRule.margin` (a real surface is clearly in front of the line).

Else the line shows.

- `margin` (proposal: 3 cm). A dash lies on the item's own surface. Without a margin, the line hides behind the surface it sits on and flickers (inferred).
- `minConfidence` (proposal: 1, medium). The measuring code uses 2 (verified). For occlusion a medium pixel is good enough, and with 2 more lines show through walls (inferred).

> [!WARNING]
> Open: the margin (3 cm?) and `minConfidence` (1 or 2?). These two numbers decide how the occlusion looks. Claude proposes to start with 3 cm and 1, then tune them on the phone (case M21).

> [!WARNING]
> Open: should the shader parity also get a GPU test (render a 2×1 depth texture off screen and read the pixels back)? It proves the shader follows the Swift rule. It needs a Metal device in the test run; Claude did not check if the team's test setup has one.

### 5.5 Box lines (reuse `OutlineMesh`)

- `OutlineBuffers.update(boxes:cameraPosition:focalLength:)` does what `ScanOutlines.show` does (verified): remove missing boxes, skip boxes that moved less than 1 cm, build the others with `OutlineMesh.radius` and `OutlineMesh.geometry`.
- The rule `hasMoved` is `private` in `ScanOutlines` (verified). B copies it into `OutlineBuffers` for now (new files only). After A is merged, move it into MeasureKit and use it in both (open).
- `focalLength` in screen points: the same formula as `RoomScanView.focalLength(of:)` (verified): `fx × max(viewWidth / pictureHeight, viewHeight / pictureWidth)`.
- Size (inferred): a 1 m cube has 120 dashes (10 per edge), 4,080 vertices and 23,040 indices (case M14). That is about 140 KB per box, and about 1.3 MB for 9 boxes.
- `OutlineGeometry` is `Sendable` and pure (verified). The build can move off the main actor later. Not in the first version.

### 5.6 Picture fit and projection

Two ways exist:

- **a. ARKit's matrices** (iOS 27.0+, verified): `displayTransform(viewRotationAngle:viewportSize:)`, `viewMatrix(viewRotationAngle:)` and `projectionMatrix(viewRotationAngle:viewportSize:zNear:zFar:)`. The angle comes from `ARSession.viewRotationAngle`, which needs `session.viewLayer` to be set (verified, `ARSession.h`). They cannot be unit-tested: a test cannot make an `ARCamera` (inferred).
- **b. Our pure maths** (`ScanProjection`): build the same matrices from `CameraModel` and the view size, with the fit of `ScanOverlay` (rotate the picture upright, aspect fill from the centre). The app is portrait only (verified), so the angle is fixed at 90.

**Recommendation (open): b in the renderer, a as the check.** Reasons: the outlines, the tags and the taps then use one fit, so they cannot disagree. And b can be unit-tested (cases M5–M8). On the phone, a debug log compares b with ARKit's `projectPoint(_:viewRotationAngle:viewportSize:)` and with `displayTransform(viewRotationAngle: 90, ...)`. They must agree within 1 point (case M23). `MetalScanView` sets `session.viewLayer = mtkView.layer` for this check.

The picture quad gets its texture coordinates from `ScanOverlay.picturePoint(fromScreen:)` at the 4 screen corners. For a 1920×1440 picture on a 390×844 view, the top-left corner is picture (0, 0.808) and the bottom-right corner is picture (1, 0.192) (computed from `ScanOverlay`, case M7). The picture's long sides are cut by 121.5 points on each side.

The depth for clipping: `zNear = DepthSampler.minProjectDepth` (0.01 m), `zFar = 0`-style infinite or 20 m (open, small).

### 5.7 Centre dots

- Today (Richie's branch, verified): spheres of 1.5 cm and a 4 mm box line, unlit, drawn over everything.
- B (proposal, open): a camera-facing disc of 1.5 cm radius for each dot, and a camera-facing strip of 4 mm for the line. An unlit sphere has one flat colour, so it looks like a disc (inferred). The colours come from `UsedPoints.palette` (verified on Richie's branch).
- `CentreDotBuffers` starts only after Richie's branch is merged into `dev` (`UsedPoints` does not exist on `dev` yet, inferred from the file list of the worktree).

### 5.8 Coaching view

- `MetalScanView` adds an `ARCoachingOverlayView` over the `MTKView`, with the same settings as Richie's `makeCoachingView`: `session`, `goal = .horizontalPlane`, `activatesAutomatically = true`, `autoresizingMask` (verified, Richie's branch). The coaching view only needs a session (verified, Apple quote in 3.4), so it does not need `ARView`.
- After his merge, call his `RoomScanView.makeCoachingView(session:in:)` instead of a copy (open), and send `onCoachingChange` the same way.

### 5.9 Threads and Swift 6

- `MTKView` calls `draw(in:)` on the main thread (inferred, the default for `MTKView`). The app's default isolation is `MainActor` (verified, A's plan). Reading `session.currentFrame` there is Apple's pull pattern (verified quote).
- The command buffer's completed handler runs on another thread. It only releases the textures of that frame. Mark it `@Sendable` and keep no other state in it (inferred).
- `preferredFramesPerSecond = 60`: ARKit sends frames "at 60 frames per second by default" (verified, Apple's Metal sample).

## 6. Memory and CPU estimate (inferred)

The base numbers are from 21 Nov: Debug, run from Xcode, Metal validation on (verified, memgraph). A Release build will be lower for both renderers; how much lower is unknown.

**What B removes (compared with today):**

| Part | During | After | Note |
|---|---|---|---|
| RealityKit per-frame + physics | 45–56 MB | – | no RealityKit (verified, memgraph, sizes) |
| RealityKit GPU | up to about 136 MB | about 136 MB | may overlap with the pools below (open) |
| RealityKit picture pools (4 of 5) | – | part of 185 MB | the split between pools is not known (verified, A's design §3) |
| `Recon3D` room mesh | 33–40 MB, growing | its pool | only with `scanRoomMesh NO` |
| 124 light probes | yes | – | no RealityKit lighting |

**What B adds:** 3 drawables of about 1179×2556×4 B ≈ 12 MB each, about 36 MB (inferred; the phone model is open). Depth attachment: 0 (memoryless). Outline buffers: about 1–2 MB. Shaders and pipelines: a few MB.

**What stays in both A and B:** `AppleCV3D` 116–125 MB and the `IOSurface` camera pools about 188 MB (ARKit, needed for tracking and the picture). That is about **300 MB** that no renderer can remove.

| | During (9 items) | After the save |
|---|---|---|
| Target | ~500 MB | ~300 MB |
| Today (21 Nov) | 901 MB peak | 509.5 MB |
| A estimate (A's note) | 690–820 MB | 400–450 MB |
| **B estimate** | **about 700–850 MB** from the Debug numbers | **about 300–375 MB** |

**CPU (inferred):** RealityKit (22%) and the room mesh (14%) go away. The new renderer draws one quad, about 9 boxes and a few dots: a few percent. So about **30% less app CPU** during the scan.

> [!NOTE]
> Interpretation (inferred): B probably reaches the "after" target or comes close. B alone probably does **not** reach "during ≤ 500 MB" in a Debug build, because about 300 MB is ARKit's and stays. The real test is a Release memgraph of both A and B on the same walk.

> [!WARNING]
> Open: the during target (500 MB) may need ARKit changes too (for example a smaller camera format), and those change the look or the tracking. That is outside A and B. Amadeus decides if the target stays.

## 7. Test cases (for Amadeus to approve)

Unit tests run with Swift Testing. Phone checks run on a LiDAR iPhone, Release build, Metal API validation off. Numbers in "Then" are computed from today's code (verified by Claude's maths, not run).

### Renderer switch (`ScanRendererChoice`)

- **M1.** **Given** no `scanRenderer` key in `UserDefaults`, **when** the choice is read, **then** it is `.arView`.
- **M2.** **Given** `-scanRenderer metal` (the string `"metal"`), **when** the choice is read, **then** it is `.metal`.
- **M3.** **Given** `-scanRenderer metl` (a typo), **when** the choice is read, **then** it is `.arView`.
- **M4.** **Given** `-scanRenderer METAL`, **when** the choice is read, **then** it is `.metal` (the value is read without case). *Open: Amadeus may want case-sensitive; then the expected value is `.arView`.*

### Projection and picture fit (`ScanProjection`)

Shared camera: fx = fy = 1500, cx = 960, cy = 720, picture 1920×1440, `cameraToWorld` = identity, view 390×844 points.

- **M5.** **Given** a box corner at world (0.1, 0.2, −2), **when** `ScanProjection` projects it to the screen, **then** the point is (260.9, 455.0) ± 0.5 pt, and it equals `ScanOverlay.screenPoint` for the same corner.
- **M6.** **Given** the same camera and a corner at world (0.1, 0.2, +1) (behind the camera), **when** it is projected, **then** its clip-space w is ≤ 0, so the GPU does not draw it.
- **M7.** **Given** the shared camera, **when** `ScanProjection` gives the picture quad's texture coordinates, **then** top-left = (0, 0.808), top-right = (0, 0.192), bottom-left = (1, 0.808), bottom-right = (1, 0.192), ± 0.001. *(Fixed 24 Nov: `ScanOverlay.picturePoint(fromScreen:)` returns nil at x = 390 or y = 844, because it checks `tap.x < width`; so the check uses the same formula without the screen check, and compares `picturePoint` only at the inner corner (0, 0).)*
- **M8.** **Given** a corner at world (0.1, 0.2, −2), **when** the vertex values for the fragment shader are made, **then** the picture fraction is (1035/1920, 570/1440) and the line depth is 2.0 m.

### Occlusion (`OcclusionRule`, with margin 3 cm, minConfidence 1, maxRange 5 m)

- **M9.** **Given** a line at 2.0 m and a LiDAR depth of 1.5 m with confidence 2, **when** the rule runs, **then** the line is hidden.
- **M10.** **Given** a line at 2.0 m and a LiDAR depth of 2.5 m with confidence 2, **then** the line shows.
- **M11.** **Given** a line at 2.0 m and a LiDAR depth of 1.99 m (inside the margin) with confidence 2, **then** the line shows.
- **M12.** **Given** a line at 2.0 m and a LiDAR depth of 0, or NaN, **then** the line shows (no depth).
- **M13.** **Given** a line at 2.0 m and a LiDAR depth of 1.0 m with confidence 0 (low), **then** the line shows.
- **M13a.** **Given** a line at 6.0 m and a LiDAR depth of 5.5 m with confidence 2, **then** the line shows (beyond 5 m).

### Dashes via `OutlineMesh` (`OutlineBuffers`)

- **M14.** **Given** a 1 m cube from (0, 0, 0) to (1, 1, 1) and radius 0.005, **when** `OutlineBuffers` builds it, **then** it has 120 dashes, 4,080 vertices and 23,040 indices, and the vertex data equals `OutlineMesh.geometry(of:radius:).positions`.
- **M15.** **Given** a built box, **when** the same box comes again moved by 0.5 cm, **then** its buffers stay the same object; **when** it comes moved by 1 cm, **then** it gets new buffers.
- **M16.** **Given** two built boxes, **when** `update` gets only one of them, **then** the other box's buffers are gone.

### Phone checks (Amadeus, on the phone)

- **M17.** **Given** a scan with `-scanRenderer metal` (the room mesh is off in Metal mode, D1) and the save, **when** a memgraph is taken on the home screen, **then** it has no `re::Engine`, no `ARView`, no `AREnvironmentProbeAnchor`, no `MTKView` and no `ScanMetalRenderer`.
- **M18.** **Given** the same 9-item walk (subject, 1 camera, 7 lights) as A's test, **when** memgraphs are taken during the scan, after scan 1 and after scan 2, **then** record the footprints next to the `ARView` run on the same walk; after the save ≤ 300 MB (D2); after scan 2 ≈ after scan 1 (no growth).
- **M19.** **Given** a box on a light, **when** the phone moves fast left and right (screen recording at 60 fps), **then** in every frame the dashed box stays on the light (no frame where the box is behind the picture).
- **M20.** **Given** a box behind a wall corner, **when** the phone looks past the corner, **then** the part behind the wall is hidden and the part in front shows; a box in open space shows fully.
- **M21.** **Given** a box on the floor, **when** the phone looks at it from 1 m and from 4 m, **then** the lines on the item's own surface do not flicker (tunes margin and `minConfidence`).
- **M22.** **Given** the same scene in both renderers, **when** screenshots are compared, **then** the picture colours, the dash length, the line thickness and the opacity look the same.
- **M23.** **Given** the debug log on, **when** a scan runs, **then** `ScanProjection` and ARKit's `projectPoint(_:viewRotationAngle:viewportSize:)` agree within 1 point, and the picture fit agrees with `displayTransform(viewRotationAngle: 90, ...)`.
- **M24.** **Given** tracking is lost (cover the camera), **when** tracking comes back, **then** Apple's coaching view shows and hides, and `onCoachingChange` sends true, then false.
- **M25.** **Given** the "Centres" debug view on (after Richie's merge), **when** items are measured, **then** the centre dots and lines show over everything, in the item colours.
- **M26.** **Given** no launch argument, **when** the app scans, **then** it uses `ARView` exactly as before, and all old tests pass (the presentation build).

Total: 27 cases (M1–M26 and M13a).

## 8. Risks and open questions

> [!NOTE]
> Risk (inferred): blocky occlusion edges from the 256×192 depth (5.3). This is the largest visible change. `.smoothedSceneDepth` (a smoother depth that ARKit can give) may help; it changes `ScanSession`'s configuration, so it waits for the rebase.

> [!NOTE]
> Risk (inferred): thin objects (a light stand) are often missing in the LiDAR depth. Then lines behind them show. Today the room mesh also misses thin objects, so the look may be the same.

> [!NOTE]
> Risk (inferred): the tags (SwiftUI) use `viewModel.camera`, which updates 5 times per second. They lag a little behind the picture today too. B does not change this. If the outlines are now perfectly locked, the tag lag may look larger.

> [!NOTE]
> Risk (inferred): two copies of the rebuild rule and the coaching setup exist until A and Richie's branch are merged. Merge them after the rebase.

> [!WARNING]
> Open 1: is the during target (500 MB) reachable at all, when about 300 MB is ARKit's own tracking and camera memory (section 6)? If not, the decision rule may always say "B continues". Amadeus decides the target or the rule.

> [!WARNING]
> Open 2: projection source: our pure `ScanProjection` (testable, one fit with the tags) or ARKit's iOS 27 matrices (Apple's maths, not testable)? Claude recommends ours, with ARKit as the phone check (5.6).

> [!WARNING]
> Open 3: the occlusion numbers: margin (3 cm?) and minimum confidence (1 or 2?), and whether a GPU parity test is wanted (5.4).

> [!WARNING]
> Open 4: Richie's branch: B needs `UsedPoints` and `makeCoachingView`. Wait for his merge, or copy them into B's new files for now?

> [!WARNING]
> Open 5: `scanRenderer` case: read without case (M4), and as a 4th field of A's `ScanRenderSettings` after the rebase (5.1)?
