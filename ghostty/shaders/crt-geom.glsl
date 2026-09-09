/*
    CRT-Geom for Ghostty
    Based on CRT-interlaced by cgwg, Themaister and DOLLS
    Copyright (C) 2010-2012 cgwg, Themaister and DOLLS

    Ported to Ghostty's Shadertoy-compatible mainImage format.
    Original: https://github.com/libretro/common-shaders
    License: GPL v2+

    Uniform mapping (RetroArch → Ghostty):
      Texture      → iChannel0
      TextureSize  → iChannelResolution[0].xy
      InputSize    → iChannelResolution[0].xy
      OutputSize   → iResolution.xy
      FrameCount   → iFrame
      TEX0.xy      → fragCoord / iResolution.xy
*/

// ── Tunable parameters ─────────────────────────────────────────────────────
const float CRTgamma         = 2.4;   // simulated CRT gamma
const float monitorgamma     = 2.2;   // output display gamma
const float d                = 1.6;   // viewer distance (monitor widths)
const float CURVATURE        = 0.0;   // 1 = curved, 0 = flat
const float R                = 5.0;   // curvature radius
const float cornersize       = 0.001;  // rounded corner size
const float cornersmooth     = 1000.0;// corner edge softness
const float x_tilt           = 0.0;   // horizontal tilt (radians)
const float y_tilt           = 0.0;   // vertical tilt (radians)
const float overscan_x       = 100.0; // horizontal overscan %
const float overscan_y       = 100.0; // vertical overscan %
const float DOTMASK          = 0.2;   // dot-mask strength [0,1]
const float SHARPER          = 1.0;   // horizontal sharpness [1,3]
const float scanline_weight  = 0.3;   // scanline beam width
const float lum              = 0.0;   // extra luminance
const float interlace_detect = 0.0;   // interlace simulation toggle
const float SATURATION       = 1.0;   // colour saturation
const float INV              = 0.0;   // 1 = inverse-gamma out, 0 = power-law

// ── Feature flags ──────────────────────────────────────────────────────────
#define LINEAR_PROCESSING   // linearise texture before filtering
#define OVERSAMPLE          // 3× oversample of scanline beam
// #define USEGAUSSIAN      // use gaussian instead of lanczos-like beam

// ── Macros ─────────────────────────────────────────────────────────────────
#define FIX(c)  max(abs(c), 1e-5)
#define PI      3.141592653589

#ifdef LINEAR_PROCESSING
#   define TEX2D(c) pow(texture(iChannel0, (c)), vec4(CRTgamma))
#else
#   define TEX2D(c) texture(iChannel0, (c))
#endif

// ── Per-invocation globals (set once at the top of mainImage) ───────────────
// GLSL global non-uniform variables are per-invocation; setting them before
// the helper calls is safe and avoids threading state through every signature.
vec2 g_sinangle;
vec2 g_cosangle;
vec2 g_aspect;
vec3 g_stretch;
vec2 g_TextureSize;
vec2 g_InputSize;
vec2 g_OutputSize;

// ── Curvature helpers ───────────────────────────────────────────────────────

float intersect(vec2 xy) {
    float A = dot(xy, xy) + d * d;
    float B = 2.0 * (R * (dot(xy, g_sinangle) - d * g_cosangle.x * g_cosangle.y) - d * d);
    float C = d * d + 2.0 * R * d * g_cosangle.x * g_cosangle.y;
    return (-B - sqrt(B * B - 4.0 * A * C)) / (2.0 * A);
}

vec2 bkwtrans(vec2 xy) {
    float c     = intersect(xy);
    vec2  point = vec2(c) * xy;
    point -= vec2(-R) * g_sinangle;
    point /= vec2(R);
    vec2  tang  = g_sinangle / g_cosangle;
    vec2  poc   = point / g_cosangle;
    float A     = dot(tang, tang) + 1.0;
    float B     = -2.0 * dot(poc, tang);
    float C     = dot(poc, poc) - 1.0;
    float a     = (-B + sqrt(B * B - 4.0 * A * C)) / (2.0 * A);
    vec2  uv    = (point - a * g_sinangle) / g_cosangle;
    float r     = FIX(R * acos(a));
    return uv * r / sin(r / R);
}

vec2 fwtrans(vec2 uv) {
    float r = FIX(sqrt(dot(uv, uv)));
    uv *= sin(r / R) / r;
    float x = 1.0 - cos(r / R);
    float D = d / R + x * g_cosangle.x * g_cosangle.y + dot(uv, g_sinangle);
    return d * (uv * g_cosangle - x * g_sinangle) / D;
}

vec3 maxscale() {
    vec2 c  = bkwtrans(-R * g_sinangle / (1.0 + R / d * g_cosangle.x * g_cosangle.y));
    vec2 a  = vec2(0.5, 0.5) * g_aspect;
    vec2 lo = vec2(fwtrans(vec2(-a.x,  c.y)).x,
                   fwtrans(vec2( c.x, -a.y)).y) / g_aspect;
    vec2 hi = vec2(fwtrans(vec2(+a.x,  c.y)).x,
                   fwtrans(vec2( c.x, +a.y)).y) / g_aspect;
    return vec3((hi + lo) * g_aspect * 0.5, max(hi.x - lo.x, hi.y - lo.y));
}

vec2 transform(vec2 coord) {
    coord *= g_TextureSize / g_InputSize;
    coord  = (coord - vec2(0.5)) * g_aspect * g_stretch.z + g_stretch.xy;
    return (bkwtrans(coord) / vec2(overscan_x / 100.0, overscan_y / 100.0)
            / g_aspect + vec2(0.5)) * g_InputSize / g_TextureSize;
}

float corner(vec2 coord) {
    coord *= g_TextureSize / g_InputSize;
    coord  = (coord - vec2(0.5)) * vec2(overscan_x / 100.0, overscan_y / 100.0)
             + vec2(0.5);
    coord  = min(coord, vec2(1.0) - coord) * g_aspect;
    vec2  cdist = vec2(cornersize);
    coord        = cdist - min(coord, cdist);
    float dist   = sqrt(dot(coord, coord));
    return clamp((cdist.x - dist) * cornersmooth, 0.0, 1.0) * 1.0001;
}

// ── Beam / scanline helpers ─────────────────────────────────────────────────

vec4 scanlineWeights(float dist, vec4 color) {
#ifdef USEGAUSSIAN
    vec4 wid     = 0.3 + 0.1 * pow(color, vec4(3.0));
    vec4 weights = vec4(dist / wid);
    return (lum + 0.4) * exp(-weights * weights) / wid;
#else
    vec4 wid     = 2.0 + 2.0 * pow(color, vec4(4.0));
    vec4 weights = vec4(dist / scanline_weight);
    return (lum + 1.4) * exp(-pow(weights * inversesqrt(0.5 * wid), wid))
           / (0.6 + 0.2 * wid);
#endif
}

// ── Colour helpers ──────────────────────────────────────────────────────────

vec3 saturate_color(vec3 textureColor) {
    float lum_val = length(textureColor) * 0.5775;
    vec3 lw = vec3(0.3, 0.6, 0.1);
    if (lum_val < 0.5)
        lw = lw * lw + lw * lw;
    float luminance     = dot(textureColor, lw);
    vec3  greyScaleColor = vec3(luminance);
    return mix(greyScaleColor, textureColor, SATURATION);
}

// Gamma-corrected output that compensates for scanline+mask embedded gamma.
#define pwr vec3(1.0 / ((-0.7 * (1.0 - scanline_weight) + 1.0) \
                        * (-0.5 * DOTMASK + 1.0)) - 1.25)

vec3 inv_gamma(vec3 col, vec3 power) {
    vec3 cir = col - 1.0;
    cir *= cir;
    return mix(sqrt(col), sqrt(1.0 - cir), power);
}

// ── Entry point ─────────────────────────────────────────────────────────────

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    // Map Ghostty uniforms to the names used throughout this shader.
    g_TextureSize = iChannelResolution[0].xy;
    g_InputSize   = iChannelResolution[0].xy;
    g_OutputSize  = iResolution.xy;

    // UV in [0,1] matching GL convention: (0,0) = bottom-left.
    vec2 TEX0 = fragCoord / iResolution.xy;

    // Precompute values that the original shader interpolated per-vertex.
    g_sinangle = sin(vec2(x_tilt, y_tilt)) + vec2(0.001);
    g_cosangle = cos(vec2(x_tilt, y_tilt)) + vec2(0.001);
    g_aspect   = vec2(1.0, 0.75); // 4:3 CRT aspect
    g_stretch  = maxscale();

    vec2  ilfac     = vec2(1.0, clamp(floor(g_InputSize.y / 200.0), 1.0, 2.0));
    vec2  sharpTS   = vec2(SHARPER * g_TextureSize.x, g_TextureSize.y);
    vec2  one       = ilfac / sharpTS;
    float mod_factor = TEX0.x * g_TextureSize.x * g_OutputSize.x / g_InputSize.x;

    // Apply curvature transformation.
    vec2 xy = (CURVATURE > 0.5) ? transform(TEX0) : TEX0;

    float cval = corner(xy);

    // Interlace offset.
    vec2 ilvec      = vec2(0.0,
        ilfac.y * interlace_detect > 1.5 ? mod(float(iFrame), 2.0) : 0.0);
    vec2 ratio_scale = (xy * g_TextureSize - vec2(0.5) + ilvec) / ilfac;

#ifdef OVERSAMPLE
    float filter_ = g_InputSize.y / g_OutputSize.y;
#endif

    vec2 uv_ratio = fract(ratio_scale);

    // Snap to centre of the underlying texel.
    xy = (floor(ratio_scale) * ilfac + vec2(0.5) - ilvec) / g_TextureSize;

    // Lanczos-2 horizontal reconstruction coefficients.
    vec4 coeffs = PI * vec4(1.0 + uv_ratio.x, uv_ratio.x,
                            1.0 - uv_ratio.x, 2.0 - uv_ratio.x);
    coeffs = FIX(coeffs);
    coeffs = 2.0 * sin(coeffs) * sin(coeffs / 2.0) / (coeffs * coeffs);
    coeffs /= dot(coeffs, vec4(1.0));

    // Reconstruct colour for current and next scanline.
    vec4 col = clamp(mat4(
        TEX2D(xy + vec2(-one.x,       0.0)),
        TEX2D(xy),
        TEX2D(xy + vec2( one.x,       0.0)),
        TEX2D(xy + vec2( 2.0 * one.x, 0.0))) * coeffs,
        0.0, 1.0);

    vec4 col2 = clamp(mat4(
        TEX2D(xy + vec2(-one.x,       one.y)),
        TEX2D(xy + vec2( 0.0,         one.y)),
        TEX2D(xy +       one),
        TEX2D(xy + vec2( 2.0 * one.x, one.y))) * coeffs,
        0.0, 1.0);

#ifndef LINEAR_PROCESSING
    col  = pow(col,  vec4(CRTgamma));
    col2 = pow(col2, vec4(CRTgamma));
#endif

    // Scanline beam weights.
    vec4 weights  = scanlineWeights(uv_ratio.y, col);
    vec4 weights2 = scanlineWeights(1.0 - uv_ratio.y, col2);

#ifdef OVERSAMPLE
    uv_ratio.y  = uv_ratio.y + 1.0 / 3.0 * filter_;
    weights      = (weights  + scanlineWeights(uv_ratio.y, col)) / 3.0;
    weights2     = (weights2 + scanlineWeights(abs(1.0 - uv_ratio.y), col2)) / 3.0;
    uv_ratio.y  = uv_ratio.y - 2.0 / 3.0 * filter_;
    weights      = weights  + scanlineWeights(abs(uv_ratio.y), col) / 3.0;
    weights2     = weights2 + scanlineWeights(abs(1.0 - uv_ratio.y), col2) / 3.0;
#endif

    vec3 mul_res = (col * weights + col2 * weights2).rgb * vec3(cval);

    // Dot-mask: alternate green/magenta tint per output pixel column.
    vec3 dotMaskWeights = mix(
        vec3(1.0, 1.0 - DOTMASK, 1.0),
        vec3(1.0 - DOTMASK, 1.0, 1.0 - DOTMASK),
        floor(mod(mod_factor, 2.0)));
    mul_res *= dotMaskWeights;

    // Output gamma correction.
    if (INV == 1.0)
        mul_res = inv_gamma(mul_res, pwr);
    else
        mul_res = pow(mul_res, vec3(1.0 / monitorgamma));

    mul_res = saturate_color(mul_res);

    fragColor = vec4(mul_res, 1.0);
}
