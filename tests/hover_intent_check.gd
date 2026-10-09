extends Node

## 悬浮怪（御剑/踩云系，locomotion_mode == "hover"）三种走位的可辨识度判据。
## 起因（用户现场 2026-10-09）：「踩着黑雾的这个敌人，为什么背对着走向我？」
## 查清的两件事：
##   ① 朝向行没选错 —— EnemyBase 的 facing 永远由「指向玩家的向量」决定，它在屏幕下方
##      就意味着「面向玩家」= 朝上 = 取图集 n（背面）行。玩家自己往上走也是背面，同一套约定。
##   ② 它其实在后撤 —— 邪修 preferred_range=260，距离 <230px 就 -dir 后退放风筝。
##      往屏幕下方退 = 朝镜头方向 = 玩家读成「朝我走来」，配上背面就成了「背对着走向我」。
## 真正的缺陷是：hover 只播 idle 单姿势、且旧版 bank 按「面向」而非「走位」，
## 于是 逼近 / 环绕 / 后撤 三种运动长得一模一样（只剩一条上下浮），玩家只能靠猜。
## 这一屏钉死六件事：
##   A1 横向：侧倾符号必须跟着**实际走位**走（逼近与后撤倾反方向）
##   A2 竖直：bank≈0 时必须有另一条通道分得开（沉身/仰身 + 影子拖在身后）
##   A3 环绕：|逼近度| 落在死区内就不叠纵向形变（免得在 0 附近来回翻）
##   A4 量级：后撤形变要在手机上看得见，不是纸面改动
##   A5 玩家口径：不传 advance 时 rotation/scale 与改动前逐字相同（不许顺手动玩家手感）
##   B1 现场：把邪修摆回截图那个距离，它确实在后撤，且渲染层读到的意图为负
## 运行: godot --headless --path . res://tests/HoverIntentCheck.tscn

var _c := TestCheck.new()
var _world: Node2D
var _player: Node2D

const DT := 1.0 / 60.0
const SPRITE_SCALE := Vector2(0.44, 0.44)
const SHADOW_POS := Vector2(0.0, 14.0)
const SHADOW_SCALE := Vector2(0.48, 0.48)
const SETTLE_FRAMES := 60   # 0.9s：够 hover_intent（一阶跟随 10/s）收敛

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	await _case_layer_pure()
	await _case_layer_scene()
	if _c.report("HOVER_RESULT"):
		get_tree().quit(0)
	else:
		get_tree().quit(1)

# ────────────────────────────────────────────────────────────────
## 纯渲染层：直接喂合成输入，不牵整局，读数完全可复现
# ────────────────────────────────────────────────────────────────
func _case_layer_pure() -> void:
	# 一只裸 sprite + 影子，初值与 XieXiuEnemy.tscn 一致（判据量的是真配置下的形变量级）
	var spr := AnimatedSprite2D.new()
	spr.scale = SPRITE_SCALE
	var shd := Sprite2D.new()
	shd.position = SHADOW_POS
	shd.scale = SHADOW_SCALE
	var world := Node2D.new()
	world.add_child(spr)
	world.add_child(shd)
	get_tree().root.add_child(world)
	await get_tree().process_frame

	_c.check(shd.has_meta(&"gait_base") == false,
		"A0 前置：影子基准（位置/缩放）尚未被捕获 ⇒ 首帧才会拿真初值")

	# A1 横向走位：侧倾符号 = 实际走位符号，逼近(+x) 与后撤(-x) 必须倾反方向
	var close_x := _drive(spr, shd, SPRITE_SCALE, Vector2(1.0, 0.0), 1.0, 1.0)
	var flee_x := _drive(spr, shd, SPRITE_SCALE, Vector2(-1.0, 0.0), -1.0, 1.0)
	_c.check(float(close_x["rot"]) > 0.0 and float(flee_x["rot"]) < 0.0,
		"A1 横向：逼近侧倾 %+.2f° / 后撤侧倾 %+.2f° 必须反向" % [
			rad_to_deg(float(close_x["rot"])), rad_to_deg(float(flee_x["rot"]))])
	_c.check(absf(float(close_x["rot"])) > 0.05 and absf(float(flee_x["rot"])) > 0.05,
		"A1 横向：两侧倾幅度都够看得见（%.2f° / %.2f°）" % [
			rad_to_deg(float(close_x["rot"])), rad_to_deg(float(flee_x["rot"]))])

	# A2 竖直走位：bank≈0（截图那个方位），只能靠沉身/仰身 + 影子拖影分
	var close_y := _drive(spr, shd, SPRITE_SCALE, Vector2(0.0, -1.0), 1.0, 1.0)
	var flee_y := _drive(spr, shd, SPRITE_SCALE, Vector2(0.0, 1.0), -1.0, 1.0)
	_c.check(absf(float(close_y["rot"])) < 0.005 and absf(float(flee_y["rot"])) < 0.005,
		"A2 竖直：bank 确实不出力（%.4f / %.4f rad）⇒ 方向只能由纵向通道给" % [
			float(close_y["rot"]), float(flee_y["rot"])])
	_c.check(float(close_y["sy"]) < SPRITE_SCALE.y and float(flee_y["sy"]) > SPRITE_SCALE.y,
		"A2 竖直：逼近沉身 %.4f / 后撤仰身 %.4f（基准 %.4f）" % [
			float(close_y["sy"]), float(flee_y["sy"]), SPRITE_SCALE.y])
	_c.check(float(close_y["oy"]) > float(flee_y["oy"]),
		"A2 竖直：逼近压低 %.3f / 后撤抬高 %.3f（offset.y 越大越靠下）" % [
			float(close_y["oy"]), float(flee_y["oy"])])
	_c.check(float(close_y["shpy"]) > float(flee_y["shpy"]),
		"A2 竖直：影子拖在身后 —— 逼近时影子留在下方 %.2f / 后撤时留在上方 %.2f" % [
			float(close_y["shpy"]), float(flee_y["shpy"])])
	_c.check(absf(float(close_y["shpy"]) - float(flee_y["shpy"])) > 2.0,
		"A2 竖直：两种走位的影子纵向错开至少 2px（实差 %.2fpx）" % absf(
			float(close_y["shpy"]) - float(flee_y["shpy"])))
	_c.check(float(flee_y["shsy"]) > SHADOW_SCALE.y and float(close_y["shsy"]) > SHADOW_SCALE.y,
		"A2 竖直：移动时影子被沿行进轴拉长（逼近 %.4f / 后撤 %.4f，基准 %.4f）" % [
			float(close_y["shsy"]), float(flee_y["shsy"]), SHADOW_SCALE.y])

	# A3 环绕：|逼近度| 在死区内 ⇒ 不叠纵向形变（只留 bank 与浮沉）
	var orbit := _drive(spr, shd, SPRITE_SCALE, Vector2(0.0, -1.0), 0.1, 1.0)
	_c.check(absf(float(orbit["sy"]) - SPRITE_SCALE.y) / SPRITE_SCALE.y < 0.02,
		"A3 环绕：|advance|=0.1 落在死区内，纵向形变 ≈0（scale.y 偏 %.2f%%）" % (
			(float(orbit["sy"]) - SPRITE_SCALE.y) / SPRITE_SCALE.y * 100.0))

	# A4 量级：后撤形变要在手机上看得见（0.44 缩放的 sprite 上至少 2% 高差）
	var flee_full := _drive(spr, shd, SPRITE_SCALE, Vector2(0.0, 1.0), -1.0, 1.0)
	var dev_pct := absf(float(flee_full["sy"]) - SPRITE_SCALE.y) / SPRITE_SCALE.y * 100.0
	_c.check(dev_pct >= 2.0,
		"A4 量级：满档后撤纵向形变 %.2f%% ≥ 2%%（手机上看得见）" % dev_pct)

	# A5 玩家口径：不传 advance（Player.gd 就是这么调的）⇒ 与改动前逐字相同
	#    旧写法：lean = deg_to_rad(7 * |dir.x| * clamp(speed,0,1.3)) * sign(dir.x)
	var p_move := Vector2(0.6, -0.8).normalized()
	var p_ratio := 1.15
	var p_read := _drive(spr, shd, SPRITE_SCALE, p_move, 0.0, p_ratio)
	var expect_rot := deg_to_rad(RunMotion.HOVER_BANK_DEG * absf(p_move.x) * clampf(p_ratio, 0.0, 1.3)) * signf(p_move.x)
	_c.check(absf(float(p_read["rot"]) - expect_rot) < 1e-4,
		"A5 玩家：不传 advance 时侧倾与旧公式一致（期望 %.5f，实得 %.5f rad）" % [expect_rot, float(p_read["rot"])])
	_c.check(absf(float(p_read["sy"]) - SPRITE_SCALE.y) / SPRITE_SCALE.y < 0.02,
		"A5 玩家：不传 advance 时纵向不引入新形变（scale.y 偏 %.2f%%）" % (
			(float(p_read["sy"]) - SPRITE_SCALE.y) / SPRITE_SCALE.y * 100.0))
	_c.check(RunMotion.HOVER_BANK_DEG == 7.0,
		"A5 玩家：侧倾角仍是 7.0°（只换了驱动向量，没顺手加大幅度）")

	world.queue_free()

## 用同一组输入连推 SETTLE_FRAMES 帧，返回收敛后的读数
## （浮沉是正弦，bob 项只进 offset.y 与 ≤0.6% 的 scale 呼吸，故 scale 读数稳定可比）
func _drive(spr: AnimatedSprite2D, shd: Sprite2D, base: Vector2, move_dir: Vector2, advance: float, ratio: float) -> Dictionary:
	for i in range(SETTLE_FRAMES):
		RunMotion.apply_hover(spr, base, true, move_dir, DT, ratio, shd, advance)
	return {
		"rot": spr.rotation,
		"sy": spr.scale.y,
		"sx": spr.scale.x,
		"oy": spr.offset.y,
		"shpy": shd.position.y,
		"shsy": shd.scale.y,
		"intent": spr.get_meta(&"hover_intent"),
	}

# ────────────────────────────────────────────────────────────────
## 现场层：把邪修摆回截图那个距离，验「它确实在后撤」且渲染层读得到
# ────────────────────────────────────────────────────────────────
func _case_layer_scene() -> void:
	SettingsManager.set_val(&"display", &"hit_stop", false, false)
	_world = Node2D.new()
	_world.name = "HoverIntentWorld"
	get_tree().root.add_child(_world)
	await get_tree().process_frame

	_player = load("res://scenes/entities/Player.tscn").instantiate() as Node2D
	_world.add_child(_player)
	_player.global_position = Vector2.ZERO
	_player.max_health = 99999.0
	_player.current_health = 99999.0
	await get_tree().process_frame

	_c.check(GameManager.player == _player, "B0 前置：EnemyBase 读到的玩家就是这一只")

	var probe := _spawn_xiexiu(210.0)
	_c.check(probe.locomotion_mode == "hover",
		"B0 前置：邪修走的是悬浮单姿势（判据测的就是这条通道）")
	_c.check(probe.preferred_range > 0.0,
		"B0 前置：邪修配了保持距离（%.0fpx ⇒ 它会后撤）" % probe.preferred_range)
	probe.queue_free()
	await get_tree().process_frame

	# 截图那一拍：玩家在屏幕上方、邪修在下方约 210px（屏幕 250px ÷ 镜头 1.2）
	var near := await _probe_intent(210.0)
	# 退到带外：330px > preferred_range+30 ⇒ 正常逼近
	var far := await _probe_intent(330.0)

	_c.check(bool(near["retreating"]),
		"B1 现场：210px 处位移与「面向玩家」反向 ⇒ 它确实在后撤（点积 %+.1f）" % float(near["dot"]))
	_c.check(bool(far["closing"]),
		"B1 现场：330px 处在逼近（点积 %+.1f）" % float(far["dot"]))
	_c.check(float(near["intent"]) < -0.5,
		"B2 现场：后撤那一拍渲染层读到意图 %+.2f（旧版这里根本没有这个读数）" % float(near["intent"]))
	_c.check(float(far["intent"]) > 0.5,
		"B2 现场：逼近那一拍读到意图 %+.2f" % float(far["intent"]))
	_c.check(float(near["intent"]) < float(far["intent"]) - 0.8,
		"B2 现场：两种走位的意图读数分得开（%+.2f vs %+.2f）" % [float(near["intent"]), float(far["intent"])])

	_world.queue_free()

## 摆一只邪修到玩家正下方 dist 处（截图那个方位：bank≈0，全靠纵向通道）
func _spawn_xiexiu(dist: float) -> EnemyBase:
	var e: EnemyBase = load("res://scenes/entities/XieXiuEnemy.tscn").instantiate() as EnemyBase
	e.global_position = _player.global_position + Vector2(0.0, dist)
	_world.add_child(e)
	return e

## 钉在该点推进 0.6s（不到 _bolt_timer 初值 1.2s，不放火球污染场景），读走位与意图
func _probe_intent(dist: float) -> Dictionary:
	var e := _spawn_xiexiu(dist)
	var pin := _player.global_position + Vector2(0.0, dist)
	var t := 0.0
	var dot := 0.0
	while t < 0.6:
		e.global_position = pin
		await get_tree().physics_frame
		t += maxf(e.get_physics_process_delta_time(), 0.0)
		dot = e.velocity.dot((_player.global_position - e.global_position).normalized())
	var out := {
		"dot": dot,
		"retreating": dot < -1.0,
		"closing": dot > 1.0,
		"intent": float(e.anim_sprite.get_meta(&"hover_intent", 0.0)),
	}
	e.queue_free()
	await get_tree().physics_frame
	return out
