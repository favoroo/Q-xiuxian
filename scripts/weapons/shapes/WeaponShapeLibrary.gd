extends RefCounted

## 法器器形族模块调度库（矢量重绘总入口）
##
## 宿主 ProceduralWeaponRenderer._draw() 先问本库：任一族模块接管了该器形（返回 true）
## 就用新画法并直接返回；全部族都未接管（返回 false）则回退宿主内的旧画法，灰度增量不破现状。
##
## 并行协作约定：重绘/新增器形只改对应族模块文件，别动本库与宿主；
## 族模块一律按路径 preload（不加 class_name），避免新类名触发全局扫描串行点。

## 新野兽派重绘三族（2026-10-24）：优先接管；未接管的器形继续落旧族模块/宿主旧画法。
const BrutalistBladeShapes = preload("res://scripts/weapons/shapes/BrutalistBladeShapes.gd")
const BrutalistHeavyShapes = preload("res://scripts/weapons/shapes/BrutalistHeavyShapes.gd")
const BrutalistCraftShapes = preload("res://scripts/weapons/shapes/BrutalistCraftShapes.gd")
const BladeShapes = preload("res://scripts/weapons/shapes/BladeShapes.gd")
const TalismanShapes = preload("res://scripts/weapons/shapes/TalismanShapes.gd")
const HeavyShapes = preload("res://scripts/weapons/shapes/HeavyShapes.gd")
const LongShapes = preload("res://scripts/weapons/shapes/LongShapes.gd")
const FineShapes = preload("res://scripts/weapons/shapes/FineShapes.gd")

const _FAMILIES := [
	BrutalistBladeShapes, BrutalistHeavyShapes, BrutalistCraftShapes,
	BladeShapes, TalismanShapes, HeavyShapes, LongShapes, FineShapes,
]

## 返回 true = 族模块已接管并完成绘制；false = 未实现，宿主回退旧画法
static func draw_shape(shape: int, r: ProceduralWeaponRenderer) -> bool:
	for fam in _FAMILIES:
		if fam.draw_shape(shape, r):
			return true
	return false
