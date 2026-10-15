class_name RecommendTip
extends RefCounted

## 「为什么推荐」详情卡的统一出口：商店货架卡与悟道卡各有一份同形实现，收口到这里。
## 理由是打分那一刻生成的只读快照（RecommendSystem 写入 offer.recommend_reasons），
## 不在 UI 里二次推算；宿主与锚点由调用方注入，与 DetailTip 同一宿主口径。

## host = 详情卡挂靠的面板（关面板时随子树一起收），anchor = 点的那颗「荐」签
static func open(host: Control, anchor: Control, reasons: Array, score: float) -> void:
	var notes: Array[String] = []
	for r in reasons:
		notes.append(String(r))
	DetailTip.show_over(host, anchor, {
		"title": "为什么推荐",
		"chip": "推荐度 %d%%" % int(round(score * 100.0)),
		"chip_color": GameStyle.JADE,
		"notes": notes,
		"foot": "由当前角色、上阵武器与属性推算，仅供参考。",
	})
