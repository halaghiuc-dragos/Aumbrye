// Shared pixel-diorama finish: patterns, quantization, banded lighting, and dithering.

float cell_hash(vec2 cell) {
	return fract(sin(dot(cell, vec2(12.9898, 78.233))) * 43758.5453);
}

// Posterizes brightness into hard bands while leaving hue and saturation alone.
//
// Quantizing each channel on its own destroys the colour: the channels round to different bands,
// so the ratios between them change and the hue swings to whichever primary survived. The castle
// stone (#383347, a barely-violet grey) came out of the old per-channel version as #2a2a55 — the
// blue channel doubled — and in the darker shading bands the green channel rounded to zero
// outright, which is why every floor and wall in the game was streaked with pure magenta.
//
// Scaling the whole colour by the ratio between its quantized and original value keeps the
// channels in proportion, so a band boundary changes how bright a surface is and never what
// colour it is.
// Bands are spaced perceptually, not linearly.
//
// Posterizing the linear value with even steps sounds right and is badly wrong: with six levels the
// lowest band covers linear 0 to 0.083, and linear 0.083 is about sRGB 0.31 — very nearly a third
// of everything the eye can see, all snapped to absolute zero. Castle walls came out 80% pure
// #000000 with only the brick highlights surviving, which read as noise on a void rather than as
// masonry. The old per-channel version had the same fault; it just showed up as hue destruction
// (a grey collapsing to #1d001d) instead of as a black hole.
//
// Encoding to roughly gamma space before quantizing spreads the bands the way the eye spaces them,
// so the darks get as many steps as the brights and shadowed surfaces keep their material.
const float QUANTIZE_GAMMA = 2.2;

vec3 quantize_color(vec3 color, float levels) {
	float value = max(max(color.r, color.g), color.b);
	if (value <= 0.0001) {
		return color;
	}
	float encoded = pow(value, 1.0 / QUANTIZE_GAMMA);
	float quantized = floor(encoded * levels + 0.5) / levels;
	float linear_value = pow(quantized, QUANTIZE_GAMMA);
	return color * (linear_value / value);
}

float voxel_edge_mask(vec2 uv) {
	float edge_x = min(fract(uv.x), 1.0 - fract(uv.x));
	float edge_y = min(fract(uv.y), 1.0 - fract(uv.y));
	float edge = step(edge_x, 0.11) + step(edge_y, 0.11);
	return clamp(edge, 0.0, 1.0);
}

// 4x4 ordered Bayer matrix in [0,1). Used to stipple shading band transitions so
// terminators read as deliberate pixel-art dithering instead of smooth gradients.
float bayer4(vec2 frag_coord) {
	vec2 p = floor(mod(frag_coord, 4.0));
	int index = int(p.x) + int(p.y) * 4;
	float table[16] = float[16](
		0.0, 8.0, 2.0, 10.0,
		12.0, 4.0, 14.0, 6.0,
		3.0, 11.0, 1.0, 9.0,
		15.0, 7.0, 13.0, 5.0
	);
	return table[index] / 16.0;
}

// Quantizes a 0..1 lighting term into hard bands, dithered along the terminator.
float band_light(float value, float bands, float dither_amount, vec2 frag_coord) {
	float safe_bands = max(2.0, bands);
	float dither = (bayer4(frag_coord) - 0.5) * (dither_amount / safe_bands);
	return clamp(floor((value + dither) * safe_bands + 0.5) / safe_bands, 0.0, 1.0);
}

// Picks the dominant axis plane so every face gets square, equally dense pixels.
// Avoids the UV stretching that box meshes of differing sizes otherwise produce.
vec2 triplanar_pattern_uv(vec3 pos, vec3 normal, float scale) {
	vec3 axis = abs(normal);
	if (axis.y >= axis.x && axis.y >= axis.z) {
		return pos.xz * scale;
	}
	if (axis.x >= axis.z) {
		return pos.zy * scale;
	}
	return pos.xy * scale;
}

// Quantized fresnel rim that keeps silhouettes readable in dark rooms.
float pixel_rim(vec3 normal, vec3 view, float steps) {
	float fresnel = 1.0 - clamp(dot(normalize(normal), normalize(view)), 0.0, 1.0);
	fresnel = pow(fresnel, 3.0);
	return floor(fresnel * steps) / steps;
}

// Static spiral pixel grain derived from portal_ellipse.gdshader (no spin animation).
vec3 apply_portal_finish(vec3 col, vec2 pattern_uv, vec3 accent, float px_scale, float strength) {
	float dist = length(pattern_uv * 0.12);
	float angle = atan(pattern_uv.y, pattern_uv.x);
	float spiral_phase = angle + dist * 5.5;
	vec2 spin_dir = vec2(cos(spiral_phase), sin(spiral_phase));
	vec2 spiral_cell = floor(spin_dir * dist * px_scale * 1.15);
	float grain = cell_hash(spiral_cell);
	float ring = fract(dist * 6.0);
	col = mix(col, accent, step(0.82, grain) * strength * 0.42);
	col = mix(col, accent * 0.55 + col * 0.45, ring * strength * 0.2);
	return col;
}
