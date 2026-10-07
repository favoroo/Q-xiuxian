shader_type canvas_item;
render_mode blend_add;

uniform vec4 ray_color : source_color = vec4(1.0, 0.94, 0.72, 0.16);
uniform float angle : hint_range(-1.5, 1.5) = -0.45;
uniform float speed : hint_range(0.0, 2.0) = 0.25;
uniform float density : hint_range(1.0, 20.0) = 7.5;
uniform float falloff : hint_range(0.1, 3.0) = 1.4;

void fragment() {
    vec2 uv = UV;
    // Rotate UV for angled sunbeams from top-left
    float s = sin(angle);
    float c = cos(angle);
    vec2 rot_uv = vec2(uv.x * c - uv.y * s, uv.x * s + uv.y * c);
    
    float t = TIME * speed;
    float wave1 = sin(rot_uv.x * density + t) * 0.5 + 0.5;
    float wave2 = sin(rot_uv.x * (density * 1.73) - t * 0.7 + 1.2) * 0.5 + 0.5;
    float wave3 = sin(rot_uv.x * (density * 0.53) + t * 0.4 + 2.5) * 0.5 + 0.5;
    
    float rays = pow(wave1 * wave2 * wave3, 1.35) * 2.2;
    float vertical_fade = pow(clamp(1.0 - uv.y * 0.78, 0.0, 1.0), falloff);
    float edge_fade = smoothstep(0.0, 0.15, uv.x) * smoothstep(1.0, 0.85, uv.x);
    
    float alpha = rays * vertical_fade * edge_fade * ray_color.a;
    COLOR = vec4(ray_color.rgb, alpha);
}
