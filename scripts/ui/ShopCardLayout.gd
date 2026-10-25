class_name ShopCardLayout
extends RefCounted

## 商店与悟道卡片式弹窗的通用布局算术工具
## 统一承载 WaveShop 与 LevelUpDialog 的斜切几何推导、留白与卡宽计算。
## 2026-10-24 常量收拢：两面板同名摆位常量过去在各文件各抄一份、靠头注「同源」人肉同步，
## 现在统一在这里定义（判据 layout_check 直读本类），改口径只动这一个文件。

# —— 两档面板共享值（同值同义才进这里；改一个就得改另一个的那种）——
const PANEL_SCREEN_PAD_Y := 24.0  ## 面板上下呼吸量（合计 24，各 12）
const PANEL_MIN_H := 420.0        ## 面板高下限

# —— 商店面板档（金币阁）：面板保留 2° 斜切视觉 ——
const SHOP_PANEL_AIR_X := 20.0    ## 面板左右呼吸量（斜切画出来的角之外再留）
## 与 WaveShop.tscn 的 StyleBoxFlat_panel.skew 同源（改 .tscn 里的 skew 必须同步这里，判据会核对两头留白）
const SHOP_PANEL_SKEW_RAD := 0.035
const SHOP_CARD_GAP_MIN := 10.0
const SHOP_CARD_GAP_MAX := 16.0
## 货架卡斜切，与 ShopOfferCardFactory 卡体 style.skew 同源
const SHOP_CARD_SKEW_RAD := 0.052

# —— 悟道面板档（回合后加点）：2026-10-19 新野兽派换肤全直角化，斜切归零 ——
const ALLOC_PANEL_AIR_X := 34.0   ## 面板左右呼吸量（直角面板比斜切的更贴边，多留一截）
## 与 LevelUpDialog.tscn 的 StyleBoxFlat_panel.skew 同源（直角化归零 = GameStyle.SLANT_PLATE，判据核对两边没漂）
const ALLOC_PANEL_SKEW_RAD := 0.0
const ALLOC_CARD_GAP_MIN := 5.0   ## 用户口径「左右间距小一点」，18 上限砍到 10（20:9 屏上 15→10）
const ALLOC_CARD_GAP_MAX := 10.0
## 悟道卡斜切，与 LevelUpDialog._create_card_entry 里 style.skew 同源（直角化归零）
const ALLOC_CARD_SKEW_RAD := 0.0

## 斜切把面板或卡片画出来的左右边推到布局盒外多少：
## 引擎按布局盒竖直中线居中斜切（style_box_flat.cpp: x_skew = -skew.x * (y - center.y)）
## ⇒ 上下各伸出半个斜切量。
static func skew_x(skew_rad: float, h: float) -> float:
	return absf(skew_rad) * h * 0.5

## 这一档屏高下面板该占的高
static func panel_h_for(screen_h: float, min_h: float = 420.0, pad_y: float = 24.0) -> float:
	return maxf(min_h, screen_h - pad_y)

## 滚动区左右要留的白：卡片斜切画出来的角比布局盒左右各宽 |skew|·h/2。
## 另保证留出选中放大与阴影余量（至少 8px），防边缘截断。
static func card_pad_x(card_skew_rad: float, h: float) -> float:
	var skew_pad := ceilf(absf(card_skew_rad) * h * 0.5)
	return maxf(skew_pad, 8.0) + 2.0

## 卡片里文字可用的宽（卡宽 - 两头内边距）
static func card_inner_w(card_w: float, pad_x: float) -> float:
	return card_w - pad_x * 2.0

## 选中缩放动画上下各让出的余量（保证放大后不被滚动区剪切）
static func pop_gutter_y(panel_h: float, sel_scale: float = 1.03) -> float:
	return ceilf(panel_h * (sel_scale - 1.0) / (2.0 * sel_scale)) + 2.0

## 线性计算卡间缝隙并夹在 min/max 之间
static func gap_for(avail: float, factor: float, gap_min: float, gap_max: float) -> float:
	return clampf(avail * factor, gap_min, gap_max)
