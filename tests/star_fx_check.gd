extends Node

## 星级开火特效判据（2026-10-25）：★3 鎏金档 / ★4 太虚霓虹档的「战斗内读数」。
##   ① 统一取色入口 GameStyle.star_fx_color / star_fx_ldr：★4 按段青紫交替、★3 恒鎏金；
##   ② 近战/横扫追加斩：★4 两段月牙不同色（读得出「第几段」），★3 两段同色；
##   ③ 弹丸：幻影弹 ★4 双色 / ★3 单色；枪口闪光与本体亮闪按星分档；
##   ④ 落雷：蓄力起手色分档；追加道电柱与落点换成星级色（主雷保持武器本色）；
##   ⑤ 光束/喷吐：★3 向金混色、★4 向电光青混色并换芯；低星逐项回落到原值（零回归）；
##   ⑥ ★4 常驻气场：升到极境挂 Star4Aura，降星即卸，★3 不挂。
## 运行: godot --headless --path . res://tests/StarFxCheck.tscn

const VEIL_ID := "zihong_jing"     ## 光束武器（紫虹镜）
const CONE_ID := "sanmei_huohu"    ## 喷吐武器（三昧火壶）
const SWORD_ID := "qingyun_sword"  ## 近战武器

var _c := TestCheck.new()

func _ready() -> void:
	get_tree().root.size = Vector2i(960, 540)
	call_deferred("_run")

func _spawn(def_id: String, star: int) -> Node:
	var w = load("res://scenes/weapons/FloatingWeapon.tscn").instantiate()
	w.setup(def_id, star)
	add_child(w)
	return w

func _run() -> void:
	# —— ① 统一取色入口 ——
	_c.check(GameStyle.star_fx_color(3) == GameStyle.FX_HDR_STAR3_GOLD, "★3 取色 = 鎏金")
	_c.check(GameStyle.star_fx_color(4, 0) == GameStyle.FX_HDR_STAR4_CYAN, "★4 段 0 = 电光青")
	_c.check(GameStyle.star_fx_color(4, 1) == GameStyle.FX_HDR_STAR4_VIOLET, "★4 段 1 = 太虚紫")
	_c.check(GameStyle.star_fx_color(4, 2) == GameStyle.FX_HDR_STAR4_CYAN, "★4 段 2 回到电光青（交替）")
	_c.check(GameStyle.star_fx_color(1) == GameStyle.FX_HDR_CORE, "★1 回落到超白（不抢戏）")
	_c.check(GameStyle.star_fx_ldr(4, 0) == GameStyle.STAR4_NEON, "★4 LDR 段 0 = STAR4_NEON")
	_c.check(GameStyle.star_fx_ldr(4, 1) == GameStyle.STAR4_NEON_EDGE, "★4 LDR 段 1 = STAR4_NEON_EDGE")

	# —— ② 近战/横扫追加斩 ——
	_c.check(MeleeHandler.echo_slash_color(4, 0) != MeleeHandler.echo_slash_color(4, 1),
			"★4 近战追加斩两段月牙异色")
	_c.check(MeleeHandler.echo_slash_color(3, 0) == MeleeHandler.echo_slash_color(3, 1),
			"★3 近战追加斩两段同色（鎏金）")
	_c.check(MeleeHandler.echo_glow_color(4, 0) != MeleeHandler.echo_glow_color(4, 1),
			"★4 追加斩闪光逐段异色")
	_c.check(MeleeHandler.echo_slash_color(4, 0).a == 1.0, "★4 月牙色不透明（alpha 归一）")

	# —— ③ 弹丸 ——
	_c.check(ProjectileHandler.phantom_tint(4, 0) != ProjectileHandler.phantom_tint(4, 1),
			"★4 幻影弹双色交替")
	_c.check(ProjectileHandler.phantom_tint(3, 0) == ProjectileHandler.phantom_tint(3, 1),
			"★3 幻影弹单色")
	_c.check(ProjectileHandler.star_flash_color(4) == GameStyle.FX_HDR_STAR4_CYAN,
			"★4 本体亮闪 = 电光青")
	_c.check(ProjectileHandler.star_flash_color(1) != ProjectileHandler.star_flash_color(4),
			"低星本体亮闪不染星级色")

	# —— ④ 落雷蓄力起手 ——
	_c.check(BurstHandler.charge_glow(1) == BurstHandler.CHARGE_GLOW, "★1 蓄力保持原金光")
	_c.check(BurstHandler.charge_glow(3) != BurstHandler.CHARGE_GLOW, "★3 蓄力换鎏金")
	_c.check(BurstHandler.charge_glow(4) == GameStyle.FX_HDR_STAR4_CYAN, "★4 蓄力换电光青")

	# —— ⑤ 光束 / 喷吐 ——
	var beam := _spawn(VEIL_ID, 4)
	await get_tree().process_frame
	var base := Color(0.70, 0.55, 1.0)
	var t4: Color = ChannelHandler.beam_tint(beam, base)
	_c.check(t4 != base, "★4 束色向电光青混色（整束换色）")
	_c.check(ChannelHandler.beam_core_tint(beam).a > 0.0, "★4 束流芯线换成星级 HDR")
	var cone4: Color = ChannelHandler.cone_tint(beam)
	_c.check(cone4.a > 0.0, "★4 喷吐锥色下发（非零 = 启用星级焰）")
	beam.setup(VEIL_ID, 2)
	_c.check(ChannelHandler.beam_tint(beam, base) == base, "★2 束色回落到武器本色（零回归）")
	_c.check(ChannelHandler.beam_core_tint(beam).a <= 0.0, "★2 芯线走默认（不下发星级色）")
	_c.check(ChannelHandler.cone_tint(beam).a <= 0.0, "★2 喷吐锥色不下发（默认火色）")
	beam.setup(VEIL_ID, 3)
	_c.check(ChannelHandler.beam_tint(beam, base) != base, "★3 束色向鎏金混色")

	var cone := _spawn(CONE_ID, 4)
	await get_tree().process_frame
	_c.check(ChannelHandler.cone_tint(cone).a > 0.0, "★4 火葫芦走星级锥色")

	# —— ⑥ ★4 常驻气场 ——
	var w4 := _spawn(SWORD_ID, 4)
	await get_tree().process_frame
	_c.check(w4.get_node_or_null("Star4Aura") != null, "★4 挂出常驻气场")
	var w3 := _spawn(SWORD_ID, 3)
	await get_tree().process_frame
	_c.check(w3.get_node_or_null("Star4Aura") == null, "★3 不挂气场")
	w4.setup(SWORD_ID, 3)
	await get_tree().process_frame
	await get_tree().process_frame
	_c.check(w4.get_node_or_null("Star4Aura") == null, "降星后气场卸除")

	_c.report("STARFX_RESULT")
	get_tree().quit(0 if _c.all_passed() else 1)
