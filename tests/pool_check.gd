extends Node

## 池化 / 缓存的自动化验证：分配上限、跨局复用、同种敌人共享帧集、缓存命中成本
## 运行: godot --headless --path . res://tests/PoolCheck.tscn
## 说明：这里不启动战斗，只用一个裸 Node2D 当宿主，避免刷怪自己产生跳字/特效污染计数。

var _c := TestCheck.new()

## 断言与输出格式统一走 tests/check.gd
func _check(cond: bool, label: String) -> void:
	_c.check(cond, label)

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	Engine.time_scale = 10.0
	var world := Node2D.new()
	world.name = "PoolCheckWorld"
	get_tree().root.add_child(world)
	await get_tree().process_frame

	_check(DamageNumber._scene_root_for(world) != null, "前置：池宿主可定位到场景根")

	# ---------- 1. 同种敌人共享 SpriteFrames ----------
	var slime_scene: PackedScene = load("res://scenes/entities/SlimeEnemy.tscn")
	var danbao_scene: PackedScene = load("res://scenes/entities/DanBaoEnemy.tscn")
	var e1 := slime_scene.instantiate() as EnemyBase
	var e2 := slime_scene.instantiate() as EnemyBase
	var e3 := danbao_scene.instantiate() as EnemyBase
	world.add_child(e1)
	world.add_child(e2)
	world.add_child(e3)

	var f1 := e1.anim_sprite.sprite_frames
	var f2 := e2.anim_sprite.sprite_frames
	var f3 := e3.anim_sprite.sprite_frames
	_check(f1 != null and f2 != null, "敌人帧集已构建")
	_check(f1.get_instance_id() == f2.get_instance_id(), "两只史莱姆共享同一 SpriteFrames")
	# pawn_red_8dir 同时是史莱姆与丹宝的贴图 → 也应命中同一份缓存
	_check(f1.get_instance_id() == f3.get_instance_id(), "同贴图的不同怪种也共享帧集")
	_check(EnemyBase.cache_size() == 1, "一张图只缓存一份 (实际 %d)" % EnemyBase.cache_size())

	# ---------- 2. 缓存命中成本远低于重建 ----------
	EnemyBase.clear_frame_cache()
	var t_build := Time.get_ticks_usec()
	EnemyBase._shared_frames("res://assets/art/pawn_red_8dir.png", false)
	t_build = Time.get_ticks_usec() - t_build
	var t_hit := Time.get_ticks_usec()
	EnemyBase._shared_frames("res://assets/art/pawn_red_8dir.png", false)
	t_hit = Time.get_ticks_usec() - t_hit
	_check(t_hit < t_build, "缓存命中快于重建 (%dµs vs %dµs)" % [t_hit, t_build])
	_check(EnemyBase.cache_size() == 1, "clear 后重建仍只占一份缓存")
	_check(EnemyBase._shared_frames("res://assets/art/pawn_red_8dir.png", true) != null, "精英档独立缓存键")
	_check(EnemyBase.cache_size() == 2, "精英/普通分键 (实际 %d)" % EnemyBase.cache_size())
	EnemyBase.clear_frame_cache()

	for e in [e1, e2, e3]:
		world.remove_child(e)
		e.free()

	# ---------- 3. 跳字池：分配上限 + 完全复用 ----------
	var cap: int = DamageNumber.POOL_CAP
	for i in range(60):
		DamageNumber.spawn(world, Vector2(10 * i, 20), 10 + i)
	_check(DamageNumber.created_count() == 60, "首轮创建 60 个跳字节点 (%d)" % DamageNumber.created_count())
	_check(DamageNumber.host_child_count() == 60, "跳字全部挂在池宿主下 (%d)" % DamageNumber.host_child_count())

	await get_tree().create_timer(1.0).timeout
	_check(DamageNumber.pool_size() == 60, "存活期结束后 60 个全部回池 (%d)" % DamageNumber.pool_size())

	for i in range(60):
		DamageNumber.spawn(world, Vector2(10 * i, 20), 20 + i, true)
	_check(DamageNumber.created_count() == 60, "第二轮零新建，全部复用 (%d)" % DamageNumber.created_count())

	# 超出上限：溢出节点用完即释放，不把池撑大
	for i in range(cap + 104):
		DamageNumber.spawn(world, Vector2(i, 0), i)
	_check(DamageNumber.created_count() == cap, "常驻新建数不超过 POOL_CAP (%d/%d)" % [DamageNumber.created_count(), cap])
	await get_tree().create_timer(1.0).timeout
	_check(DamageNumber.host_child_count() <= cap, "溢出节点已释放，宿主子节点数回落 (%d)" % DamageNumber.host_child_count())

	# ---------- 4. 特效池 ----------
	for i in range(40):
		JuiceEffect.spawn_hit_sparks(world, Vector2(i, i), Vector2.RIGHT, i % 5 == 0)
	_check(JuiceEffect.created_count() == 40, "首轮创建 40 个特效节点 (%d)" % JuiceEffect.created_count())
	await get_tree().create_timer(0.6).timeout
	_check(JuiceEffect.pool_size() == 40, "特效全部回池 (%d)" % JuiceEffect.pool_size())
	for i in range(40):
		JuiceEffect.spawn_death_burst(world, Vector2(i, i), i % 10 == 0)
	_check(JuiceEffect.created_count() == 40, "第二轮特效零新建 (%d)" % JuiceEffect.created_count())

	# ---------- 5. 特效并行数组：下标覆盖 + 复用归零 ----------
	var fx := JuiceEffect.new()
	world.add_child(fx)
	fx._begin(JuiceEffect.EffectType.HIT_SPARKS, Vector2.ZERO, 0.2, JuiceEffect.Z_OVERLAY)
	_check(fx._p_pos.size() == JuiceEffect.PARTICLE_SLOTS, "入树后一次性开好常驻容量 (%d)" % fx._p_pos.size())
	for i in range(12):
		fx._add_particle(Vector2.ZERO, Vector2.RIGHT, 10.0, Color.WHITE, 2.0)
	fx._add_ring(4.0, 28.0, Color.WHITE, 3.0)
	_check(fx._p_count == 12 and fx._r_count == 1, "粒子/光环按下标写入并计数 (%d/%d)" % [fx._p_count, fx._r_count])
	fx._begin(JuiceEffect.EffectType.STEP_DUST, Vector2.ONE, 0.2, JuiceEffect.Z_DUST)
	_check(fx._p_count == 0 and fx.z_index == JuiceEffect.Z_DUST, "复用后计数归零、层级重设")
	_check(fx._p_pos.size() == JuiceEffect.PARTICLE_SLOTS, "复用不清容量，仍走覆盖路径")
	world.remove_child(fx)
	fx.free()

	# ---------- 6. 缓存清理不影响运行中对象 ----------
	DamageNumber.clear_cache()
	JuiceEffect.clear_cache()
	_check(DamageNumber.created_count() == 0 and JuiceEffect.created_count() == 0, "clear_cache 归零计数")
	DamageNumber.spawn(world, Vector2(0, 0), 1)
	_check(DamageNumber.created_count() == 1, "清理后可重新建池并继续工作")

	world.free()
	Engine.time_scale = 1.0

	if _c.report("POOL_RESULT"):
		get_tree().quit(0)
	else:
		get_tree().quit(1)
