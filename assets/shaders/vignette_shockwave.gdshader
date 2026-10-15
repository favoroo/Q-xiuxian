shader_type canvas_item;

// 暗角 + 受击屏幕冲击波（可选高档位，默认关）。
// 仅当玩家开启 screen_shockwave 时由 Main._sync_shockwave_channel 挂到 vignette_rect：
// 声明 hint_screen_texture 会触发每帧全屏 BackBufferCopy，故拆到独立 shader，
// 默认（纯暗角）走 vignette_soft.gdshader（零 screen_texture 引用 → 零拷贝）。

uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;
uniform vec4 tint_color : source_color = vec4(0.08, 0.1, 0.14, 0.08);
uniform float vignette_intensity : hint_range(0.0, 1.0) = 0.42;
uniform float vignette_opacity : hint_range(0.0, 1.0) = 0.62;

// 屏幕冲击波参数（T-6.2 受击屏幕冲击波，可选高档位，默认关）
uniform vec2 shockwave_center = vec2(0.5, 0.5);
uniform float shockwave_progress : hint_range(0.0, 1.0) = 0.0;
uniform float shockwave_strength = 0.0;
uniform float shockwave_thickness = 0.08;

void fragment() {
	vec2 uv = UV;
	vec2 coord = (uv - 0.5) * 2.0;
	float dist = length(coord);
	float vignette = smoothstep(0.55, 1.42, dist * (1.0 + vignette_intensity));

	vec4 col = mix(vec4(0.0, 0.0, 0.0, 0.0), vec4(0.04, 0.05, 0.08, vignette_opacity), vignette);
	col = mix(col, tint_color, tint_color.a * vignette);

	// 当冲击波生效且有强度时，在环带内从 screen_texture 采样折射画面
	if (shockwave_strength > 0.001 && shockwave_progress > 0.0) {
		// 960x540 设计视口纵横比补偿 (16:9 = 1.7777)，保持径向环为正圆
		vec2 diff = (SCREEN_UV - shockwave_center) * vec2(1.7777, 1.0);
		float d = length(diff);
		float ring_radius = shockwave_progress * 1.15;
		float ring_dist = abs(d - ring_radius);
		if (ring_dist < shockwave_thickness) {
			float ring_factor = 1.0 - smoothstep(0.0, shockwave_thickness, ring_dist);
			// 随着向外扩散，扭曲强度随距离衰减
			float decay = (1.0 - shockwave_progress) * shockwave_strength;
			vec2 dir = (d > 0.0001) ? normalize(diff) : vec2(0.0, 0.0);
			// 径向向外位移采样 UV，形成环状凸透镜折射
			vec2 disp = dir * (ring_factor * decay * 0.038);
			vec2 sample_uv = clamp(SCREEN_UV - disp, vec2(0.001), vec2(0.999));
			vec3 scene_col = texture(screen_texture, sample_uv).rgb;
			// 冲击波波前细微灵光泛白
			vec3 ring_highlight = vec3(0.92, 0.96, 1.0) * (ring_factor * decay * 0.22);
			float alpha = clamp(ring_factor * decay * 2.0, 0.0, 1.0);
			col = mix(col, vec4(scene_col + ring_highlight, 1.0), alpha);
		}
	}

	COLOR = col;
}
