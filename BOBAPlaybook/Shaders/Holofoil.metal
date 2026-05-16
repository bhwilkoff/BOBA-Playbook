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
    float2 uv = geometry.uv0();
    half4 base = textures.base_color().sample(s, uv);
    // RealityKit's rounded-corner alpha is in base.a; we keep it.

    // ── 2. Perturbation noise (low-frequency oil-slick distortion)
    // Sample at 2× UV scale so noise is faster than the card art.
    half3 perturbSample = textures.emissive_color().sample(s, uv * 2.0).rgb;
    // Map [0,1] → [-1,1] for signed distortion.
    float2 distortion = float2(perturbSample.x, perturbSample.y) * 2.0 - 1.0;
    distortion *= 0.15;

    // ── 3. View direction → stripe-axis projection → rainbow LUT
    // Per WWDC25 Metal-RealityKit-APIs guidance: view_direction()
    // is in WORLD space; we want tangent-space-relative, but for a
    // flat card the tangent space is well-aligned with X/Y of the
    // model. For Battlefoil the stripe axis is 45° diagonal (X+Y).
    float3 V = normalize(geometry.view_direction());

    // Tangent-space projection: dot V's XY against the stripe axis.
    // float2(0.707, 0.707) = unit vector at 45°.
    float2 stripeAxis = float2(0.7071, 0.7071);
    float t = dot(V.xy, stripeAxis) + distortion.x;
    // Remap [-1, 1] → [0, 1] for the LUT lookup.
    float lutU = t * 0.5 + 0.5;
    half3 rainbow = textures.normal().sample(s, float2(lutU, 0.5)).rgb;

    // ── 4. Fresnel gate (grazing-only) ──────────────────────────
    float3 N = float3(surface.normal());
    // dot(N, V) is 1 head-on, 0 at grazing. Fresnel ramp k=3 gives
    // a tight grazing-only response.
    float fresnel = pow(1.0 - saturate(dot(N, V)), 3.0);

    // ── 5. Foil mask (where foil exists vs paper) ────────────────
    // v6.0 uses a uniform white mask = full-card foil. v6.1 will
    // introduce per-treatment region masks (Battlefoil only on the
    // background, Inspired Ink only on the serialized strip, etc.).
    float foilMask = textures.ambient_occlusion().sample(s, uv).r;

    // ── 6. Composite ─────────────────────────────────────────────
    // Add rainbow shimmer on top of base art. Multiplied by mask
    // (where foil is) and fresnel (only at grazing angles). The 0.85
    // scale prevents the rainbow from overpowering the card art.
    half3 shimmer = rainbow * half(fresnel * foilMask * 0.85);
    half3 finalColor = base.rgb + shimmer;

    // ── 7. PBR-style material output ─────────────────────────────
    // Set scalar metallic/roughness for the lighting calculation.
    // Foil regions are metallic (0.7) and slightly rough (0.25) so
    // they catch sparkle highlights; paper would be (0.0, 0.55) but
    // for v6.0 we use the foil values uniformly.
    surface.set_base_color(half4(finalColor, base.a));
    surface.set_metallic(0.7);
    surface.set_roughness(0.25);
    // Alpha-test: discard fully-transparent corner pixels so the
    // rounded card silhouette renders correctly even at oblique
    // camera angles (no transparency-sort issues — discard avoids
    // depth-write skip). Matches the opacityThreshold = 0.001 we
    // apply to PhysicallyBasedMaterial elsewhere.
    if (base.a < 0.001h) {
        discard_fragment();
    }
}
