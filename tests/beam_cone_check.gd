extends Node

## 束流类攻击（BEAM 光束 / CONE 喷吐）判据（2026-10-13 束流支路新增）
##
## 钉四件事：
## 1) 光束长度同源：_beam_len == 器口射线被首个受击区截断的距离；桩敌撤走后打满射程。
##    渲染器下发长度与判定同一字段（画多远==判多远）。
## 2) 光束横向同源：束线上的桩敌挨打、偏出半宽+受击半径的桩敌不挨打。
## 3) 喷吐锥形同源：锥内桩敌挨打且挂灼烧、锥外与背后不挨打；
##    渲染锥长 == 判定锥长、锥宽 == 判定半角正切（画多宽==判多宽）。
## 4) tick 折算同源：单 tick 伤害 == 整管伤害 × TICK / 有效冷却（纸面 DPS 即实伤）。
##
## 运行: godot --headless --path . res://tests/BeamConeCheck.tscn
## 反例：① 把 BEAM_HIT_OVERHANG 改成 0 ⇒ 挡束者打不到，第 1 条红；
##       ② 把渲染器下发长度改小 ⇒ 第 1/3 条红；③ 把 tick 折算的 TICK 换掉 ⇒ 第 4 条红。

## 只带 GameManager 要读的那两个字段（照 weapon_aim_check 桩体先例）
class StubPlayer:
	extends Node2D
	var current_health: float = 120.0
	var max_health: float = 120.0

class StubEnemy:
	extends Node2D
	var hit_count: int = 0
	var burn_calls: int = 0
	var last_amount: float = 0.0
	func take_damage(amount: float, _knockback: Vector2, _crit: bool = false, _from_dot: bool = false) -> void:
		hit_count += 1
		last_amount = amount
	func apply_burn(_dps: float, _dur: float) -> void:
		burn_calls += 1

var _c := TestCheck.new()
var _world: Node2D

func _ready() -> void:
	GameManager.reset_run()
	_world = Node2D.new()
	_world.name = "World"
	add_child(_world)
	var stub := StubPlayer.new()
	_world.add_child(stub)
	GameManager.player = stub
	call_deferred("_run")

func _run() -> void:
	await _test_beam()
	await _test_cone()
	if _c.report("BEAMCONE_RESULT"):
		get_tree().quit(0)
	else:
		get_tree().quit(1)

func _make(def_id: String) -> FloatingWeapon:
	var w: FloatingWeapon = load("res://scenes/weapons/FloatingWeapon.tscn").instantiate()
	w.setup(def_id, 1)
	_world.add_child(w)
	w.position = Vector2.ZERO
	# 关掉自主循环：本判据手动喂目标与 tick，不让它自己索敌自己开火
	w.set_process(false)
	return w

## 桩敌：Area2D 挂碰撞层 4（束流/锥形的查询掩码），父节点带 take_damage（照 weapon_aim_check 先例）
func _foe(at: Vector2) -> StubEnemy:
	var foe := StubEnemy.new()
	foe.position = at
	var area := Area2D.new()
	area.collision_layer = 4
	area.collision_mask = 0
	var cs := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 20.0
	cs.shape = circle
	area.add_child(cs)
	foe.add_child(area)
	_world.add_child(foe)
	return foe

# ---------------- 光束（紫虹镜） ----------------

func _test_beam() -> void:
	var w := _make("zihong_jing")
	var foe := _foe(Vector2(120.0, 0.0))
	var off := _foe(Vector2(120.0, 60.0))   # 偏出 束半宽5 + 受击半径20 ⇒ 必然离线
	await get_tree().physics_frame
	await get_tree().physics_frame

	# 起喷前渲染器收着
	_c.check(w.beam_renderer != null and not w.beam_renderer.visible, "光束未起喷时渲染器隐藏")

	w.current_target = foe
	w._apply_facing(0.0)   # 正东瞄准
	w._perform_channel_attack()
	w._tick_channel(0.016)

	# 1) 长度截断：器口到桩敌表面（120 − 受击半径20 − 器口距）
	var expect_len := 120.0 - 20.0 - w.muzzle_len
	_c.near(w._beam_len, expect_len, 2.5,
		"光束被桩敌表面截断（期望 %.1f，实得 %.1f）" % [expect_len, w._beam_len])
	_c.check(w.beam_renderer.visible and absf(w.beam_renderer.length - w._beam_len) < 0.01,
		"渲染束长 == 判定束长（同源下发）")

	# 2) 命中：线上桩敌挨打（挡束者被 BEAM_HIT_OVERHANG 盖进判定）、离线桩敌不挨打
	_c.check(foe.hit_count >= 1, "束线上桩敌挨打（挡束者计入判定）")
	_c.equals(off.hit_count, 0, "离线桩敌不挨打")

	# 4) tick 折算同源：单跳伤害 == 整管 × TICK / 有效冷却（暴击则 ×暴击倍率，两种都认）
	var eff_cd: float = maxf(0.05, w.attack_cooldown * GameManager.get_effective_attack_speed_mult())
	var base: float = w._final_damage() * FloatingWeapon.BEAM_TICK / eff_cd
	var crit_v: float = base * GameManager.get_crit_mult()
	_c.check(absf(foe.last_amount - base) < 0.05 or absf(foe.last_amount - crit_v) < 0.05,
		"光束单跳伤害与纸面同源（期望 %.2f 或暴击 %.2f，实得 %.2f）" % [base, crit_v, foe.last_amount])

	# 打满射程：桩敌清掉后光束顶到射程 − 器口距
	# （桩体必须在 add_child 前摆好位：Area2D 的物理形状要等下一物理帧才跟上传送，
	#   先创建再改 position 会让射线打到它的上一帧位置）
	foe.queue_free()
	off.queue_free()
	var far := _foe(Vector2(500.0, 0.0))
	await get_tree().physics_frame
	await get_tree().physics_frame
	w.current_target = far
	w._tick_channel(0.016)
	var max_len: float = w.attack_range * w._range_mult() - w.muzzle_len
	_c.near(w._beam_len, max_len, 0.5,
		"无遮挡光束打满射程（期望 %.1f，实得 %.1f）" % [max_len, w._beam_len])

	# 收束：目标消失即熄
	far.queue_free()
	w.current_target = null
	w._tick_channel(0.016)
	_c.check(not w.beam_renderer.visible, "目标消失光束收束（不空喷）")
	w.queue_free()
	await get_tree().physics_frame

# ---------------- 喷吐（火葫芦） ----------------

func _test_cone() -> void:
	var w := _make("sanmei_huohu")
	var in_foe := _foe(Vector2(120.0, 0.0))                          # 锥心
	var edge_foe := _foe(Vector2(120.0, 0.0).rotated(deg_to_rad(40.0)))  # 锥外（40° > 28° 半角）
	var behind := _foe(Vector2(-120.0, 0.0))                         # 背后
	await get_tree().physics_frame
	await get_tree().physics_frame

	w.current_target = in_foe
	w._apply_facing(0.0)
	w._perform_channel_attack()
	w._tick_channel(0.016)

	# 3) 锥形同源：渲染锥长 == 射程 − 器口距，锥宽 == 锥长 × tan(半角)
	var cone_len: float = w.attack_range * w._range_mult() - w.muzzle_len
	_c.check(w.cone_renderer != null and w.cone_renderer.visible, "喷吐起喷后渲染器亮起")
	_c.near(w.cone_renderer.length, cone_len, 0.5,
		"渲染锥长 == 判定锥长（期望 %.1f，实得 %.1f）" % [cone_len, w.cone_renderer.length])
	_c.near(w.cone_renderer.half_width, cone_len * tan(deg_to_rad(FloatingWeapon.CONE_HALF_ANGLE)), 0.5,
		"渲染锥宽 == 判定半角正切（画多宽==判多宽）")
	_c.check(in_foe.hit_count >= 1, "锥内桩敌挨打")
	_c.check(in_foe.burn_calls >= 1, "锥内桩敌被点燃（proc_burn 下发）")
	_c.equals(edge_foe.hit_count, 0, "锥外桩敌不挨打（40° 在 28° 半角外）")
	_c.equals(behind.hit_count, 0, "背后桩敌不挨打")

	# 4) tick 折算同源
	var eff_cd: float = maxf(0.05, w.attack_cooldown * GameManager.get_effective_attack_speed_mult())
	var base: float = w._final_damage() * FloatingWeapon.CONE_TICK / eff_cd
	var crit_v: float = base * GameManager.get_crit_mult()
	_c.check(absf(in_foe.last_amount - base) < 0.05 or absf(in_foe.last_amount - crit_v) < 0.05,
		"喷吐单跳伤害与纸面同源（期望 %.2f 或暴击 %.2f，实得 %.2f）" % [base, crit_v, in_foe.last_amount])

	# 收束
	w.current_target = null
	w._tick_channel(0.016)
	_c.check(not w.cone_renderer.visible, "目标消失喷吐收束（不空喷）")
	w.queue_free()
	await get_tree().physics_frame
