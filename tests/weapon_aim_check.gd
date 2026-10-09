extends Node

## 法器「朝向 + 出膛点」判据（2026-10-09，用户口径：「庚金飞剑发射东西的时候朝向不对，并没有正确
## 朝向敌人。发射应该是从它的剑尖那里发射出去才合理，现在不知道从哪里发射出来的」）
##
## 量的是三件互相独立、旧代码各自都会翻车的事：
## 1) 画出来的剑尖指哪儿 —— 把贴图坐标系里标定的 tip 按引擎的变换链（本体转角 + 贴图补偿 +
##    flip_v 镜像 + 缩放）反算回世界坐标，要求它和瞄准轴重合。旧写法只转本体、贴图不补偿，
##    天生朝右上 35° 的飞剑永远偏着 35° ⇒ 这条直接红。
## 2) 弹丸从哪儿出膛 —— 出膛点必须落在 1) 算出来的那个剑尖上（会转的法器），或落在瞄准轴的
##    器口半径上（保持竖直的重器）。旧写法 MuzzlePoint 钉在 Sprite2D 里 (20,0)，正落在剑格上。
## 3) 出膛的到底是什么 —— 五把远程法器的弹丸贴图必须各自不同且等于表里的 bullet。
##    2026-10-08 那轮"飞剑出飞剑、火符出火符"只改了表和弹丸脚本，出膛那一圈从来没读表，
##    运行时五把法器打出去的全是同一张公共火符（这条在旧代码上是红的）。
##
## 另外钉两条顺手修的同源问题：
## 4) 近战弧光的月牙外缘 == 那一帧查询圆的半径（画多大==判多大）。
## 5) 弹丸转不转由表里的 bullet_spin 说了算（玄冰飞针写的是 false，旧代码按穿透数反推 ⇒ 在乱转）。
##
## 运行: godot --headless --path . res://tests/WeaponAimCheck.tscn
##       godot --headless --path . res://tests/WeaponAimCheck.tscn -- --selftest
##       # 反例：把飞剑的补偿角清零，第 1 条必须报红 —— 用来证明这条断言真的有牙齿

const DIRS_DEG := [0.0, 45.0, 90.0, 135.0, 180.0, -135.0, -90.0, -45.0]
const TOL_DEG := 2.0        ## 剑尖指向与瞄准轴的允许误差
const TOL_PX := 1.0         ## 出膛点与"画出来的剑尖"的允许误差
const TARGET_AT := Vector2(300.0, 120.0)   ## 开火台的目标：斜向，八方向里最容易露馅的那种
const SLASH_ART_HALF_DEG := 70.0    ## slash_effect.png 那弯月牙自身的张角（极坐标量出来 ±70°、半径 24..31）

## 只带 GameManager 要读的那两个字段：get_player_stat_dict() 会去 player 身上取血量算词条
class StubPlayer:
	extends Node2D
	var current_health: float = 120.0
	var max_health: float = 120.0

var _selftest: bool = false
var _c := TestCheck.new()
var _world: Node2D

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	for a in args:
		if String(a) == "--selftest":
			_selftest = true
	GameManager.reset_run()
	_world = Node2D.new()
	_world.name = "World"
	add_child(_world)
	# 一个不带碰撞的桩玩家：FloatingWeapon 的索敌/分配都要读 player.global_position
	var stub := StubPlayer.new()
	_world.add_child(stub)
	GameManager.player = stub
	call_deferred("_run")

func _run() -> void:
	_test_table()
	await _test_facing()
	await _test_projectile_bay()
	await _test_melee_arc()
	if _selftest:
		_run_selftest()
		return
	if _c.report("WEAPONAIM_RESULT"):
		get_tree().quit(0)
	else:
		get_tree().quit(1)

# ---------------- 数据表标定 ----------------

## 每件会转/会射的法器都得在表里标定 tip（不许靠兜底值混过去）；环绕类走 SunOrb，本体不转，不算。
func _test_table() -> void:
	var unmarked: Array[String] = []
	var bogus: Array[String] = []
	for def_id in WeaponData.SHOP_POOL:
		var def := WeaponData.get_def(def_id)
		if int(def.get("behavior", -1)) == WeaponData.Behavior.DRONE:
			continue
		if not def.has("tip"):
			unmarked.append(def_id)
			continue
		var tip: Vector2 = def["tip"]
		# 图标都是 48×48，画布中心到角 = 33.9：标定值超出这个量级就是写错了坐标系
		if tip.length() <= 6.0 or tip.length() > 34.0:
			bogus.append("%s(%s)" % [def_id, str(tip)])
	_c.check(unmarked.is_empty(), "非环绕法器全部在 WeaponData 里标定了 tip（未标定: %s）" % str(unmarked))
	_c.check(bogus.is_empty(), "tip 落在 48×48 画布的合理量级内（异常: %s）" % str(bogus))
	var no_spin: Array[String] = []
	for def_id in WeaponData.SHOP_POOL:
		var def := WeaponData.get_def(def_id)
		if int(def.get("behavior", -1)) == WeaponData.Behavior.PROJECTILE and not def.has("bullet_spin"):
			no_spin.append(def_id)
	_c.check(no_spin.is_empty(), "每把弹丸法器都显式声明 bullet_spin（缺: %s）" % str(no_spin))

# ---------------- 朝向 / 出膛点 ----------------

## 引擎真正画出来的剑尖在世界哪儿：贴图坐标系 tip → flip_v 纵向镜像 → 世界变换
## （global_transform 已经带上了 Sprite2D 自己的 0.55 缩放，这里不许再乘一次）
func _drawn_tip(w: FloatingWeapon) -> Vector2:
	var spr: Sprite2D = w.sprite
	var tip: Vector2 = w.tip_local
	if spr.flip_v:
		tip.y = -tip.y
	return spr.global_position + spr.global_transform.basis_xform(tip)

## 画出来的剑尖方位与瞄准轴差多少度
func _facing_err(w: FloatingWeapon, aim: float) -> float:
	var v := _drawn_tip(w) - w.global_position
	if v.length_squared() < 0.0001:
		return 180.0
	return rad_to_deg(absf(angle_difference(v.angle(), aim)))

func _make(def_id: String) -> FloatingWeapon:
	var w: FloatingWeapon = load("res://scenes/weapons/FloatingWeapon.tscn").instantiate()
	w.setup(def_id, 1)
	_world.add_child(w)
	w.position = Vector2(80.0, -40.0)
	# 关掉自主循环：本判据要的是"给定瞄准角，画出来对不对"，不是让它自己索敌自己开火
	w.set_process(false)
	return w

## 八方向逐件量：会转的法器要求"画出来的剑尖 == 瞄准轴"且"出膛点 == 那个剑尖"；
## upright 的重器反过来 —— 本体必须保持世界竖直，出膛点落在瞄准轴上的器口半径处。
func _test_facing() -> void:
	for def_id in WeaponData.SHOP_POOL:
		var def := WeaponData.get_def(def_id)
		if int(def.get("behavior", -1)) == WeaponData.Behavior.DRONE:
			continue
		var w := _make(def_id)
		await get_tree().process_frame
		var upright := bool(def.get("upright", false))
		var worst_face := 0.0
		var worst_muzzle := 0.0
		var worst_upright := 0.0
		for d in DIRS_DEG:
			var aim := deg_to_rad(float(d))
			w._apply_facing(aim)
			var muz: Vector2 = w.muzzle_point.global_position - w.global_position
			if upright:
				var want := Vector2.RIGHT.rotated(aim) * (w.tip_local.length() * w.sprite.scale.x)
				worst_muzzle = maxf(worst_muzzle, muz.distance_to(want))
				worst_upright = maxf(worst_upright, rad_to_deg(absf(angle_difference(w.sprite.global_rotation, 0.0))))
			else:
				worst_face = maxf(worst_face, _facing_err(w, aim))
				worst_muzzle = maxf(worst_muzzle, w.muzzle_point.global_position.distance_to(_drawn_tip(w)))
		var label := "%s(%s)" % [String(def.get("name", "?")), def_id]
		if upright:
			_c.near(worst_muzzle, 0.0, TOL_PX, "%s 出膛点在瞄准轴的器口半径上（最大偏差 %.2fpx）" % [label, worst_muzzle])
			_c.near(worst_upright, 0.0, TOL_DEG, "%s 本体保持世界竖直（最大偏转 %.2f°）" % [label, worst_upright])
		else:
			_c.near(worst_face, 0.0, TOL_DEG, "%s 八方向剑尖指向与瞄准轴重合（最大偏差 %.2f°）" % [label, worst_face])
			_c.near(worst_muzzle, 0.0, TOL_PX, "%s 出膛点正落在画出来的剑尖上（最大偏差 %.2fpx）" % [label, worst_muzzle])

# ---------------- 开火台：弹丸从剑尖出、朝敌人飞、各是各的样子 ----------------

func _spawned() -> Array[BladeProjectile]:
	var out: Array[BladeProjectile] = []
	for c in get_tree().current_scene.get_children():
		var p := c as BladeProjectile
		if p != null:
			out.append(p)
	return out

func _test_projectile_bay() -> void:
	var used_textures := {}
	var checked := 0
	for def_id in WeaponData.SHOP_POOL:
		var def := WeaponData.get_def(def_id)
		if int(def.get("behavior", -1)) != WeaponData.Behavior.PROJECTILE:
			continue
		var w := _make(def_id)
		await get_tree().process_frame
		var target := Node2D.new()
		target.position = TARGET_AT
		_world.add_child(target)
		w.current_target = target
		var aim := w._aim_at(target.global_position)
		w._apply_facing(aim)
		var tip := _drawn_tip(w)
		w._perform_projectile_attack()
		var shots := _spawned()
		var count := maxi(1, int(def.get("projectile_count", 1)))
		var label := "%s(%s)" % [String(def.get("name", "?")), def_id]
		_c.equals(shots.size(), count, "%s 一次开火出膛 %d 发" % [label, count])
		var worst_pos := 0.0
		var worst_dir := 0.0
		var sum_dir := Vector2.ZERO
		for p in shots:
			worst_pos = maxf(worst_pos, p.global_position.distance_to(tip))
			var to_target: Vector2 = target.global_position - p.global_position
			worst_dir = maxf(worst_dir, rad_to_deg(absf(angle_difference(p.direction.angle(), to_target.angle()))))
			sum_dir += p.direction.normalized()
			# 出膛点离本体中心的距离 = 标定值 × 贴图缩放（钉住"从剑尖出"而不是"从中心出"）
			_c.check(p.global_position.distance_to(w.global_position) > 6.0,
				"%s 弹丸不从本体圆心冒出来（实得 %.1fpx）" % [label, p.global_position.distance_to(w.global_position)])
		_c.near(worst_pos, 0.0, TOL_PX, "%s 弹丸从画出来的剑尖出膛（最大偏差 %.2fpx）" % [label, worst_pos])
		# 一次 n 发是"照着目标扇形错开"的：单发最大偏角 = spread×(n-1)/2，整轮合成的方向必须正对目标
		var fan := rad_to_deg(float(def.get("spread_angle", 0.0)) * float(count - 1) * 0.5) + 2.0
		_c.near(worst_dir, 0.0, fan, "%s 每一发都咬在目标方位的扇形包络内（最大偏角 %.2f°，包络 %.2f°）" % [label, worst_dir, fan])
		_c.near(rad_to_deg(absf(angle_difference(sum_dir.angle(), w._aim_at(target.global_position)))), 0.0, 2.0,
			"%s 一轮合成的中心方向正对目标" % label)
		var tex_path := ""
		for p in shots:
			var tex: Texture2D = p.sprite.texture
			tex_path = String(tex.resource_path) if tex != null else ""
			_c.equals(p.spin, bool(def.get("bullet_spin", false)),
				"%s 弹丸自旋按表（bullet_spin=%s，实得 %s）" % [label, str(def.get("bullet_spin", false)), str(p.spin)])
			break
		var want_path := String(def.get("bullet", ""))
		_c.equals(tex_path, want_path, "%s 弹丸外观 = 表里那张（%s）" % [label, want_path.get_file()])
		used_textures[tex_path] = String(def.get("name", "?"))
		checked += 1
		for p in shots:
			p.free()
	# 旧 bug 的总账：五把远程法器共用一张公共火符 ⇒ 去重后只剩 1 种
	_c.equals(used_textures.size(), checked,
		"%d 把远程法器的弹丸外观两两不同（实得 %d 种: %s）" % [checked, used_textures.size(), str(used_textures.values())])

# ---------------- 近战弧光与判定同源 ----------------

func _test_melee_arc() -> void:
	for def_id in WeaponData.SHOP_POOL:
		var def := WeaponData.get_def(def_id)
		if int(def.get("behavior", -1)) != WeaponData.Behavior.MELEE:
			continue
		var w := _make(def_id)
		await get_tree().process_frame
		var target := Node2D.new()
		target.position = TARGET_AT
		_world.add_child(target)
		w.current_target = target
		w._perform_melee_attack()
		var judged := w._melee_arc_radius()
		var drawn := FloatingWeapon.SLASH_ART_OUTER * w.slash_sprite.scale.x
		var label := "%s(%s)" % [String(def.get("name", "?")), def_id]
		_c.near(drawn, judged, 0.5, "%s 弧光外缘 == 判定圆半径（判定 %.1fpx，画到 %.1fpx）" % [label, judged, drawn])
		_c.equals(w.slash_sprite.position, Vector2(FloatingWeapon.MELEE_LUNGE, 0.0),
			"%s 弧光轴心 == 判定圆心（本体前突 %s px）" % [label, str(FloatingWeapon.MELEE_LUNGE)])
		# 月牙张角 ±70°：挥砍摆幅必须小于它，那一帧打出去的方向才始终被画出来的那一片罩住
		var sweep := rad_to_deg(deg_to_rad(45.0) * w.arc_scale)
		_c.check(sweep <= SLASH_ART_HALF_DEG,
			"%s 挥砍摆幅 %.1f° 落在月牙张角 ±%.0f° 内（否则弧光罩不住判定方向）" % [label, sweep, SLASH_ART_HALF_DEG])

# ---------------- 反例：证明第 1 条断言真的有牙齿 ----------------

## 把飞剑的贴图补偿清零 = 退回 2026-10-09 之前的写法，同一套算法必须报红
func _run_selftest() -> void:
	var w := _make("gengjin_feijian")
	await get_tree().process_frame
	var aim := w._aim_at(TARGET_AT)
	w._apply_facing(aim)
	var fixed := _facing_err(w, aim)
	w.sprite.rotation = 0.0      # 旧写法：贴图不补偿，本体转多少算多少
	var broken := _facing_err(w, aim)
	print("SELFTEST 补偿后偏差 %.2f°，清零补偿后偏差 %.2f°" % [fixed, broken])
	var ok := fixed <= TOL_DEG and broken > TOL_DEG
	print("WEAPONAIM_SELFTEST: %s" % ("PASS（关掉补偿就报红，断言有牙齿）" if ok else "FAIL（这条断言抓不住旧写法）"))
	get_tree().quit(0 if ok else 1)
