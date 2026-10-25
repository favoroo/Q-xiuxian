class_name ShopWeaponTip
extends RefCounted

## 商店武器悬浮详情卡：全部属性 + 流派进度 + 快捷操作（三合一 / 装备卸换 / 出售）。
## 从 WaveShop 拆出：宿主仍是 shop（DetailTip 判据按宿主收卡），操作回调经 shop 门面刷新。

static func open(shop: WaveShop, item: Dictionary, pool: String, index: int, anchor: Control) -> void:
	var id: String = String(item.get("id", ""))
	var def := WeaponData.get_def(id)
	if def.is_empty():
		return
	var star := clampi(int(item.get("star", 1)), 1, WeaponData.MAX_STAR)
	var in_stash := pool == "stash"
	var mergeable: bool = star < WeaponData.MAX_STAR and GameManager.count_copies(id, star) >= 3

	# 单发与节奏一律走 WeaponDamageReadout，与货架卡同一个数。
	# Fixed: 这条乘区链以前在弹窗里自己乘了一遍，漏了神识分流与机关羁绊 —— 挂 6 把武器时
	# 把实际的 32.5 报成 52（虚高 60%），玩家按面板数字判断"这把值不值"必然判错。
	var slots_here := GameManager.slots_used()
	if in_stash and slots_here < GameManager.max_weapon_slots():
		slots_here += 1
	var per_hit: float = WeaponDamageReadout.per_hit(id, star, slots_here)
	var cd := WeaponDamageReadout.effective_cd(id, star)
	var base_range: float = float(def.get("range", 0.0))
	var eff_range: float = base_range * GameManager.attack_range_mult * GameManager.synergy_range_mult
	var range_buffed: bool = not is_equal_approx(eff_range, base_range)
	var range_txt: String = "%.0f" % eff_range
	if range_buffed:
		range_txt = "%.0f（基础 %.0f）" % [eff_range, base_range]

	var syn_parts: Array[String] = []
	for t in def.get("tags", []):
		var sinfo: Dictionary = WeaponData.SYNERGIES.get(t, {})
		if not sinfo.is_empty():
			var cnt: int = GameManager.get_tag_count(String(t))
			syn_parts.append("%s(%d/6)" % [sinfo.get("name", t), cnt])

	var max_slots: int = GameManager.max_weapon_slots()
	var slots_full: bool = GameManager.slots_used() >= max_slots
	var loc_txt := "背包中" if in_stash else "装备中"
	if in_stash and slots_full:
		loc_txt = "背包中（装备已满 %d/%d）" % [GameManager.slots_used(), max_slots]

	# 「基础 × 星级」「属性转化」两行删掉：箭头行已经把"纸面 → 你现在"讲完，
	# 系数从哪来改由下方账单句按伤害单位逐项交代（2026-10-11 用户：看不懂"属性加成"是什么）。
	var rows: Array = [
		["当前位置", loc_txt, GameStyle.PAPER_DIM if in_stash else GameStyle.GOOD],
		["攻击方式", WeaponData.behavior_label(def), StatsTipFactory.behavior_color(def)],
		["单发伤害", WeaponDamageReadout.arrow_text(WeaponData.damage_for(id, star), per_hit),
				GameStyle.JADE],
		[WeaponDamageReadout.per_second_label(id), BonusRows.fmt_num(
				WeaponDamageReadout.per_second(id, star, slots_here)), GameStyle.JADE],
		["流派进度", " · ".join(syn_parts) if not syn_parts.is_empty() else "—", GameStyle.GOOD],
		["攻击间隔", "%.2f 秒" % cd],
		["攻击范围", range_txt, GameStyle.JADE if range_buffed else GameStyle.PAPER],
	]
	# 落雷/区域类：卡面「攻击范围」是锁敌落点圈，真正的爆炸半径是另一个字段（burst_radius）。
	# 不补这行会出现「范围 265 的金雷锥炸得比范围 250 的巨印还小」的观感反差（2026-10-20 射程体系重做）。
	if int(def.get("behavior", -1)) == WeaponData.Behavior.BURST:
		var base_br := float(def.get("burst_radius", 0.0))
		var eff_br := base_br * GameManager.attack_range_mult * GameManager.synergy_range_mult
		var br_txt := "%.0f" % eff_br
		if not is_equal_approx(eff_br, base_br):
			br_txt = "%.0f（基础 %.0f）" % [eff_br, base_br]
		rows.append(["爆炸半径", br_txt, GameStyle.PAPER])
	var feats := StatsTipFactory.weapon_feats(def)
	if not feats.is_empty():
		rows.append(["特性", feats])
	# ★3 觉醒 / ★4 极境两行：合成前就看得见「升到几星会解锁什么」（未达成灰色预告，达成亮色）——
	# 文案唯一真话在 WeaponData.star3_perk_desc / star4_perk_desc，别处不许再拼一份。
	var perk_desc := WeaponData.star3_perk_desc(id)
	if not perk_desc.is_empty():
		rows.append(["★3 觉醒", perk_desc, GameStyle.GOLD if star >= 3 else GameStyle.PAPER_DIM])
	var asc_desc := WeaponData.star4_perk_desc(id)
	if not asc_desc.is_empty():
		rows.append(["★4 极境", asc_desc, GameStyle.STAR4_NEON if star >= WeaponData.MAX_STAR else GameStyle.PAPER_DIM])
	# 元素件这一行就是那圈暖橙红描边的解释（2026-10-12 用户：角标遮图，改用边框颜色说这件事）。
	# 描边是这一屏唯一的提示，点开必须还能读到字，否则颜色就成了没人教的暗号（同 GameStyle.is_elemental）。
	if GameStyle.is_elemental(id):
		var e_coef := WeaponData.elemental_scaling_coef(id)
		var e_edmg: float = float(GameManager.get_player_stat_dict().get("elemental_damage", 0.0))
		rows.append(["元素加成", "系数 ×%.1f · 当前元素伤害 %+.1f" % [e_coef, e_edmg], GameStyle.ELEMENT])

	var copies_total := GameManager.count_copies(id, star)
	var price := GameManager.weapon_sell_price(id, star)
	var notes: Array[String] = [
		WeaponDamageReadout.bonus_bill_text(id, star),
	]
	if mergeable:
		notes.append("已集齐 3 件同名同星，可点击下方【三合一】升至 %s！" % WeaponData.star_text(star + 1))
	else:
		notes.append("三合一升星：同名同星集满 3 件可合成升星（当前持有 %d/3 件）。" % copies_total)

	# 报价差异必须写明白：初始武器与后来买到的同名副本卖价不同，玩家只能从这里看出来。
	# 只改文案不加行 —— 这张卡本来就在 540 高度边缘，多一行会顶出视口。
	var starter_price: bool = WeaponInventory.starter_bonus_applies(GameManager, id)
	var foot := "同名同星 %d 件 · %s %d 金币" % [
		copies_total, "初始武器原价回收" if starter_price else "出售可得", price]
	if in_stash:
		foot += "\n在背包中：未装备、不参与攻击，可用于三合一升星或换装装备。"

	# 合成演出的起飞点/落点：keeper 是点开的这一格，另外两件从陈列行里按同名同星扫出来。
	# 现在抓而不是等按下再抓：卡片开着时遮罩挡着滚动，这一刻的矩形就是玩家眼睛里的位置
	# （详情卡一关，槽位会被重建，新节点得等下一帧才有 rect）
	var merge_sources: Array = []
	if mergeable:
		merge_sources = _collect_merge_sources(shop, id, star, pool, index, anchor)

	var actions: Array = []
	if mergeable:
		actions.append([{
			"text": "◆ 三合一 · 升至 %s ◆" % WeaponData.star_text(star + 1),
			"color": GameStyle.JADE,
			"edge_color": GameStyle.JADE_EDGE,
			"text_color": GameStyle.INK_TEXT,
			"callback": func() -> void:
				var keep := {"pool": "equipped", "index": index}
				if in_stash:
					keep["pool"] = "stash"
				elif item.get("is_drone", false):
					keep["pool"] = "drone"
					keep["index"] = int(item.get("drone_index", -1))
				# 详情卡开着时遮罩挡着操作，状态不会变；这里再核一次只是兜底 ——
				# 凑不齐三件就别播合成演出，免得动画放完却没合成
				if GameManager.count_copies(id, star) < 3:
					AudioManager.play_sfx("ui_error", 0.9)
					shop.selected = {}
					shop.refresh(false)
					return
				# 把两件被消耗的图标从各自格子里拎起来，飞进 keeper 那一格再合成（2026-10-24 用户
				# 要的就是「那几个图标一起移动到要合成的那个位置」）。起飞/落点矩形在开卡那一刻
				# 就抓好了（merge_sources）—— 按键时旧行正被 queue_free、新行还没排布局，现抓只
				# 能抓到零矩形。原件（含重建出来的同名格子）当场藏掉，迸发帧 refresh 一并重建。
				var target_rect := Rect2()
				var fly_rects: Array[Rect2] = []
				for i in range(merge_sources.size()):
					var entry: Dictionary = merge_sources[i]
					var rect: Rect2 = entry.get("rect", Rect2())
					if i == 0:
						target_rect = rect
					else:
						fly_rects.append(rect)
						_hide_row_slots(shop, entry.get("src", {}))
				var icon_path := String(def.get("icon", ""))
				if icon_path.is_empty():
					icon_path = String(item.get("icon", ""))
				# 同池里排在 keeper 之前的副本被吃掉后，keeper 会向左补位：算出重建后的下标，
				# 让结果图标滑行跟到格子的最终位置（不然会停在原地、格子已挪走）
				var keeper_shift := 0
				for i in range(1, merge_sources.size()):
					var cs: Dictionary = (merge_sources[i] as Dictionary).get("src", {})
					if String(cs.get("pool", "")) == pool and int(cs.get("index", -1)) < index:
						keeper_shift += 1
				var final_src := {"pool": pool, "index": index - keeper_shift}
				# 合成延到演出的迸发帧执行：merge_success / weapon_awaken 音效、陈列行刷新出的
				# 新星图标、keeper 上的迸发同帧落地，声画才对齐（演出本身是纯表现层，见 MergeFx 头注）
				MergeFx.play_slots(shop, icon_path, fly_rects, target_rect, func() -> void:
					if not GameManager.merge_weapon(id, star, keep):
						AudioManager.play_sfx("ui_error", 0.9)
					# 演出这 0.2 秒里商店被关掉的极端路径兜底：合成数据已落地，只是没面板可刷
					if not is_instance_valid(shop):
						return
					shop.selected = {}
					shop.refresh(false)
				, func() -> Rect2:
					return _row_rect_matching(shop, final_src, id, star + 1))
		}])

	var row_ops: Array = []
	if in_stash:
		var move_disabled := slots_full
		var move_text := "装备已满(%d/%d)" % [GameManager.slots_used(), max_slots] if slots_full else "装 备"
		row_ops.append({
			"text": move_text,
			"disabled": move_disabled,
			"color": GameStyle.GOOD if not move_disabled else GameStyle.NAVY2,
			"edge_color": GameStyle.GOOD_DK if not move_disabled else GameStyle.LINE,
			"text_color": GameStyle.INK_TEXT if not move_disabled else GameStyle.GREY,
			"callback": func() -> void:
				if GameManager.equip_from_stash(index):
					shop.selected = {}
					shop.refresh(false)
		})
	else:
		var unequip_disabled := GameManager.stash.size() >= WeaponData.MAX_STASH_SLOTS
		var unequip_text := "背包已满" if unequip_disabled else "卸入背包"
		row_ops.append({
			"text": unequip_text,
			"disabled": unequip_disabled,
			"color": GameStyle.NAVY2,
			"edge_color": GameStyle.LINE,
			"text_color": GameStyle.PAPER if not unequip_disabled else GameStyle.GREY,
			"callback": func() -> void:
				if GameManager.unequip_to_stash(index):
					shop.selected = {}
					shop.refresh(false)
		})

	row_ops.append({
		"text": ("原价售 %d" if starter_price else "售 %d 金币") % price,
		"color": GameStyle.BAD,
		"edge_color": GameStyle.BAD_DK,
		"text_color": GameStyle.CHALK,
		"callback": func() -> void:
			var ok := false
			if in_stash:
				ok = GameManager.sell_stash(index)
			else:
				ok = GameManager.sell_weapon(index)
			if ok:
				shop.selected = {}
				shop.refresh(false)
	})
	actions.append(row_ops)

	var tip_data := {
		"title": "%s %s" % [String(def.get("name", "武器")), WeaponData.star_text(star)],
		"chip": " · ".join(syn_parts) if not syn_parts.is_empty() else String(def.get("tag", "")),
		"chip_color": GameStyle.JADE_DK if in_stash else GameStyle.GOLD_DK,
		"rows": rows,
		"body": String(def.get("desc", "")),
		"notes": notes,
		"foot": foot,
		"actions": actions,
	}

	var tip := DetailTip.show_over(shop, anchor, tip_data)
	if tip != null:
		tip.closed.connect(func() -> void:
			if shop.selected.get("pool", "") == pool and int(shop.selected.get("index", -1)) == index:
				shop.selected = {}
				shop._refresh_inventory()
		)

## 合成演出的参与者：第 0 项是 keeper（点开的这一格），随后是两件被消耗的副本。
## 每项 {"src": {"pool","index"}, "rect": 全局矩形}，src 抄的是槽位 drag_src 的登记口径。
## 消耗哪两件必须复刻 WeaponInventory 的选取顺序（背包 0→、灵宝 0→、悬浮武器从尾部←），
## 否则 4 件以上时飞的格子与实际被吃掉的格子对不上，重建后「飞走的格子又长回来」。
static func _collect_merge_sources(shop: WaveShop, w_id: String, star: int,
		keeper_pool: String, keeper_index: int, anchor: Control) -> Array:
	var out: Array = [{
		"src": {"pool": keeper_pool, "index": keeper_index},
		"rect": anchor.get_global_rect() if anchor != null and is_instance_valid(anchor) else Rect2(),
	}]
	if shop == null or not is_instance_valid(shop) or shop.owned_container == null:
		return out
	# 陈列行按池分桶（行的排列：悬浮武器 → 灵宝 → 分隔签 → 背包）
	var stash_hits: Array = []
	var drone_hits: Array = []
	var wpn_hits: Array = []
	for child in shop.owned_container.get_children():
		if not (child is Control) or not child.has_meta("drag_src"):
			continue
		var src: Dictionary = child.get_meta("drag_src")
		var sp := String(src.get("pool", ""))
		var si := int(src.get("index", -1))
		if sp != "equipped" and sp != "stash":
			continue
		if sp == keeper_pool and si == keeper_index:
			continue
		var it := _row_item_for(src)
		if it.is_empty() or String(it.get("id", "")) != w_id or int(it.get("star", 1)) != star:
			continue
		var entry := {"src": {"pool": sp, "index": si}, "rect": (child as Control).get_global_rect()}
		if sp == "stash":
			stash_hits.append(entry)
		elif bool(it.get("is_drone", false)):
			drone_hits.append(entry)
		else:
			wpn_hits.append(entry)
	# 复刻引擎消耗顺序：背包先、灵宝次、悬浮武器取尾部，满 2 件即止
	var consumed: Array = []
	for e in stash_hits:
		if consumed.size() >= 2:
			break
		consumed.append(e)
	for e in drone_hits:
		if consumed.size() >= 2:
			break
		consumed.append(e)
	var k := wpn_hits.size() - 1
	while k >= 0 and consumed.size() < 2:
		consumed.append(wpn_hits[k])
		k -= 1
	out.append_array(consumed)
	return out

## 陈列行 src（pool/index）→ 那件武器/灵宝的数据：上阵池按 summary 口径（悬浮武器在前、
## 灵宝在后），背包池按 stash 下标。空格 / 分隔签 / 越界一律空字典。
static func _row_item_for(src: Dictionary) -> Dictionary:
	var pool := String(src.get("pool", ""))
	var idx := int(src.get("index", -1))
	if pool == "equipped":
		var summary: Array = GameManager.get_weapons_summary()
		if idx >= 0 and idx < summary.size():
			return summary[idx]
	elif pool == "stash":
		if idx >= 0 and idx < GameManager.stash.size():
			return GameManager.stash[idx]
	return {}

## 按 src（pool/index）在当前陈列行里找格位的全局矩形，并核对该格确实是 w_id 的 new_star 件
## （合成会删格子、整行左移，重建后的下标要现算现比；核不上返回空矩形 = 结果图标停在原地）
static func _row_rect_matching(shop: WaveShop, src: Dictionary, w_id: String, new_star: int) -> Rect2:
	if shop == null or not is_instance_valid(shop) or shop.owned_container == null:
		return Rect2()
	var want_pool := String(src.get("pool", ""))
	var want_index := int(src.get("index", -1))
	for child in shop.owned_container.get_children():
		if not (child is Control) or not child.has_meta("drag_src"):
			continue
		var s: Dictionary = child.get_meta("drag_src")
		if String(s.get("pool", "")) != want_pool or int(s.get("index", -1)) != want_index:
			continue
		var it := _row_item_for(s)
		if String(it.get("id", "")) == w_id and int(it.get("star", 1)) == new_star:
			return (child as Control).get_global_rect()
		return Rect2()
	return Rect2()

## 按 src 把当前陈列行里那一格的原件藏掉（modulate 透明，不改尺寸不破布局判据）：
## 按键那一刻旧行正在被 queue_free、新行还没摆完，两个都找得到就都藏 ——
## 飞行体从开卡时抓好的矩形起飞，原件不藏会同时出现「格子里一个 + 飞行中一个」。
static func _hide_row_slots(shop: WaveShop, src: Dictionary) -> void:
	if shop == null or not is_instance_valid(shop) or shop.owned_container == null:
		return
	var want_pool := String(src.get("pool", ""))
	var want_index := int(src.get("index", -2))
	for child in shop.owned_container.get_children():
		if not (child is Control) or not child.has_meta("drag_src"):
			continue
		var s: Dictionary = child.get_meta("drag_src")
		if String(s.get("pool", "")) == want_pool and int(s.get("index", -1)) == want_index:
			(child as Control).modulate.a = 0.0
