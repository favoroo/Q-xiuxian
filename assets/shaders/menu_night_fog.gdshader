shader_type canvas_item;
render_mode unshaded;

// ---------------------------------------------------------------------------
// 首页噩梦氛围雾（2026-10-30 升级）
//
// 兼顾「卡片保持原汁原味高质感色块」与「噩梦模式浓烈氛围」的双重诉求：
// 1. 四周暗角瘴气（Vignette Miasma）：从边缘与四角向中心侵袭的深黑/紫煞，
//    与四周血朱画框浑然一体，将整个屏幕"封"在夜幕与魔煞之中；
// 2. 多层血煞流雾（Crimson Flow）：横向拉伸的翻滚流云，雾脊呈现鲜活血朱色；
// 3. 漂游血煞星屑（Embers）：在风雾中若隐若现飞舞的微弱暗红火星/煞气星屑；
// 4. 极慢呼吸律动（0.45Hz）：整屏迷雾与边缘瘴气带着呼吸般起伏，动静结合；
// 5. 零贴图纯计算、动态吃内置 TIME、night=0 时 visible=false 零开销。
// ---------------------------------------------------------------------------

uniform float night : hint_range(0.0, 1.0) = 0.0;          // 情绪权重（宿主补间）
uniform float aspect_ratio = 1.7777778;                    // 屏幕宽高比
uniform float alpha_scale : hint_range(0.0, 1.0) = 0.62;   // 整层浓度封顶
uniform vec4 fog_col : source_color = vec4(0.12, 0.04, 0.16, 1.0);     // 雾体：深邃紫黑
uniform vec4 fog_tint : source_color = vec4(0.85, 0.16, 0.14, 1.0);    // 雾脊与血煞：鲜活血朱
uniform vec4 miasma_col : source_color = vec4(0.02, 0.01, 0.03, 1.0);  // 边缘深渊墨夜

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float amp = 0.55;
	for (int i = 0; i < 3; i++) {
		v += amp * vnoise(p);
		p = p * 2.08 + vec2(17.3, 7.1);
		amp *= 0.5;
	}
	return v;
}

void fragment() {
	vec2 uv = UV;
	vec2 p = vec2(uv.x * aspect_ratio, uv.y);
	float t = TIME;

	// 1. 横向流云异速漂移
	vec2 drift1 = vec2(t * 0.028, t * 0.012);
	vec2 drift2 = vec2(-t * 0.019, t * 0.018);
	float n1 = fbm(vec2(p.x * 0.85, p.y * 2.60) + drift1);
	float n2 = fbm(vec2(p.x * 1.60, p.y * 4.20) + drift2 + n1 * 0.95);
	float n = n1 * 0.65 + n2 * 0.35;

	// 2. 絮状游丝
	float wisp = vnoise(vec2(p.x * 3.2, p.y * 10.0) + vec2(-t * 0.035, t * 0.022));
	float bank = smoothstep(0.42, 0.64, n);
	bank = clamp(bank + (wisp - 0.5) * 0.20 * bank * (1.0 - bank) * 4.0, 0.0, 1.0);

	// 3. 四周深渊暗角瘴气（Vignette Miasma）
	vec2 d = (uv - 0.5) * vec2(aspect_ratio, 1.0);
	float dist_sq = dot(d, d);
	vec2 de = min(uv, vec2(1.0) - uv);
	float rect_edge = 1.0 - smoothstep(0.01, 0.22, min(de.x * aspect_ratio, de.y));
	float radial_edge = smoothstep(0.16, 0.72, dist_sq);
	float edge_raw = max(rect_edge * 0.80, radial_edge);
	float edge_miasma = clamp(edge_raw + (n2 - 0.45) * 0.30 * edge_raw, 0.0, 1.0);

	// 4. 极慢呼吸（0.45Hz）
	float breathe = 0.90 + 0.10 * sin(t * 0.45);

	// 5. 飘拂的血煞浓度
	float crimson = clamp(pow(bank, 1.6) * 1.5 + (1.0 - abs(bank - 0.5) * 2.0) * 0.4, 0.0, 1.0);

	// 6. 稀疏漂游的血煞星屑（Spore/Ember）
	vec2 ember_p = vec2(p.x * 18.0 + t * 0.12, p.y * 22.0 - t * 0.08);
	float ember_noise = hash21(floor(ember_p));
	vec2 ember_f = fract(ember_p) - 0.5;
	float ember = 0.0;
	if (ember_noise > 0.978) {
		float ed = length(ember_f);
		ember = smoothstep(0.35, 0.02, ed) * (0.5 + 0.5 * sin(t * 3.0 + ember_noise * 20.0));
	}

	// 综合透明度：
	float alpha_val = (0.02 + 0.36 * bank + edge_miasma * 0.44 + ember * 0.45) * breathe * night;

	// 色彩混合
	vec3 base_col = mix(fog_col.rgb, miasma_col.rgb, edge_miasma * 0.70);
	vec3 fog_color = mix(base_col, fog_tint.rgb, crimson * 0.65);
	fog_color = mix(fog_color, vec3(1.0, 0.35, 0.20), ember * 0.75);

	COLOR = vec4(fog_color, clamp(alpha_val * alpha_scale, 0.0, 1.0));
}
