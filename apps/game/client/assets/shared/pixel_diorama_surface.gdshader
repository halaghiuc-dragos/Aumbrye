shader_type spatial;

// `specular_disabled` is gone.
//
// It was correct while every surface here was matt banded stone, and it is what made reflections
// impossible: a material that writes no specular has nothing for a reflection probe, the sky, or
// screen-space reflections to write *into*, so wet flagstone could only ever be darker flagstone.
// The specular term is now computed in `light()` and quantised like everything else, so surfaces
// reflect without the render losing its pixel-art banding.
render_mode specular_schlick_ggx;

#include "res://assets/shared/pixel_diorama_surface.gdshaderinc"
