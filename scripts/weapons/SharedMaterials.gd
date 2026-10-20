class_name SharedMaterials
extends RefCounted

## 武器侧共享材质单例（2026-10-20 移动端 draw call 专项）
## 背景：FloatingWeapon 每把武器的 aura / muzzle_flash 各 `CanvasItemMaterial.new()` 一份
## ADD 混合材质，TurretUnit 枪口闪光同样各自新建 —— 6 把武器 ≈ 12+ 份独享 ADD 材质，
## 每份都是独立材质桶，跨武器无法合批，是固定 draw call 基底的稳定来源。
## ADD 混合无 per-instance 参数（颜色走 sprite 的 modulate），因此可全体共享同一实例。
## 注意：material 会被多节点引用，绝不能在其中写入实例级 uniform（本项目也未写）。

static var _add_mat: CanvasItemMaterial = null

## 共享的 ADD 混合 CanvasItemMaterial（懒建一次，全局复用）
static func add_blend() -> CanvasItemMaterial:
	if _add_mat == null:
		_add_mat = CanvasItemMaterial.new()
		_add_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	return _add_mat

## 退出场景时释放静态引用（防 "resources still in use at exit" 假警报）
static func clear() -> void:
	_add_mat = null
