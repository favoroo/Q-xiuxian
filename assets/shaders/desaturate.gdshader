shader_type canvas_item;

// 去色：把彩色像素按亮度压成灰相，用于「已经用完」的物件（如放过法的聚灵阵界碑）。
// amount 0=原样，1=全灰；grey_tint 决定灰相的冷暖倾向；darken 让耗尽态比活性时更沉一档。
// 只改颜色不改透明度，所以像素画的边缘与阴影照旧。
// 注意：.gdshader 里 # 是预处理指令，注释必须用 // —— 写成 GDScript 的 ## 会让整个着色器编译失败。
// 同理，Godot 4 的 canvas_item 没有 MODULATE 内置量（那是 3.x 的），modulate 要在 vertex()
// 里把 COLOR 取成 varying 才拿得到，否则 Sprite 上的 modulate 会被着色器吃掉。

varying vec4 vertex_color;

uniform float amount : hint_range(0.0, 1.0) = 0.0;
uniform vec4 grey_tint : source_color = vec4(0.86, 0.87, 0.9, 1.0);
uniform float darken : hint_range(0.0, 1.0) = 0.25;

void vertex() {
	vertex_color = COLOR;
}

void fragment() {
	vec4 src = texture(TEXTURE, UV);
	float luma = dot(src.rgb, vec3(0.2126, 0.7152, 0.0722));
	vec3 grey = vec3(luma) * grey_tint.rgb * (1.0 - darken);
	COLOR = vec4(mix(src.rgb, grey, clamp(amount, 0.0, 1.0)), src.a) * vertex_color;
}
