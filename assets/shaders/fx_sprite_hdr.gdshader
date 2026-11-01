shader_type canvas_item;
render_mode blend_mix;

// pixelfx 精灵表 HDR 起辉增强 Shader
// 将纹理采样与 COLOR 顶点色相乘后，对超过 luma_threshold 的亮核区域进行超白提亮，
// 使得高亮粒子/刃芒/雷光突破 1.0 阈值触发环境 Glow，暗部与背景保持清晰不发蒙。

uniform float luma_threshold : hint_range(0.5, 0.95) = 0.68;
uniform float hdr_boost : hint_range(1.0, 3.0) = 1.95;

void fragment() {
	vec4 col = texture(TEXTURE, UV) * COLOR;
	float luma = dot(col.rgb, vec3(0.299, 0.587, 0.114));
	float boost_factor = smoothstep(luma_threshold, 1.0, luma);
	col.rgb *= mix(1.0, hdr_boost, boost_factor);
	COLOR = col;
}
