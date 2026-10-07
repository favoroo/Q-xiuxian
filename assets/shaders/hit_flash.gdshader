shader_type canvas_item;

uniform vec4 flash_color : source_color = vec4(1.0, 1.0, 0.95, 1.0);
uniform float flash_modifier : hint_range(0.0, 1.0) = 0.0;

void fragment() {
    vec4 texture_color = texture(TEXTURE, UV);
    vec4 final_color = mix(texture_color, vec4(flash_color.rgb, texture_color.a), flash_modifier);
    COLOR = final_color;
}
