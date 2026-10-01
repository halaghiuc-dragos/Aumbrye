shader_type spatial;

render_mode specular_schlick_ggx;

// Walls and floors never dissolve, so the dissolve block is compiled out (see the include).
#define NO_DISSOLVE
#include "res://assets/shared/pixel_diorama_surface.gdshaderinc"
