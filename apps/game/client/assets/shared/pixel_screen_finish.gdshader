shader_type canvas_item;

// Screen-space finish applied to the low-res SubViewportContainer, before the
// nearest-neighbour upscale.
//
// Everything here samples on **whole source-pixel offsets**. That is the rule the original "no
// blur, no bloom, no sub-pixel sampling" note was protecting: what ruins a pixel render is
// *interpolating between* source pixels, not reading more than one of them. Halation and the
// chromatic fringe below both read neighbours, both land on the pixel grid, and the output is as
// crisp as it was with neither.

uniform float contrast : hint_range(0.5, 2.0) = 1.08;
uniform float saturation : hint_range(0.0, 2.0) = 1.06;
uniform float lift : hint_range(-0.2, 0.2) = 0.0;
uniform vec4 shadow_tint : source_color = vec4(0.18, 0.16, 0.26, 1.0);
uniform float shadow_tint_amount : hint_range(0.0, 1.0) = 0.14;
uniform vec4 highlight_tint : source_color = vec4(1.0, 0.94, 0.82, 1.0);
uniform float highlight_tint_amount : hint_range(0.0, 1.0) = 0.1;
uniform float vignette_strength : hint_range(0.0, 1.0) = 0.18;
uniform float vignette_softness : hint_range(0.1, 2.0) = 0.85;
uniform float damage_pulse : hint_range(0.0, 1.0) = 0.0;
uniform vec4 pulse_tint : source_color = vec4(0.62, 0.08, 0.08, 1.0);

// Sustained low-health tension. Deliberately not the same channel as damage_pulse: that one is a
// one-shot flash that decays to nothing, so while it is fading it cannot also hold a state. A
// player at 20% health needs the frame to *stay* wrong, and still needs each individual hit to
// register on top of it.
//
// It breathes rather than sitting still, because a constant tint stops being visible after a few
// seconds — the eye adapts to it and it just becomes the game's colour. Movement does not adapt
// away. The breath is quantized to a handful of steps for the same reason the rest of the pipeline
// bands its shading: a smooth pulse at this resolution reads as a fault, not as an effect.
uniform float distress : hint_range(0.0, 1.0) = 0.0;
uniform vec4 distress_tint : source_color = vec4(0.46, 0.05, 0.07, 1.0);
uniform float posterize_levels : hint_range(0.0, 64.0) = 0.0;

// --- cinematic finish ---------------------------------------------------------------------------

// Filmic shoulder and toe.
//
// The 3D pass already tonemaps, but it tonemaps to a *display* image; what separates a frame that
// looks photographed from one that looks rendered is the second, gentler S applied to the finished
// picture — highlights that roll rather than clip, and shadows that lift off pure black onto a
// slightly cool floor. At 0 this is a straight pass-through.
uniform float filmic_amount : hint_range(0.0, 1.0) = 0.65;
uniform float filmic_toe : hint_range(0.0, 0.4) = 0.055;
uniform float filmic_shoulder : hint_range(0.0, 1.0) = 0.32;

// Three-way colour grade. `gain` multiplies the highlights, `gamma` bends the midtones and
// `slope_lift` raises the floor — the standard lift/gamma/gain a colourist works in, rather than
// the single contrast knob this had.
uniform vec3 grade_gain = vec3(1.03, 1.0, 0.97);
uniform vec3 grade_gamma = vec3(1.0, 1.0, 1.02);
uniform vec3 grade_lift = vec3(0.004, 0.004, 0.012);

// Halation: the faint bleed a bright highlight leaves in the emulsion around it.
//
// Not bloom — the 3D pass already blooms in HDR, which handles the glow *of* a light source. This
// is the wider, redder smear that survives into the print, and it is most of why firelight in film
// feels hot. Sampled on a ring of whole source pixels.
uniform float halation_strength : hint_range(0.0, 1.0) = 0.22;
uniform float halation_radius : hint_range(1.0, 6.0) = 3.0;
uniform vec3 halation_tint = vec3(1.0, 0.42, 0.22);

// Lateral chromatic aberration, growing toward the corners the way a real lens's does. Whole
// pixels, so the fringe is a hard one-pixel offset rather than a smear.
uniform float aberration_strength : hint_range(0.0, 4.0) = 1.1;

// Film grain, quantised into a handful of steps for the same reason the shading is banded.
uniform float grain_strength : hint_range(0.0, 0.3) = 0.022;
uniform float grain_size : hint_range(1.0, 6.0) = 2.0;

// Size of one source pixel in UV. Set by `PixelDioramaViewport`; the fallback matches a 1920-wide
// render so an unset value degrades to something sane rather than to a division by zero.
// Literal, not `1.0 / 1920.0`: Godot's shader parser wants a constant *expression* here and a
// division is not one.
uniform vec2 source_texel = vec2(0.00052083, 0.00092593);

float luminance(vec3 color) {
	return dot(color, vec3(0.2126, 0.7152, 0.0722));
}

float hash21(vec2 p) {
	return fract(sin(dot(p, vec2(41.3, 289.1))) * 43758.5453);
}

// Reinhard-with-toe. Cheap, monotonic, and it keeps hue: the whole colour is scaled by the ratio
// the curve applies to its own luminance rather than each channel being bent on its own, which is
// the same reasoning `quantize_color` uses in the 3D pass.
vec3 filmic_curve(vec3 col) {
	float l = max(luminance(col), 0.00001);
	float toed = max(l - filmic_toe, 0.0) / (1.0 - filmic_toe);
	float shouldered = toed / (1.0 + toed * filmic_shoulder);
	shouldered *= 1.0 + filmic_shoulder;
	return col * mix(1.0, shouldered / l, filmic_amount);
}

void fragment() {
	vec2 centered_uv = UV - vec2(0.5);
	float radius = length(centered_uv);

	// Chromatic aberration: red and blue sampled a whole source pixel further out than green, and
	// only toward the corners. Applied at the top so everything downstream grades the fringed image
	// rather than fringing an already-graded one.
	vec4 source = texture(TEXTURE, UV);
	vec3 col = source.rgb;
	if (aberration_strength > 0.001) {
		vec2 dir = radius > 0.0001 ? centered_uv / radius : vec2(0.0);
		vec2 offset = dir * source_texel * floor(aberration_strength * radius * 2.0 + 0.5);
		col.r = texture(TEXTURE, UV + offset).r;
		col.b = texture(TEXTURE, UV - offset).b;
	}

	// Halation. Eight taps on a ring at whole-pixel offsets; only what is already bright
	// contributes, so ordinary lit surfaces cost nothing visible and a flame smears.
	if (halation_strength > 0.001) {
		float r = floor(halation_radius + 0.5);
		vec3 bleed = vec3(0.0);
		for (int i = 0; i < 8; i++) {
			float a = float(i) * 0.7853981634;
			vec2 tap = vec2(cos(a), sin(a)) * r * source_texel;
			vec3 neighbour = texture(TEXTURE, clamp(UV + tap, vec2(0.0), vec2(1.0))).rgb;
			bleed += max(neighbour - vec3(0.62), vec3(0.0));
		}
		col += bleed * 0.125 * halation_strength * halation_tint;
	}

	col = filmic_curve(col);

	// Lift / gamma / gain, then the legacy single-knob contrast on top of it.
	col = max(col + grade_lift, vec3(0.0));
	col = pow(col, 1.0 / max(grade_gamma, vec3(0.01)));
	col *= grade_gain;

	col = (col - 0.5) * contrast + 0.5 + lift;

	float luma = luminance(col);
	col = mix(vec3(luma), col, saturation);

	// Split tone: cool the shadows, warm the highlights. Cheap way to give the
	// palette depth without adding light sources.
	col = mix(col, shadow_tint.rgb * col * 2.0, (1.0 - luma) * shadow_tint_amount);
	col = mix(col, highlight_tint.rgb * col, luma * highlight_tint_amount);

	if (vignette_strength > 0.001) {
		vec2 centered = UV - vec2(0.5);
		float falloff = smoothstep(vignette_softness, 0.2, length(centered));
		col *= mix(1.0 - vignette_strength, 1.0, falloff);
	}

	// Applied before the damage pulse so a fresh hit still flashes brighter than the standing
	// tension, keeping "I just took damage" distinguishable from "I am nearly dead".
	if (distress > 0.001) {
		vec2 centered = UV - vec2(0.5);
		float edge = smoothstep(0.10, 0.66, length(centered));
		float breath = 0.70 + 0.30 * sin(TIME * 2.3);
		breath = floor(breath * 5.0 + 0.5) / 5.0;
		float amount = distress * edge * breath;
		col = mix(col, distress_tint.rgb * col * 1.15, amount);
		// Pull the corners down as well. Tint alone reads as a colour grade; darkening the frame
		// is what makes the play space feel like it is closing in.
		col *= mix(1.0, 0.78, amount);
	}

	if (damage_pulse > 0.001) {
		vec2 centered = UV - vec2(0.5);
		float edge = smoothstep(0.15, 0.55, length(centered));
		col = mix(col, pulse_tint.rgb * col * 1.35, damage_pulse * edge);
	}

	if (posterize_levels >= 2.0) {
		col = floor(col * posterize_levels + 0.5) / posterize_levels;
	}

	// Grain last, after posterising — grain that is itself posterised is a fixed dither pattern
	// rather than noise, and would sit still on screen. Quantised into five steps so it stays part
	// of the same visual language, and weighted toward the midtones the way film grain is: clean
	// blacks, clean highlights, texture in between.
	if (grain_strength > 0.001) {
		vec2 grain_cell = floor(FRAGCOORD.xy / max(grain_size, 1.0));
		float n = hash21(grain_cell + floor(TIME * 24.0)) - 0.5;
		n = floor(n * 5.0) / 5.0;
		float mid = 1.0 - abs(luminance(col) * 2.0 - 1.0);
		col += n * grain_strength * mid;
	}

	COLOR = vec4(clamp(col, vec3(0.0), vec3(1.0)), source.a);
}
