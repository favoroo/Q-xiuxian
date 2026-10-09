shader_type canvas_item;

// 去色：把彩色像素按亮度压成灰相，用于「已经用完」的物件（如放过法的聚灵阵界碑）。
// amount 0=原样，1=全灰；grey_tint 决定灰相的冷暖倾向；darken 让耗尽态比活性时更沉一档。
// 只改颜色不改透明度，所以像素画的边缘与阴影照旧。
// 注意：.gdshader 里 # 是预处理指令，注释必须用 // —— 写成 GDScript 的 ## 会让整个着色器编译失败。
// 同理，Godot 4 的 canvas_item 没有 MODULATE 内置量（那是 3.x 的），modulate 要在 vertex()
// 里把 COLOR 取成 varying 才拿得到，否则 Sprite 上的 modulate 会被着色器吃掉。
//
// fill_ratio 是同一张材质上叠的第二件事：充能进度「灌进碑里」—— 自下而上把已灌到的
// 那一段提亮成灵气色，液面那一条再亮一档。界碑是竖的、进度是长的，所以进度画在碑身上
// 比在旁边立一根小条更一眼读得出「这座碑正在被灌满」。用完（amount→1）时灌灵自动熄灭，
// 不必每个调用点记得清 fill_ratio。

varying vec4 vertex_color;

uniform float amount : hint_range(0.0, 1.0) = 0.0;
uniform vec4 grey_tint : source_color = vec4(0.86, 0.87, 0.9, 1.0);
uniform float darken : hint_range(0.0, 1.0) = 0.25;
uniform float fill_ratio : hint_range(0.0, 1.0) = 0.0;
uniform vec4 fill_color : source_color = vec4(0.56, 0.72, 1.0, 1.0);
// 液面亮带的厚度（UV 单位，1.0 = 整张图高）
uniform float fill_band : hint_range(0.005, 0.2) = 0.045;

void vertex() {
	vertex_color = COLOR;
}

void fragment() {
	vec4 src = texture(TEXTURE, UV);
	float luma = dot(src.rgb, vec3(0.2126, 0.7152, 0.0722));
	vec3 grey = vec3(luma) * grey_tint.rgb * (1.0 - darken);
	vec3 col = mix(src.rgb, grey, clamp(amount, 0.0, 1.0));
	float f = clamp(fill_ratio, 0.0, 1.0) * (1.0 - clamp(amount, 0.0, 1.0));
	if (f > 0.0) {
		// UV.y 向下增大：液面在 1-f，其下即「已灌到」
		float surface_y = 1.0 - f;
		float below = smoothstep(surface_y - 0.010, surface_y + 0.010, UV.y);
		float band = 1.0 - clamp(abs(UV.y - surface_y) / fill_band, 0.0, 1.0);
		band = band * band * (3.0 - 2.0 * band);
		// 灌到的那一段：略微提亮 + 压一层灵气色；液面那一条单独亮一档，
		// 因为「液面在哪儿」才是给人读进度的那条边线
		col = col * (1.0 + 0.22 * below) + fill_color.rgb * (0.34 * below + 0.95 * band);
	}
	COLOR = vec4(col, src.a) * vertex_color;
}
