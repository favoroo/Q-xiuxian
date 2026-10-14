class_name UnitTargetingTests
extends UnitTestsBase

## 单测模块：多武器智能索敌 / 远程点杀位档 / 御灵动态轨道（从 tests/unit_runner.gd 拆出，2026-10-11）。
## 调用顺序与判据契约（UNIT_RESULT: ALL PASS / 退出码）由 UnitRunner 统一保证；
## _c 与 EPS 继承自 UnitTestsBase，函数体与拆分前逐字一致。
func _test_weapon_targeting() -> void:
	# 1. 空输入与无敌人
	var empty_res := GameBalance.assign_weapon_targets([], [])
	_c.equals(empty_res.size(), 0, "空武器表返回空数组")

	var w4 := [
		{"base_angle": 0.0, "range": 150.0, "prev_id": 0},
		{"base_angle": PI * 0.5, "range": 150.0, "prev_id": 0},
		{"base_angle": PI, "range": 150.0, "prev_id": 0},
		{"base_angle": -PI * 0.5, "range": 150.0, "prev_id": 0},
	]
	_c.equals(GameBalance.assign_weapon_targets(w4, []), [-1, -1, -1, -1], "无敌人时全部无目标")

	# 2. 单一敌人：射程内全部集火，超射程不打
	var single_enemy := [{"id": 101, "dist": 120.0, "angle": 0.0}]
	_c.equals(GameBalance.assign_weapon_targets(w4, single_enemy), [0, 0, 0, 0], "单一敌人时 4 把剑全部集火")

	var mixed_range := [
		{"base_angle": 0.0, "range": 100.0, "prev_id": 0},
		{"base_angle": PI, "range": 200.0, "prev_id": 0},
	]
	_c.equals(GameBalance.assign_weapon_targets(mixed_range, single_enemy), [-1, 0], "超出单把武器射程的不强行锁定")

	# 3. 四面来敌：4 把剑按各自槽位扇区一对一迎战 4 个方向的敌人
	var four_dirs := [
		{"id": 1, "dist": 110.0, "angle": 0.0},       # 右 (东)
		{"id": 2, "dist": 115.0, "angle": PI * 0.5},  # 下 (南)
		{"id": 3, "dist": 120.0, "angle": PI},        # 左 (西)
		{"id": 4, "dist": 125.0, "angle": -PI * 0.5}, # 上 (北)
	]
	var assigned4 := GameBalance.assign_weapon_targets(w4, four_dirs)
	_c.equals(assigned4, [0, 1, 2, 3], "四面受敌时 4 把剑按各自方位一对一分流迎击")

	# 4. 武器多于敌人（3 把剑 vs 2 个反方向敌人）：绝不漏掉任一方向敌人（防 Overkill 扎堆）
	var w3 := [
		{"base_angle": 0.0, "range": 150.0, "prev_id": 0},
		{"base_angle": 2.0 * PI / 3.0, "range": 150.0, "prev_id": 0},
		{"base_angle": -2.0 * PI / 3.0, "range": 150.0, "prev_id": 0},
	]
	var two_dirs := [
		{"id": 10, "dist": 95.0, "angle": 0.0},
		{"id": 20, "dist": 130.0, "angle": PI},
	]
	var assigned3 := GameBalance.assign_weapon_targets(w3, two_dirs)
	_c.check(0 in assigned3 and 1 in assigned3, "3 剑对 2 敌时两侧敌人均被覆盖（实际: %s）" % str(assigned3))

	# 5. 贴身危急敌人优先解围：40px 贴脸敌人必定优先获得防守
	var danger_case := [
		{"id": 99, "dist": 40.0, "angle": PI},
		{"id": 88, "dist": 110.0, "angle": 0.0},
	]
	var w_single := [{"base_angle": 0.0, "range": 150.0, "prev_id": 0}]
	_c.equals(GameBalance.assign_weapon_targets(w_single, danger_case), [0], "即使在背后，贴身危急敌人也优先保命迎击")

	# 6. 目标粘滞性：距离与角度相近的两个敌人，保持原锁定目标不来回抽搐
	var close_pair := [
		{"id": 501, "dist": 110.0, "angle": 0.05},
		{"id": 502, "dist": 108.0, "angle": -0.05},
	]
	var sticky_w := [{"base_angle": 0.0, "range": 150.0, "prev_id": 501}]
	_c.equals(GameBalance.assign_weapon_targets(sticky_w, close_pair), [0], "粘滞保护：已锁定目标微弱劣势时不跳变")

	# 7. 椭圆等效距离与同屏可见优先：垂直方向等效距离放大，且同屏敌人坚决优先于屏外敌人
	var horiz_ed := GameBalance.elliptical_distance(Vector2(200.0, 0.0))
	var vert_ed := GameBalance.elliptical_distance(Vector2(0.0, 200.0))
	_c.near(horiz_ed, 200.0, 0.01, "椭圆距离：水平方向保持原长 200px")
	_c.check(vert_ed > 300.0, "椭圆距离：垂直 200px 折算等效距离 > 300px（防垂直打出屏幕盲区）")
	_c.check(GameBalance.is_in_viewport(Vector2(200, 150), Vector2.ZERO), "视口判定：(200,150) 处于视口内")
	_c.check(not GameBalance.is_in_viewport(Vector2(0, 260), Vector2.ZERO), "视口判定：垂直 260px 超出视口半高")
	var on_vs_off := [
		{"id": 601, "dist": 100.0, "angle": 0.0, "on_screen": false},
		{"id": 602, "dist": 140.0, "angle": PI, "on_screen": true},
	]
	_c.equals(GameBalance.assign_weapon_targets(w_single, on_vs_off), [1], "同屏优先：哪怕屏外敌人更近且顺向，仍优先锁定同屏可见敌人")

# ---------------- 音频接线完整性 ----------------
## 这一组断言专门挡三类「听起来正常其实哑了」的事故：
##   注册了 key 但素材没进包 / 没被导入（本项目踩过：新烘的 wav 未跑 editor import）
##   调用点写了文件名当 key（曾经的 play_sfx("powerUp2") 一直静默无效）
##   总线布局没加载（音量设置就会对着不存在的总线空转）

func _test_ranged_focus_dps() -> void:
	var ranged: Array[String] = []
	var others: Array[float] = []
	for w_id in WeaponData.SHOP_POOL:
		var def := WeaponData.get_def(w_id)
		var dps := WeaponData.sustained_single_dps(w_id, 1)
		if int(def.get("behavior", -1)) == WeaponData.Behavior.PROJECTILE:
			ranged.append(w_id)
		else:
			others.append(dps)
	others.sort()
	@warning_ignore("integer_division")
	var med: float = others[others.size() / 2] if not others.is_empty() else 0.0

	# 1. 尺子本身先自证：口径与运行时逐条对齐，估计算错这里就红
	_c.equals(WeaponData.targets_per_shot("huoyan_fu"), 2, "火焰符双符齐掷 = 单发最多结算 2 敌，仍属点杀位")
	_c.equals(WeaponData.targets_per_shot("gengjin_feijian"), 2, "庚金飞剑贯穿两敌")
	_c.equals(WeaponData.targets_per_shot("wanmu_lingfu"), 3, "万木灵符 1 穿透 + 2 弹射 = 单发 3 敌")
	_c.equals(WeaponData.targets_per_shot("liuye_feidao"), 9, "柳叶飞刀 3 发 × 3 穿透 = 单发 9 敌")
	_c.equals(WeaponData.targets_per_shot("bajiao_fan"), 6, "横扫扇形天生群体，不进点杀位")
	# 火焰符 ★1：damage × 发数 ÷ 冷却 + 单张灼烧（冷却 < 灼烧时长 ⇒ 常驻）。数字全从表里取，
	# 这三条验的是"公式的语义"，不是某一次的数值快照 —— 以后调伤害不用回来改断言
	var hf := WeaponData.get_def("huoyan_fu")
	var hf_dmg: float = float(hf.get("damage", 0.0))
	var hf_cd: float = float(hf.get("cooldown", 1.0))
	var hf_n: float = float(hf.get("projectile_count", 1))
	_c.near(WeaponData.sustained_single_dps("huoyan_fu", 1),
		hf_dmg * hf_n / hf_cd + hf_dmg * float(hf.get("burn_ratio", 0.0)), 0.001,
		"单体 DPS = 逐发弹伤之和 + 常驻灼烧（与 BladeProjectile 的 burn_dps 同源）")
	# 青云剑 ★1：面板即实伤（不再暗乘 1.35）
	var qy := WeaponData.get_def("qingyun_sword")
	_c.near(WeaponData.sustained_single_dps("qingyun_sword", 1),
		float(qy.get("damage", 0.0)) / float(qy.get("cooldown", 1.0)), 0.001,
		"近战单体 DPS 面板即实伤")
	# 玄冰飞针：三发齐射对单目标按最多 2 发命中折算
	var xb := WeaponData.get_def("xuanbing_feizhen")
	_c.near(WeaponData.sustained_single_dps("xuanbing_feizhen", 1),
		float(xb.get("damage", 0.0)) * float(mini(2, int(xb.get("projectile_count", 1)))) / float(xb.get("cooldown", 1.0)), 0.001,
		"多发散射弹丸对单目标按上限 2 发折算")
	_c.check(WeaponData.sustained_single_dps("huoyan_fu", 3) > WeaponData.sustained_single_dps("huoyan_fu", 2),
		"星级越高单体 DPS 越高（尺子跟 damage_for/cooldown_for 同向）")

	# 2. 分类自洽：点杀位这一档不许空（空了就等于这条判据没人守着）
	var focus: Array[String] = []
	for w_id in ranged:
		if WeaponData.is_focus_ranged(w_id):
			focus.append(w_id)
	_c.check(focus.size() >= 2, "点杀位远程法器至少两把（实得 %d 把：%s）" % [focus.size(), str(focus)])

	# 3. 档位下限：点杀位 ≥ 中位，全体弹丸 ≥ 0.8 × 中位
	var worst_focus: float = 1e9
	for w_id in focus:
		worst_focus = minf(worst_focus, WeaponData.sustained_single_dps(w_id, 1))
	# 下限取 0.95× 而不是 1.0×：留一点余量，免得别人把近战/环绕往上抬 3% 就把远程表逼着跟着改
	_c.check(worst_focus >= med * 0.95,
		"点杀位单体 DPS %.1f ≥ 0.95×非远程中位 %.1f（贴脸与环绕必须被啃硬目标的速度反超）" % [worst_focus, med * 0.95])
	var worst_ranged: float = 1e9
	var worst_id: String = ""
	for w_id in ranged:
		var v := WeaponData.sustained_single_dps(w_id, 1)
		if v < worst_ranged:
			worst_ranged = v
			worst_id = w_id
	_c.check(worst_ranged >= med * 0.75,
		"最弱弹丸【%s】单体 DPS %.1f ≥ 0.75×中位 %.1f" % [worst_id, worst_ranged, med * 0.75])

	# 4. 群体档不许反过来吃掉单体档：弹丸单发结算的敌人越多，单价就该越便宜
	_c.check(int(WeaponData.get_def("huoyan_fu").get("price", 0)) <= int(WeaponData.get_def("liuye_feidao").get("price", 0)),
		"单发只咬 1 敌的火焰符不比单发咬 9 敌的柳叶飞刀贵")
	_c.check(WeaponData.sustained_single_dps("huoyan_fu", 1) > WeaponData.sustained_single_dps("liuye_feidao", 1),
		"火焰符对孤立目标的 DPS 高于群体弹丸（各档各有各的活）")
	_c.check(WeaponData.sustained_single_dps("gengjin_feijian", 1) > WeaponData.sustained_single_dps("liuye_feidao", 1),
		"庚金飞剑对孤立目标的 DPS 高于群体弹丸")

	# 5. 元素 DoT 叠层共鸣与元素伤害跳字加成校验
	_c.near(GameBalance.stack_burn_dps(0.0, 20.0), 20.0, EPS, "首次灼烧全额生效")
	_c.near(GameBalance.stack_burn_dps(20.0, 16.0), 24.0, EPS, "已灼烧目标再受灼烧时叠加 25% 共鸣伤害")
	_c.near(GameBalance.burn_tick_damage(20.0, 0.0, 1.0), 10.0, EPS, "0 元素伤害时灼烧每跳 0.5s 为 10 点")
	_c.near(GameBalance.burn_tick_damage(20.0, 10.0, 1.0), 14.0, EPS, "10 点元素伤害为灼烧每跳额外提供 +4 点伤害")
	_c.near(GameBalance.burn_tick_damage(20.0, 10.0, 1.5), 21.0, EPS, "离火羁绊倍率 1.5x 完整放大灼烧跳字")
	_c.near(GameBalance.poison_tick_damage(10.0, 10.0), 8.0, EPS, "10 点元素伤害为剧毒每跳额外提供 +3 点伤害")

func _test_spirit_orbit_dynamics() -> void:
	# 1. 无敌情巡航：非战斗状态，所有灵宝平稳处于基准半径
	var empty_res := GameBalance.compute_spirit_orbit([0.0, PI], [], 58.0, 28.0, 135.0)
	_c.equals(bool(empty_res.get("in_combat", true)), false, "无敌情时不触发战斗激战状态")
	_c.near(float(empty_res["radii"][0]), 58.0, EPS, "空敌情下第 1 枚灵宝回归 58px 基准半径")
	_c.near(float(empty_res["radii"][1]), 58.0, EPS, "空敌情下第 2 枚灵宝回归 58px 基准半径")

	# 2. 贴身危急突破（32px）：正前方灵宝极限内收至 32px 护体解围，杜绝贴身盲区
	var danger_enemies := [{"dist": 32.0, "angle": 0.0}]
	var danger_res := GameBalance.compute_spirit_orbit([0.0, PI], danger_enemies, 58.0, 28.0, 135.0)
	_c.equals(bool(danger_res.get("in_combat", false)), true, "贴脸近敌触发战斗激战状态")
	_c.near(float(danger_res["radii"][0]), 32.0, EPS, "同侧灵宝迅速内收至 32px 贴身封堵")

	# 3. 极度贴身（10px）：内收半径被地板 min_radius(28px) 截断，不会坍缩进玩家中心
	var super_close := [{"dist": 10.0, "angle": 0.0}]
	var close_res := GameBalance.compute_spirit_orbit([0.0], super_close, 58.0, 28.0, 135.0)
	_c.near(float(close_res["radii"][0]), 28.0, EPS, "内收最低安全地板 28px 防止穿模倒扣")

	# 4. 扇区索敌扑击（105px）：朝向扇区内的敌人引发灵宝主动出圈扑杀
	var lunge_enemies := [{"dist": 105.0, "angle": 0.1}]
	var lunge_res := GameBalance.compute_spirit_orbit([0.0, PI], lunge_enemies, 58.0, 28.0, 135.0)
	_c.near(float(lunge_res["radii"][0]), 105.0, EPS, "正前方扇区灵宝主动扑击外扩至 105px")

	# 5. 超出最大射程（260px）：不触发激战加速，保持基准半径
	var far_enemies := [{"dist": 260.0, "angle": 0.0}]
	var far_res := GameBalance.compute_spirit_orbit([0.0, PI], far_enemies, 58.0, 28.0, 135.0)
	_c.equals(bool(far_res.get("in_combat", true)), false, "超远距离敌人不触发战斗状态")
	_c.near(float(far_res["radii"][0]), 58.0, EPS, "超远敌人下灵宝保持 58px")

	# 6. 转速测试：默认基础巡航角速度减小至平稳的 2.4 rad/s，且随攻速加点等比放大
	var base_spd := GameBalance.spirit_orbit_angular_speed(2.4, 1.0, 1.0, false, 1)
	_c.near(base_spd, 2.4, EPS, "默认无加点非战斗旋转角速度为 2.4 rad/s（平稳巡航）")
	var combat_spd := GameBalance.spirit_orbit_angular_speed(2.4, 1.0, 1.0, true, 1)
	_c.near(combat_spd, 2.4 * 1.18, EPS, "临战微幅加速 1.18x（~2.83 rad/s）")
	# 模拟技能加点 1 次 haste_up（施法间隔 ×0.88）
	var haste1_spd := GameBalance.spirit_orbit_angular_speed(2.4, 0.88, 1.0, false, 1)
	_c.near(haste1_spd, 2.4 * (1.0 / 0.88), EPS, "加点 1 次法诀迅捷攻速 +13.6%，转速等比提升")
	_c.check(haste1_spd > base_spd, "攻速加点后御灵旋转速度切实增加")
	# 模拟攻速堆叠（施法间隔 0.50）
	var haste_high_spd := GameBalance.spirit_orbit_angular_speed(2.4, 0.50, 1.0, false, 1)
	_c.near(haste_high_spd, 2.4 * 2.0, EPS, "攻速翻倍时御灵转速翻倍为 4.8 rad/s")

	# 7. 全局默认参数与新常数校验：基准半径 80px，最大外扩 185px，基础转速 2.8 rad/s
	_c.near(GameBalance.SPIRIT_BASE_RADIUS, 80.0, EPS, "御灵基准半径常数提升至 80px")
	_c.near(GameBalance.SPIRIT_MAX_REACH, 185.0, EPS, "御灵最大外扩常数提升至 185px")
	_c.near(GameBalance.SPIRIT_BASE_ANGULAR_SPEED, 2.8, EPS, "御灵基础旋转角速度提升至 2.8 rad/s")
	var default_res := GameBalance.compute_spirit_orbit([0.0], [])
	_c.near(float(default_res["radii"][0]), 80.0, EPS, "缺省入参计算回归 80px 基础半径")
