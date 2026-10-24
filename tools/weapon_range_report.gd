extends SceneTree
## 全武器「伤害 × 范围」分布体检（临时报表工具，不进判据）
## 运行: G=/Applications/Godot.app/Contents/MacOS/Godot
##       $G --headless --path . --script res://tools/weapon_range_report.gd
## 口径：★1 基础面板，不含玩家属性/羁绊/暴击。
## - 单体 DPS = WeaponData.sustained_single_dps（官方尺子：灼烧/剧毒按常驻折算、环绕×接触占空比、机关按 turret_fire_cd）
## - 单次总伤 = 单发 × 发数（出膛口径）；弹射/穿透的额外目标数不计入此列
## - 总伤×射程 / DPS×射程：跨类别比无意义（近战贴脸风险溢价是设计取向），同类内比才见离群

const _CAT: Array[String] = ["近战", "横扫", "点杀远程", "铺面/弹射", "范围爆", "光束", "喷吐", "环绕", "机关"]

func _cmp(a: Dictionary, c: Dictionary) -> bool:
	if int(a["cat"]) != int(c["cat"]):
		return int(a["cat"]) < int(c["cat"])
	return float(a["prod"]) < float(c["prod"])

func _min_of(a: Array) -> float:
	var m := float(a[0])
	for v in a:
		m = minf(m, float(v))
	return m

func _max_of(a: Array) -> float:
	var m := float(a[0])
	for v in a:
		m = maxf(m, float(v))
	return m

func _avg_of(a: Array) -> float:
	var s := 0.0
	for v in a:
		s += float(v)
	return s / maxf(1.0, float(a.size()))

func _init() -> void:
	var wd: GDScript = load("res://scripts/data/WeaponData.gd")
	var defs: Dictionary = wd.DEFS
	var rows: Array = []
	for id in defs.keys():
		var def: Dictionary = defs[id]
		var b := int(def.get("behavior", 0))
		var dmg := float(def.get("damage", 0.0))
		var cd := maxf(0.05, float(def.get("cooldown", 1.0)))
		var count := maxi(1, int(def.get("projectile_count", 1)))
		var volley := dmg * float(count)
		var dps := float(wd.sustained_single_dps(id, 1))
		var rng := float(def.get("range", 0.0))
		# 群体潜力（直伤 + 基准异常量）：弹丸逐跳衰减（BladeProjectile.PIERCE_HIT_DECAY=0.5，同一发
		# 第 2 跳起减半；多发齐射是独立弹丸各发全额）。异常量按官方尺子基准 dmg×ratio×uptime
		# （运行时叠层共鸣已加帽：毒 ≤×3 / 灼烧 ≤×2.5，见 BalanceCombat.POISON_CAP_MULT/BURN_CAP_MULT）。
		# 非弹丸类无衰减，按官方 targets_per_shot 粗估目标数。
		var factor := 1.0
		if b == 1: # PROJECTILE
			var per_bullet := maxi(1, int(def.get("pierce", 1))) + maxi(0, int(def.get("bounce_count", 0)))
			factor = 2.0 * (1.0 - pow(0.5, float(per_bullet)))
		else:
			factor = float(maxi(1, int(wd.targets_per_shot(id))))
		var period := cd
		if b == 4: # TURRET：机关按每座开火间隔算 DPS（双座常驻 ×2 见分析）
			period = maxf(0.1, float(def.get("turret_fire_cd", 0.75)))
		var dot_ratio := 0.0
		if bool(def.get("proc_burn", false)):
			dot_ratio += float(def.get("burn_ratio", 0.4)) * minf(1.0, float(def.get("burn_dur", 3.0)) / period)
		if bool(def.get("proc_poison", false)):
			dot_ratio += float(def.get("poison_ratio", 0.3)) * minf(1.0, float(def.get("poison_dur", 2.5)) / period)
		# 展示分类：0近战 1横扫 2点杀远程 3铺面/弹射 4范围爆 5光束 6喷吐 7环绕 8机关
		var cat := 0
		match b:
			0: cat = 0
			5: cat = 1
			1: cat = 2 if bool(wd.is_focus_ranged(id)) else 3
			2: cat = 4
			6: cat = 5
			7: cat = 6
			3: cat = 7
			4: cat = 8
		rows.append({
			"cat": cat, "name": String(def.get("name", id)),
			"dmg": dmg, "count": count, "volley": volley, "cd": cd,
			"dps": dps, "rng": rng, "prod": dps * rng,
			"gprod": volley * factor * (1.0 + dot_ratio) / period * rng,
		})
	rows.sort_custom(_cmp)

	print("全武器共 %d 把（★1 基础面板，不含玩家属性/羁绊/暴击）" % rows.size())
	print("| 武器 | 类别 | 伤害 | 发数 | 单次总伤 | 冷却 | 单体DPS | 射程 | 总伤×射程 | DPS×射程 | 铺面潜力×射程 |")
	print("|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|")
	var by_cat := {}
	for r in rows:
		print("| %s | %s | %.1f | %d | %.1f | %.2f | %.1f | %.0f | %.0f | %.0f | %.0f |" % [
			r["name"], _CAT[int(r["cat"])], r["dmg"], r["count"], r["volley"],
			r["cd"], r["dps"], r["rng"], float(r["volley"]) * float(r["rng"]), r["prod"], r["gprod"],
		])
		var cat := int(r["cat"])
		if not by_cat.has(cat):
			by_cat[cat] = {"dmg": [], "dps": [], "prod": []}
		(by_cat[cat]["dmg"] as Array).append(float(r["dmg"]))
		(by_cat[cat]["dps"] as Array).append(float(r["dps"]))
		(by_cat[cat]["prod"] as Array).append(float(r["prod"]))

	print("\n== 分类汇总 ==")
	for cat in by_cat.keys():
		var dmg_arr: Array = by_cat[cat]["dmg"]
		var dps_arr: Array = by_cat[cat]["dps"]
		var prod_arr: Array = by_cat[cat]["prod"]
		print("%s: n=%d | 单发 %.1f—%.1f(avg %.1f) | 单体DPS %.1f—%.1f(avg %.1f) | DPS×射程 %.0f—%.0f(avg %.0f)" % [
			_CAT[int(cat)], dps_arr.size(),
			_min_of(dmg_arr), _max_of(dmg_arr), _avg_of(dmg_arr),
			_min_of(dps_arr), _max_of(dps_arr), _avg_of(dps_arr),
			_min_of(prod_arr), _max_of(prod_arr), _avg_of(prod_arr),
		])
	quit()
