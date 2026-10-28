shader_type canvas_item;

// 噩梦难度专属视野迷雾（缩小玩家可视范围，外圈黑雾遮蔽一切敌我实体）：
// 零 hint_screen_texture 引用 → 零每帧 BackBufferCopy。
// 以玩家屏幕归一化位置为中心，内圈清晰、过渡带煞雾翻涌、外圈浓黑紫完全遮蔽。

uniform vec2 player_screen_uv = vec2(0.5, 0.5);
uniform float aspect_ratio = 1.7777778; // 屏幕宽高比（width / height）
uniform float clear_ratio = 0.305556;   // 165 / 540（清晰视野半径，约占屏幕半高的 60%）
uniform float feather_ratio = 0.444444; // 240 / 540（羽化外沿，超出即完全进入浓黑迷雾）
uniform float max_alpha : hint_range(0.0, 1.0) = 1.0;
uniform vec4 fog_color : source_color = vec4(0.015, 0.010, 0.025, 1.0);
uniform vec4 fog_edge_tint : source_color = vec4(0.48, 0.12, 0.20, 1.0);
uniform float time_val = 0.0;

void fragment() {
	vec2 diff = UV - player_screen_uv;
	diff.x *= aspect_ratio;
	float d = length(diff);
	float angle = atan(diff.y, diff.x);

	// 极角双频微流动波纹 + 呼吸律动：使迷雾边缘有活体煞气翻涌感
	float wave = sin(angle * 4.0 + time_val * 1.8) * 0.024 
	           + sin(angle * 7.0 - time_val * 2.3) * 0.015 
	           + sin(time_val * 2.5) * 0.010;
	float eff_d = d + wave;

	// 内圈完全透明（清晰视野），平滑过渡到外圈浓黑
	float t = smoothstep(clear_ratio, feather_ratio, eff_d);

	// 边缘交界处泛出朱砂暗红煞气，外部过渡至深渊极暗紫黑
	float edge = smoothstep(0.0, 0.35, t) * (1.0 - smoothstep(0.45, 1.0, t));
	vec3 col = mix(fog_color.rgb, fog_edge_tint.rgb, edge * 0.55);

	COLOR = vec4(col, t * max_alpha);
}
