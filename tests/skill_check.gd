extends Node

## 随行神通系统判据（真实 Main 场景，不打 mock）：
##   1. SkillData.final_stats 基础值与 9 名道统的强化合并（数值唯一真话）
##   2. 冲刺真实产生位移且途中无敌；神行/疾风 buff 写入 GameManager 乘区并精确回滚
##   3. 冷却流转：CD 中拒绝释放、CD 归零可再放；reset_run 后技能字段全清零
## 运行: godot --headless --path . res://tests/SkillCheck.tscn
## 退出码 0 且末行 SKILL_CHECK_RESULT: ALL PASS

var _c := TestCheck.new()

func _ready() -> void:
	call_deferred("_run")

func _dismiss() -> void:
	for node_name in ["LevelUpDialog", "WaveShop", "PlayerStatsDialog", "PauseMenu", "SettingsDialog"]:
		var n := get_node_or_null("/root/Main/UILayer/" + node_name)
		if n != null and n.visible:
			n.visible = false
	get_tree().paused = false

func _check_data() -> void:
	# 基础值
	var dash := SkillData.final_stats("dash", "")
	_c.near(float(dash["cooldown"]), 8.0, 0.001, "缩地成寸基础冷却 8 秒")
	_c.near(float(dash["distance"]), 260.0, 0.001, "缩地成寸基础距离 260")
	# 道统强化合并（抽查三个代表：加算/乘算/冷却）
	var jianchi_haste := SkillData.final_stats("haste", "jianchi")
	_c.near(float(jianchi_haste["duration"]), 7.5, 0.001, "剑痴疾风咒持续 5+2.5=7.5 秒")
	var meiying_dash := SkillData.final_stats("dash", "meiying")
	_c.near(float(meiying_dash["distance"]), 403.0, 0.5, "魅影缩地成寸距离 260×1.55=403")
	var shiyue_aegis := SkillData.final_stats("aegis", "shiyue")
	_c.near(float(shiyue_aegis["duration"]), 2.6, 0.001, "石岳金光护体 1.6+1.0=2.6 秒")
	var duobao_aegis := SkillData.final_stats("aegis", "duobao")
	_c.near(float(duobao_aegis["cooldown"]), 13.0, 0.001, "多宝金光护体冷却 20×0.65=13 秒")
	# 契合判定：无强化的组合不许误判
	_c.check(SkillData.is_enhanced_for_cultivator("haste", "jianchi"), "剑痴契合疾风咒")
	_c.check(not SkillData.is_enhanced_for_cultivator("dash", "jianchi"), "剑痴不契合缩地成寸")
	_c.check(not SkillData.enhance_desc("haste", "dubi").is_empty(), "独臂刀圣疾风咒有强化文案")
	_c.check(SkillData.enhance_desc("gale", "jianchi").is_empty(), "剑痴神行术无强化文案")

func _run() -> void:
	_check_data()

	var main = load("res://scenes/main/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await get_tree().process_frame
	await get_tree().process_frame
	_c.check(is_instance_valid(main), "主场景已进树")

	GameManager.cultivator_id = "jianchi"
	GameManager.pending_skill_id = "gale"
	GameManager.start_run("qingyun_sword")
	get_tree().paused = false
	_dismiss()
	# 等 WaveSpawner 从 WAITING 进 FIGHT（技能只允许战斗中释放）
	for i in range(12):
		await get_tree().process_frame
		_dismiss()
	var player: Player = GameManager.player
	_c.check(player != null, "玩家已生成")
	_c.equals(GameManager.active_skill_id, "gale", "start_run 后 pending 神通转正")

	var spawner: WaveSpawner = GameManager.wave_spawner
	_c.check(spawner != null and int(spawner.phase) == int(WaveSpawner.Phase.FIGHT), "已进入战斗阶段（技能才可释放）")

	# ---- 神行术：写入移速乘区 + CD 起转 + CD 中拒绝再放 ----
	_c.check(player.try_activate_skill(), "神行术首次释放成功")
	_c.near(GameManager.buff_move_speed_mult, 1.6, 0.001, "神行术写入移速乘区 1.6")
	_c.check(player.skill_cd_left > 0.0, "释放后冷却起转")
	_c.check(not player.try_activate_skill(), "冷却中再次释放被拒绝")
	# buff 到期精确回滚（拨快倒计时，不等满 4 秒）
	player._skill_buffs["gale"] = 0.02
	for i in range(6):
		await get_tree().physics_frame
	_c.near(GameManager.buff_move_speed_mult, 1.0, 0.001, "神行术到期后移速乘区精确回滚 1.0")
	_c.check(player._skill_buffs.is_empty(), "buff 表已清空")

	# ---- 疾风咒：写入攻速乘区（剑痴契合 → 持续 7.5 秒） ----
	GameManager.active_skill_id = "haste"
	player.skill_cd_left = 0.0
	_c.check(player.try_activate_skill(), "疾风咒释放成功")
	_c.near(GameManager.buff_attack_speed_mult, 0.6, 0.001, "疾风咒写入攻速乘区 0.6")
	_c.near(float(player._skill_buffs.get("haste", 0.0)), 7.5, 0.05, "剑痴契合：疾风咒持续 7.5 秒")
	player._skill_buffs["haste"] = 0.02
	for i in range(6):
		await get_tree().physics_frame
	_c.near(GameManager.buff_attack_speed_mult, 1.0, 0.001, "疾风咒到期后攻速乘区精确回滚 1.0")

	# ---- 金光护体：无敌计时起 ----
	GameManager.active_skill_id = "aegis"
	player.skill_cd_left = 0.0
	player.invulnerable_time = 0.0
	_c.check(player.try_activate_skill(), "金光护体释放成功")
	_c.near(player.invulnerable_time, 1.6, 0.1, "金光护体起 1.6 秒无敌")

	# ---- 回春术：按最大气血比例回复 ----
	GameManager.active_skill_id = "renewal"
	player.skill_cd_left = 0.0
	player.invulnerable_time = 0.0
	player.current_health = player.max_health * 0.4
	_c.check(player.try_activate_skill(), "回春术释放成功")
	_c.near(player.current_health, player.max_health * 0.65, 1.0, "回春术回复 25% 最大气血")

	# ---- 缩地成寸：真实位移 + 途中无敌 + CD 归零可再放 ----
	GameManager.active_skill_id = "dash"
	player.skill_cd_left = 0.0
	player.invulnerable_time = 0.0
	player.velocity = Vector2.ZERO
	player.facing = "s"
	var before: Vector2 = player.global_position
	_c.check(player.try_activate_skill(), "缩地成寸释放成功")
	for i in range(20):
		await get_tree().physics_frame
	var moved: float = player.global_position.distance_to(before)
	_c.check(moved > 150.0, "冲刺产生真实位移（%.0f px，期望 ~260）" % moved)
	player.skill_cd_left = 0.0
	await get_tree().physics_frame
	_c.check(player.try_activate_skill(), "冷却归零后可再次释放")

	# ---- HUD 技能按钮交互判据：圆形半透明 + 触控双指响应 + 按下即放 ----
	var hud: GameHUD = main.get_node_or_null("UILayer/GameHUD")
	_c.check(hud != null, "HUD 节点存在")
	await get_tree().process_frame
	var skill_box: Control = hud.get("_skill_box")
	var skill_btn: Button = hud.get("_skill_btn")
	_c.check(skill_box != null and skill_btn != null, "HUD 技能按钮节点已构建")
	_c.check(skill_box.visible, "战斗中技能按钮处于可见态")
	_c.near(skill_btn.size.x, GameHUD.SKILL_BTN_SIZE, 1.0, "技能按钮尺寸符合规范 76px")

	# 测试点按 HUD 按钮（鼠标模拟单点）触发释放
	player.skill_cd_left = 0.0
	var mouse_ev := InputEventMouseButton.new()
	mouse_ev.button_index = MOUSE_BUTTON_LEFT
	mouse_ev.pressed = true
	mouse_ev.position = skill_btn.size * 0.5
	hud._on_skill_btn_input(mouse_ev)
	await get_tree().process_frame
	_c.check(player.skill_cd_left > 0.0, "点击 HUD 按钮按下即放触发技能（冷却起转）")

	# 测试第二根手指（触屏双指拉摇杆时 index = 1）触控直通
	player.skill_cd_left = 0.0
	var touch_ev := InputEventScreenTouch.new()
	touch_ev.index = 1
	touch_ev.pressed = true
	touch_ev.position = skill_btn.global_position + skill_btn.size * 0.5
	hud._input(touch_ev)
	await get_tree().process_frame
	_c.check(player.skill_cd_left > 0.0, "第二根手指触控直通触发技能（解决移动中点技能无反应）")

	# 测试冷却中点击：产生抖动反馈
	await get_tree().process_frame
	hud._trigger_skill_press()
	_c.check(bool(hud.get("_skill_shaking")), "冷却中点击触发震颤反馈")

	# ---- reset_run 清零 ----
	GameManager.reset_run()
	_c.equals(GameManager.active_skill_id, "", "reset_run 清空本局技能")
	_c.near(GameManager.buff_move_speed_mult, 1.0, 0.001, "reset_run 回滚移速 buff 乘区")
	_c.near(GameManager.buff_attack_speed_mult, 1.0, 0.001, "reset_run 回滚攻速 buff 乘区")

	if _c.report("SKILL_CHECK_RESULT"):
		get_tree().quit(0)
	else:
		get_tree().quit(1)
