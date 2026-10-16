class_name BalanceTargeting
extends RefCounted

## 索敌与折算数值：多武器智能索敌分流、藏宝匣两段式分配、武器属性受益折算、
## 御灵（环绕道具）动态轨道、多武器神识分流。全部 static 纯函数。
## 与 GameBalance 同规约：不读 autoload、不碰节点、不调全局 randf()；只读 WeaponData 静态表。

# ---------------- 多武器智能索敌与分流分配 ----------------

const DANGER_ZONE_RADIUS := 75.0  ## 贴身危急警戒半径（防暴毙优先集火区）
const TARGETING_ELLIPSE_Y_RATIO := 0.65  ## 椭圆索敌垂直短轴压缩比（适配 16:9 扁平视野，防垂直打出屏幕盲区）
const VIEWPORT_SAFE_HALF_EXTENTS := Vector2(426.0, 235.0)  ## 默认视口半宽半高（960x540 / zoom 1.1 内缩 10px 安全边界）

## 椭圆等效距离：将 y 轴按 y_ratio 还原为长轴标尺，计算在长轴尺度下的等效距离
## 当 eff_dist <= range 时，几何点正好位于 (x/range)^2 + (y/(range*y_ratio))^2 <= 1 内
static func elliptical_distance(offset: Vector2, y_ratio: float = TARGETING_ELLIPSE_Y_RATIO) -> float:
	var scaled_y := offset.y / maxf(0.01, y_ratio)
	return sqrt(offset.x * offset.x + scaled_y * scaled_y)

## 目标是否在以 center 为中心的当前屏幕可视视口范围内
static func is_in_viewport(pos: Vector2, center: Vector2, half_extents: Vector2 = VIEWPORT_SAFE_HALF_EXTENTS) -> bool:
	var diff := (pos - center).abs()
	return diff.x <= half_extents.x and diff.y <= half_extents.y

## 为多把在场武器智能分配攻击目标（纯函数：无副作用、无节点依赖、确定性回归）
## weapons_info: Array[Dictionary]，每项包含 { "base_angle": float, "range": float, "prev_id": int }
## enemies_info: Array[Dictionary]，每项包含 { "id": int, "dist": float, "angle": float, "on_screen": bool (可选) }
## 返回 Array[int]，长度等于 weapons_info.size()，每项对应 enemies_info 的下标（-1 为无目标）
static func assign_weapon_targets(weapons_info: Array, enemies_info: Array, danger_radius: float = DANGER_ZONE_RADIUS) -> Array:
	var w_count := weapons_info.size()
	var e_count := enemies_info.size()
	var result: Array = []
	for i in range(w_count):
		result.append(-1)

	if w_count == 0 or e_count == 0:
		return result

	# 1. 若仅单一目标，所有在射程内的武器集中集火该目标（集火模式）
	if e_count == 1:
		var single_dist: float = float(enemies_info[0].get("dist", 0.0))
		for i in range(w_count):
			var w_range: float = float(weapons_info[i].get("range", 150.0))
			if single_dist <= w_range:
				result[i] = 0
		return result

	var assigned_counts := {}
	for e_idx in range(e_count):
		assigned_counts[e_idx] = 0

	# 2. 贴身危急威胁优先防守：
	# 若有敌人突破到贴身危险区（<= danger_radius），优先为每个贴身敌人分配角度最契合的武器解围
	var danger_enemy_indices: Array[int] = []
	for e_idx in range(e_count):
		var d: float = float(enemies_info[e_idx].get("dist", 9999.0))
		if d <= danger_radius:
			danger_enemy_indices.append(e_idx)

	for danger_e_idx in danger_enemy_indices:
		var e_ang: float = float(enemies_info[danger_e_idx].get("angle", 0.0))
		var e_dist: float = float(enemies_info[danger_e_idx].get("dist", 0.0))
		var best_w_idx := -1
		var best_diff := 999.0
		for w_idx in range(w_count):
			if result[w_idx] != -1:
				continue
			var w_range: float = float(weapons_info[w_idx].get("range", 150.0))
			if e_dist > w_range:
				continue
			var w_ang: float = float(weapons_info[w_idx].get("base_angle", 0.0))
			var diff := absf(wrapf(e_ang - w_ang, -PI, PI))
			if diff < best_diff:
				best_diff = diff
				best_w_idx = w_idx
		if best_w_idx != -1:
			result[best_w_idx] = danger_e_idx
			assigned_counts[danger_e_idx] = int(assigned_counts.get(danger_e_idx, 0)) + 1

	# 3. 对其余武器进行多向扇区分流分配：
	# 综合考量目标占用惩罚、扇区角度契合度、距离权重及目标粘滞性
	for w_idx in range(w_count):
		if result[w_idx] != -1:
			continue

		var w_info: Dictionary = weapons_info[w_idx]
		var w_range: float = float(w_info.get("range", 150.0))
		var w_base_angle: float = float(w_info.get("base_angle", 0.0))
		var prev_id: int = int(w_info.get("prev_id", 0))

		var best_e_idx := -1
		var lowest_cost := 9999999.0

		for e_idx in range(e_count):
			var e_info: Dictionary = enemies_info[e_idx]
			var e_dist: float = float(e_info.get("dist", 9999.0))
			if e_dist > w_range:
				continue

			var e_ang: float = float(e_info.get("angle", 0.0))
			var e_id: int = int(e_info.get("id", 0))
			var count_assigned: int = int(assigned_counts.get(e_idx, 0))
			var angle_diff := absf(wrapf(e_ang - w_base_angle, -PI, PI))

			# 成本函数：
			# - 屏幕外可见性惩罚（1500 分）：场上有任何屏幕内敌人时，武器坚决优先打同屏可见怪，杜绝打屏幕外盲区
			# - 已被分配惩罚（500 分/武器）：强烈驱使武器挑选未被覆盖的不同方向敌人，防止 Overkill
			# - 扇区契合度（0~120 分）：使槽位方位更顺路的武器迎战该侧敌人
			# - 相对距离（0~80 分）：同方向优先打击距离更近的敌人
			# - 目标粘滞奖励（-40 分）：当前已锁定敌人拥有微弱粘滞优势，防止帧间目标抖动
			var on_screen: bool = bool(e_info.get("on_screen", true))
			var offscreen_penalty := 0.0 if on_screen else 1500.0
			var stickiness_bonus := 40.0 if (prev_id != 0 and prev_id == e_id) else 0.0
			var cost: float = offscreen_penalty \
				+ float(count_assigned) * 500.0 \
				+ (angle_diff / PI) * 120.0 \
				+ (e_dist / maxf(1.0, w_range)) * 80.0 \
				- stickiness_bonus

			if cost < lowest_cost:
				lowest_cost = cost
				best_e_idx = e_idx

		if best_e_idx != -1:
			result[w_idx] = best_e_idx
			assigned_counts[best_e_idx] = int(assigned_counts.get(best_e_idx, 0)) + 1

	return result

# ---------------- 藏宝匣：可砸，但不算威胁 ----------------
## 匣子本身的数值（刷几口 / 三档权重 / 击数 / 掉落表）在 BalanceChest，2026-10-11 寻宝流改版
## 时迁出；这里只留索敌分配 —— 两段式那半条链路仍然归本类管。

## 纯函数：两段式分配 —— 先按原有规则把武器派给妖怪，剩下确实无事可做的武器再去砸匣子。
## 为什么分两段而不是把匣子混进 enemies_info 一起排：匣子和妖怪在同一条成本函数里
## 只比"角度 + 距离"，一个脚边的匣子会把武器从还没人管的妖怪身上拽走（匣子不会打你，会打你的妖会）。
## 两段式保证：妖怪永远优先，匣子只吃闲着的武器与多出来的弹道。
## enemies_info / chests_info 同构：{ "id": int, "dist": float, "angle": float }
## 返回 Array[int]，下标落在 enemies_info ++ chests_info 这条拼接数组上（-1 = 无事可做）
static func assign_targets_with_chests(weapons_info: Array, enemies_info: Array, chests_info: Array) -> Array:
	var result: Array = assign_weapon_targets(weapons_info, enemies_info)
	if chests_info.is_empty():
		return result
	var idle_weapons: Array = []
	var idle_slots: Array[int] = []
	for w_idx in range(result.size()):
		if int(result[w_idx]) < 0:
			idle_weapons.append(weapons_info[w_idx])
			idle_slots.append(w_idx)
	if idle_weapons.is_empty():
		return result
	var chest_assign: Array = assign_weapon_targets(idle_weapons, chests_info)
	for i in range(idle_slots.size()):
		var c_idx := int(chest_assign[i])
		if c_idx >= 0:
			result[idle_slots[i]] = enemies_info.size() + c_idx
	return result

# ---------------- 武器属性受益折算（仿土豆兄弟属性加成） ----------------

## 纯函数：根据武器设定的 stat_scalings 与玩家当前属性状态，计算出附加在基础伤害上的数值增量
## stat_scalings: { "armor": 3.5, "crit_rate": 40.0, ... }
## player_stats: { "armor": float, "crit_rate": float, "hp_regen": float, ... }
## star: 星级，每升一星该武器的属性转化效率提升 25%（★1: 1.0x, ★2: 1.25x, ★3: 1.5x）
## 总额就是 weapon_stat_bonus_parts 各项之和 —— 只留一份折算实现，账单与总额不可能对不上。
static func weapon_stat_bonus(stat_scalings: Dictionary, player_stats: Dictionary, star: int = 1) -> float:
	var bonus: float = 0.0
	for v in weapon_stat_bonus_parts(stat_scalings, player_stats, star).values():
		bonus += float(v)
	return bonus

## 纯函数：属性 → 这把武器的逐项裸伤明细 {stat_scalings 键: 该项加了多少裸伤}，已含星级效率。
## 卡面与详情弹窗的「属性加伤账单」直接读它：玩家看到的是每项贡献的伤害数，不是系数百分比
## （armor 3.5 这类系数按百分比印出来会显示成「护甲(+4%)」，max_hp_bonus 0.12 更是直接四舍五入成「+0%」）。
static func weapon_stat_bonus_parts(stat_scalings: Dictionary, player_stats: Dictionary, star: int = 1) -> Dictionary:
	var parts: Dictionary = {}
	if stat_scalings.is_empty():
		return parts
	var star_mult: float = 1.0 + 0.25 * float(clampi(star, 1, 3) - 1)
	for key in stat_scalings.keys():
		var coef: float = float(stat_scalings[key])
		var val: float = 0.0
		match key:
			"armor":
				val = maxf(0.0, float(player_stats.get("armor", 0.0)))
			"max_hp_bonus":
				val = maxf(0.0, float(player_stats.get("max_hp", 100.0)) - 100.0)
			"hp_regen":
				val = maxf(0.0, float(player_stats.get("hp_regen", 0.0)))
			"lifesteal":
				val = maxf(0.0, float(player_stats.get("lifesteal", 0.0)))
			"crit_rate":
				val = maxf(0.0, float(player_stats.get("crit_rate", 0.05)) - 0.05)
			"crit_mult_bonus":
				val = maxf(0.0, float(player_stats.get("crit_mult", 1.5)) - 1.5)
			"move_speed_bonus":
				val = maxf(0.0, float(player_stats.get("move_speed_mult", 1.0)) - 1.0)
			"cdr_bonus":
				val = maxf(0.0, 1.0 - float(player_stats.get("attack_speed_mult", 1.0)))
			"damage_bonus":
				val = maxf(0.0, float(player_stats.get("weapon_damage_mult", 1.0)) - 1.0)
			"range_bonus":
				val = maxf(0.0, float(player_stats.get("attack_range_mult", 1.0)) - 1.0)
			"melee_damage":
				val = maxf(0.0, float(player_stats.get("melee_damage", 0.0)))
			"ranged_damage":
				val = maxf(0.0, float(player_stats.get("ranged_damage", 0.0)))
			"elemental_damage":
				val = maxf(0.0, float(player_stats.get("elemental_damage", 0.0)))
			"engineering_damage":
				val = maxf(0.0, float(player_stats.get("engineering_damage", 0.0)))
			"contraption_damage":
				val = maxf(0.0, float(player_stats.get("contraption_damage", 0.0)))
			"harvest":
				val = maxf(0.0, float(player_stats.get("harvest", 0.0)))
		parts[String(key)] = val * coef * star_mult
	return parts

static func stat_scaling_label(key: String) -> String:
	match key:
		"melee_damage": return "近战伤害"
		"ranged_damage": return "远程伤害"
		"elemental_damage": return "元素伤害"
		"engineering_damage": return "召唤伤害"
		"contraption_damage": return "机关伤害"
		"armor": return "护甲"
		"max_hp_bonus": return "最大生命"
		"hp_regen": return "生命回复"
		"lifesteal": return "吸血概率"
		"crit_rate": return "额外暴击率"
		"crit_mult_bonus": return "额外暴击伤害"
		"move_speed_bonus": return "移速加成"
		"cdr_bonus": return "攻击间隔"
		"damage_bonus": return "武器伤害加成"
		"range_bonus": return "范围加成"
		"harvest": return "收益"
	return key

## 加点 apply 字段 → 武器 stat_scalings 键的映射（upgrade_benefits_weapon 用）。
## 与上面 weapon_stat_bonus 的折算 match 同源：武器 stat_scalings 里配了这个键才真吃这条属性。
## max_hp→max_hp_bonus / crit_mult→crit_mult_bonus / move_speed_mult→move_speed_bonus 是三处异名。
const APPLY_WEAPON_STAT_MAP := {
	"melee_damage": "melee_damage",
	"ranged_damage": "ranged_damage",
	"elemental_damage": "elemental_damage",
	"engineering_damage": "engineering_damage",
	"contraption_damage": "contraption_damage",
	"armor": "armor",
	"max_hp": "max_hp_bonus",
	"hp_regen": "hp_regen",
	"lifesteal": "lifesteal",
	"crit_rate": "crit_rate",
	"crit_mult": "crit_mult_bonus",
	"move_speed_mult": "move_speed_bonus",
	"harvest": "harvest",
}

## 这条加点通过**哪些属性链路**让某件武器变强（返回命中的 apply 键，顺序同 apply 表）。
## 与 upgrade_benefits_weapon 同一份判定，只多回一份「为什么是它」：悟道卡片下方那排
## 「受益装备」图标点开后的详情卡用它写清这条链路，不再另抄一套口径（改判定只改这里）。
## 纯函数：只读 WeaponData 静态表，不读 autoload。
static func upgrade_benefit_reasons(apply: Dictionary, w_id: String) -> Array[String]:
	var out: Array[String] = []
	for key in apply.keys():
		var k := String(key)
		match k:
			"weapon_damage_mult", "attack_speed_mult_mul", "knockback_mult", \
			"attack_range_mult", "element_damage_all", "elite_damage":
				if not out.has(k):
					out.append(k)
			"bonus_pierce":
				if int(WeaponData.get_def(w_id).get("behavior", WeaponData.Behavior.MELEE)) \
						== WeaponData.Behavior.PROJECTILE and not out.has(k):
					out.append(k)
			_:
				if k.begins_with("element_damage_"):
					var elem := k.trim_prefix("element_damage_")
					if elem in WeaponData.ELEMENTS and WeaponData.element_of(w_id) == elem \
							and not out.has(k):
						out.append(k)
				elif APPLY_WEAPON_STAT_MAP.has(k):
					var sk: String = APPLY_WEAPON_STAT_MAP[k]
					if float(WeaponData.get_def(w_id).get("stat_scalings", {}).get(sk, 0.0)) > 0.0 \
							and not out.has(k):
						out.append(k)
	return out

## 这条加点（UpgradeData 的 "apply" 字典）会不会让某件武器变强（悟道卡片下方挂受益武器图标用）。
## 口径与伤害结算逐条对齐：
##   全局乘区（武器伤害/攻击间隔/击退/攻击范围/全元素/斩将）→ 全体武器受益；
##   单元素真解 → 按 WeaponData.element_of 五行 tags 匹配；
##   破甲透劲（bonus_pierce）→ 只喂弹丸类（FloatingWeapon.p.pierce_left）；
##   stat_scalings 键 → 武器配了该属性转化系数才算；
##   其余（闪避/拾取/金币/幸运/经验/重掷/反伤等玩家功能属性）→ 不作用于武器。
## 判据与 upgrade_benefit_reasons 同一条链：有链路才算受益，不另写一遍分支。
static func upgrade_benefits_weapon(apply: Dictionary, w_id: String) -> bool:
	return not upgrade_benefit_reasons(apply, w_id).is_empty()

# ---------------- 御灵（环绕道具）动态轨道与战斗感知 ----------------

const SPIRIT_BASE_RADIUS := 80.0         ## 巡航基准半径（无威胁时的平稳环绕距离）
const SPIRIT_MIN_RADIUS := 28.0          ## 极限收缩半径（完全覆盖 24~40px 贴身盲区）
const SPIRIT_MAX_REACH := 185.0          ## 默认最大扑击外扩极限
const SPIRIT_DANGER_DIST := 54.0         ## 贴身危急警戒线（低于此距离道具迅速内收护体）
const SPIRIT_SECTOR_HALF_ANGLE := 1.18   ## 扇区扑击半角（~67.6°，灵宝朝向前方扇区）
const SPIRIT_BASE_ANGULAR_SPEED := 2.8   ## 基础默认旋转角速度（从 2.4 提升至 2.8 rad/s）

## 少具转速补偿（2026-10-15，用户口径：「只配一个召唤武器太弱，转快点」）：
## 环绕是接触伤害，具数越少扫掠覆盖越差、对同一敌人的经过频率越低。
## 按场上灵宝总具数给基础转速乘区：1 具 ×1.25 / 2 具 ×1.10 / ≥3 具不补。
## 单敌实伤随转速近线性水涨船高，是最直接的"单召唤加强"；不折进 spirit_contact_duty
## 纸面折算尺（图鉴展示口径保持不变，低估方向安全）。
const SPIRIT_LONE_SPEED_MULT: Array[float] = [1.25, 1.10, 1.0]

## 计算环绕灵宝的实时旋转角速度（弧度/秒）：随技能加点的攻速加成等比提升
## attack_speed_mult: GameManager.attack_speed_mult（默认 1.0，加点 haste_up 每次乘以 0.88）
## synergy_haste_mult: GameManager.synergy_haste_mult（雷法/玄水羁绊加成）
## in_combat: 战斗感知圈内有敌人时触发温和激战加速（1.18x）
## orb_count: 场上灵宝总具数（少具补偿，见 SPIRIT_LONE_SPEED_MULT）
static func spirit_orbit_angular_speed(
	base_speed: float = SPIRIT_BASE_ANGULAR_SPEED,
	attack_speed_mult: float = 1.0,
	synergy_haste_mult: float = 1.0,
	in_combat: bool = false,
	max_star: int = 1,
	orb_count: int = 1
) -> float:
	var eff_cd_mult: float = clampf(attack_speed_mult * synergy_haste_mult, 0.25, 1.5)
	var haste_scale: float = 1.0 / eff_cd_mult
	var combat_scale: float = 1.18 if in_combat else 1.0
	var star_scale: float = 1.0 + 0.08 * float(clampi(max_star, 1, 3) - 1)
	var lone_scale: float = SPIRIT_LONE_SPEED_MULT[clampi(orb_count, 1, 3) - 1]
	return base_speed * haste_scale * combat_scale * star_scale * lone_scale

## 环绕灵宝接触结算占空比：轨道扫掠 + 扇区扑击 + 26px 接触圈下，敌人处于可结算位置的
## 时间占比实测估计（tests/WeaponProbe.tscn 灵蝶 ★1 口径）。纸面 DPS × 该系数 = 有效 DPS，
## WeaponData.sustained_single_dps 的 DRONE 分支按此折算，让平衡判据用"实伤口径"钉数值。
const SPIRIT_CONTACT_DUTY := 0.75

## 接触占空比按星级抬升：升星后一具灵宝分身为二/为三（Player.sync_drones 按星生数），
## 多具同环扫掠让敌人处于可结算位置的占比更高。★1 保持实测基准 0.75，御灵 DPS 带 [30,38] 不动。
const SPIRIT_CONTACT_DUTY_PER_STAR: Array[float] = [0.75, 0.81, 0.84]

## 纯函数：某星级的环绕灵宝接触结算占空比（WeaponData.sustained_single_dps 与平衡仿真共用同一把尺）
static func spirit_contact_duty(star: int = 1) -> float:
	return float(SPIRIT_CONTACT_DUTY_PER_STAR[clampi(star, 1, 3) - 1])

## 计算多枚环绕灵宝的动态目标半径与战斗激战状态（纯函数：无节点依赖、无副作用）
## orb_angles: Array[float]，每枚灵宝当前在玩家身周的公转角（弧度）
## 性能静态复用缓冲：供 compute_spirit_orbit 60Hz 零分配返回
static var _orbit_res_buf: Dictionary = {"radii": [], "in_combat": false}
static var _orbit_radii_buf: Array[float] = []

## enemies_info: Array[Dictionary]，每个敌人的信息 { "dist": float, "angle": float }
## 返回: { "radii": Array[float], "in_combat": bool }
static func compute_spirit_orbit(
	orb_angles: Array,
	enemies_info: Array,
	base_radius: float = SPIRIT_BASE_RADIUS,
	min_radius: float = SPIRIT_MIN_RADIUS,
	max_reach: float = SPIRIT_MAX_REACH
) -> Dictionary:
	var count := orb_angles.size()
	_orbit_radii_buf.resize(count)
	for i in range(count):
		_orbit_radii_buf[i] = base_radius

	_orbit_res_buf["radii"] = _orbit_radii_buf
	_orbit_res_buf["in_combat"] = false

	if count == 0:
		return _orbit_res_buf

	if enemies_info.is_empty():
		return _orbit_res_buf

	# 1. 判定是否处于战斗感知圈内（max_reach 范围内有敌人）。
	# 性能：本函数被 Player 每物理帧调用（60Hz），不建中间数组（原 in_range/danger
	# 两个 Array[Dictionary] 每帧新建即 ~240 次分配/秒），改记计数二次遍历 enemies_info。
	var in_combat := false
	var in_range_count := 0
	var danger_count := 0
	var sum_dist := 0.0

	for e in enemies_info:
		var d: float = float(e.get("dist", 9999.0))
		if d <= max_reach + 20.0:
			in_combat = true
		if d <= max_reach:
			in_range_count += 1
			sum_dist += d
		if d <= SPIRIT_DANGER_DIST:
			danger_count += 1

	if not in_combat or in_range_count == 0:
		_orbit_res_buf["in_combat"] = in_combat
		return _orbit_res_buf

	var avg_reach_dist: float = clampf(sum_dist / float(in_range_count), min_radius, base_radius * 1.25)

	# 2. 为每枚灵宝计算自适应半径
	for i in range(count):
		var orb_a: float = float(orb_angles[i])
		var assigned_r := -1.0

		# 2.1 贴身危急优先内收自保：灵宝公转到危急敌人附近时，收缩到敌人身前封堵
		var closest_danger_dist := 9999.0
		if danger_count > 0:
			for de in enemies_info:
				var dd: float = float(de.get("dist", 9999.0))
				if dd > SPIRIT_DANGER_DIST:
					continue
				var de_ang: float = float(de.get("angle", 0.0))
				var diff := absf(wrapf(de_ang - orb_a, -PI, PI))
				if diff <= PI * 0.5 and dd < closest_danger_dist:
					closest_danger_dist = dd
		if closest_danger_dist < 9999.0:
			assigned_r = clampf(closest_danger_dist, min_radius, base_radius)

		# 2.2 扇区索敌扑击：灵宝正前方扇区内的最近敌人，灵宝动态外扩扑击
		if assigned_r < 0.0:
			var best_sector_dist := 9999.0
			for e in enemies_info:
				var ed: float = float(e.get("dist", 9999.0))
				if ed > max_reach:
					continue
				var e_ang: float = float(e.get("angle", 0.0))
				var diff := absf(wrapf(e_ang - orb_a, -PI, PI))
				if diff <= SPIRIT_SECTOR_HALF_ANGLE and ed < best_sector_dist:
					best_sector_dist = ed
			if best_sector_dist < 9999.0:
				assigned_r = clampf(best_sector_dist, min_radius, max_reach)

		# 2.3 环体自适应呼吸：未锁定单体时柔性匹配敌群平均基准，否则回归 base_radius
		if assigned_r < 0.0:
			assigned_r = avg_reach_dist

		_orbit_radii_buf[i] = assigned_r

	_orbit_res_buf["in_combat"] = in_combat
	return _orbit_res_buf

# ---------------- 多武器神识分流（仿土豆兄弟多武器负载与成长节拍） ----------------

const MULTI_WEAPON_LOAD_PER_EXTRA := 0.15  ## 每多御使一把武器的神识分流系数
## 环绕灵宝的神识分流权重：召唤物自主作战、不占主人神识，按半权计入分流。
## （机关炮台不半权：它已有多座并发 + 机关羁绊乘区两条成长线。2026-10-11 用户「全召唤打 Boss 磨血」）
const MULTI_WEAPON_DRONE_WEIGHT := 0.5

## 纯函数：根据当前上阵武器总数（含悬浮武器与环绕灵物），计算单把武器的直击神识分流效率
## 1 把: 1.00 (100%), 2 把: ~0.870 (总 1.74x), 3 把: ~0.769 (总 2.31x), 4 把: ~0.690 (总 2.76x),
## 5 把: ~0.625 (总 3.12x), 6 把: ~0.571 (总 3.43x)。
## 每多买一把武器总输出稳步提升，但 2026-10-15 反割草收紧（0.12→0.15，用户口径「多把武器伤害叠加就很容易割草」）：
## 6 把总输出 3.75x→3.43x，把成型期的叠加收益压回与敌人血量曲线相称的档位，同时抬高「三合一升星腾槽位」的相对收益。
## drone_count：其中环绕灵宝的把数，按 MULTI_WEAPON_DRONE_WEIGHT 半权折算
##（纯御灵 6 把：有效 3 把 ⇒ 单把 ~0.769，总 4.62x —— 以多打少不再被神识分流拖死）。
static func multi_weapon_damage_mult(slot_count: int, drone_count: int = 0) -> float:
	var eff_slots := float(maxi(1, slot_count)) \
		- MULTI_WEAPON_DRONE_WEIGHT * float(clampi(drone_count, 0, maxi(1, slot_count)))
	return 1.0 / (1.0 + MULTI_WEAPON_LOAD_PER_EXTRA * (eff_slots - 1.0))
