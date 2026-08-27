shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, depth_test_disabled, fog_disabled;

// Screen-space contour pass.
//
// The diorama shader's `edge_strength` darkens *texture-space* cell borders — the seams between
// pattern cells on a surface. It is not a silhouette, so nothing in the game had one: a character
// standing against a wall of similar value simply dissolved into it, and the whole render read flat
// however carefully the palettes were tuned. A dark contour around every form is what separates
// hand-drawn pixel art from a flat-shaded 3D scene, and it is the one thing the pipeline lacked.
//
// Drawn as a full-screen quad inside the pixel SubViewport, on its own visual layer so the gameplay
// camera never sees it. Depth discontinuities give the outer silhouette; normal discontinuities give
// the interior creases where two faces of the same object meet.

uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
uniform sampler2D normal_tex : hint_normal_roughness_texture, filter_nearest;
// What is already drawn underneath, so the contour can take some of its colour rather than always
// being a hole punched to black.
uniform sampler2D screen_tex : hint_screen_texture, filter_nearest;

uniform vec4 outline_color : source_color = vec4(0.03, 0.025, 0.05, 1.0);
uniform float outline_strength : hint_range(0.0, 1.0) = 0.85;
// In rendered pixels. Held to whole numbers by the caller so the contour lands on the pixel grid.
uniform float thickness : hint_range(1.0, 4.0) = 1.0;

// Depth difference counted as a silhouette, as a fraction of the sample's own distance. Relative
// rather than absolute, or every distant object grows a thick black halo while near ones get none.
uniform float depth_threshold : hint_range(0.001, 0.2) = 0.022;
uniform float depth_falloff : hint_range(0.0, 1.0) = 0.35;

// How far two surface normals must diverge before the crease between them is drawn.
uniform float normal_threshold : hint_range(0.0, 1.0) = 0.42;
// Interior creases are drawn softer than silhouettes: at full strength every box corner in the
// scene gets a hard black line and the world turns into a wireframe.
uniform float interior_scale : hint_range(0.0, 1.0) = 0.45;

// Beyond this many metres the contour fades out. A one-pixel line on something 40m away is noise
// that crawls as the camera moves; the palette carries distance instead.
uniform float fade_start : hint_range(1.0, 200.0) = 26.0;
uniform float fade_end : hint_range(1.0, 300.0) = 46.0;

// The contour is not one colour.
//
// A single flat near-black line around every form is what an inked cel looks like, and it is the
// one thing in this render that ignored the atmosphere everything else obeys: a wall thirty metres
// back sat behind fog, aerial perspective and a graded palette, and then had a pure #080608 line
// drawn on top of it. That line is the nearest thing on screen and it flattens the depth the rest
// of the pipeline works to build.
//
// Two fixes, both cheap. The contour tints toward the distance colour as it recedes, so far
// silhouettes are drawn in the haze rather than through it. And where a surface is bright the
// contour lightens toward its own colour instead of punching to black, which is what stops a
// torch-lit edge being outlined in soot.
uniform vec4 outline_far_color : source_color = vec4(0.31, 0.29, 0.42, 1.0);
uniform float outline_depth_tint : hint_range(0.0, 1.0) = 0.8;
uniform float outline_light_relief : hint_range(0.0, 1.0) = 0.45;

void vertex() {
	// Clip-space cover, so the quad fills the screen whatever the camera is doing and cannot be
	// frustum-culled out of the frame it is meant to draw over.
	POSITION = vec4(VERTEX.xy * 2.0, 1.0, 1.0);
}

float view_depth(vec2 uv, mat4 inv_proj) {
	float raw = texture(depth_tex, uv).x;
	vec3 ndc = vec3(uv * 2.0 - 1.0, raw);
	vec4 view = inv_proj * vec4(ndc, 1.0);
	return -view.z / max(view.w, 0.000001);
}

vec3 view_normal(vec2 uv) {
	return normalize(texture(normal_tex, uv).xyz * 2.0 - 1.0);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 texel = 1.0 / VIEWPORT_SIZE * thickness;

	float centre_depth = view_depth(uv, INV_PROJECTION_MATRIX);
	vec3 centre_normal = view_normal(uv);

	// Four-tap cross. Eight taps only thickens the line on diagonals, which at this scale reads as
	// a blur rather than as a heavier stroke.
	vec2 offsets[4] = vec2[4](
		vec2(texel.x, 0.0), vec2(-texel.x, 0.0),
		vec2(0.0, texel.y), vec2(0.0, -texel.y)
	);

	float depth_edge = 0.0;
	float normal_edge = 0.0;
	for (int i = 0; i < 4; i++) {
		vec2 sample_uv = clamp(uv + offsets[i], vec2(0.0), vec2(1.0));
		float d = view_depth(sample_uv, INV_PROJECTION_MATRIX);
		// Only a *nearer* neighbour marks this pixel as background behind a silhouette, which keeps
		// the contour on the outside of the form instead of doubling it on both sides of every edge.
		depth_edge = max(depth_edge, (centre_depth - d) / max(centre_depth, 0.001));
		normal_edge = max(normal_edge, 1.0 - dot(centre_normal, view_normal(sample_uv)));
	}

	float silhouette = smoothstep(
		depth_threshold, depth_threshold * (1.0 + depth_falloff * 4.0), depth_edge
	);
	float crease = smoothstep(normal_threshold, normal_threshold + 0.28, normal_edge)
		* interior_scale;
	float edge = clamp(max(silhouette, crease), 0.0, 1.0);

	// The sky has no geometry to outline; without this the horizon gets a hard black band. Tested
	// at both extremes rather than against one of them, because which end of the buffer means "far"
	// depends on whether the renderer is using a reversed depth range, and a contour pass should not
	// quietly invert when that changes.
	float raw = texture(depth_tex, uv).x;
	edge *= step(0.0000001, raw) * step(raw, 0.9999999);
	edge *= 1.0 - smoothstep(fade_start, fade_end, centre_depth);

	// Recede the contour into the distance colour, then let a bright surface bleach it.
	float distance_mix = smoothstep(2.0, fade_end, centre_depth) * outline_depth_tint;
	vec3 line = mix(outline_color.rgb, outline_far_color.rgb, distance_mix);
	vec3 behind = texture(screen_tex, uv).rgb;
	float brightness = dot(behind, vec3(0.2126, 0.7152, 0.0722));
	line = mix(line, mix(line, behind, 0.65), smoothstep(0.35, 0.9, brightness) * outline_light_relief);

	ALBEDO = line;
	ALPHA = edge * outline_strength;
}
