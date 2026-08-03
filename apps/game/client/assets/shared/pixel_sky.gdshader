shader_type sky;

// Hard-banded sky. A smooth gradient is the fastest way to make a pixel-art
// scene look like an untextured 3D scene, so the elevation ramp is quantized
// into a small number of stops and the sun is a stepped disc plus halo.

uniform vec4 zenith_color : source_color = vec4(0.24, 0.34, 0.56, 1.0);
uniform vec4 horizon_color : source_color = vec4(0.74, 0.64, 0.52, 1.0);
uniform vec4 ground_color : source_color = vec4(0.18, 0.16, 0.18, 1.0);
uniform float bands : hint_range(2.0, 24.0) = 8.0;
uniform float horizon_falloff : hint_range(0.5, 8.0) = 2.4;
uniform vec4 sun_color : source_color = vec4(1.0, 0.94, 0.76, 1.0);
uniform float sun_size : hint_range(0.0, 0.3) = 0.045;
uniform float sun_glow : hint_range(0.0, 1.0) = 0.4;
uniform float cloud_amount : hint_range(0.0, 1.0) = 0.0;
uniform vec4 cloud_color : source_color = vec4(0.92, 0.9, 0.88, 1.0);

float sky_hash(vec2 cell) {
	return fract(sin(dot(cell, vec2(12.9898, 78.233))) * 43758.5453);
}

// Value noise, sampled on a coarse grid so the clouds come out as blocks with
// hard edges rather than the soft blobs a continuous sample would give.
float cloud_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = sky_hash(i);
	float b = sky_hash(i + vec2(1.0, 0.0));
	float c = sky_hash(i + vec2(0.0, 1.0));
	float d = sky_hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

void sky() {
	float elevation = EYEDIR.y;

	if (elevation < 0.0) {
		COLOR = ground_color.rgb;
	} else {
		float t = pow(clamp(elevation, 0.0, 1.0), 1.0 / horizon_falloff);
		float safe_bands = max(2.0, bands);
		float stepped = clamp(floor(t * safe_bands) / (safe_bands - 1.0), 0.0, 1.0);
		vec3 col = mix(horizon_color.rgb, zenith_color.rgb, stepped);

		// Cloud belt sits low in the sky and is sampled on a fixed angular pixel
		// grid, so the puffs stay the same apparent size wherever the camera looks.
		if (cloud_amount > 0.001) {
			vec2 dome = vec2(atan(EYEDIR.x, EYEDIR.z) * 26.0, elevation * 62.0);
			vec2 grid = floor(dome) + 0.5;
			float puff = cloud_noise(grid * 0.16) * 0.65 + cloud_noise(grid * 0.42) * 0.35;
			float belt = (1.0 - smoothstep(0.06, 0.34, elevation)) * smoothstep(0.0, 0.05, elevation);
			float mask = step(1.0 - cloud_amount * 0.42, puff) * belt;
			float rim = step(1.0 - cloud_amount * 0.34, puff) * belt;
			col = mix(col, cloud_color.rgb * 0.86, mask);
			col = mix(col, cloud_color.rgb, rim);
		}

		if (LIGHT0_ENABLED) {
			vec3 to_sun = -LIGHT0_DIRECTION;
			float d = clamp(dot(EYEDIR, to_sun), 0.0, 1.0);
			float disc = step(1.0 - sun_size * sun_size, d);
			float halo = floor(pow(d, 42.0) * 4.0) / 4.0;
			col = mix(col, sun_color.rgb, clamp(halo * sun_glow + disc, 0.0, 1.0));
		}

		COLOR = col;
	}
}
