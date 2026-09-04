shader_type spatial;

// `specular_disabled` is gone.
//
// It was correct while every surface here was matt banded stone, and it is what made reflections
// impossible: a material that writes no specular has nothing for a reflection probe, the sky, or
// screen-space reflections to write *into*, so wet flagstone could only ever be darker flagstone.
// The specular term is now computed in `light()` and quantised like everything else, so surfaces
// reflect without the render losing its pixel-art banding.
render_mode specular_schlick_ggx;

#include "res://assets/shared/pixel_diorama_finish.gdshaderinc"

// surface_kind: 0 = floor, 1 = wall, 2 = prop, 3 = accent
// Floors and walls sample world space so tiling continues across seams; props and
// accents sample object space so the pattern stays locked to moving geometry.

uniform vec4 color_base : source_color = vec4(0.35, 0.32, 0.38, 1.0);
uniform vec4 color_shadow : source_color = vec4(0.25, 0.22, 0.28, 1.0);
uniform vec4 color_accent : source_color = vec4(0.55, 0.42, 0.28, 1.0);
uniform float pixel_scale : hint_range(1.0, 64.0) = 8.0;
// Distance over which the surface pattern fades to flat colour. See `detail` in `fragment()`.
uniform float detail_near = 9.0;
uniform float detail_far = 26.0;
uniform float pattern_strength : hint_range(0.0, 1.0) = 0.58;
uniform float stitch_strength : hint_range(0.0, 1.0) = 0.28;
uniform float color_levels : hint_range(4.0, 16.0) = 6.0;
uniform float edge_strength : hint_range(0.0, 1.0) = 0.45;
uniform float shade_bands : hint_range(2.0, 16.0) = 4.0;
uniform float shade_dither : hint_range(0.0, 1.0) = 0.55;
uniform float light_wrap : hint_range(0.0, 1.0) = 0.25;
uniform float rim_strength : hint_range(0.0, 1.0) = 0.08;
// instance uniform: per-MeshInstance3D via set_instance_shader_parameter(), so every character
// and prop can share one ShaderMaterial resource instead of a duplicate per flash/dissolve event.
instance uniform float flash_amount : hint_range(0.0, 1.0) = 0.0;
instance uniform vec3 flash_color : source_color = vec3(1.0);
instance uniform float flash_emission : hint_range(0.0, 4.0) = 0.0;
// Persistent counterpart to the flash_* triad above: `MaterialFlash.set_persistent_glow()` drives
// this one and never tweens it back to zero, so a boss phase's glow survives the hit-flashes that
// keep resetting `flash_amount` mid-fight.
instance uniform float phase_glow_energy : hint_range(0.0, 4.0) = 0.0;
instance uniform vec3 phase_glow_color : source_color = vec3(1.0);
instance uniform float dissolve_clip : hint_range(0.0, 1.0) = 1.0;
instance uniform vec3 dissolve_origin = vec3(0.0);
instance uniform vec3 dissolve_dir = vec3(0.0, 1.0, 0.0);
instance uniform float dissolve_sweep : hint_range(0.0, 1.0) = 0.6;
uniform int surface_kind : hint_range(0, 3) = 0;
uniform bool use_vertex_color = false;
instance uniform vec3 skin_tint = vec3(1.0);
uniform sampler2D tile_atlas : source_color, filter_nearest, repeat_enable;
uniform bool use_tile_atlas = false;
uniform int tile_row = 0;
uniform int tile_variants = 4;

// --- wind and weather -------------------------------------------------------------------------
//
// Published by `WindService` and `WeatherService` (see `[shader_globals]` in project.godot). Global
// rather than per-material so that everything that moves in the breeze moves *together*: canvas,
// grass and banner cloth all solve the same field, and none of them can drift out of step.
global uniform vec3 wind_vector;
global uniform float wind_time;
global uniform float rain_amount;

// How far, in metres per metre of height, this surface is pushed by a full-strength wind. Zero for
// everything solid; a stall's canvas and a blade of grass opt in.
uniform float wind_sway : hint_range(0.0, 1.0) = 0.0;
// World height the sway pivots about: the ground a tent is pegged to, or the crossbar a banner
// hangs from. Distance is taken as an absolute value, so the one uniform covers both — geometry
// rooted below the anchor leans away from it and geometry hung above it swings under it, which is
// what separates a stall wall from a flag.
//
// Measured in *world* space rather than object space because half the pieces that need to sway are
// rotated (a pitched roof panel's own Y axis is its thickness), and a rotated anchor leans the
// wrong way.
uniform float wind_anchor_y = 0.0;
// How much rain darkens and glosses this surface. Flagstone and soil take it; canvas under a roof
// and anything indoors does not.
uniform float wetness_response : hint_range(0.0, 1.0) = 0.0;

// --- reflectance ------------------------------------------------------------------------------
//
// How shiny this material is when dry. Most of the world is 1.0 rough and 0.0 specular — chalky
// stone, canvas, timber — and looks wrong any other way. What earns a lower roughness is metal:
// the iron on a chest, a gate's ironwork, an anvil. Driven per material rather than per surface
// kind because the accent slot is both gilded trim and painted cloth depending on who asked for it.
uniform float roughness_base : hint_range(0.05, 1.0) = 1.0;
uniform float specular_base : hint_range(0.0, 1.0) = 0.0;
uniform float metallic_base : hint_range(0.0, 1.0) = 0.0;
// Roughness a full puddle settles to. Not zero: a mirror-flat puddle reflects the sky as a hard
// edged copy of it and reads as a hole in the floor.
uniform float puddle_roughness : hint_range(0.0, 1.0) = 0.06;
// How many steps the specular highlight is quantised into. The whole point of this renderer is
// that light arrives in bands; a smooth Blinn lobe on a wet flagstone would be the one gradient on
// screen and would read as a bug.
uniform float specular_bands : hint_range(2.0, 12.0) = 4.0;

varying vec3 v_world_pos;
varying vec3 v_world_normal;
varying vec3 v_local_pos;
varying vec3 v_local_normal;

void vertex() {
	v_local_pos = VERTEX;
	v_local_normal = NORMAL;
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	if (wind_sway > 0.0001) {
		// Displacement grows with height above the anchor, so the pegged hem of a tent wall stays
		// put and the eave above it travels — which is what makes a slab of geometry read as cloth
		// rather than as a sliding box.
		float h = abs(v_world_pos.y - wind_anchor_y);
		float phase = wind_time + v_world_pos.x * 0.35 + v_world_pos.z * 0.27;
		float wave = sin(phase) * 0.6 + sin(phase * 2.3 + 1.7) * 0.4;
		vec3 push = wind_vector * wind_sway * h * (0.6 + 0.4 * wave);
		// Applied in world space and taken back into model space, because the sway direction is a
		// world direction and the mesh it lands on may be turned any way at all.
		VERTEX += (inverse(MODEL_MATRIX) * vec4(push, 0.0)).xyz;
		v_world_pos += push;
	}
}

// Authored character meshes supply ARRAY_COLOR per voxel; when use_vertex_color is
// set, skip the procedural prop pattern. Floors and walls still use world-space cells.
const float WORLD_CELL_RATIO = 0.25;

vec2 pattern_coords() {
	if (surface_kind == 0 || surface_kind == 1) {
		return triplanar_pattern_uv(v_world_pos, v_world_normal, pixel_scale * WORLD_CELL_RATIO);
	}
	return triplanar_pattern_uv(v_local_pos, v_local_normal, pixel_scale);
}

vec3 shade_floor(vec2 uv, vec2 cell, float grain, float detail) {
	float checker = mod(cell.x + cell.y, 2.0);
	float mortar = clamp(step(fract(uv.x), 0.06) + step(fract(uv.y), 0.06), 0.0, 1.0);
	vec3 col = mix(color_base.rgb, color_shadow.rgb, checker * pattern_strength * 0.55 * detail);
	col = mix(col, color_shadow.rgb * 0.8, mortar * pattern_strength * 0.6 * detail);
	col = mix(col, color_accent.rgb, step(0.9, grain) * pattern_strength * 0.22 * detail);
	return col;
}

vec3 shade_wall(vec2 uv, float grain, float detail) {
	// Running-bond brick: every other row is offset by half a brick.
	float row = floor(uv.y * 0.5);
	vec2 brick_uv = vec2(uv.x * 0.5 + mod(row, 2.0) * 0.5, uv.y * 0.5);
	vec2 brick_cell = floor(brick_uv);
	float shade = cell_hash(brick_cell);
	float mortar = clamp(step(fract(brick_uv.x), 0.05) + step(fract(brick_uv.y), 0.07), 0.0, 1.0);
	vec3 col = mix(color_base.rgb, color_shadow.rgb, shade * pattern_strength * 0.45 * detail);
	col = mix(col, color_shadow.rgb * 0.7, mortar * pattern_strength * 0.85 * detail);
	col = mix(col, color_accent.rgb, step(0.94, grain) * pattern_strength * 0.16 * detail);
	return col;
}

vec3 shade_prop(vec2 uv, vec2 cell, float grain, float detail) {
	float checker = mod(cell.x + cell.y, 2.0);
	float plank = step(0.72, fract(uv.y * 0.5 + grain * 0.12));
	vec3 col = mix(color_base.rgb, color_shadow.rgb, checker * pattern_strength * 0.4 * detail);
	col = mix(col, color_shadow.rgb * 0.88, plank * pattern_strength * 0.4 * detail);
	col = mix(col, color_accent.rgb, step(0.9, grain) * pattern_strength * 0.22 * detail);
	return col;
}

// Gilded trim: horizontal bands with scattered inlay studs.
//
// This used to be `mod(cell.x * 7.0 + cell.y * 11.0, 6.0)`, a weighted sum of the two cell axes.
// That expression is constant along diagonal lines, so it painted regular diagonal stripes across
// every accent surface — and since the accent slot carries the biome's *emissive* colour, a door
// panel came out as bright orange diagonals on brown. It read as hazard tape, not as ornament.
//
// Bands run with the geometry instead, and the studs sit on a row-offset grid so they never line
// up into a diagonal again.
vec3 shade_accent(vec2 uv, float detail) {
	vec3 col = color_base.rgb;
	// A recessed band every other row, the way a metal frieze is chased.
	float band = fract(uv.y * 0.5);
	col = mix(col, color_shadow.rgb, step(0.76, band) * pattern_strength * 0.55 * detail);
	col = mix(col, color_base.rgb * 1.12, step(0.06, band) * step(band, 0.16) * detail);
	// Inlay studs, offset half a cell on alternate rows so the eye reads a pattern, not a lattice.
	vec2 stud_cell = floor(vec2(uv.x + mod(floor(uv.y), 2.0) * 0.5, uv.y));
	float stud = step(0.82, cell_hash(stud_cell + vec2(5.0, 2.0)));
	col = mix(col, color_accent.rgb, stud * pattern_strength * 0.6 * detail);
	return col;
}

// How wet this fragment is: the world's rain, this material's willingness to take it, and the fact
// that water does not sit on a vertical face.
float wetness_amount() {
	return clamp(rain_amount * wetness_response, 0.0, 1.0) * clamp(v_world_normal.y, 0.0, 1.0);
}

// Where the water pools.
//
// Water finds a hollow and spreads to a rim, so a puddle is round. This used to be two octaves of
// *quantised* cell noise — `floor(cell * 0.28)` against `floor(cell * 0.9)` — which draws pools as
// axis-aligned rectangular blocks with stepped edges. On a flagstone floor that reads as a few
// stones having been painted a different colour.
//
// It is a disc now: one pool per coarse cell, its centre jittered inside that cell and its radius
// hashed from it, with a little low-frequency wobble on the rim so it is a puddle rather than a
// stamped coin. Sampled on continuous world-space coordinates rather than floored ones, so the
// outline is a curve — and still derived from the same coordinates, so pools stay put as the
// camera moves.
//
// Most cells hold no water at all. That is the point: a puddle is something you could step around.

// Size of the cell one pool lives in, as a fraction of a pattern cell.
const float PUDDLE_GRID = 0.24;
// Fraction of cells that hold a pool.
const float PUDDLE_COVERAGE = 0.55;

float puddle_mask(vec2 uv) {
	vec2 grid = uv * PUDDLE_GRID;
	vec2 id = floor(grid);
	vec2 f = fract(grid) - 0.5;
	float present = cell_hash(id + vec2(11.0, 5.0));
	if (present > PUDDLE_COVERAGE) {
		return 0.0;
	}
	// Off-centre in its cell, so a row of pools is not a row of dots on a grid.
	vec2 centre = (vec2(cell_hash(id + vec2(7.0, 2.0)), cell_hash(id + vec2(23.0, 41.0))) - 0.5) * 0.34;
	vec2 offset = f - centre;
	float radius = mix(0.16, 0.4, cell_hash(id + vec2(3.0, 19.0)));
	// Two low harmonics on the rim: enough to stop it being a circle, not enough to stop it being
	// round. Phased per cell so no two pools have the same outline.
	float ang = atan(offset.y, offset.x);
	float phase = cell_hash(id) * 6.2831853;
	radius *= 1.0 + 0.14 * sin(ang * 3.0 + phase) + 0.07 * sin(ang * 5.0 - phase);
	// The soft band is the wet margin around standing water, which is what a real edge looks like.
	return 1.0 - smoothstep(radius * 0.78, radius, length(offset));
}


void fragment() {
	vec2 uv = pattern_coords();
	vec2 cell = floor(uv);
	float grain = cell_hash(cell);

	// Past a few metres a cell is smaller than a rendered pixel, and the pattern turns into
	// crawling noise. Fade detail out and let the flat palette carry the distance instead.
	//
	// The range is authored rather than fixed at 9..26m, because that range is tuned for props the
	// player walks past and it silently erases the pattern on anything further off. The village in
	// the backdrop stands at seventy metres and upward: every wall, roof and field in it came out
	// as flat untextured colour, and no amount of tuning the materials could have shown otherwise.
	// Those surfaces are also physically much larger, so their cells are still bigger than a pixel
	// at that range and there is nothing to crawl.
	float detail = 1.0 - smoothstep(detail_near, detail_far, length(VERTEX));

	vec3 col;
	if (use_vertex_color) {
		col = COLOR.rgb * skin_tint;
	} else if (use_tile_atlas && surface_kind <= 1) {
		float variant_count = max(1.0, float(tile_variants) * detail);
		int variant = int(cell_hash(cell) * variant_count);
		variant = min(variant, int(variant_count) - 1);
		vec2 tile_origin = vec2(float(variant), float(tile_row)) / 8.0;
		vec2 tile_uv = fract(uv) / 8.0 + tile_origin;
		col = texture(tile_atlas, tile_uv).rgb;
	} else if (surface_kind == 0) {
		col = shade_floor(uv, cell, grain, detail);
	} else if (surface_kind == 1) {
		col = shade_wall(uv, grain, detail);
	} else if (surface_kind == 2) {
		col = shade_prop(uv, cell, grain, detail);
	} else {
		col = shade_accent(uv, detail);
	}

	float stitch = step(0.9, cell_hash(cell + vec2(3.0, 7.0)));
	col = mix(col, mix(color_shadow.rgb, color_base.rgb, 0.35), stitch * stitch_strength * detail);

	float edge = voxel_edge_mask(uv);
	col = mix(col, color_shadow.rgb * 0.75, edge * edge_strength * detail);

	if (dissolve_clip < 0.999) {
		vec3 cell3 = floor(v_local_pos * pixel_scale * 0.5);
		float dither = cell_hash(cell3.xz + vec2(cell3.y * 17.0, cell3.y * 31.0));
		vec3 sweep_dir = dissolve_dir;
		if (length(sweep_dir) < 0.001) {
			sweep_dir = vec3(0.0, 1.0, 0.0);
		} else {
			sweep_dir = normalize(sweep_dir);
		}
		float sweep = clamp(dot(normalize(v_local_pos - dissolve_origin), sweep_dir), -1.0, 1.0);
		float threshold = dissolve_clip - dissolve_sweep * (0.5 - sweep * 0.5);
		if (dither > threshold) {
			discard;
		}
	}

	col = mix(col, flash_color, flash_amount);
	EMISSION += flash_color * flash_amount * flash_emission;
	EMISSION += phase_glow_color * phase_glow_energy;

	// Wet ground. Two things happen to stone in the rain and both matter more than any reflection:
	// it goes darker, and it stops being uniformly matt. Puddles are the second one — the pattern
	// cells that already vary the surface pick out where the water sits, so the sheen collects in
	// patches rather than glazing the whole floor evenly.
	float wet = wetness_amount();
	if (wet > 0.001) {
		float pooled = puddle_mask(uv) * wet;
		// Damp stone all over, and standing water in the hollows. Both had to go further than they
		// did: at the old strengths a soaked plaza was a barely perceptible half-stop darker, and
		// rain that changes nothing about the ground is rain that reads as a particle effect
		// happening in front of the scene rather than weather landing on it.
		col = mix(col, col * 0.52, wet * 0.72);
		col = mix(col, col * 0.26 + vec3(0.024, 0.036, 0.055), pooled * 0.9);
	}

	ALBEDO = quantize_color(col, max(2.0, color_levels));
	// Reflectance. A puddle is the only thing most of this world does that is not chalk: it drops
	// the roughness far enough for the sky, the reflection probes and the screen-space reflection
	// pass to land on it, which is where "wet" actually comes from — the darkening above only says
	// "damp".
	float pooled_here = puddle_mask(uv) * wet;
	// Damp stone is a little glossy everywhere; standing water is near-mirror, which is what gives
	// the screen-space reflection pass something smooth enough to trace against.
	ROUGHNESS = mix(mix(roughness_base, 0.55, wet * 0.5), puddle_roughness, pooled_here);
	METALLIC = metallic_base;
	SPECULAR = max(specular_base, max(pooled_here, wet * 0.35) * 0.7);
}

void light() {
	float ndl = dot(NORMAL, LIGHT);
	ndl = ndl * (1.0 - light_wrap) + light_wrap;
	float shade = band_light(clamp(ndl * 0.5 + 0.5, 0.0, 1.0), shade_bands, shade_dither, FRAGCOORD.xy);
	float rim = pixel_rim(NORMAL, VIEW, 4.0) * rim_strength;
	DIFFUSE_LIGHT += ATTENUATION * LIGHT_COLOR * (shade + rim);

	// Specular, computed here because defining `light()` replaces the whole lighting model — the
	// engine's own specular lobe never runs, so a material that wants a highlight has to draw one.
	//
	// Banded, like the diffuse term. The lobe is Blinn-Phong rather than GGX on purpose: at four
	// quantisation steps the difference between the two is invisible, and the cheap one leaves the
	// budget for the screen-space reflection pass that does the actual work on wet ground.
	float rough = clamp(ROUGHNESS, 0.03, 1.0);
	float sheen = max(specular_base, wetness_amount() * puddle_mask(pattern_coords()));
	if (sheen > 0.001) {
		float shininess = mix(96.0, 6.0, rough);
		float lobe = pow(clamp(dot(NORMAL, normalize(LIGHT + VIEW)), 0.0, 1.0), shininess);
		lobe = floor(lobe * specular_bands) / specular_bands;
		SPECULAR_LIGHT += ATTENUATION * LIGHT_COLOR * lobe * sheen * 1.4;
	}
}
