shader_type canvas_item;

## 死亡消散消融材质（空洞冷冽灵体溃散）
## 噪声阈值消融 + HDR 超白边缘描边（在 WorldEnvironment glow 下起辉）

uniform sampler2D noise_texture : repeat_enable, filter_linear;
uniform float dissolve_amount : hint_range(0.0, 1.0) = 0.0;
uniform float edge_width : hint_range(0.0, 0.25) = 0.06;
uniform vec4 edge_color : source_color = vec4(2.4, 1.9, 0.6, 1.0);

void fragment() {
    vec4 tex = texture(TEXTURE, UV) * COLOR;
    if (tex.a <= 0.001) {
        discard;
    }

    if (dissolve_amount > 0.0) {
        // 兼容 Sprite2D 的真实 UV 与 CanvasItem 纯顶点绘制
        vec2 sample_uv = (UV == vec2(0.0)) ? (SCREEN_UV * 4.0) : UV;
        float noise = texture(noise_texture, sample_uv).r;
        if (noise < dissolve_amount) {
            discard;
        }
        if (noise < dissolve_amount + edge_width) {
            tex.rgb = edge_color.rgb;
        }
    }

    COLOR = tex;
}
