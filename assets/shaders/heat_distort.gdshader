shader_type canvas_item;

// 热浪扭曲（T-6.1，可选高档位，默认关）：全屏 ColorRect 的屏幕空间折射。
// 通道结构：CanvasLayer 自带 BackBufferCopy（COPY_MODE_VIEWPORT）供 SCREEN_TEXTURE，
// 本 shader 只在热区圆内抖 UV 折射 + 极淡热泛亮，热区外直通。
// HeatDistortionFx._process 每帧下发 heats：xyz = 屏幕归一中心 xy + 归一半径 r，w = 强度
// （w<=0 的槽位在循环里直接跳过）。缩放走 canvas_items + expand，SCREEN_UV 即设计视口
// 归一坐标，与 960×540 渲染规格同基。

// 热区槽位（最多 4 团热：多把火葫芦 + 火雨落点并存）
uniform vec4 heats[4];
// 波动参数：x = time(s)，y = 错相步进（多热区不同步呼吸）
uniform vec2 wave = vec2(0.0, 0.0);
// 全局强度总闸（设置开启即 1.0，留调参余量）
uniform float intensity = 1.0;

// Godot 4 屏幕纹理：BackBufferCopy(COPY_MODE_VIEWPORT) 供屏
uniform sampler2D screen_tex : hint_screen_texture, filter_linear;

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 distort = vec2(0.0);
	float heat_sum = 0.0;

	for (int i = 0; i < 4; i++) {
		vec4 h = heats[i];
		if (h.w <= 0.0) { continue; }
		// 纵横比补偿：SCREEN_UV 的 x/y 跨度不同，按 960:540 还原圆形衰减场
		vec2 d = (uv - h.xy) * vec2(1.7777, 1.0);
		float fall = clamp(1.0 - length(d) / max(h.z, 0.0001), 0.0, 1.0);
		fall = fall * fall * (3.0 - 2.0 * fall); // smoothstep 缓入缓出，热区边缘无接缝
		// 扭曲场：径向涌动 + 时间正弦叠加的竖向火舌抖动（无需噪声贴图）
		float t = wave.x * (1.0 + wave.y + float(i) * 0.13);
		vec2 dir = (length(d) > 0.0001) ? normalize(d) : vec2(0.0, -1.0);
		vec2 wave_off = vec2(
			sin(t * 9.0 + uv.y * 34.0) * 0.6 + sin(t * 17.0 - uv.y * 61.0) * 0.4,
			sin(t * 12.0 + uv.x * 26.0) * 0.8
		) * 0.010;
		distort += (dir * fall * 0.004 + wave_off * fall) * h.w;
		heat_sum += fall * h.w;
	}

	vec2 refr_uv = clamp(uv + distort * intensity, vec2(0.001), vec2(0.999));
	vec3 col = texture(screen_tex, refr_uv).rgb;

	// 热泛亮：热心极淡暖色（分量远低于 1.0，不触发 glow，只提「空气被烤热」的体感）
	vec3 haze = vec3(1.0, 0.62, 0.28) * clamp(heat_sum, 0.0, 1.0) * 0.05 * intensity;
	COLOR = vec4(col + haze, 1.0);
}
