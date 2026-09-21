shader_type spatial;
render_mode blend_mix, unshaded, cull_disabled, depth_draw_never;

// Reserved for transient trails: unlike the opaque shared emissive shader this consumes vertex alpha.
uniform vec4 tint : source_color = vec4(1.0);
uniform float emission_energy : hint_range(0.0, 8.0) = 2.0;

void fragment() {
	vec4 color = vec4(tint.rgb * COLOR.rgb, tint.a * COLOR.a);
	ALBEDO = color.rgb;
	EMISSION = color.rgb * emission_energy;
	ALPHA = color.a;
}
