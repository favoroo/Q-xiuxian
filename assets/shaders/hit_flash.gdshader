shader_type canvas_item;

uniform vec4 flash_color : source_color = vec4(1.0, 1.0, 0.95, 1.0);
uniform float flash_modifier : hint_range(0.0, 1.0) = 0.0;

void fragment() {
    // 兼容 Sprite2D 贴图与 CanvasItem 自定义 _draw() 顶点色绘制
    vec4 texture_color = texture(TEXTURE, UV) * COLOR;
    vec4 final_color = vec4(mix(texture_color.rgb, flash_color.rgb, flash_modifier), texture_color.a);
    COLOR = final_color;
}
