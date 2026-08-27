shader_type sky;

// Hard-banded sky. A smooth gradient is the fastest way to make a pixel-art
// scene look like an untextured 3D scene, so the elevation ramp is quantized
// into a small number of stops and the sun is a stepped disc plus halo.

uniform vec4 zenith_color : source_color = vec4(0.24, 0.34, 0.56, 1.0);
uniform vec4 horizon_color : source_color = vec4(0.74, 0.64, 0.52, 1.0);
uniform vec4 ground_color : source_color = vec4(0.18, 0.16, 0.18, 1.0);
// The colour straight overhead.
//
// The ramp used to end at the zenith colour, and `floor(t * bands) / (bands - 1.0)` saturates: with
// eight bands every direction above about forty degrees of elevation landed on the same stop, so
// the whole middle of the dome — the part directly over the player — was one flat fill with no
// banding in it at all. A third stop past the zenith gives the overhead its own rings instead of a
// hole in the middle of the sky.
uniform vec4 apex_color : source_color = vec4(0.10, 0.13, 0.28, 1.0);
uniform float bands : hint_range(2.0, 24.0) = 8.0;
// How wide the blend between two bands is, as a fraction of a band. 0 is the hard step this used to
// draw; 1 is a smooth gradient with no bands left. The stops still read as rings, they just stop
// having a one-pixel edge between them.
uniform float band_softness : hint_range(0.0, 1.0) = 0.45;
uniform float horizon_falloff : hint_range(0.5, 8.0) = 2.4;
uniform vec4 sun_color : source_color = vec4(1.0, 0.94, 0.76, 1.0);
uniform float sun_size : hint_range(0.0, 0.3) = 0.045;
uniform float sun_glow : hint_range(0.0, 1.0) = 0.4;
uniform float cloud_amount : hint_range(0.0, 1.0) = 0.0;
uniform vec4 cloud_color : source_color = vec4(0.92, 0.9, 0.88, 1.0);
// The underside of a cloud is not the same colour as its top. Without this the belt reads as torn
// paper stuck to the dome; with it each puff has a lit crown and a shaded base and reads as mass.
uniform vec4 cloud_shadow_color : source_color = vec4(0.55, 0.52, 0.58, 1.0);
// How fast the belt drifts. Signed, and multiplied into the same wind the world uses.
uniform float cloud_drift : hint_range(0.0, 0.2) = 0.02;
// How far up the sky clouds reach. The old belt was pinned between 0.06 and 0.34 elevation, which
// is a band just above the horizon and nothing overhead at all.
uniform float cloud_ceiling : hint_range(0.1, 1.0) = 0.62;
// How far the deck travels across the sky per metre the wind has carried it.
//
// Tuned by angle rather than by eye: at the base wind of about a third of a metre a second this
// works out at roughly half a degree of sky a second, so a cloud takes a couple of minutes to cross
// the view. The first value that made the deck visibly move was five times this and had the clouds
// racing overhead in under a minute, which reads as a time-lapse rather than as weather.
const float CLOUD_SPEED = 26.0;

// Wind, so the clouds move with the same weather that bends the grass underneath them. Declared in
// `[shader_globals]` and published by `WindService`.
global uniform vec3 wind_vector;
global uniform float wind_time;
// Accumulated wind travel. The deck drifts by how far the wind has *carried* it, not by the
// current wind vector times a clock — see `WindService._drift`.
global uniform vec3 wind_drift;

// The sun and moon, placed by `Celestial` and handed over by `DayNightService`.
//
// `sun_direction` duplicates what `LIGHT0_DIRECTION` carries, because the sun light is *hidden*
// below the horizon — its shadow pass is not worth paying for all night — and a hidden light stops
// reporting a direction. The disc has to keep setting and rising whatever the light is doing.
uniform vec3 sun_direction = vec3(0.0, 1.0, 0.0);
uniform vec3 moon_direction = vec3(0.0, -1.0, 0.0);
// Axis across the moon's disc pointing at the sun; the terminator lies square to it.
uniform vec3 moon_sun_axis = vec3(1.0, 0.0, 0.0);
// Fraction of the disc lit: 0 at new moon, 1 at full.
uniform float moon_phase : hint_range(0.0, 1.0) = 1.0;
uniform float moon_bright : hint_range(0.0, 1.0) = 0.0;
// Angular radius of the moon's disc. Generously larger than life — the real moon is a quarter of a
// degree and would be four pixels here.
uniform float moon_size : hint_range(0.0, 0.2) = 0.055;
uniform vec4 moon_color : source_color = vec4(0.94, 0.94, 0.88, 1.0);
uniform vec4 moon_dark_color : source_color = vec4(0.12, 0.14, 0.22, 1.0);
uniform float star_amount : hint_range(0.0, 1.0) = 0.0;
uniform float star_density : hint_range(0.9, 1.0) = 0.984;

// The contour every solid thing in this game wears.
//
// The world's outline is a screen-space depth and normal edge pass, and the sky has neither — so
// the clouds, the sun, the moon and the stars were the only things on screen with no dark rim
// around them, which is exactly the sort of inconsistency the eye notices without being able to
// name it. There is nothing to detect an edge *from* up here, so each element draws its own: a band
// just outside its own coverage mask, in the same colour and at the same weight as the world pass.
uniform vec4 sky_outline_color : source_color = vec4(0.03, 0.025, 0.05, 1.0);
uniform float sky_outline_strength : hint_range(0.0, 1.0) = 0.75;
// The axis the sky turns on — the celestial pole, which sits at an altitude equal to the observer's
// latitude — and how far round it has turned. Stars are fixed to *this* frame, not to the horizon,
// so over a night they wheel about the pole: the ones near it barely move, the ones on the
// celestial equator swing right across the sky and set.
uniform vec3 celestial_pole = vec3(0.0, 0.73, -0.68);
uniform float star_rotation = 0.0;
// Whole days elapsed. Comets are rare events keyed off this, so one is a particular night's sky
// rather than a permanent fixture.
uniform float sky_day = 0.0;
uniform float meteor_time = 0.0;

// Quantises `x` into `count` stops, with a soft seam between each pair rather than a hard cut.
//
// Divides by `count` rather than `count - 1`: the old expression put its top stop a whole band
// early and then clamped, which is what flattened the overhead.
float soft_band(float x, float count, float softness) {
	float scaled = clamp(x, 0.0, 1.0) * count;
	float idx = floor(scaled);
	float f = scaled - idx;
	float w = max(softness, 0.001) * 0.5;
	float blend = smoothstep(0.5 - w, 0.5 + w, f);
	return clamp((idx + blend) / count, 0.0, 1.0);
}

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

// Turns a direction about an arbitrary axis. Rodrigues, which is the cheapest way to get the sky
// wheeling about the pole without building a matrix per pixel.
vec3 rotate_about(vec3 v, vec3 axis, float ang) {
	float c = cos(ang);
	float s = sin(ang);
	return v * c + cross(axis, v) * s + axis * dot(axis, v) * (1.0 - c);
}


// The colour of a star, from its hash.
//
// Real stars are not white. The spread from hot blue-white through white and yellow to cool orange
// is subtle at this brightness but it is the difference between a star field and a spray of
// identical dots, and the eye picks it up even when it cannot name it.
vec3 star_tint(float h) {
	vec3 hot = vec3(0.72, 0.82, 1.0);
	vec3 warm = vec3(1.0, 0.86, 0.66);
	vec3 white = vec3(1.0, 0.99, 0.96);
	return h < 0.5 ? mix(hot, white, h * 2.0) : mix(white, warm, (h - 0.5) * 2.0);
}


// The Milky Way: a great circle of unresolved starlight, inclined to the celestial equator.
//
// Most of what makes a real night sky beautiful is that it is not uniform. This is the band that
// breaks it up — a soft glow along the galactic plane, brightest towards the core, with a dust lane
// bitten out of the middle of it.
float milky_way(vec3 star_dir, out float dust) {
	// Galactic pole, roughly 60 degrees off the celestial one.
	vec3 gal_pole = normalize(vec3(0.48, 0.51, -0.71));
	float off_plane = abs(dot(star_dir, gal_pole));
	float band = 1.0 - smoothstep(0.0, 0.34, off_plane);
	// Brighter towards one side of the sky, the way the core is.
	vec3 core = normalize(cross(gal_pole, vec3(0.0, 1.0, 0.0)));
	float toward_core = dot(star_dir, core) * 0.5 + 0.5;
	band *= mix(0.35, 1.0, toward_core * toward_core);
	// Clumping, so the band has structure rather than being an airbrushed stripe.
	vec2 cloud_uv = vec2(atan(star_dir.x, star_dir.z) * 6.0, off_plane * 26.0);
	float clump = cloud_noise(cloud_uv) * 0.6 + cloud_noise(cloud_uv * 2.7 + 9.0) * 0.4;
	// The dark rift down the middle, which is dust in front of the light rather than a gap in it.
	dust = (1.0 - smoothstep(0.0, 0.09, off_plane)) * smoothstep(0.35, 0.62, clump);
	return band * (0.55 + 0.75 * clump);
}


// A sparse field of stars, of several sizes.
//
// Sampled on an angular grid in the *rotating* star frame, so a star keeps its place among the
// other stars and its size on screen, and the whole field turns about the pole through the night.
//
// Three magnitude classes rather than one continuous ramp: a handful of bright stars with visible
// glints, a scattering of mid ones, and a dense wash of faint ones inside the Milky Way. That
// hierarchy is what the eye reads as depth — an even field of same-sized dots reads as noise.
vec3 star_field(vec3 star_dir, float galaxy, float scale, float threshold, float size_gain) {
	vec2 cell = vec2(atan(star_dir.x, star_dir.z), asin(clamp(star_dir.y, -1.0, 1.0))) * scale;
	vec2 id = floor(cell);
	float present = sky_hash(id);
	// The galaxy seeds extra stars where it runs, which is most of why it reads as stars at all.
	float local_threshold = threshold - galaxy * (1.0 - threshold) * 0.75;
	if (present < local_threshold) {
		return vec3(0.0);
	}
	vec2 centre = vec2(sky_hash(id + vec2(3.0, 11.0)), sky_hash(id + vec2(7.0, 23.0)));
	vec2 offset = fract(cell) - centre;
	float d = length(offset);
	// Magnitude, weighted so bright stars are rare.
	float magnitude = sky_hash(id + vec2(31.0, 5.0));
	float bright = magnitude * magnitude * magnitude;
	float radius = (0.05 + 0.2 * bright) * size_gain;
	float core = smoothstep(radius, 0.0, d);
	// Diffraction glint on the brightest few: two thin spikes through the star. This is the single
	// cheapest thing that makes a bright star look bright rather than merely large.
	float glint = 0.0;
	if (bright > 0.42) {
		float spike = max(
			smoothstep(radius * 3.6, 0.0, abs(offset.x)) * smoothstep(radius * 0.7, 0.0, abs(offset.y)),
			smoothstep(radius * 3.6, 0.0, abs(offset.y)) * smoothstep(radius * 0.7, 0.0, abs(offset.x))
		);
		glint = spike * (bright - 0.42) * 1.4;
	}
	// Scintillation, each star on its own beat. Low stars twinkle harder, which is true and is a
	// free depth cue.
	float low = 1.0 - clamp(star_dir.y * 1.6, 0.0, 1.0);
	float beat = sin(meteor_time * mix(1.4, 4.2, magnitude) + magnitude * 31.0);
	float flicker = 1.0 - 0.4 * low * (0.5 - 0.5 * beat);
	float lum = (core + glint * 0.55) * (0.25 + 0.75 * magnitude) * flicker;
	// The contour, as a dark ring around the brighter stars. Subtracted rather than mixed, because
	// this returns an additive colour — the caller adds it to the sky.
	float halo = clamp(smoothstep(radius * 1.5, radius * 1.02, d) - core, 0.0, 1.0);
	vec3 tint = star_tint(sky_hash(id + vec2(17.0, 43.0))) * lum;
	return tint - sky_outline_color.rgb * halo * sky_outline_strength * bright;
}


// One streak on the sky: a point travelling a great circle with a tail behind it.
//
// Cheap because it never needs the meteor's position as such. The plane of its path has a normal;
// how far a pixel sits off that plane is one dot product, and how far along the path it sits is one
// atan. A streak is the strip near the plane, behind the head.
float streak(vec3 eye, vec3 from, vec3 travel, float head, float tail_len, float width) {
	vec3 normal = normalize(cross(from, travel));
	float off_plane = abs(dot(eye, normal));
	if (off_plane > width * 3.0) {
		return 0.0;
	}
	float along = atan(dot(eye, travel), dot(eye, from));
	float behind = head - along;
	if (behind < 0.0 || behind > tail_len) {
		return 0.0;
	}
	// Thinner and fainter the further down the tail, and the head itself is a hard point.
	float taper = 1.0 - behind / tail_len;
	float body = smoothstep(width * taper, 0.0, off_plane) * taper * taper;
	float point = smoothstep(width * 2.2, 0.0, length(eye - normalize(from * cos(head) + travel * sin(head))));
	return clamp(body + point * 1.6, 0.0, 2.0);
}


// Shooting stars. Several slots run at once, each firing at its own irregular interval, so they
// arrive singly and unpredictably rather than on a beat.
float meteors(vec3 eye) {
	float total = 0.0;
	for (int i = 0; i < 4; i++) {
		float fi = float(i);
		float slot = meteor_time / 9.0 + fi * 0.317;
		float n = floor(slot);
		float f = fract(slot);
		vec2 seed = vec2(n, fi * 13.0);
		// Most slots stay empty: a sky with a meteor every two seconds is a firework display.
		if (sky_hash(seed) > 0.34) {
			continue;
		}
		// Somewhere in the upper sky, travelling in some direction across it.
		float az = sky_hash(seed + 1.0) * 6.2831853;
		float alt = 0.25 + sky_hash(seed + 2.0) * 1.1;
		vec3 from = vec3(sin(az) * cos(alt), sin(alt), -cos(az) * cos(alt));
		float bearing = sky_hash(seed + 3.0) * 6.2831853;
		vec3 east = normalize(cross(vec3(0.0, 1.0, 0.0), from));
		vec3 north = cross(from, east);
		vec3 travel = normalize(east * cos(bearing) + north * sin(bearing));
		// Fast: a meteor crosses its arc in a fraction of the slot and is gone.
		float life = clamp(f / 0.07, 0.0, 1.0);
		if (life >= 1.0) {
			continue;
		}
		float head = life * (0.18 + sky_hash(seed + 4.0) * 0.3);
		// Fades in over the first instant and out over the last, so neither end pops.
		float fade = smoothstep(0.0, 0.1, life) * (1.0 - smoothstep(0.55, 1.0, life));
		total += streak(eye, from, travel, head, 0.055, 0.0016) * fade;
	}
	return total;
}


// A comet: slow, bright-headed, with a long tail that always points away from the sun.
//
// Rare on purpose. It is keyed off the day rather than the clock, so a comet belongs to a
// particular few nights and then is gone — which is the whole appeal of one.
float comet(vec3 eye, out float head_amount) {
	head_amount = 0.0;
	float era = floor(sky_day / 6.0);
	if (sky_hash(vec2(era, 91.0)) > 0.4) {
		return 0.0;
	}
	// Creeps across the sky over its several nights.
	float progress = fract(sky_day / 6.0);
	float az = sky_hash(vec2(era, 5.0)) * 6.2831853;
	float alt = 0.35 + sky_hash(vec2(era, 9.0)) * 0.8;
	vec3 from = vec3(sin(az) * cos(alt), sin(alt), -cos(az) * cos(alt));
	// The tail streams directly away from the sun, which is the one thing everybody knows about
	// comets and the one thing a fake one always gets wrong.
	vec3 anti_sun = -sun_direction;
	vec3 travel = normalize(anti_sun - from * dot(from, anti_sun));
	float head = 0.06 + progress * 0.5;
	// Long and broad: a comet's tail is millions of kilometres of dust, not a scratch. It also
	// widens away from the head rather than tapering to nothing, so the profile is a fan.
	// Narrower and shorter than the first attempt, which drew a hard-edged wedge bright enough to
	// read as a searchlight rather than as a comet.
	float streak_amount = streak(eye, from, travel, head, 0.34, 0.011);
	vec3 nucleus = normalize(from * cos(head) + travel * sin(head));
	float to_nucleus = length(eye - nucleus);
	// A distinct nucleus inside a coma: the hard point is the body, the soft halo around it is the
	// gas boiling off it, and having both is what stops the head reading as the end of a line.
	head_amount = smoothstep(0.005, 0.0, to_nucleus) + smoothstep(0.030, 0.004, to_nucleus) * 0.45;
	// Brightest in the middle of its pass.
	return streak_amount * (0.35 + 0.65 * sin(progress * 3.14159));
}


// The moon: a disc with a terminator across it.
//
// The lit part of a moon is bounded by an ellipse whose width is set by the phase, so the shape
// runs continuously from a thin crescent through a half to a full disc without any special cases.
// Returned as (lit, disc) so the caller can draw the dark limb as well — earthshine on the unlit
// side is what stops a crescent looking like a detached sliver.
vec3 moon_disc(vec3 eye) {
	float d = dot(eye, moon_direction);
	if (d < cos(moon_size * 1.1)) {
		return vec3(0.0);
	}
	// Position within the disc, in units of its radius: along the sunward axis and square to it.
	vec3 offset = eye - moon_direction * d;
	vec3 across = normalize(cross(moon_direction, moon_sun_axis));
	float u = dot(offset, moon_sun_axis) / moon_size;
	float v = dot(offset, across) / moon_size;
	float r = clamp(length(vec2(u, v)), 0.0, 1.0);
	float disc = smoothstep(1.0, 0.86, r);
	// A ring just outside the limb, for the contour. Returned in z.
	// Thin, like the world's contour: a rim a fifth as wide as the first attempt's.
	float rim = smoothstep(1.06, 0.99, r) - disc;
	// The terminator, as the standard ellipse: at full it clears the whole disc, at new none of it.
	float edge = (1.0 - 2.0 * moon_phase) * sqrt(max(0.0, 1.0 - v * v));
	float lit = smoothstep(edge - 0.08, edge + 0.08, u) * disc;
	// Limb darkening, so the disc is a sphere rather than a sticker.
	lit *= mix(1.0, 0.78, r * r);
	return vec3(lit, disc, clamp(rim, 0.0, 1.0));
}


// Cloud coverage at one grid cell, 0 or 1.
//
// Pulled out of `sky()` so the outline can ask the same question about the *neighbouring* cells.
// A contour is "not cloud here, but cloud next door" — the first attempt instead darkened the cells
// whose noise value fell in a band, which scatters dark flecks around the puff rather than drawing
// a line along its edge.
float cloud_cover(vec2 grid, float amount) {
	float puff =
		cloud_noise(grid * 0.11) * 0.52
		+ cloud_noise(grid * 0.27 + 13.0) * 0.31
		+ cloud_noise(grid * 0.63 + 41.0) * 0.17;
	puff = clamp((puff - 0.34) / 0.32, 0.0, 1.0);
	return step(1.0 - amount * 0.46, puff);
}


void sky() {
	float elevation = EYEDIR.y;

	if (elevation < 0.0) {
		COLOR = ground_color.rgb;
	} else {
		float t = pow(clamp(elevation, 0.0, 1.0), 1.0 / horizon_falloff);
		float safe_bands = max(2.0, bands);
		float stepped = soft_band(t, safe_bands, band_softness);
		vec3 col = mix(horizon_color.rgb, zenith_color.rgb, stepped);
		// The overhead ramp, banded on raw elevation rather than on the horizon-weighted curve —
		// that curve is compressed near the horizon precisely so the low sky gets the detail, which
		// leaves nothing for the top. Half as many stops, so the rings widen as they climb.
		float apex_t = soft_band(
			smoothstep(0.3, 1.0, elevation), max(2.0, safe_bands * 0.5), band_softness
		);
		col = mix(col, apex_color.rgb, apex_t);

		// The cloud deck.
		//
		// Two layers, not one. A single belt of puffs at one altitude reads as wallpaper however
		// good the puffs are, because nothing in it is nearer than anything else. The low deck is
		// the cumulus — dense, lit on top, shaded underneath — and above it a thin cirrus sheet
		// drifting faster on a stretched grid. The parallax between the two is what gives the sky
		// depth, and it costs one extra noise sample.
		if (cloud_amount > 0.001) {
			// One number, and it only ever moves the deck *around* the dome.
			//
			// The two components of the wind used to be fed to the two axes of the dome grid: the
			// x travel shifted the azimuth and the z travel shifted the elevation. The elevation
			// axis is up and down the sky, so that half read as the whole deck sliding towards or
			// away from the viewer — and because the hub and the arena pin their wind due south,
			// `wind_drift.x` stayed near zero and *all* of the motion went into it. The clouds
			// crawled up the sky instead of across it.
			//
			// Clouds now scroll on the azimuth alone, at a rate given by how far the wind has
			// carried them however it is blowing. `CLOUD_SPEED` converts ground travel into dome
			// travel, and it is a large number because the grid is in radians-times-26 and the
			// deck is kilometres up.
			float scroll = length(wind_drift.xz) * cloud_drift * CLOUD_SPEED;
			// Sampled on a fixed angular grid, so puffs keep the same apparent size wherever the
			// camera looks — and quantised, so they stay blocks with hard edges.
			vec2 dome = vec2(atan(EYEDIR.x, EYEDIR.z) * 26.0 + scroll, elevation * 52.0);
			vec2 grid = floor(dome) + 0.5;
			// Three octaves at halving amplitude: a big shape with smaller shapes bitten out of its
			// edge, rather than one blobby outline.
			float puff =
				cloud_noise(grid * 0.11) * 0.52
				+ cloud_noise(grid * 0.27 + 13.0) * 0.31
				+ cloud_noise(grid * 0.63 + 41.0) * 0.17;
			// Summing three octaves of uniform noise gives something close to a normal
			// distribution: mean 0.5, and almost nothing out past 0.8. The thresholds below were
			// tuned against a *single* octave's flat 0..1 spread, so against the sum they fired
			// almost never. Stretching the useful middle band back over the full range restores the
			// intended coverage without touching the authored `cloud_amount`.
			puff = clamp((puff - 0.34) / 0.32, 0.0, 1.0);
			// Reaches from just off the horizon to `cloud_ceiling`, thinning at the top the way a
			// deck does rather than stopping at a line.
			float belt =
				(1.0 - smoothstep(cloud_ceiling * 0.45, cloud_ceiling, elevation))
				* smoothstep(0.0, 0.05, elevation);
			float core = step(1.0 - cloud_amount * 0.34, puff) * belt;
			float fringe = step(1.0 - cloud_amount * 0.46, puff) * belt;
			// Lit crown, shaded base: the same puff value read at a slightly higher elevation says
			// whether there is more cloud above this pixel, which is exactly where the shadow is.
			float above = clamp((cloud_noise((grid + vec2(0.0, 2.0)) * 0.11) - 0.34) / 0.32, 0.0, 1.0);
			float lit = step(above, puff * 0.92);

			// The high sheet. Stretched hard along the dome and squashed across it, because cirrus
			// is drawn out into streaks by the wind at that altitude; drifting at nearly twice the
			// speed, because it is in a faster stream. Sits above the cumulus and never below it.
			vec2 high_dome = vec2(
				atan(EYEDIR.x, EYEDIR.z) * 9.0 + scroll * 1.9,
				elevation * 74.0
			);
			vec2 high_grid = floor(high_dome) + 0.5;
			float veil = cloud_noise(high_grid * 0.14) * 0.66 + cloud_noise(high_grid * 0.41) * 0.34;
			veil = clamp((veil - 0.42) / 0.3, 0.0, 1.0);
			float high_belt = smoothstep(cloud_ceiling * 0.5, 1.0, elevation);
			float wisp = veil * high_belt * cloud_amount * 0.5;
			col = mix(col, mix(cloud_shadow_color.rgb, cloud_color.rgb, 0.8), wisp);

			col = mix(col, cloud_shadow_color.rgb, fringe * 0.55);
			col = mix(col, mix(cloud_shadow_color.rgb, cloud_color.rgb, lit), core);
		}

		// The night sky, drawn first so everything else in it occludes what is behind.
		if (star_amount > 0.001) {
			// Into the rotating star frame. Everything from here to the moon is fixed to *this*
			// frame, so the whole sky turns about the pole through the night rather than sitting
			// pinned to the horizon.
			vec3 pole = normalize(celestial_pole);
			vec3 star_dir = rotate_about(EYEDIR, pole, star_rotation);

			// Thicker air near the horizon: everything up here fades out towards it.
			float clarity = smoothstep(0.0, 0.26, EYEDIR.y) * star_amount;

			float dust = 0.0;
			float galaxy = milky_way(star_dir, dust);
			// The band itself, before any individual star in it.
			// Not one colour. The galactic core runs warm — old yellow stars behind a lot of dust —
			// and the arms away from it run cold and blue. Grading the band along its own length is
			// most of the difference between "a grey smear" and "the Milky Way".
			vec3 core_hue = vec3(0.46, 0.38, 0.34);
			vec3 arm_hue = vec3(0.26, 0.32, 0.50);
			float along = dot(star_dir, normalize(cross(normalize(vec3(0.48, 0.51, -0.71)), vec3(0.0, 1.0, 0.0))));
			vec3 galaxy_tint = mix(arm_hue, core_hue, clamp(along * 0.5 + 0.5, 0.0, 1.0));
			// Dust reddens what little gets through it, the way it really does.
			galaxy_tint = mix(galaxy_tint, vec3(0.34, 0.22, 0.20), dust * 0.8);
			// Faint. At 0.42 this drew a broad pale band right across the sky that reads as an
			// aurora rather than as unresolved starlight — the brightest single thing up there,
			// and brighter than the moon it sat next to. The real thing is barely above the sky
			// glow; what should carry it is the stars it seeds, not the wash itself.
			col += galaxy_tint * galaxy * (1.0 - dust * 0.82) * clarity * 0.11;

			// Three passes at different scales: a coarse grid of bright stars with glints, a finer
			// one of ordinary stars, and a very fine wash that only really appears inside the
			// Milky Way. Together they give the field a range of sizes instead of one.
			vec3 stars = vec3(0.0);
			stars += star_field(star_dir, galaxy, 30.0, 0.9905, 1.0) * 1.25;
			stars += star_field(star_dir, galaxy, 62.0, 0.9840, 0.85) * 0.8;
			stars += star_field(star_dir, galaxy, 128.0, 0.9880, 0.7) * 0.45 * (0.25 + galaxy);
			// Dust hides what is behind it.
			col = max(col + stars * clarity * (1.0 - dust * 0.8), vec3(0.0));

			// A comet, on the few nights there is one.
			float comet_head = 0.0;
			float tail = comet(EYEDIR, comet_head);
			if (tail > 0.001 || comet_head > 0.001) {
				vec3 tail_color = vec3(0.62, 0.78, 0.85);
				col += tail_color * tail * clarity * 0.22;
				col += vec3(0.88, 0.94, 1.0) * comet_head * clarity;
			}

			// Shooting stars.
			float shower = meteors(EYEDIR);
			col += vec3(1.0, 0.96, 0.86) * shower * clarity;
		}

		if (moon_bright > 0.001) {
			vec3 moon = moon_disc(EYEDIR);
			// Contour first, so the disc covers all but its own rim.
			col = mix(col, sky_outline_color.rgb, moon.z * moon_bright * sky_outline_strength);
			// Earthshine: the unlit limb is faintly visible, which is why you can see the whole
			// disc of a young moon and not just the crescent.
			// Earthshine on the unlit limb. Strong enough that a new moon is still a disc in the
			// sky rather than nothing at all.
			col = mix(col, moon_dark_color.rgb, moon.y * moon_bright * 0.8);
			col = mix(col, moon_color.rgb, moon.x * moon_bright);
			// A soft halo, brighter the fuller the moon.
			float halo = pow(clamp(dot(EYEDIR, moon_direction), 0.0, 1.0), 190.0);
			col += moon_color.rgb * halo * moon_bright * (0.25 + 0.75 * moon_phase) * 0.5;
		}

		// The sun. Taken from `sun_direction` rather than from `LIGHT0_DIRECTION`, because the sun
		// light is hidden outright once it is below the horizon and a hidden light reports nothing —
		// which used to leave the disc stuck wherever it was when the light went out.
		if (sun_size > 0.0001) {
			vec3 to_sun = sun_direction;
			float d = clamp(dot(EYEDIR, to_sun), 0.0, 1.0);
			float disc = step(1.0 - sun_size * sun_size, d);
			// A slightly larger disc gives the contour; the sun itself then covers the middle.
			float sun_rim = step(1.0 - sun_size * sun_size * 1.14, d) - disc;
			float halo = floor(pow(d, 42.0) * 4.0) / 4.0;
			col = mix(col, sky_outline_color.rgb, clamp(sun_rim, 0.0, 1.0) * sky_outline_strength);
			col = mix(col, sun_color.rgb, clamp(halo * sun_glow + disc, 0.0, 1.0));
		}

		COLOR = col;
	}
}
