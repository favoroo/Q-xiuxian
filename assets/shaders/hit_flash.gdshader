shader_type canvas_item;

// 受击闪白（2026-10-17 性能专项改版）：
// 旧版走 per-instance uniform（flash_modifier/flash_color），19 个敌人场景全部
// resource_local_to_scene=true —— 每实例独享一份 ShaderMaterial，35 只怪 = 35 份唯一材质，
// 打断 canvas 批处理（759 draw call 的主要来源之一）。
// 新版零 uniform：全部实例共享同一份材质，闪白权重由顶点色 COLOR 携带 ——
// Godot canvas_item 的 COLOR = 纹理顶点色 × modulate × self_modulate。
// 敌人侧约定（EnemyBase._write_flash_channel）：
//   self_modulate = Color(1,1,1,1).lerp(flash_color_scaled, flash_mod)
//   flash_mod ∈ [0,1]：0 ⇒ 纯原色（直通），1 ⇒ 顶点色已按 flash 色提亮，
//   >1 分量经顶点色外溢为超白（HDR 起辉）。
// 兼容性：modulate（节点级）仍归冰缓/引信/蓄力染色业务，COLOR 相乘天然叠加，
// 两层染色互不覆盖；shader 本体退化为直通 —— 提亮/混色全在 CPU 侧顶点色完成，
// 材质批处理不再被 per-instance uniform 上传打断。

void fragment() {
    vec4 texture_color = texture(TEXTURE, UV) * COLOR;
    COLOR = texture_color;
}
