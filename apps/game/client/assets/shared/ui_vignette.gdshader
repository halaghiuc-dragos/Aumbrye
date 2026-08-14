shader_type canvas_item;

// Menu backdrop vignette.
//
// Every menu in the game sat on a single flat fill, so a panel floated on a dead field with no
// sense of a space behind it. This darkens and cools the edges of the screen so the eye is pushed
// to the middle where the panel is, without hiding whatever the backdrop is drawn over.
//
// The falloff is quantized to a handful of steps rather than left smooth: the rest of the game
// posterizes its shading into bands, and a smooth gradient at this size reads as compression
// banding instead of as a deliberate edge.

uniform vec4 edge_tint : source_color = vec4(0.0, 0.0, 0.02, 1.0);
uniform float edge_strength : hint_range(0.0, 1.0) = 0.55;
uniform float inner_radius : hint_range(0.0, 1.5) = 0.32;
uniform float outer_radius : hint_range(0.0, 1.5) = 1.02;
uniform float steps : hint_range(2.0, 32.0) = 10.0;

// Darkening the edges of a field that is already almost black buys nothing — there is no range
// left to take away. The depth has to come from the other end: a shallow pool of warm light in
// the middle, the colour of the gold the panels are framed in, so the menu reads as something
// standing in a lit room rather than a rectangle on a void.
uniform vec4 center_tint : source_color = vec4(0.34, 0.26, 0.16, 1.0);
uniform float center_strength : hint_range(0.0, 1.0) = 0.16;
uniform float center_radius : hint_range(0.0, 1.5) = 0.62;

// Slow drifting motes, the same dust the world's atmosphere layer puts in every room. A menu on a
// perfectly still field looks like a screenshot; a few specks rising through it make the panel feel
// like it is hanging in the same air the game is played in.
//
// They are drawn as hard-edged cells on a grid rather than as soft sprites, because everything
// else on screen is quantized to a pixel and a smooth round dot would be the one thing in the
// frame that is not.
uniform vec4 mote_tint : source_color = vec4(0.86, 0.76, 0.52, 1.0);
uniform float mote_strength : hint_range(0.0, 1.0) = 0.44;
uniform float mote_density : hint_range(4.0, 96.0) = 30.0;
uniform float mote_speed : hint_range(0.0, 0.5) = 0.035;
uniform float mote_pixel : hint_range(64.0, 1024.0) = 320.0;

float hash21(vec2 p) {
	return fract(sin(dot(p, vec2(21.98, 78.233))) * 43758.5453);
}

// One mote per grid cell, each with its own phase, drift and brightness.
float motes(vec2 uv, float aspect) {
	vec2 grid = vec2(mote_density * aspect, mote_density);
	vec2 p = uv * grid;
	// Rising, with a slow lateral sway so the field never reads as a scrolling texture.
	p.y -= TIME * mote_speed * grid.y;
	vec2 cell = floor(p);
	float seed = hash21(cell);
	if (seed < 0.86) {
		return 0.0;
	}
	vec2 local = fract(p) - 0.5;
	local.x += 0.28 * sin(TIME * (0.25 + seed) + seed * 12.0);
	// Quantize to the UI's pixel grid so a mote is a square of pixels, not a circle. The step has
	// to be the same on both axes — dividing by the (non-square) cell grid stretched every mote
	// into a horizontal dash.
	float step_px = max(1.0, mote_pixel / grid.y);
	local = floor(local * step_px) / step_px;
	float d = max(abs(local.x), abs(local.y));
	float twinkle = 0.55 + 0.45 * sin(TIME * (0.7 + seed * 1.6) + seed * 30.0);
	return step(d, 0.055) * twinkle * (0.4 + 0.6 * seed);
}

void fragment() {
	// Scaled so the corners reach 1.0 regardless of aspect.
	float dist = length((UV - vec2(0.5)) * vec2(1.0, 1.0)) * 1.41421356;
	float falloff = smoothstep(inner_radius, outer_radius, dist);
	falloff = floor(falloff * steps + 0.5) / steps;
	float amount = falloff * edge_strength;

	float glow = 1.0 - smoothstep(0.0, center_radius, dist);
	glow = floor(glow * steps + 0.5) / steps;
	COLOR.rgb += center_tint.rgb * glow * center_strength;

	// Motes sit under the vignette so the edges swallow them, keeping the eye centred.
	float mote = motes(UV, 16.0 / 9.0);
	COLOR.rgb += mote_tint.rgb * mote * mote_strength;

	COLOR.rgb = mix(COLOR.rgb, edge_tint.rgb, amount);
	// The backdrop is deliberately translucent so the world stays visible behind a modal; the
	// vignette only deepens that toward the frame rather than sealing the screen off.
	COLOR.a = clamp(COLOR.a + (1.0 - COLOR.a) * amount * 0.55, 0.0, 1.0);
}
