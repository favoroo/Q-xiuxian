shader_type canvas_item;

// 结界光幕流光（T-4.1）：挂在 ArenaVisualLayer.BoundaryFlowBand 上。
// UV.x = 顺时针整圈周长参数 [0,1]（四段梯形在宿主 _draw 中拼接，整数波数保证 0/1 接缝无缝）；
// UV.y = 横向 [0=内缘, 1=外缘]。三道亮团沿法阵缓慢流转（约 20s/圈），叠加慢呼吸。
// HDR 起辉：flow_color 分量 >1.0 超阈值自动泛光，阈值见 Main.tscn WorldEnvironment
// glow_hdr_threshold=1.0，零额外性能开销。
// ⚠ flow_color 与 GameStyle.FX_HDR_WATER（水系灵蓝超白）同源，改动必须两处同步。
uniform vec4 base_color : source_color = vec4(0.25, 0.80, 1.0, 1.0);   // 幽蓝底（原结界主光丝色）
uniform vec4 flow_color : source_color = vec4(0.80, 1.80, 2.50, 1.0);  // 灵蓝超白亮团（= GameStyle.FX_HDR_WATER）
uniform float flow_speed : hint_range(0.0, 0.5) = 0.05;  // 流速：圈/秒
uniform float pulse_speed : hint_range(0.0, 4.0) = 1.2;  // 呼吸角频率（rad/s，与灵脉 6s 呼吸错拍）

void fragment() {
	// 横向包络：中亮缘暗（羽化，不糊出带外）
	float across = smoothstep(0.0, 1.0, 1.0 - abs(UV.y - 0.5) * 2.0);
	// 慢呼吸
	float pulse = 0.78 + 0.22 * sin(TIME * pulse_speed);
	// 三道亮团沿周长顺时针流转（pow 收窄成团）
	float wave = pow(0.5 + 0.5 * sin((UV.x - TIME * flow_speed) * TAU * 3.0), 6.0);
	vec4 col = mix(base_color, flow_color, wave);
	col.a *= across * pulse * (0.35 + 0.65 * wave);
	COLOR = col;
}
