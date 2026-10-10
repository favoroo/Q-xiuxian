extends Node

## 玩家受击与开局外观判据：
##   1. 未选人时外观完全隐藏，不加载或展示旧青衫像素图 pawn_blue_8dir.png
##   2. 选人后 ProceduralCultivatorView 正常挂载并显示，旧 AnimatedSprite 保持隐藏
##   3. 受击第一击正常扣血并起无敌帧，在无 buff 状态下无敌帧正常逐帧衰减
##   4. 无敌帧归零后下一击敌人伤害正常结算（彻底解决永久无敌 Bug）
## 运行: godot --headless --path . res://tests/PlayerDamageAndVisualCheck.tscn
## 退出码 0 且末行 PLAYER_DAMAGE_AND_VISUAL_CHECK_RESULT: ALL PASS

var _c := TestCheck.new()

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	GameManager.reset_run()
	_test_initial_visuals()
	_test_select_cultivator_visuals()
	_test_damage_and_invulnerability()

	if not _c.all_passed():
		print("PLAYER_DAMAGE_AND_VISUAL_CHECK_RESULT: FAILED (%d failures)" % _c.failures.size())
		get_tree().quit(1)
	else:
		print("PLAYER_DAMAGE_AND_VISUAL_CHECK_RESULT: ALL PASS (%d checks)" % _c.passed)
		get_tree().quit(0)

func _test_initial_visuals() -> void:
	# 确保在未选人状态下
	GameManager.cultivator_id = ""
	var p_scene: PackedScene = load("res://scenes/entities/Player.tscn")
	var p := p_scene.instantiate() as Player
	add_child(p)

	_c.check(not p.anim_sprite.visible, "开局未选人时 anim_sprite 保持隐藏")
	_c.check(not p.shadow_sprite.visible, "开局未选人时 shadow_sprite 保持隐藏")
	_c.check(p.procedural_view == null or not p.procedural_view.visible, "开局未选人时 procedural_view 不可见")
	_c.check(p.anim_sprite.sprite_frames == null, "开局未选人时不加载旧像素图集")

	p.queue_free()

func _test_select_cultivator_visuals() -> void:
	GameManager.cultivator_id = "jianchi"
	var p_scene: PackedScene = load("res://scenes/entities/Player.tscn")
	var p := p_scene.instantiate() as Player
	add_child(p)

	_c.check(p.is_procedural, "选定 jianchi 后进入 procedural 程序化渲染分支")
	_c.check(p.procedural_view != null and p.procedural_view.visible, "procedural_view 正常创建并显示")
	_c.check(not p.anim_sprite.visible, "旧 anim_sprite 保持隐藏不显示")
	_c.check(p.shadow_sprite.visible, "选定角色后 shadow_sprite 正常显示")

	p.queue_free()

func _test_damage_and_invulnerability() -> void:
	GameManager.cultivator_id = "jianchi"
	var p_scene: PackedScene = load("res://scenes/entities/Player.tscn")
	var p := p_scene.instantiate() as Player
	add_child(p)
	GameManager.player = p

	var max_hp := p.max_health
	_c.check(p.current_health == max_hp, "初始满血 %.1f" % max_hp)
	_c.check(p.invulnerable_time == 0.0, "初始无敌时间为 0")
	_c.check(p._skill_buffs.is_empty(), "初始无任何技能增益 Buff")

	# 1. 首次受击
	p.take_damage(20.0)
	var hp_after_hit1 := p.current_health
	_c.check(hp_after_hit1 < max_hp, "首次受击成功扣血 (从 %.1f 降至 %.1f)" % [max_hp, hp_after_hit1])
	_c.check(p.invulnerable_time > 0.4, "首次受击后触发无敌帧 (当前 %.2f s)" % p.invulnerable_time)

	# 2. 无敌期间再次受击应免疫
	p.take_damage(20.0)
	_c.check(p.current_health == hp_after_hit1, "无敌帧期间受击被免疫，血量未变 (%.1f)" % p.current_health)

	# 3. 模拟帧流转（无任何 buff 的常态）
	# invulnerable_time 约为 0.55s，步进 0.1s 循环 7 次累计 0.7s
	for i in range(7):
		p._physics_process(0.1)

	_c.check(p.invulnerable_time <= 0.0, "经过 0.7s 物理步进后无敌时间成功归零 (当前 %.2f s)" % p.invulnerable_time)
	_c.check(p.anim_sprite.modulate == Color.WHITE, "无敌结束后 modulate 复位为纯白")

	# 4. 无敌结束后第二次受击应再次扣血（核心验证：绝不再永久无敌）
	p.take_damage(20.0)
	var hp_after_hit2 := p.current_health
	_c.check(hp_after_hit2 < hp_after_hit1, "无敌结束后再次受击扣血成功 (从 %.1f 降至 %.1f)" % [hp_after_hit1, hp_after_hit2])
	_c.check(p.invulnerable_time > 0.4, "再次受击重新起无敌帧")

	p.queue_free()
