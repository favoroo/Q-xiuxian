extends Node

## 打击音分层判据（2026-10-23，用户口径：「参考死亡细胞，让整体音响更有打击感」）
##
## 量的是三件互相独立、旧代码各自会翻车的事：
## 1) 暴击单播。旧写法同时播 enemy_hit + enemy_hit_crit 两声：双倍占 16 通道池，
##    且两 key 的 SFX_GAP_MS 不同步（hit 18ms / crit 40ms）⇒ 连击暴击会出现
##    「hit 在响、crit 被吞」。现在暴击必须只播 crit 一声（配方自带完整五层主体）。
## 2) 普通命中不叠重击层。重击层只给精英 / 大击退 / 单次打掉 35%+ 生命三种来源；
##    普通小怪轻击多播一声 heavy 就是低频糊成一坨。
## 3) DoT tick 全程静默。持续伤害每 0.5s 一跳，出声会把打击音彻底淹没。
##
## 捕获方式：AudioManager.begin_sfx_capture() —— headless 不出声，但「想播什么」量得到；
## 捕获态不进播放器池、不查节流表，所以这里量的是调用意图，不是混音结果。
##
## 运行: godot --headless --path . res://tests/HitSfxLayerCheck.tscn
## 反例（判据的牙齿，改回旧写法必红）：
##   ① 暴击改回双播 → ① 报红；
##   ② 去掉 hit_sfx_is_heavy 的 35% 闸、改成无条件播 heavy → ② 报红。

var _c := TestCheck.new()
var _world: Node2D

func _ready() -> void:
	GameManager.reset_run()
	_world = Node2D.new()
	_world.name = "World"
	add_child(_world)
	call_deferred("_run")

func _run() -> void:
	# ① 暴击只播 crit 一声（旧写法是 enemy_hit + enemy_hit_crit 两声）
	var crit_enemy := _make(9999.0)
	var crit_seq := _capture_hit(crit_enemy, 10.0, Vector2(100, 0), true, false)
	_c.check(crit_seq.size() == 1, "暴击只播一声（实收 %d 声: %s）" % [crit_seq.size(), str(crit_seq)])
	_c.check(crit_seq.has("enemy_hit_crit"), "暴击播的是 enemy_hit_crit（实收 %s）" % str(crit_seq))
	_c.check(not crit_seq.has("enemy_hit"), "暴击不再叠播 enemy_hit（实收 %s）" % str(crit_seq))

	# ② 普通小怪轻击只播 enemy_hit 一声，不叠重击层
	var light_enemy := _make(9999.0)
	var light_seq := _capture_hit(light_enemy, 10.0, Vector2(100, 0), false, false)
	_c.check(light_seq.size() == 1, "普通轻击只播一声（实收 %d 声: %s）" % [light_seq.size(), str(light_seq)])
	_c.check(light_seq.has("enemy_hit"), "普通轻击播 enemy_hit（实收 %s）" % str(light_seq))
	_c.check(not light_seq.has("enemy_hit_heavy"), "普通轻击不叠重击层（实收 %s）" % str(light_seq))

	# ③ 单次打掉 35%+ 生命的重击要补一层 heavy（伤害驱动的新来源）
	var heavy_enemy := _make(100.0)
	var heavy_seq := _capture_hit(heavy_enemy, 50.0, Vector2(100, 0), false, false)
	_c.check(heavy_seq.has("enemy_hit"), "重击仍播基础命中声（实收 %s）" % str(heavy_seq))
	_c.check(heavy_seq.has("enemy_hit_heavy"), "单次 50%% 生命补重击层（实收 %s）" % str(heavy_seq))

	# ④ DoT tick 全程静默（暴击 DoT 也不许出声）
	var dot_enemy := _make(9999.0)
	var dot_seq := _capture_hit(dot_enemy, 10.0, Vector2.ZERO, false, true)
	_c.check(dot_seq.is_empty(), "DoT tick 不出声（实收 %s）" % str(dot_seq))
	var dot_crit_seq := _capture_hit(dot_enemy, 10.0, Vector2.ZERO, true, true)
	_c.check(dot_crit_seq.is_empty(), "DoT 暴击 tick 也不出声（实收 %s）" % str(dot_crit_seq))

	# ⑤ 伤害驱动的响度/音高确实传进了播放参数（不是只算了不用）
	var small_enemy := _make(1000.0)
	var small_recs := _capture_hit_records(small_enemy, 10.0, Vector2(100, 0), false, false)
	var big_enemy := _make(100.0)
	var big_recs := _capture_hit_records(big_enemy, 60.0, Vector2(100, 0), false, false)
	if small_recs.size() > 0 and big_recs.size() > 0:
		var small_scale := float(small_recs[0].get("scale", 0.0))
		var big_scale := float(big_recs[0].get("scale", 0.0))
		_c.check(big_scale > small_scale,
			"大伤害（60%%生命）的播放响度高于小伤害（1%%生命）：%.3f > %.3f" % [big_scale, small_scale])
	else:
		_c.check(false, "伤害驱动采样没捕到 enemy_hit 记录")

	_world.free()
	if _c.report("HITSFX_RESULT"):
		get_tree().quit(0)
	else:
		get_tree().quit(1)

## 造一只敌人（slime），血量拉满，摆到视口中心保证在屏（音效不受视口门控，但保持与实战同构）
func _make(hp: float) -> EnemyBase:
	var scene: PackedScene = load("res://scenes/entities/SlimeEnemy.tscn")
	var e := scene.instantiate() as EnemyBase
	_world.add_child(e)
	e.activate()
	e.max_hp = hp
	e.current_hp = hp
	e.global_position = get_viewport().get_visible_rect().get_center()
	e._offscreen = false
	return e

## 打一刀并返回「实际想播的 key 序列」
func _capture_hit(e: EnemyBase, amount: float, knockback: Vector2, is_crit: bool, from_dot: bool) -> PackedStringArray:
	var recs := _capture_hit_records(e, amount, knockback, is_crit, from_dot)
	var out := PackedStringArray()
	for rec in recs:
		out.append(String(rec.get("key", "")))
	return out

func _capture_hit_records(e: EnemyBase, amount: float, knockback: Vector2, is_crit: bool, from_dot: bool) -> Array:
	AudioManager.begin_sfx_capture()
	e.take_damage(amount, knockback, is_crit, from_dot)
	# end_sfx_capture 返回的是 AudioManager 内部 _captured 的引用；下一次 begin 会 clear 同一数组，
	# 所以这里必须 duplicate，否则前后两次捕获会指向同一份数据（判据自己踩过的坑）。
	return AudioManager.end_sfx_capture().duplicate(true)
