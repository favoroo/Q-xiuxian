shader_type canvas_item;

// 结界光幕流光（空洞冷冽国风 · 九天锁灵结界）
// 摒弃现代斑马斜条，采用流云灵潮、冷月清辉与晶壁玉光
// UV.x = 顺时针整圈周长参数 [0,1]；UV.y = 横向 [0=外缘虚空, 1=内缘战台]
uniform vec4 base_color : source_color = vec4(0.12, 0.36, 0.58, 0.65);  // 幽冷玉蓝底色
uniform vec4 flow_color : source_color = vec4(0.55, 1.35, 2.00, 0.95);  // 灵华月白亮潮（起辉但典雅清澈）
uniform float flow_speed : hint_range(0.0, 0.5) = 0.035;                // 灵潮慢速周转
uniform float pulse_speed : hint_range(0.0, 4.0) = 0.9;                 // 整体天地呼吸

void fragment() {
	// 横向晶壁包络：中心聚光、两端微羽化
	float y = UV.y;
	float across = sin(y * PI); // 纯净正弦拱形，内外边缘平滑沉降
	across = pow(across, 1.25);

	// 慢呼吸
	float pulse = 0.85 + 0.15 * sin(TIME * pulse_speed);

	// 1. 双频灵潮波澜（大潮平缓推移，次波轻柔交织）
	float tide1 = 0.5 + 0.5 * sin((UV.x - TIME * flow_speed) * TAU * 2.0);
	float tide2 = 0.5 + 0.5 * sin((UV.x + TIME * flow_speed * 0.35) * TAU * 4.0 + y * 1.2);
	float wave = pow(tide1, 4.0) * 0.70 + pow(tide2, 3.0) * 0.30;

	// 2. 战台内侧晶纹微界（UV.y 靠近 0.85 处的一抹清辉）
	float inner_gleam = smoothstep(0.60, 0.85, y) * smoothstep(1.0, 0.85, y);

	// 3. 柔和混合输出
	vec4 col = mix(base_color, flow_color, clamp(wave * 0.85 + inner_gleam * 0.5, 0.0, 1.0));
	col.a *= across * pulse * (0.38 + 0.62 * wave + inner_gleam * 0.3);

	COLOR = col;
}
