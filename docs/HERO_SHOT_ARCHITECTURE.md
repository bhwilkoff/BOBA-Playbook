# Hero Shot — Architecture & Iteration Journal

A 10-second 3D card video feature in BOBA Playbook iOS app. RealityKit
+ Metal + CoreImage post-process. v7.3 is the current shipping state
after 50+ iterations across v5.0 → v7.3.

This doc captures the **architecture as-built** plus the **iteration
journal** that shaped it. The journal exists because most of the
patterns here aren't obvious from reading the final code — they're
hard-learned from bugs that shipped and got rolled back.

For the underlying methodology + RealityKit patterns that this feature
depends on, see the three skills:

- [`3d-feature-sim-validation`](~/.claude/skills/3d-feature-sim-validation/SKILL.md) — the offline-sim methodology that finally enabled self-validated iteration
- [`realitykit-3d-card-rendering`](~/.claude/skills/realitykit-3d-card-rendering/SKILL.md) — the RealityKit patterns this feature exercises
- [`3d-feature-debug-loop`](~/.claude/skills/3d-feature-debug-loop/SKILL.md) — the discipline that broke us out of the 15+ iteration trust death-spiral

---

## What it does

User opens Hero Shot from any card detail view. Picks a "Style" (camera arc), a "Length" (5/10/15s), and a "Motion" (card spin). Generates a 1080×1920 portrait MP4 that shows the card art with cinematic camera motion + lighting + a brand watermark, suitable for social media sharing.

## Final architecture (v7.3)

### Scene graph

```
RealityRenderer root
├── envBackdrop                — equirectangular env image as a plane behind
├── rimHalo                    — palette-tinted gradient plane behind card (opacity 0.85)
├── cardPivot (rotates Y for spin)
│   ├── front  (UnlitMaterial path → PhysicallyBasedMaterial w/ .pbrMatte)
│   ├── back   (PhysicallyBasedMaterial, no clearcoat, roughness 0.85)
│   └── edge   (box, halfThickness × 1.9 = 0.285mm thick, tinted UIColor.white)
├── keyLight   (DirectionalLight 11_000 from (0.3, 0.4, 0.5))
├── fillLight  (DirectionalLight  4_500 from (0, 0.05, 0.5))
│                              ↑ rim light intentionally REMOVED
└── IBL        (ImageBasedLightComponent intensityExponent -5.0)
```

### Camera arcs

Two arc presets in the shipping UI (Detail and Tech Demo removed in v7.3):

- **Reveal** — slide in from -X, settle at hero pose `(0, 0.015, 0.34)` FOV 32°, push to climax `(0, 0.018, 0.30)` FOV 30°.
- **Showcase** — orbit ±22° around card at 0.25m radius, settle at slightly off-axis hero pose.

### Card motion

- **`.slowRotate`** (default) — sinusoidal sway ±30° around face-on. Never edge-on. Safe default.
- **`.entranceSpin`** — full 2π rotation over the first 35% of clip, then settle. Card passes through edge-on briefly (0.3mm physical thickness is genuinely a thin sliver); smoothstep velocity sweeps through quickly so eye reads "spin" not "vanished."
- **`.static`** — no card motion.

### Post-process

CoreImage pass after RealityRenderer outputs each pixel buffer:

```swift
applyExposurePass(to: pixelBuffer,
                   ev: -0.3,         // ~20% darker than neutral
                   saturation: 1.15,
                   contrast: 1.08,
                   ciContext: ciContext)
```

Then a watermark composite ("BOBA PLAYBOOK" brand mark at bottom-right) writes via `AVAssetWriter`.

## Key files

| File | Role |
|---|---|
| `BOBAPlaybook/Views/HeroShot/HeroShotRenderer.swift` | Core scene builder, camera arcs, lighting, post-process. ~1900 lines. The brain. |
| `BOBAPlaybook/Views/HeroShot/HeroShotView.swift` | SwiftUI surface — pickers, preview, generate button. Texture loading lives here (`loadFrontTexture`). |
| `BOBAPlaybook/Components/BOBACardEntity.swift` | Shared 3D card construction. Front + back + edge with material variants. Also used by House of BoBA. |
| `BOBAPlaybook/Shaders/Holofoil.metal` | Metal surface shader (currently inert — sparkle overlay was removed in v7.0 but shader kept for future). |
| `AppVersion.xcconfig` | Marketing + build version bumped per ship. v7.3 = 2.270 / 533. |
| `tools/HeroShotSim/sim3d.swift` | macOS RealityFoundation sim that mirrors the iOS scene. THE most important debugging tool. |
| `tools/HeroShotSim/test_card*.jpg` | Test assets matching the real /full/ R2 tier resolution. |

## Texture pipeline (v7.3)

Source: Cloudflare R2 `/full/` tier at `https://pub-d2cb69f3a56c44a6b98f5e3975bc44c2.r2.dev/full/{imageFile}`.

Actual measured sizes: **477×667 to 745×1040** per card (NOT the documented "≤1200px" in CARD_SCHEMA.md). For the Hero Shot framing the card occupies ~877 vertical pixels of the 1920-tall output → source/display ratio is borderline 1:1 to 0.5× upsample. Pixelation is the user-visible result for the smallest sources.

Mitigation pipeline in `loadFrontTexture`:

```swift
let upsampled = Self.upsampleAndSharpen(image, scale: 2.0)  // Lanczos
let rounded = BOBACardEntity.roundedCorners(upsampled)
let tex = try TextureResource(image: rounded.cgImage!,
    withName: nil,
    options: TextureResource.CreateOptions(
        semantic: .color,
        mipmapsMode: .allocateAndGenerateAll
    ))
```

The combination of:

1. **Lanczos pre-upscale** (2x) — synthetic detail, gives mipmap chain a higher-LOD source
2. **Mipmap chain** — GPU picks the right LOD for the screen-space sampling rate
3. **PBR matte material** — Lambert math averages texture samples within the fragment's lighting hemisphere = inherent anti-aliasing
4. **Post-process EV -0.3** — pulls highlights out of clipping risk

…produces "soft but vivid" rendering that perceptually reads as "no pixelation" without the source assets actually being higher-res. The authoritative fix is to regenerate `/full/` at 1500+ px (tracked as task #128 in SCRATCHPAD; deferred).

## The sim (`tools/HeroShotSim/sim3d.swift`)

The sim is a **single-file macOS CLI** that uses `RealityFoundation` (NOT `RealityKit` — that's iOS-only) to render the same scene graph the iOS feature renders. It produces PNG contact sheets that I can inspect via the Read tool.

### Why the sim exists

iOS Simulator's `RealityRenderer` hangs on offline render. Repeatedly confirmed. The only path to validating Hero Shot output without a physical device is the macOS RealityFoundation sim.

Before the sim existed (v5.0–v6.5), every "fix" was shipped blind. After the sim shipped (v6.5+), the feedback loop tightened to minutes per iteration:

```
hypothesis → change sim → recompile → render PNG → Read PNG → confirm fix or refine
```

### How to compile + run

```bash
cd tools/HeroShotSim
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcrun -sdk macosx swiftc -O \
  -framework RealityFoundation -framework Metal -framework MetalKit \
  -framework CoreImage -framework AppKit \
  -o sim3d sim3d.swift

# Render rotation strip for one card
./sim3d test_card.jpg .

# Output: sim3d_v68_rotation.png (4 cols × 3 rows = 12 yaw angles)
# Read tool can decode it as multimodal image content.
```

The 12-yaw rotation strip is the **single most valuable** diagnostic — it catches:

- Front material wash at any rotation
- Back plane visibility / wash
- Edge box occlusion bugs (front art hidden behind solid edge color)
- Edge-on disappearance issues
- Sparkle overlay artifacts (when overlay was a thing)

### The `renderIOSv67RotationStrip` function

`tools/HeroShotSim/sim3d.swift` exports a single function that produces the diagnostic contact sheet. It builds:

- Backdrop plane with env image
- Rim halo plane
- `cardPivot` with front + back + edge children
- 3-point lighting (key + fill, NO rim per v7.1)
- IBL with `intensityExponent = -5.0`
- Camera at hero pose `(0, 0.015, 0.34)` FOV 32°

For each yaw in `[0, 30, 60, ..., 330]`:
- Sets `cardPivot.orientation = simd_quatf(angle: yawRad, axis: SIMD3<Float>(0, 1, 0))`
- Renders frame via `RealityRenderer`
- Applies `applyiOSPostProcess(ev: -0.3, saturation: 1.15, contrast: 1.08)`
- Captures the result tile

Composites 12 tiles into one PNG. ~5 seconds total render time on M1/M2.

## Iteration journal — what didn't work + why

This is the part of the doc most worth preserving. Every "lesson learned" below has a corresponding rolled-back commit.

### v5.4 — Lanczos 3x + mipmaps "fixed" pixelation

✓ Worked initially. Combined with PBR pipeline, gave soft-but-vivid output.
✗ Created a follow-on assumption that Lanczos was the lever to lean on. When v6.3 switched to UnlitMaterial, Lanczos became a NEGATIVE — synthetic upscale produced soft texels that Unlit then rendered RAW = soft pixelation. Lesson: every "fix" depends on the surrounding pipeline. Always re-validate when an adjacent component changes.

### v6.0.x — PBR + holofoil shader washed out

✓ Card never went edge-on-invisible (PBR edges caught light).
✗ User reported "washed out" across 12+ iterations. Lambert averaging + high IBL = soft pigment.
Fix attempt: switch to UnlitMaterial (v6.3). Fixed washout, broke other things.

### v6.5–v6.7 — Custom sparkle overlay plane

✗ The CustomMaterial overlay plane in front of the card was a novel construction with no foundation in stock RealityKit. Each iteration produced a different artifact: black dots, colored dots, dim halos. The "premultiplied alpha gotcha" was the root cause but only diagnosed in v6.9 via a research agent.
Lesson: when a custom approach produces a different bug at every iteration, that's a signal the foundation is wrong. Step back; consider whether the feature needs the complexity at all.

### v6.8 — disabled edge box to fix "white sliver"

✗ The cream-white (UIColor.white-0.92) edge box was visible as a side strip during rotation. Disabled `includeEdge: false`.
✗ This INTRODUCED a worse bug: at yaw≈90°, both front and back planes are edge-on with zero pixels visible. Card vanished briefly mid-rotation.
Fix: re-enable edge with palette-sampled dark tint (v6.9). Then in v7.3, switch to pure white edge per user request — cards in real life have white paper edges; the v6.8 issue was the SIZE of the wash, not the WHITE itself.

### v7.0 — pulled camera back 1.7× to address pixelation

✗ Made card too small. User: "this is not the right way to downsample or eliminate the pixelation."
Lesson: source pixel count IS the constraint. Pulling camera back trades subject prominence for crispness 1:1 — that's the wrong knob for hero shots. The right knobs are: get higher-res source assets, or use material softening (PBR) to mask source limits.

### v7.0 — removed sparkle overlay entirely

✓ Eliminated the dot artifacts permanently. User accepted the loss of "shimmer."
Lesson: every "premium feel" feature has a cost. If the feature can't ship without bugs, ship without the feature.

### v7.1 → v7.3 — final tuning

Three rounds of small parameter adjustments based on user observations:
- v7.1: restore PBR pipeline, drop Lanczos to 2x (not 3x), remove rim light, IBL exp -5
- v7.2: restore full 2π `.entranceSpin` rotation, drop post-process EV to 0.0
- v7.3: brightness -20% (EV -0.3), glow -15% (rim halo opacity 0.85), edge white, trim Style/Length menus

All v7.x ships were sim-validated before hitting the user.

## What's still imperfect (acknowledged)

- **Smallest cards (477px source) still pixelate slightly at push-climax frame.** The authoritative fix is regenerating `/full/` R2 tier at 1500+ px (task #128).
- **Back wash at yaw=180°** (if user picks `.entranceSpin`) — back catches key+fill light Lambert at the same dot product the front does at yaw=0°. Acceptable since `.slowRotate` is default and `.entranceSpin` sweeps through quickly.
- **No view-dependent shimmer/holofoil.** Sparkle overlay removed in v7.0. Could be reintroduced via the original `holofoilSurface` shader on a `CustomMaterial(.unlit)` if foil treatment becomes a feature need. Has known washout risk.

## How to iterate Hero Shot in the future

Every change should follow the pattern:

1. **Read this doc** + the related skills first. Many of the obvious "fixes" have been tried.
2. **Build the sim** if it's not already built. Edit `tools/HeroShotSim/sim3d.swift` to match the iOS scene change you're considering.
3. **Render the 12-yaw strip** before changing the iOS code. Look at the PNG via Read tool.
4. **If sim looks right**, port the change to iOS.
5. **iOS build → device test** as final validation.
6. **Bump `AppVersion.xcconfig`** + commit with a message that quotes the user feedback the change addresses.

## Skills referenced

- `~/.claude/skills/3d-feature-sim-validation/SKILL.md` — the offline-sim methodology
- `~/.claude/skills/realitykit-3d-card-rendering/SKILL.md` — the RealityKit patterns
- `~/.claude/skills/3d-feature-debug-loop/SKILL.md` — the discipline of diagnostic-first iteration
