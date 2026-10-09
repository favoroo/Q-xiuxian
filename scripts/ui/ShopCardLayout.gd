class_name ShopCardLayout
extends RefCounted

## 商店与悟道卡片式弹窗的通用布局算术工具
## 统一承载 WaveShop 与 LevelUpDialog 的斜切几何推导、留白与卡宽计算。

## 斜切把面板或卡片画出来的左右边推到布局盒外多少：
## 引擎按布局盒竖直中线居中斜切（style_box_flat.cpp: x_skew = -skew.x * (y - center.y)）
## ⇒ 上下各伸出半个斜切量。
static func skew_x(skew_rad: float, h: float) -> float:
	return absf(skew_rad) * h * 0.5

## 这一档屏高下面板该占的高
static func panel_h_for(screen_h: float, min_h: float = 420.0, pad_y: float = 24.0) -> float:
	return maxf(min_h, screen_h - pad_y)

## 滚动区左右要留的白：卡片斜切画出来的角比布局盒左右各宽 |skew|·h/2。
## 加 2.0 像素防边缘截断。
static func card_pad_x(card_skew_rad: float, h: float) -> float:
	return ceilf(absf(card_skew_rad) * h * 0.5) + 2.0

## 卡片里文字可用的宽（卡宽 - 两头内边距）
static func card_inner_w(card_w: float, pad_x: float) -> float:
	return card_w - pad_x * 2.0

## 选中缩放动画上下各让出的余量（保证放大后不被滚动区剪切）
static func pop_gutter_y(panel_h: float, sel_scale: float = 1.03) -> float:
	return ceilf(panel_h * (sel_scale - 1.0) / (2.0 * sel_scale)) + 2.0

## 线性计算卡间缝隙并夹在 min/max 之间
static func gap_for(avail: float, factor: float, gap_min: float, gap_max: float) -> float:
	return clampf(avail * factor, gap_min, gap_max)
