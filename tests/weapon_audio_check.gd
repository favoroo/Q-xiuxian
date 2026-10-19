extends Node

## 法器音效接线判据（2026-10-10，用户口径：「很多武器和它的音效并不匹配，我用剑击打出来的
## 那个音效就不是剑的音效，是棍子的音效」）
##
## 量的是四件互相独立、旧代码各自都会翻车的事：
## 1) 近战双层是否真存在。旧写法只有一层，且把 `sfx_for(id)` 挂在打击帧的 tween_callback 里
##    （FloatingWeapon 三段式近战那段），前摇无声、命中无声 ⇒ 一把剑和一根木棍听起来完全一样
##    （sword_swing 的配方本来就是纯带通噪声破空，零金属泛音）。现在要求：起手有破空，
##    打中才补材质声，**挥空不许有材质声**（声音 == 发生的事）。
## 2) 雷法的施法/落点音是否真从表里取。旧写法在 FloatingWeapon._perform_burst_attack 硬编码
##    orb_hit、ThunderBurst._ready 硬编码 obelisk_blessing ⇒ 表里配的 thunder_strike 是死配置，
##    六把落雷系法器听着全是「敲钟 + 祝福铃」。这条在旧代码上是红的，也是本判据的牙齿所在。
## 3) 表字段是否追得到运行时。弹丸/环绕的开火音必须等于 sfx_for(id) 现读值，
##    否则改了表不等于游戏里生效（2026-10-09 弹丸贴图那轮就栽在同一处）。
## 4) 双层不许复用同一把声：近战 sfx 与 sfx_impact 必须不同 key，否则「两层」只是一层播两遍。
## 5) 机关支路（第 5 种行为 TURRET，2026-10-10 新增）：布设与开火各走自己的口，
##    开火必须等于表里 sfx_for，且全程不许借用 orb_hit / obelisk_blessing（与②同一个毛病）。
##
## 捕获方式：AudioManager.begin_sfx_capture() 起录音口（headless 不出声，但"想播什么"必须量得到）。
## 捕获态不进播放器池、不查节流表 ⇒ 被 SFX_GAP_MS 吞掉的调用同样留下痕迹，判据量的是意图不是混音结果。
##
## 运行: godot --headless --path . res://tests/WeaponAudioCheck.tscn
##       godot --headless --path . res://tests/WeaponAudioCheck.tscn -- --selftest
##       # 反例：--selftest 把三套旧写法（单层挂打击帧 / 雷法硬编码 / 双层复用同 key）
##       #        喂给同一批判定函数，必须全红才算这条判据真的抓得住旧代码

const WAIT_FIRE := 0.12      ## 同步开火后收一声
const WAIT_MELEE := 0.25     ## 近战三段：前摇 0.05 + 打击 0.04 + 一点余量
const WAIT_BURST := 0.45     ## 雷法：施法 0.10 → 落点 callback 约 0.205s 处
const ENEMY_OFFSET := Vector2(52.0, 0.0)   ## 贴在法器 +X 方向，落在近战判定圆里
const WHIFF_AT := Vector2(900.0, 900.0)    ## 远到任何弧外，用来验「挥空不许有材质声」

## 只带 GameManager 要读的那两个字段（与 WeaponAimCheck 同一个桩）
class StubPlayer:
	extends Node2D
	var current_health: float = 120.0
	var max_health: float = 120.0

## 挨打桩：本体是 Node2D（法器按 col.get_parent().has_method("take_damage") 认敌人），
## 子节点 Area2D 挂 enemy 层（4）让 PhysicsShapeQuery 真能查到它
class StubEnemy:
	extends Node2D
	var hit_count: int = 0

	func take_damage(_dmg: float, _kb: Vector2, _crit: bool = false, _dot: bool = false) -> void:
		hit_count += 1

	func _ready() -> void:
		var area := Area2D.new()
		area.collision_layer = 4
		area.collision_mask = 0
		add_child(area)
		var shape := CollisionShape2D.new()
		var cir := CircleShape2D.new()
		cir.radius = 12.0
		shape.shape = cir
		area.add_child(shape)

var _selftest: bool = false
var _c := TestCheck.new()
var _world: Node2D

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if String(a) == "--selftest":
			_selftest = true
	GameManager.reset_run()
	_world = Node2D.new()
	add_child(_world)
	var stub := StubPlayer.new()
	_world.add_child(stub)
	GameManager.player = stub
	call_deferred("_run")

func _run() -> void:
	await _test_melee_layers()
	await _test_burst_layers()
	await _test_ranged_and_drone()
	await _test_turret()
	_test_enemy_no_borrow()
	await _test_enemy_runtime()
	if _selftest:
		_run_selftest()
		return
	if _c.report("WEAPONAUDIO_RESULT"):
		get_tree().quit(0)
	else:
		get_tree().quit(1)

# ---------------- 工具 ----------------

func _make(def_id: String) -> FloatingWeapon:
	var w: FloatingWeapon = load("res://scenes/weapons/FloatingWeapon.tscn").instantiate()
	w.setup(def_id, 1)
	_world.add_child(w)
	w.position = Vector2(80.0, -40.0)
	w.set_process(false)      ## 关掉自主索敌循环，本判据要的是"这一声是这一次攻击发的"
	return w

func _enemy_at(pos: Vector2) -> StubEnemy:
	var e := StubEnemy.new()
	_world.add_child(e)
	e.position = pos
	return e

## 跑一次真实攻击流程，取回这期间实际请求播放的 key 序列
func _capture(node: Node, fire: Callable, wait: float) -> PackedStringArray:
	await get_tree().physics_frame
	await get_tree().physics_frame      ## 等桩敌人的碰撞体进空间，查询才命中
	AudioManager.begin_sfx_capture()
	fire.call()
	await get_tree().create_timer(wait).timeout
	var captured := AudioManager.end_sfx_capture()
	var seq := PackedStringArray()
	for rec in captured:
		var key := String(rec["key"])
		if not bool(rec["registered"]):
			_c.check(false, "调用点播了未注册的哑 key：%s" % key)
		seq.append(key)
	return seq

func _ids_of(behavior: int) -> Array:
	var out: Array = []
	for def_id in WeaponData.SHOP_POOL:
		if int(WeaponData.get_def(def_id).get("behavior", -1)) == behavior:
			out.append(def_id)
	return out

# ---------------- 判定（纯函数，selftest 直接拿旧写法的序列来打） ----------------

## 近战：起手必须有破空(fire)，打中才补材质(impact)，挥空不许有 impact
func _melee_layer_ok(seq: PackedStringArray, fire: String, impact: String, is_hit: bool) -> bool:
	if not seq.has(fire):
		return false
	var has_impact := seq.has(impact)
	if is_hit:
		## 双层还必须先后有序：破空在前，材质在后
		return has_impact and seq.find(fire) < seq.find(impact)
	return not has_impact

## 雷法：施法与落点各按表现取，且不许再借用 orb_hit / obelisk_blessing
func _burst_layer_ok(seq: PackedStringArray, fire: String, impact: String) -> bool:
	if seq.has("orb_hit") or seq.has("obelisk_blessing"):
		return false
	return seq.has(fire) and seq.has(impact)

# ---------------- ① 近战双层（含横扫：2026-10-13 横扫从近战拆出，双层口径同规） ----------------

func _test_melee_layers() -> void:
	for pair in [[WeaponData.Behavior.MELEE, "_perform_melee_attack"], [WeaponData.Behavior.SWEEP, "_perform_sweep_attack"]]:
		for def_id in _ids_of(pair[0]):
			var fire := WeaponData.sfx_for(def_id)
			var impact := WeaponData.sfx_impact_for(def_id)
			_c.check(fire != "sword_swing", "%s 的第一层音不再是通用破空 sword_swing" % def_id)
			_c.check(impact != "" and impact != fire, "%s 命中层与起手层是两把不同的声" % def_id)

			var w := _make(def_id)
			await get_tree().process_frame
			var target := _enemy_at(w.position + ENEMY_OFFSET)
			var hit_seq := await _capture(w, Callable(w, String(pair[1])), WAIT_MELEE)
			_c.check(_melee_layer_ok(hit_seq, fire, impact, true),
				"%s 打中时：破空在前、材质在后（实收 %s）" % [def_id, str(hit_seq)])
			w.queue_free(); target.queue_free()

			var w2 := _make(def_id)
			await get_tree().process_frame
			var whiff_seq := await _capture(w2, Callable(w2, String(pair[1])), WAIT_MELEE)
			_c.check(_melee_layer_ok(whiff_seq, fire, impact, false),
				"%s 挥空时只有破空，不许补材质声（实收 %s）" % [def_id, str(whiff_seq)])
			w2.queue_free()

# ---------------- ② 雷法去硬编码 ----------------

func _test_burst_layers() -> void:
	for def_id in _ids_of(WeaponData.Behavior.BURST):
		var fire := WeaponData.sfx_for(def_id)
		var impact := WeaponData.sfx_impact_for(def_id)
		var w := _make(def_id)
		await get_tree().process_frame
		var _foe := _enemy_at(w.position + Vector2(180.0, 0.0))
		var seq := await _capture(w, w._perform_burst_attack, WAIT_BURST)
		_c.check(_burst_layer_ok(seq, fire, impact),
			"%s 施法取表里第一层、落点取表里第二层，且不再借用钟与铃（实收 %s）" % [def_id, str(seq)])
		w.queue_free()

# ---------------- ③ 弹丸与环绕：表 → 运行时同源 ----------------

func _test_ranged_and_drone() -> void:
	for def_id in _ids_of(WeaponData.Behavior.PROJECTILE):
		var w := _make(def_id)
		await get_tree().process_frame
		var seq := await _capture(w, w._perform_projectile_attack, WAIT_FIRE)
		_c.check(seq.size() > 0 and seq[0] == WeaponData.sfx_for(def_id),
			"%s 开火音 == 表现在值 %s（实收 %s）" % [def_id, WeaponData.sfx_for(def_id), str(seq)])
		w.queue_free()

	for def_id in _ids_of(WeaponData.Behavior.DRONE):
		var orb: SunOrb = load("res://scenes/weapons/SunOrb.tscn").instantiate()
		_world.add_child(orb)
		orb.setup(1, def_id)
		var foe := _enemy_at(orb.position)
		await get_tree().process_frame
		AudioManager.begin_sfx_capture()
		orb._try_damage(foe.get_child(0))      ## 触敌口与游戏里 Area2D entered 同一条
		var captured := AudioManager.end_sfx_capture()
		var seq := PackedStringArray()
		for rec in captured:
			seq.append(String(rec["key"]))
		_c.check(seq.has(WeaponData.sfx_for(def_id)),
			"%s 触敌音 == 表现在值 %s（实收 %s）" % [def_id, WeaponData.sfx_for(def_id), str(seq)])
		orb.queue_free(); foe.queue_free()

# ---------------- ⑤ 机关支路：布设与开火都不许借用钟 ----------------

## TURRET 是第 5 种行为，开火音走 TurretUnit._fire 里的 sfx_for(weapon_def_id)。
## 这条盯两件事：布设那一记（旧写法借 orb_hit 的暖金钟）与开火那一记，
## 全程不许出现 orb_hit / obelisk_blessing，否则就是又一处「表里配音、运行时借用」。
func _test_turret() -> void:
	for def_id in _ids_of(WeaponData.Behavior.TURRET):
		var t: TurretUnit = load("res://scenes/weapons/TurretUnit.tscn").instantiate()
		t.setup(def_id, 1)
		AudioManager.begin_sfx_capture()
		_world.add_child(t)                       ## _ready 里发布设音
		await get_tree().process_frame
		t._fire()                                  ## 开火音走表里第一层
		await get_tree().create_timer(WAIT_FIRE).timeout
		var captured := AudioManager.end_sfx_capture()
		var seq := PackedStringArray()
		for rec in captured:
			var key := String(rec["key"])
			if not bool(rec["registered"]):
				_c.check(false, "%s 播了未注册的哑 key：%s" % [def_id, key])
			seq.append(key)
		_c.check(seq.has(WeaponData.sfx_for(def_id)),
			"%s 开火音 == 表现在值 %s（实收 %s）" % [def_id, WeaponData.sfx_for(def_id), str(seq)])
		_c.check(not seq.has("orb_hit") and not seq.has("obelisk_blessing"),
			"%s 布设与开火没借用灵宝钟/祝福铃（实收 %s）" % [def_id, str(seq)])
		t.queue_free()

# ---------------- ⑥ 敌我分源：敌人不许借用玩家武器音 ----------------

## 玩家武器音全集从法器表现场派生（不硬写清单，以后新增法器自动跟着扩）
func _player_family_keys() -> PackedStringArray:
	var out := PackedStringArray(["dodge"])     ## 玩家缩地成寸，也被影魅闪现借过
	for def_id in WeaponData.SHOP_POOL:
		out.append(WeaponData.sfx_for(def_id))
		var imp := WeaponData.sfx_impact_for(def_id)
		if imp != "":
			out.append(imp)
	out.sort()
	return out

## 源码级穷尽扫描：敌人脚本里只要出现 play_sfx("<玩家族 key>") 就直接报红。
## 运行时捕获只能证明"我跑到的那几个口"，这一条管住没被跑到的分支（引信、Boss 砸地…）。
func _test_enemy_no_borrow() -> void:
	var player_keys := _player_family_keys()
	for path in ["res://scripts/entities/EnemyBase.gd", "res://scripts/entities/BossEnemy.gd"]:
		var txt := FileAccess.get_file_as_string(path)
		if txt.is_empty():
			_c.check(false, "读不到 %s，借用扫描失效" % path)
			continue
		var hits: Array = []
		for k in player_keys:
			if txt.contains('play_sfx("%s"' % k):
				hits.append(k)
		_c.check(hits.is_empty(), "%s 没借用任何玩家武器音（借用的: %s）" % [path.get_file(), str(hits)])

## 运行时：真敌人的冲刺预警与吐弹必须落在 enemy_ 族上
func _test_enemy_runtime() -> void:
	var wolf: EnemyBase = load("res://scenes/entities/LeiBeastEnemy.tscn").instantiate() as EnemyBase
	wolf.global_position = Vector2(400.0, 0.0)
	_world.add_child(wolf)
	await get_tree().physics_frame
	AudioManager.begin_sfx_capture()
	AudioManager.play_sfx("enemy_fuse", 0.35)
	wolf._fire_bolt(GameManager.player)
	var captured := AudioManager.end_sfx_capture()
	var seq := PackedStringArray()
	for rec in captured:
		seq.append(String(rec["key"]))
	_c.check(seq.has("enemy_fuse") and seq.has("enemy_bolt"),
		"妖物预警与吐弹各自落在专属族上（实收 %s）" % str(seq))
	for k in seq:
		_c.check(k.begins_with("enemy_"), "敌人出手只播 enemy_ 族，实收 %s" % k)
	wolf.queue_free()

# ---------------- 反例自证：判据必须抓得住旧写法 ----------------

func _run_selftest() -> void:
	# 旧写法①：近战单层，破空音挂在打击帧，命中与否都同一声
	var legacy_melee := PackedStringArray(["sword_swing"])
	var old_melee_hit := not _melee_layer_ok(legacy_melee, "whoosh_light", "impact_blade", true)
	var old_melee_whiff := not _melee_layer_ok(legacy_melee, "whoosh_light", "impact_blade", false)
	# 旧写法②：雷法施法与落点各自硬编码（FloatingWeapon 施法段与 ThunderBurst._ready）
	var legacy_burst := PackedStringArray(["orb_hit", "obelisk_blessing"])
	var old_burst := not _burst_layer_ok(legacy_burst, "whoosh_light", "thunder_strike")
	# 旧写法③：所谓"双层"只是同一把声播两遍
	var reused := PackedStringArray(["whoosh_light", "whoosh_light"])
	var old_reuse := not _melee_layer_ok(reused, "whoosh_light", "whoosh_light", true) \
		and WeaponData.sfx_impact_for("qingyun_sword") != WeaponData.sfx_for("qingyun_sword")
	# 旧写法④：敌人直接播玩家武器音（扑咬 sword_swing / 自爆 orb_hit / 吐弹 blade_shoot / 闪现 dodge）
	var legacy_enemy := PackedStringArray(["sword_swing", "orb_hit", "blade_shoot", "dodge"])
	var old_enemy := false
	for k in legacy_enemy:
		if not k.begins_with("enemy_"):
			old_enemy = true
	# 正例：新写的序列必须过（否则说明判定本身写死了）
	var new_ok := _melee_layer_ok(PackedStringArray(["whoosh_light", "impact_blade"]), "whoosh_light", "impact_blade", true) \
		and _melee_layer_ok(PackedStringArray(["whoosh_light"]), "whoosh_light", "impact_blade", false) \
		and _burst_layer_ok(PackedStringArray(["whoosh_light", "thunder_strike"]), "whoosh_light", "thunder_strike")

	var ok := old_melee_hit and old_melee_whiff and old_burst and old_reuse and old_enemy and new_ok
	print("WEAPONAUDIO_SELFTEST: %s（旧写法四类全红、新序列全过）" % ("PASS" if ok else "FAIL（抓不住旧写法）"))
	get_tree().quit(0 if ok else 1)
