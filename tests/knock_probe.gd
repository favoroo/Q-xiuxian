extends Node

## 真机链路的震退方向判据（不打任何 mock）：让番天镇岳印在真实战斗里连打，
## 逐帧翻每一个敌人身上那一支 knockback_velocity，并在每一次真实落点上把新旧两条方向规则
## 对着同一批活体几何各算一遍 —— 任何一次震退都不许指向玩家。
## 为什么单测不够：UnitRunner 只验得出 GameBalance.knock_dir 的数学，
## 「落点到底落在玩家内侧还是外侧」由 assign_weapon_targets + 真实物理决定，只有真跑一局才看得见。
## 运行: godot --headless --path . res://tests/KnockProbe.tscn
## 退出码 0 = 无一例往玩家身上推；末行带样本数，样本数为 0 说明这局压根没震到东西（判据是空的）。

var _c := TestCheck.new()

func _ready() -> void:
	call_deferred("_run")

func _dismiss() -> void:
	for node_name in ["LevelUpDialog", "WaveShop", "PlayerStatsDialog", "PauseMenu", "SettingsDialog"]:
		var n := get_node_or_null("/root/Main/UILayer/" + node_name)
		if n != null and n.visible:
			n.visible = false
	get_tree().paused = false

func _run() -> void:
	# 走 root.add_child 而不是 change_scene：change_scene_to_file 会把当前场景（= 本 runner 自己）
	# 释放掉，_run 的协程再也不回来，进程直接挂住（实测挂过 7 分钟）。
	# 代价是 current_scene 仍是 runner 根 —— FloatingWeapon._spawn_lightning 把落雷爆发挂到
	# get_tree().current_scene，所以爆发节点挂在 runner 根下、不在 main 子树里 ⇒ 扫描必须从
	# get_tree().root 起，只扫 main 会报「大印一个没砸」。
	var main = load("res://scenes/main/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await get_tree().process_frame
	await get_tree().process_frame
	_c.check(is_instance_valid(main), "主场景已进树")

	# 本命直接上镇岳印（BURST、burst_radius 95、落点按角度扇区分配 —— 就是翻车那一件）
	GameManager.cultivator_id = "fuzhen"
	GameManager.start_run("fantian_yin")
	get_tree().paused = false
	# 击退叠到后期量级：劲力外放 + 雷音阵 + 厚土羁绊，力越大方向毛病越看得清
	GameManager.knockback_mult = 1.6
	GameManager.synergy_knockback_mult = 1.8
	# 第 1 波怪太稀，落点上可核算的人次不够；密度抬到两倍以上，方向毛病才有次数可数
	GameManager.enemy_count_mult *= 2.5

	var samples := 0          ## 活体敌人身上取到有效震退读数的次数
	var bad := 0              ## 其中指向玩家的次数
	var min_proj := 1e9       ## 全部采样里最小的「沿远离玩家方向投影」，负 = 往玩家推
	var burst_frames := 0     ## 在场雷击爆发的帧次（证明大印真砸了）
	var far_impacts := 0      ## 落点在玩家震退圈外的帧次（旧写法会往回推的那个几何条件）
	var burst_weapons := 0    ## 在场 BURST 法器数峰值（镇岳印确实上阵，不是只靠灵蝶接触）
	var pairs := 0            ## 真实落点上逐个敌人的方向核算次数
	var old_bad := 0          ## 同一批活体几何上，旧径向规则会推向玩家的次数
	var frames := 0
	while frames < 1500:
		await get_tree().process_frame
		frames += 1
		if frames % 12 == 0:
			_dismiss()
		var player: Node2D = GameManager.player
		if player == null:
			continue

		# 1. 逐帧查每一个敌人身上那一支震退速度
		for node in get_tree().get_nodes_in_group("enemies"):
			if not (node is Node2D) or not ("knockback_velocity" in node):
				continue      # 组里还挂着敌人的碰撞子节点，它们没有这个字段
			var e := node as Node2D
			var kbv: Vector2 = e.knockback_velocity
			if kbv.length_squared() < 4.0:
				continue
			var away: Vector2 = e.global_position - player.global_position
			if away.length_squared() < 25.0:
				continue
			samples += 1
			var proj := kbv.dot(away.normalized()) / kbv.length()
			min_proj = minf(min_proj, proj)
			if proj < -0.01:
				bad += 1
				if bad <= 3:
					print("  [越界] %s 距玩家 %.0f，震退沿远离玩家投影 %.3f" % [e.name, away.length(), proj])

		# 2. 扫整棵树：数在场的爆发 / BURST 法器，并拿真实落点几何把新旧两条方向规则各算一遍
		var stack: Array = [get_tree().root]
		var live_bursts := 0
		var live_weapons := 0
		while not stack.is_empty():
			var nd: Node = stack.pop_back()
			if nd is ThunderBurst:
				var b := nd as Node2D
				live_bursts += 1
				var far: bool = b.global_position.distance_to(player.global_position) > float(b.radius)
				if far:
					far_impacts += 1
				for en in get_tree().get_nodes_in_group("enemies"):
					if not (en is Node2D):
						continue
					var e2 := en as Node2D
					if e2.global_position.distance_to(b.global_position) > float(b.radius):
						continue
					var av: Vector2 = e2.global_position - player.global_position
					if av.length_squared() < 25.0:
						continue
					av = av.normalized()
					pairs += 1
					# 旧规则：纯径向（以落点为心）
					if (e2.global_position - b.global_position).normalized().dot(av) < -0.01:
						old_bad += 1
					# 新规则：统一出口
					if GameBalance.knock_dir(b.global_position, e2.global_position, player.global_position).dot(av) < -0.01:
						bad += 1
			elif nd is FloatingWeapon and int(nd.behavior) == WeaponData.Behavior.BURST:
				live_weapons += 1
			for ch in nd.get_children():
				stack.append(ch)
		burst_frames += live_bursts
		burst_weapons = maxi(burst_weapons, live_weapons)

	_c.check(burst_weapons > 0, "番天镇岳印确实上阵（在场 BURST 法器峰值 %d 把）" % burst_weapons)
	_c.check(burst_frames > 0, "大印真砸过（在场雷击爆发累计 %d 帧次）" % burst_frames)
	_c.check(far_impacts > 0, "确有落点落在玩家震退圈外（%d 帧次 —— 翻车的正是这个条件）" % far_impacts)
	_c.check(samples > 200, "震退读数够多（活体采样 %d 次 / 逐帧扫 1500 帧）" % samples)
	_c.check(pairs > 60, "真实落点上的方向核算够多（%d 个人次）" % pairs)
	_c.check(bad == 0, "活体震退与落点方向都没有一次指向玩家（越界 %d 次，最小投影 %.3f）" % [bad, min_proj])
	print("  [对照] 同一批真实落点几何 %d 人次里，旧径向规则有 %d 次会把敌人推向玩家（新规则 0 次）" % [pairs, old_bad])

	if _c.report("KNOCK_PROBE_RESULT"):
		get_tree().quit(0)
	else:
		get_tree().quit(1)
