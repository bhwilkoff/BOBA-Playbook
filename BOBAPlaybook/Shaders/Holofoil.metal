// Holofoil surface shader — v6.0.
//
// Real holographic-foil shimmer for trading-card hero shots, per the
// research synthesis on premium PBR foil rendering:
//
//   1. Sample card art into baseColor as usual.
//   2. Sample a low-frequency perturbation texture (Perlin-ish noise)
//      to break the rainbow into "oil-slick" flow.
//   3. Project the tangent-space view direction onto a stripe axis
//      (45° diagonal for Battlefoil) + perturbation, use that as a
//      1D lookup into a rainbow LUT.
//   4. Gate the rainbow with a fresnel mask so shimmer is visible
//      only at grazing angles — not from straight-on.
//   5. Modulate by a foil-mask texture (per-treatment, defines WHERE
//      on the card foil exists vs paper). For v6.0 a uniform mask
//      makes the entire card foil; v6.1 will introduce per-treatment
//      masks.
//
// Stock PhysicallyBasedMaterial can't produce this — it ships a hard-
// striped roughness map which IS a striped pattern when sampled, not
// shimmer. Roughness modulates specular spread, not direction. Real
// foil shimmer requires the view-direction-dependent LUT setup above.
//
// References:
//   - Apple, Modifying RealityKit rendering using custom materials
//   - Apple, RealityKit Custom Shader API PDF (Metal-RealityKit-APIs.pdf)
//   - Cyanilux, Holofoil Card Shader Breakdown
//   - Daniel Ilett, Holofoil Cards in Shader Graph and Unity URP

#include <metal_stdlib>
#include <RealityKit/RealityKit.h>

using namespace metal;

/// Surface shader entry. RealityKit calls this once per fragment on
/// the card front mesh. We read uniforms from `params.uniforms()`
/// passed by Swift via CustomMaterial.parameters.
///
/// Custom textures bound to the material:
///   .baseColor       — card art (rounded-corner alpha)
///   .roughness       — unused (we set scalar roughness in shader)
///   .metallic        — unused (we set scalar metallic in shader)
///   .emissiveColor   — perturbation noise (R channel: x, G channel: y)
///   .normal          — rainbow LUT (1D texture stored as 2D)
///   .ambientOcclusion — foil mask (R channel)
///
/// We hijack the unused texture slots because CustomMaterial only
/// exposes the PBR texture set; there's no general "extra texture"
/// slot. Naming is misleading in the code but the bindings are
/// stable.
[[visible]]
void holofoilSurface(realitykit::surface_parameters params)
{
    auto surface = params.surface();
    auto geometry = params.geometry();
    auto textures = params.textures();

    constexpr sampler s(filter::linear,
                        mip_filter::linear,
                        s_address::repeat,
                        t_address::repeat);

    // ── 1. Base card art ─────────────────────────────────────────
    // v6.0.3: flip UV.y. CustomMaterial.SurfaceShader receives UVs in
    // the raw mesh attribute space, which is Y-flipped vs the layout
    // RealityKit's stock PhysicallyBasedMaterial uses internally.
    // Without this, the card art renders upside-down when the card
    // is in the front-mesh upright pose. (User-reported v6.0.1 bug.)
    float2 uv = float2(geometry.uv0().x, 1.0 - geometry.uv0().y);
    half4 base = textures.base_color().sample(s, uv);
    // RealityKit's rounded-corner alpha is in base.a; we keep it.

    // ── 2. Perturbation noise (low-frequency oil-slick distortion)
    // Sample at 2× UV scale so noise is faster than the card art.
    half3 perturbSample = textures.emissive_color().sample(s, uv * 2.0).rgb;
    // Map [0,1] → [-1,1] for signed distortion.
    float2 distortion = float2(perturbSample.x, perturbSample.y) * 2.0 - 1.0;
    distortion *= 0.15;

    // ── 3. UV-dominant rainbow LUT lookup (v6.0.7) ───────────────
    // v6.0–v6.0.6 used `dot(V.xy, stripeAxis)` which biased the LUT
    // to ONE hue region for any given camera angle. For a card whose
    // base art shared that hue (e.g., magenta Bojax + red-rainbow at
    // yaw=50°), the shimmer was INVISIBLE because adding red to red
    // doesn't change much. Sim emulator confirmed this — even at
    // intensity=1.0 the shimmer was invisible at moderate angles.
    //
    // Fix: drive the LUT primarily by UV (so DIFFERENT regions of
    // the card show DIFFERENT rainbow hues simultaneously) plus a
    // view-direction term for the "rainbow flows as you tilt" feel.
    // This is how real holofoil reads.
    float3 V = normalize(geometry.view_direction());

    float viewOffset = V.x * 0.6 + V.y * 0.4;
    float t = uv.x * 1.5 + uv.y * 0.7
              + viewOffset
              + distortion.x * 0.2;
    // Wrap to [0,1) so the rainbow tiles cleanly across the card.
    float lutU = fract(t);
    half3 rainbow = textures.normal().sample(s, float2(lutU, 0.5)).rgb;

    // ── 4. Fresnel gate (grazing ramp) — v6.0.7 exp 1.5 ──────────
    // Sim emulator at yaw=50° revealed exp=5-7 made shimmer effectively
    // INVISIBLE even at high intensity — at moderate viewing angles
    // (which is most of the animation), fresnel was 0.5-3% with those
    // exponents. Exp 1.5 ramps gracefully:
    //   yaw=0° → 0% (no shimmer head-on)
    //   yaw=30° → 5% (subtle hint)
    //   yaw=60° → 35% (visible)
    //   yaw=90° → 100% (full shimmer at grazing)
    // This is the holofoil progression: invisible head-on, increasingly
    // dramatic as the card tilts.
    float3 N = float3(surface.normal());
    float fresnel = pow(1.0 - saturate(dot(N, V)), 1.5);

    // ── 5. Foil mask (where foil exists vs paper) ────────────────
    // v6.0 uses a uniform white mask = full-card foil. v6.1 will
    // introduce per-treatment region masks (Battlefoil only on the
    // background, Inspired Ink only on the serialized strip, etc.).
    float foilMask = textures.ambient_occlusion().sample(s, uv).r;

    // ── 6. Composite (v6.0.4 — SCREEN blend) ─────────────────────
    // v6.0.1 used ADDITIVE blending with a luma damp. User after
    // ship: "still quite bright/white at multiple moments." Root
    // cause: ADDITIVE pushes bright pixels past 1.0 → clamped white.
    // Even with the luma damp protecting fully-saturated pixels,
    // anything in the 0.6-0.9 luma band (skin tones, light backgrounds,
    // off-white borders) gets pushed into clipping.
    //
    // Fix: SCREEN blend. `screen(a, b) = 1 - (1-a)*(1-b)`. Property:
    // bright pixels (a close to 1) stay close to 1 regardless of b;
    // dark pixels brighten by ~b. This is how iridescent foil ACTUALLY
    // composites onto a card optically: the rainbow doesn't ADD to
    // the base color, it REFLECTS the back-light through the foil
    // layer. Never overflows white.
    //
    // Intensity 0.60 (v6.0.7). With UV-dominant lookup + gentle
    // fresnel ramp, this combo is sim-emulator-validated as visibly
    // iridescent across the rotation animation without washing out
    // the card art (SCREEN blend's bright-pixel protection + LUT
    // brightness 0.55 cap = no channel saturation).
    half3 shimmer = rainbow * half(fresnel * foilMask * 0.60);
    half3 inv_base = half3(1.0h) - base.rgb;
    half3 inv_shimmer = half3(1.0h) - shimmer;
    half3 finalColor = half3(1.0h) - inv_base * inv_shimmer;

    // ── 7. Output via EMISSIVE channel (v6.2.1) ──────────────────
    // User across 12+ iterations: "card is washed out." Root cause
    // identified: PBR .lit pipeline modulates base_color by Lambert
    // diffuse + spec + IBL. Source card art (flat, saturated) is
    // averaged with light contributions → physical softening that
    // can't be undone with EV/sat/contrast post-process.
    //
    // FIX: write the final color via set_emissive_color instead of
    // set_base_color. In RealityKit's .lit pipeline, emissive is
    // ADDED to the lit base at full brightness with no light
    // modulation. By setting base_color = black and emissive =
    // (card_art + shimmer), the card renders at source-pigment
    // punch regardless of scene lights. Shimmer is preserved as
    // an additive contribution on top.
    //
    // Trade-off: card surface no longer reacts to 3-point lights
    // (no specular highlights, no diffuse shading). For a flat
    // printed card that matches what users want — the card should
    // look like the printed art, not like a glossy 3D object.
    surface.set_base_color(half3(0.0h));
    surface.set_emissive_color(finalColor);
    surface.set_metallic(0.0);
    surface.set_roughness(1.0);
    // Alpha-test: discard fully-transparent corner pixels so the
    // rounded card silhouette renders correctly even at oblique
    // camera angles (no transparency-sort issues — discard avoids
    // depth-write skip). Matches the opacityThreshold = 0.001 we
    // apply to PhysicallyBasedMaterial elsewhere.
    if (base.a < 0.001h) {
        discard_fragment();
    }
}

/// v6.5 — sparkle-only overlay shader.
///
/// Used on a separate plane in front of the card that produces just
/// the shimmer effect (no card art). Each fragment computes the same
/// view-direction-dependent rainbow + fresnel + perturbation as
/// holofoilSurface, but DISCARDS fragments where the shimmer
/// luminance is below threshold — so only the BRIGHTEST shimmer
/// pixels render, forming a sparkle pattern over the card.
///
/// Binding (same as holofoilSurface):
///   normal           → rainbow LUT
///   emissive_color   → perturbation noise
///   ambient_occlusion → foil mask (uniform white for v6.5)
[[visible]]
void holofoilOverlaySparkle(realitykit::surface_parameters params)
{
    auto surface = params.surface();
    auto geometry = params.geometry();
    auto textures = params.textures();
    auto uniforms = params.uniforms();

    constexpr sampler s(filter::linear, mip_filter::linear,
                        s_address::repeat, t_address::repeat);

    float2 uv = float2(geometry.uv0().x, 1.0 - geometry.uv0().y);

    // v6.7 — animated perturbation. The time uniform drifts the
    // perturbation sample over the duration of the clip so sparkles
    // visibly twinkle (some appear, others disappear) rather than
    // staying static. Drift is slow (~0.5 UV units per 10s) so the
    // pattern still reads as coherent foil texture, just alive.
    float t_anim = uniforms.time() * 0.08;
    float2 driftUV = uv * 2.0 + float2(t_anim, t_anim * 0.6);

    // Perturbation (drifting in UV space over time)
    half3 perturbSample = textures.emissive_color().sample(s, driftUV).rgb;
    float2 distortion = float2(perturbSample.x, perturbSample.y) * 2.0 - 1.0;

    // UV + view → rainbow LUT lookup
    float3 V = normalize(geometry.view_direction());
    float viewOffset = V.x * 0.6 + V.y * 0.4;
    float t = uv.x * 1.5 + uv.y * 0.7 + viewOffset + distortion.x * 0.20;
    float lutU = fract(t);
    half3 rainbow = textures.normal().sample(s, float2(lutU, 0.5)).rgb;

    // Fresnel ramp
    float3 N = float3(surface.normal());
    float fresnel = pow(1.0 - saturate(dot(N, V)), 1.5);

    // Foil mask
    float foilMask = textures.ambient_occlusion().sample(s, uv).r;

    // v6.8 — switch from discard_fragment() to alpha output. The v6.7
    // approach was: compute shimmer, then discard fragments with low
    // perturbLum. The user-reported "black specks that move across
    // the front of the image" maps to a real failure mode: on certain
    // iOS Metal pipeline stages, `discard_fragment()` from a non-uniform
    // control flow path can be elided, in which case the supposed-to-be-
    // discarded fragments render with the computed shimmer color on an
    // OPAQUE overlay plane — dim shimmer over black base = near-black
    // opaque pixels overlaying the card. Plus the time-driven UV drift
    // animates the failure region across the card → "moving black
    // specks." Sim couldn't reproduce because RealityFoundation on macOS
    // honors the discard reliably; on iOS Metal it's a latent risk.
    //
    // Fix: emit alpha through the base_color.a channel and rely on the
    // overlay material's .transparent blending mode. Premultiplied
    // alpha (RealityKit default): src_rgb stays as emissive, src_alpha
    // controls coverage. Non-sparkle pixels (alpha=0) blend to full
    // transparency regardless of emissive output → no speck risk.
    half3 perturbHF = textures.emissive_color().sample(s, uv * 5.0 + float2(t_anim * 1.7, -t_anim * 1.3)).rgb;
    half perturbLum = (perturbHF.r + perturbHF.g + perturbHF.b) / 3.0h;
    half sparkleAlpha = ((perturbLum >= 0.55h) && (foilMask >= 0.1h)) ? 1.0h : 0.0h;

    // Shimmer color: bright rainbow with fresnel boost for grazing
    // shine. Floor 0.7 so head-on sparkles stay visible against
    // the card's colors. Multiply by alpha to keep premultiplied
    // semantics — zero-alpha pixels contribute zero color too.
    float fresnelGain = 0.7 + fresnel * 0.9;
    half3 shimmer = rainbow * half(fresnelGain) * sparkleAlpha;

    // v6.9 — fix premultiplied-alpha bug. RealityKit's surface
    // shader output is premultiplied: final_pixel = (base_color *
    // opacity) + dst * (1 - opacity). The v6.8 code set
    // base_color = (0, 0, 0) and opacity = sparkleAlpha. At sparkle
    // pixels: (0,0,0) * 1 + dst * 0 = (0,0,0) = BLACK opaque. That's
    // the user-reported "black specks moving across the card." The
    // emissive_color was unused because emissive is ADDED post-blend
    // in some pipelines but in RealityKit's premultiplied output the
    // base IS the visible color.
    //
    // Fix: pass shimmer as base_color directly. At sparkle pixels:
    // shimmer * 1 + dst * 0 = shimmer (colored sparkle ✓). At
    // non-sparkle pixels: shimmer*sparkleAlpha=0, opacity=0:
    // (0,0,0) * 0 + dst * 1 = dst (card shows ✓).
    surface.set_base_color(shimmer);
    surface.set_emissive_color(half3(0.0h));
    surface.set_opacity(sparkleAlpha);
    surface.set_metallic(0.0);
    surface.set_roughness(1.0);
}
