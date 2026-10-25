class_name TurretHandler
extends RefCounted

## 召唤炮台（TURRET）行为实现（2026-10-24 自 FloatingWeapon 拆出）。
## 纪律：首参 w 为宿主武器（不标类型，鸭类型访问——武器侧硬类型引用会触发
## 循环类依赖，把弹丸 preload 打成空 PackedScene，项目坑 12）。

static func perform(w) -> void:
	w.is_attacking = true
	var player = GameManager.player
	var spawn_pos: Vector2 = player.global_position if player != null else w.global_position

	# 原地清理失效炮塔（2026-10-21）：旧写法每次开火新建一个 Array 拷贝，6 法器数Hz 齐射
	# 就是每秒几十次小分配。改原地倒序删除，零分配。
	for i in range(w.active_turrets.size() - 1, -1, -1):
		var t: TurretUnit = w.active_turrets[i]
		if t == null or not is_instance_valid(t) or t._is_dying:
			w.active_turrets.remove_at(i)

	# 炮台上限随星抬升：★1 cap / ★2 cap+1 / ★3 cap+2 / ★4 极境「神机齐射」cap+3。
	# 这条线性档就是极境的「多布一台」，不再额外加码 —— 6 把炮台武器全 ★4 时场上最多
	# 6×6 台机体，再加会顶爆索敌查询与节点数（性能红线优先于纸面数字）。
	var cap: int = int(w.def.get("turret_cap", 2)) + (w.star - 1)
	if w.active_turrets.size() >= cap:
		var oldest: TurretUnit = w.active_turrets.pop_front() as TurretUnit
		if oldest != null and is_instance_valid(oldest):
			oldest.dismiss()

	var turret: TurretUnit = w.turret_scene.instantiate() as TurretUnit
	turret.setup(w.weapon_def_id, w.star)
	# 机关布设环形分布（2026-10-25）：旧写法直接在 spawn_pos 周围 ±22,±16 随机，
	# 导致炮台直接生成在玩家身体/肚脐眼上，多台堆叠遮蔽角色本体。
	# 改为在身周 38~58px 外环展开（Y 轴 0.75 俯视压扁），呈众星拱月守御阵列，避开身体重叠。
	var angle: float = GameManager.rng.randf() * TAU
	var dist: float = GameManager.rng.randf_range(38.0, 58.0)
	var spawn_offset := Vector2(cos(angle) * dist, sin(angle) * dist * 0.75)
	turret.global_position = spawn_pos + spawn_offset
	var battle_layer: Node = player.get_parent() if (player != null and player.get_parent() != null) else (w.get_tree().current_scene if w.get_tree() != null else w)
	battle_layer.add_child(turret)
	w.active_turrets.append(turret)

	# 召唤沉身演出：下沉 + 金光亮闪 → 弹性回正（帧内状态机，零 Tween）
	w._begin_lunge(w.TURRET_DIP, 0.08, 0.12, true)
	w._flash_sprite(Color(1.4, 1.3, 0.8), 0.12)
