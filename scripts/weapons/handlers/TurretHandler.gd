class_name TurretHandler
extends RefCounted

## 机关布设（2026-11-03 从「按冷却自动在脚下布设 N 座」改为「玩家手动落位一座」）。
##
## 纪律：首参 w 为宿主武器（不标类型，鸭类型访问——武器侧硬类型引用会触发
## 循环类依赖，把弹丸 preload 打成空 PackedScene，项目坑 12）。
##
## 职责边界：
##   调用方（TurretCommand）负责「空地校验 / 编制余额 / 整备倒数」；
##   这里只管：清失效节点、建/取池体、setup、挂树、登记编制、入场演出。
##   旧版「超上限顶掉最旧的一座」随 cap 一起废弃 —— 每把武器只带一座（BalanceTurret）。

## 最近一次布设失败的原因码（"" = 没失败）。调用方只拿得到 null，必须靠它说清「为什么」：
##   "cap"   = 编制已满（调用方已按 free_charges() 挡过，这里只是兜底）
##   "scene" = 机关场景/PackedScene 拿不到或实例化不出 TurretUnit
static var last_error: String = ""

## 在 pos 落一座机关。keep_durability ≥ 0 用于「收回重摆」（耐久随机关一起回来）。
## from_pos = 人物出发点的世界坐标（器核投送演出）；Vector2.INF = 直接落地（判据/整备复出）。
static func deploy(w, pos: Vector2, keep_durability: float = -1.0, from_pos: Vector2 = Vector2.INF) -> TurretUnit:
	last_error = ""
	# 原地清理失效机关（旧写法每次布设新建一个 Array 拷贝，零分配版照旧）
	for i in range(w.active_turrets.size() - 1, -1, -1):
		var t: TurretUnit = w.active_turrets[i]
		if t == null or not is_instance_valid(t) or t._is_dying:
			w.active_turrets.remove_at(i)
	# 编制闸（2026-11-03）：上限 = 1 + 「双联神机」额外编制。调用方已经按 free_charges() 判过，
	# 这里是兜底 —— 满编制时不落位也不撤旧的（旧写法「已有一座就先撤掉」是单编制时代的补丁）。
	if w.active_turrets.size() >= int(w.turret_cap()):
		last_error = "cap"
		return null

	var scene: PackedScene = w.turret_scene()
	var turret: TurretUnit = TurretUnit.acquire_or_new(scene)
	if turret == null:
		# 这里以前完全静默：真机上玩家只看到一句「现在不能布设机关」。留带标签的错误进设备日志。
		last_error = "scene"
		push_error("[TURRET] 机关场景无法实例化：%s（scene=%s）" % [w.TURRET_SCENE_PATH, str(scene)])
		return null
	turret.setup(w.weapon_def_id, w.star)
	# 落点由调用方给定（脚下空地）：不再做「玩家身周 38~58px 随机外环」——
	# 随机落位是自动布设时代为了避开身体重叠的权宜手段，手动布设里位置就是玩家的决策。
	turret.global_position = pos
	var player = GameManager.player
	var battle_layer: Node = player.get_parent() if (player != null and player.get_parent() != null) else (w.get_tree().current_scene if w.get_tree() != null else w)
	battle_layer.add_child(turret)
	turret.begin_life(keep_durability, from_pos)
	turret._owner_weapon = w
	w.active_turrets.append(turret)

	w.is_attacking = true
	# 落位沉身演出：下沉 + 金光亮闪 → 弹性回正（帧内状态机，零 Tween）
	w._begin_lunge(w.TURRET_DIP, 0.08, 0.12, true)
	w._flash_sprite(Color(1.4, 1.3, 0.8), 0.12)
	return turret