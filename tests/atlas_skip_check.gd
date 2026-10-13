extends Node

## 程序化渲染不加载图集判据（2026-10-13 内存优化）：
##   背景：全部 19 位修士与 14 种敌人均已切程序化矢量渲染，但 _ready 仍无条件
##   load 960×960 八方向图集并建 SpriteFrames（单张解码后 3.5MB，合计约 70MB 常驻），
##   而屏上角色实际只有 120~145px —— 图集是纯死重。
## 本判据钉住三条不变量：
##   1. 程序化敌人 / 修士的 anim_sprite 不带 sprite_frames（图集不加载）
##   2. 敌人共享帧集缓存保持为空（cache_size == 0）—— 这是「没白建」的直接证据
##   3. anim_sprite 作为形变状态载体的链路仍然通：步态/悬浮/蠕动照常写 scale·offset，
##      并转发给 procedural_view（否则角色会变成一动不动）
## 运行: godot --headless --path . res://tests/AtlasSkipCheck.tscn
## 退出码 0 且末行 ATLAS_SKIP_RESULT: ALL PASS

var _c := TestCheck.new()

## 断言与输出格式统一走 tests/check.gd
func _check(cond: bool, label: String) -> void:
	_c.check(cond, label)

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	await _test_enemy_skips_atlas()
	await _test_enemy_frame_cache_empty()
	await _test_gait_state_carrier_still_works()
	await _test_player_skips_atlas()
	_test_pooled_frames_still_available()

	if not _c.all_passed():
		print("ATLAS_SKIP_RESULT: FAILED (%d failures)" % _c.failures.size())
		get_tree().quit(1)
	else:
		print("ATLAS_SKIP_RESULT: ALL PASS (%d checks)" % _c.passed)
		get_tree().quit(0)

## 1. 程序化敌人的 anim_sprite 不该带帧集（图集没加载）
func _test_enemy_skips_atlas() -> void:
	GameManager.reset_run()
	var world := Node2D.new()
	add_child(world)
	EnemyBase.clear_frame_cache()

	# 逐个覆盖有 spritesheet_path 的敌种：它们原本都会 load 图集
	var ids: Array[String] = [
		"SlimeEnemy", "DanBaoEnemy", "XieXiuEnemy", "FlowerEnemy", "LeiBeastEnemy",
		"BossEnemy", "ChileiEliteEnemy", "GolemEnemy", "GuYaoEnemy", "YingMeiEnemy",
		"ZhuMuEnemy", "XueYongEnemy", "FengQunEnemy", "JianshaEliteEnemy",
	]
	var leaked: Array[String] = []
	for id in ids:
		var path := "res://scenes/entities/%s.tscn" % id
		if not ResourceLoader.exists(path):
			continue
		var e := (load(path) as PackedScene).instantiate() as EnemyBase
		world.add_child(e)
		await get_tree().process_frame
		if e.anim_sprite.sprite_frames != null:
			leaked.append(id)
		# 程序化视图必须挂上，否则就是「图集没加载、矢量也没画」的黑洞
		_check(e.procedural_view != null, "%s 已挂程序化视图" % id)
		_check(e.procedural_view != null and e.procedural_view.config != null,
			"%s 程序化配置非空（决定图集可跳过）" % id)
		_check(not e.anim_sprite.visible, "%s 旧 anim_sprite 保持隐藏" % id)
		world.remove_child(e)
		e.free()

	_check(leaked.is_empty(),
		"程序化敌人不加载图集（实际泄漏 %d 个：%s）" % [leaked.size(), ", ".join(leaked)])

	world.queue_free()

## 2. 帧集缓存保持空 —— 图集一张都没解码，这是内存收益的直接证据
func _test_enemy_frame_cache_empty() -> void:
	EnemyBase.clear_frame_cache()
	var world := Node2D.new()
	add_child(world)
	for i in range(4):
		var e := (load("res://scenes/entities/SlimeEnemy.tscn") as PackedScene).instantiate() as EnemyBase
		world.add_child(e)
		await get_tree().process_frame
	_check(EnemyBase.cache_size() == 0,
		"共享帧集缓存为空（实际 %d 套 —— 非 0 说明图集仍被加载）" % EnemyBase.cache_size())
	for ch in world.get_children():
		ch.free()
	world.queue_free()

## 3. anim_sprite 仍是形变状态载体：链路断了角色就不动
func _test_gait_state_carrier_still_works() -> void:
	var world := Node2D.new()
	add_child(world)
	# 史莱姆是 slither（蠕动），用它的 scale 伸缩当探针
	var e := (load("res://scenes/entities/SlimeEnemy.tscn") as PackedScene).instantiate() as EnemyBase
	world.add_child(e)
	await get_tree().process_frame

	var base_scale: Vector2 = e.anim_sprite.scale
	# 直接喂位移驱动步态：无帧集时 RunMotion 内部按默认 4 帧 / 10fps 推进相位
	e.velocity = Vector2(60.0, 0.0)
	for i in range(20):
		e._update_facing_and_anim(0.05, Vector2(1.0, 0.0), 3600.0)
	var moved: bool = not e.anim_sprite.scale.is_equal_approx(base_scale) \
		or not is_zero_approx(e.anim_sprite.offset.y)
	_check(moved, "无帧集时步态形变照常推进（scale/offset 有变化）")
	# 转发给 procedural_view 的口径必须一致
	_check(e.procedural_view != null and e.procedural_view.scale.is_equal_approx(e.anim_sprite.scale),
		"形变已转发给 procedural_view（矢量视图与状态载体同源）")

	world.remove_child(e)
	e.free()
	world.queue_free()

## 4. 玩家：程序化道统不加载图集，且矢量视图正常工作
func _test_player_skips_atlas() -> void:
	GameManager.cultivator_id = "fuzhen"
	var p := (load("res://scenes/entities/Player.tscn") as PackedScene).instantiate() as Player
	add_child(p)
	await get_tree().process_frame

	_check(p.is_procedural, "fuzhen 进入 procedural 分支")
	_check(p.anim_sprite.sprite_frames == null,
		"程序化修士不加载图集（sprite_frames 应为 null）")
	_check(p.procedural_view != null and p.procedural_view.visible, "procedural_view 正常显示")
	_check(p.procedural_view != null and p.procedural_view.renderer != null, "渲染器已装配")

	# 受击闪白材质仍可用（它来自 anim_sprite.material，与 sprite_frames 无关）
	_check(p.hit_flash_mat != null, "受击闪白材质仍可解析（不依赖图集）")

	p.queue_free()

## 5. 兜底路径仍在：无程序化配置时图集帧集可以正常构建（防将来新增 gait 敌种踩空）
func _test_pooled_frames_still_available() -> void:
	EnemyBase.clear_frame_cache()
	var sf := EnemyBase._shared_frames("res://assets/art/pawn_red_8dir.png", false)
	_check(sf != null, "兜底：显式取帧集仍可构建（无程序化配置的敌种走这条）")
	_check(sf != null and sf.has_animation("run_s"), "兜底帧集含 run_s 动画")
	_check(EnemyBase.cache_size() == 1, "兜底路径仍走共享缓存")
	EnemyBase.clear_frame_cache()
