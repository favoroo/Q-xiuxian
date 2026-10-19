shader_type canvas_item;

// 青玉大石板地面（程序化纹理，替换 courtyard_tile.png）
// 设计目标：干净、通透、无裂痕 —— 手工打磨的大块石板 + 极淡磨损，
// 与「墨阑玉简」UI 的冷冽玉简气质统一。全内置函数，不采样外部纹理，
// headless/dummy 渲染器下自动退化为基色，不影响测试。

uniform vec4 base_color : source_color = vec4(0.208, 0.243, 0.263, 1.0);   // 青玉暖灰基调
uniform vec4 gap_color : source_color = vec4(0.10, 0.13, 0.15, 1.0);        // 石缝暗色
uniform float tile_size : hint_range(40.0, 400.0) = 160.0;                  // 石板边长（世界像素）
uniform float gap_width : hint_range(0.5, 6.0) = 2.0;                       // 石缝线宽（世界像素）
uniform float tone_variation : hint_range(0.0, 0.1) = 0.03;                 // 石板间明度微差
uniform float wear_intensity : hint_range(0.0, 0.1) = 0.02;                 // 大尺度磨损起伏幅度

// UV 范围对应的世界尺寸（ColorRect 实际铺满 ±2400，即 4800 见方）
uniform vec2 world_size = vec2(4800.0, 4800.0);

float hash21(vec2 p) {
	p = fract(p * vec2(234.34, 435.345));
	p += dot(p, p + 34.23);
	return fract(p.x * p.y);
}

// 低频 value noise：大尺度明暗起伏（手工打磨石面感）
float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

void fragment() {
	vec2 world_pos = UV * world_size;

	// 石板网格
	vec2 tile_coord = world_pos / tile_size;
	vec2 tile_id = floor(tile_coord);
	vec2 tile_uv = fract(tile_coord);

	// 石缝：距格边 gap_width 内渐暗，smoothstep 消除硬边
	float px = gap_width / tile_size;  // 线宽换算到 tile_uv 域
	float ex = min(tile_uv.x, 1.0 - tile_uv.x);
	float ey = min(tile_uv.y, 1.0 - tile_uv.y);
	float edge = min(ex, ey);
	float gap = 1.0 - smoothstep(0.0, px, edge);

	// 每块石板的明度微差（确定性 hash，不随时间变）
	float tone = (hash21(tile_id) - 0.5) * 2.0 * tone_variation;

	// 大尺度磨损起伏（低频 noise，幅度很小）
	float wear = (vnoise(world_pos * 0.008) - 0.5) * 2.0 * wear_intensity;

	vec4 col = base_color * (1.0 + tone + wear);
	col = mix(col, gap_color, gap * 0.85);

	COLOR = col;
}
