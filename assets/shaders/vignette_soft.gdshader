shader_type canvas_item;

// 纯暗角（默认）：不声明 hint_screen_texture → 不触发每帧全屏 BackBufferCopy。
// 受击屏幕冲击波（需采样屏幕画面）拆到 vignette_shockwave.gdshader，由开关按需挂载。

uniform vec4 tint_color : source_color = vec4(0.08, 0.1, 0.14, 0.08);
uniform float vignette_intensity : hint_range(0.0, 1.0) = 0.42;
uniform float vignette_opacity : hint_range(0.0, 1.0) = 0.62;

void fragment() {
	vec2 uv = UV;
	vec2 coord = (uv - 0.5) * 2.0;
	float dist = length(coord);
	float vignette = smoothstep(0.55, 1.42, dist * (1.0 + vignette_intensity));

	vec4 col = mix(vec4(0.0, 0.0, 0.0, 0.0), vec4(0.04, 0.05, 0.08, vignette_opacity), vignette);
	col = mix(col, tint_color, tint_color.a * vignette);

	COLOR = col;
}
