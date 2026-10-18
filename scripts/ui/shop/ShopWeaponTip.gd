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
	var feats := StatsTipFactory.weapon_feats(def)
	if not feats.is_empty():
		rows.append(["特性", feats])
	# 元素件这一行就是那圈暖橙红描边的解释（2026-10-12 用户：角标遮图，改用边框颜色说这件事）。
	# 描边是这一屏唯一的提示，点开必须还能读到字，否则颜色就成了没人教的暗号（同 GameStyle.is_elemental）。
	if GameStyle.is_elemental(id):
		var e_coef := WeaponData.elemental_scaling_coef(id)
		var e_edmg: float = float(GameManager.get_player_stat_dict().get("elemental_damage", 0.0))
		rows.append(["元素加成", "系数 ×%.1f · 当前元素伤害 %+.1f" % [e_coef, e_edmg], GameStyle.ELEMENT])

	var copies_total := GameManager.count_copies(id, star)
	var price := WeaponData.sell_price(id, star)
	var notes: Array[String] = [
		WeaponDamageReadout.bonus_bill_text(id, star),
	]
	if mergeable:
		notes.append("已集齐 3 件同名同星，可点击下方【三合一】升至 %s！" % WeaponData.star_text(star + 1))
	else:
		notes.append("三合一升星：同名同星集满 3 件可合成升星（当前持有 %d/3 件）。" % copies_total)

	var foot := "同名同星 %d 件 · 出售可得 %d 金币" % [copies_total, price]
	if in_stash:
		foot += "\n在背包中：未装备、不参与攻击，可用于三合一升星或换装装备。"

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
				if not GameManager.merge_weapon(id, star, keep):
					AudioManager.play_sfx("ui_error", 0.9)
				shop.selected = {}
				shop.refresh(false)
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
		"text": "售 %d 金币" % price,
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
