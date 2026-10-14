extends Node

## 2026-10-14 地面贴花判据（震裂/焦痕）。钉死六件事：
##   ① spawn 出膛：贴花在场、可见、不在池，active_count 记账
##   ② 震裂形态：5~7 条折线裂纹，所有折点收在包络圈 ×0.95 内（贴花版「视觉不超出名义半径」）
##   ③ 焦痕形态：多子圆聚合，所有子圆收在包络圈 ×0.95 内
##   ④ 生命周期：HOLD 留存期不回收，HOLD+FADE 走完后回池休眠（短暂留存后消失）
##   ⑤ 对象池：回收后再 spawn 复用同一实例，零新建
##   ⑥ 纯视觉：贴花没有碰撞体，不参与判定（判定在持有者侧）
## 运行: godot --headless --path . res://tests/GroundDecalCheck.tscn

var _c := TestCheck.new()
var _world: Node2D

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	Engine.time_scale = 8.0

	_world = Node2D.new()
	_world.name = "GroundDecalWorld"
	get_tree().root.add_child(_world)
	await get_tree().process_frame

	await _case_spawn()
	await _case_crack_shape()
	await _case_scorch_shape()
	await _case_lifecycle()
	await _case_pool_reuse()
	_case_pure_visual()

	print("GROUND_DECAL 判据跑完")
	Engine.time_scale = 1.0
	GroundDecal.clear_pool()
	if _c.report("GROUND_DECAL_RESULT"):
		get_tree().quit(0)
	else:
		get_tree().quit(1)

## ① spawn 出膛记账
func _case_spawn() -> void:
	var before: int = GroundDecal.active_count
	var d := GroundDecal.spawn(_world, Vector2(100, 100), GroundDecal.Kind.CRACK, 100.0)
	await get_tree().process_frame
	_c.check(d != null and is_instance_valid(d), "spawn 返回有效贴花")
	_c.check(d.visible and not d._pooled, "出膛后可见且不在池")
	_c.equals(GroundDecal.active_count, before + 1, "active_count +1")
	_c.check(GroundDecal._host.position.y == GroundDecal.GROUND_SORT_Y, "贴花宿主 Y 钉在角色之前（GROUND_SORT_Y）")
	_c.check(GroundDecal._host.z_index <= 0, "贴花宿主 z_index 不抬高压人")
	d.recycle()
	await get_tree().process_frame

## ② 震裂形态：折线数量与包络约束
func _case_crack_shape() -> void:
	var d := GroundDecal.spawn(_world, Vector2(300, 300), GroundDecal.Kind.CRACK, 175.0)
	await get_tree().process_frame
	_c.check(d._cracks.size() >= 5 and d._cracks.size() <= 7,
		"震裂 5~7 条裂纹（%d）" % d._cracks.size())
	var ok := true
	for pts in d._cracks:
		if pts.size() < 2:
			ok = false
		for p in pts:
			if p.length() > 175.0 * 0.95 + 0.01:
				ok = false
	_c.check(ok, "裂纹折点全部收在包络圈 ×0.95 内")
	d.recycle()
	await get_tree().process_frame

## ③ 焦痕形态：子圆聚合与包络约束
func _case_scorch_shape() -> void:
	var d := GroundDecal.spawn(_world, Vector2(500, 300), GroundDecal.Kind.SCORCH, 60.0)
	await get_tree().process_frame
	_c.check(d._blobs.size() >= 7 and d._blobs.size() <= 9,
		"焦痕 7~9 个子圆聚合（%d）" % d._blobs.size())
	var ok := true
	for b in d._blobs:
		if Vector2(b.x, b.y).length() + b.z > 60.0 * 0.95 + 0.01:
			ok = false
	_c.check(ok, "焦痕子圆全部收在包络圈 ×0.95 内")
	d.recycle()
	await get_tree().process_frame

## ④ 生命周期：留存期在，走完后回池（HOLD 1.6 + FADE 0.7 = 2.3s 游戏时间）
func _case_lifecycle() -> void:
	var d := GroundDecal.spawn(_world, Vector2(700, 300), GroundDecal.Kind.CRACK, 100.0)
	await get_tree().process_frame
	# 留存期内（1.0s 游戏时间 < HOLD 1.6s）不回收
	var t := 0.0
	while t < 1.0:
		await get_tree().physics_frame
		t += 1.0 / 60.0 * 8.0
	_c.check(not d._pooled and d.visible, "留存期内贴花仍在场（短暂留存）")
	# 走完 HOLD+FADE（再等 1.6s 游戏时间，累计 2.6s > 2.3s）后回池
	t = 0.0
	while t < 1.6:
		await get_tree().physics_frame
		t += 1.0 / 60.0 * 8.0
	_c.check(d._pooled and not d.visible, "渐隐走完后回池休眠（不留永久痕迹）")
	await get_tree().process_frame

## ⑤ 对象池：回收后复用同一实例
## 前置清池：前面用例回池的休眠体还在池里，清掉重建才能钉「只新建 1 个」的读数
func _case_pool_reuse() -> void:
	GroundDecal.clear_pool()
	var a := GroundDecal.spawn(_world, Vector2(100, 500), GroundDecal.Kind.SCORCH, 80.0)
	await get_tree().process_frame
	a.recycle()
	await get_tree().process_frame
	var b := GroundDecal.spawn(_world, Vector2(200, 500), GroundDecal.Kind.CRACK, 90.0)
	await get_tree().process_frame
	_c.check(b == a, "再 spawn 复用池内同一实例")
	_c.equals(GroundDecal.created_count, 1, "清池后全程只新建 1 个实例（其余复用）")
	b.recycle()
	await get_tree().process_frame

## ⑥ 纯视觉：无碰撞体子节点
func _case_pure_visual() -> void:
	var d := GroundDecal.spawn(_world, Vector2(300, 500), GroundDecal.Kind.CRACK, 100.0)
	await get_tree().process_frame
	var has_collision := false
	for child in d.get_children():
		if child is CollisionShape2D or child is CollisionPolygon2D:
			has_collision = true
	_c.check(not has_collision, "贴花无碰撞体（纯视觉，判定在持有者侧）")
	d.recycle()
	await get_tree().process_frame
