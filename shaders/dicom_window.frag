#include <flutter/runtime_effect.glsl>

uniform vec2 u_resolution;
uniform float u_window_center;
uniform float u_window_width;
uniform float u_rescale_intercept;
uniform float u_rescale_slope;

uniform sampler2D u_texture;

out vec4 fragColor;

void main() {
    vec2 uv = FlutterFragCoord().xy / u_resolution;
    
    vec4 texColor = texture(u_texture, uv);
    
    float raw_value = texColor.r * 65535.0; 
    float hu = (raw_value * u_rescale_slope) + u_rescale_intercept;
    
    float min_val = u_window_center - (u_window_width / 2.0);
    float max_val = u_window_center + (u_window_width / 2.0);
    
    float mapped_color = (hu - min_val) / (max_val - min_val);
    
    mapped_color = clamp(mapped_color, 0.0, 1.0);
    
    fragColor = vec4(mapped_color, mapped_color, mapped_color, 1.0);
}