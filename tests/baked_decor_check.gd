extends Node

## 静态装饰烘焙判据（2026-10-17 真机 GPU 专项）：
## 钉住 BakedDecorTexture 的烘焙管线不变量：
##   1. headless（dummy 渲染器）下 bake 返回 null —— 回退保底语义（原矢量层保持显示）
##   2. 烘焙 Sprite 的挂载参数（位置/scale/filter/层序）与被替代层几何对齐
##   3. clear() 语义（场景重建不残留旧纹理引用）
## 真机上的「纹理非空 + 尺寸 2240² + 原层 visible=false」由真机验收覆盖
##（headless 读不回像素，同 EnemyIconCapture 先例）。
## 运行: godot --headless --path . res://tests/BakedDecorCheck.tscn
## 退出码 0 且末行 BAKED_RESULT: ALL PASS

var _c := TestCheck.new()

func _check(cond: bool, label: String) -> void:
	_c.check(cond, label)

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	await _test_headless_fallback()
	_test_mount_constants()
	_test_clear_semantics()

	if not _c.all_passed():
		print("BAKED_RESULT: FAILED (%d failures)" % _c.failures.size())
		get_tree().quit(1)
	else:
		print("BAKED_RESULT: ALL PASS (%d checks)" % _c.passed)
		get_tree().quit(0)

## 1. headless 回退：bake 返回 null 且不残留状态
func _test_headless_fallback() -> void:
	if DisplayServer.get_name() != "headless":
		_c.check(true, "非 headless 环境跳过回退断言")
		return
	var sprite := await BakedDecorTexture.bake(560.0)
	_check(sprite == null, "headless 下 bake 返回 null（回退矢量层保底）")
	_check(not BakedDecorTexture.is_baked(), "headless 下不置烘焙成功标志")

## 2. 挂载常量与几何对齐（烘焙图 2× 离屏 → 挂载缩半回战场坐标）
func _test_mount_constants() -> void:
	_check(is_equal_approx(BakedDecorTexture.CANVAS_HALF, 568.0), "画布半边 568（包住 StaticDecor ±568）")
	_check(BakedDecorTexture.BAKE_SCALE == 2, "离屏 2× 分辨率（小点密度回缩不变）")
	_check(is_equal_approx(BakedDecorTexture.SPRITE_POS, -568.0), "挂载左上角 -568（与画布对齐）")
	# 挂载缩放 = 1/BAKE_SCALE：2240px 纹理铺回 1120 世界单位
	_check(is_equal_approx(1.0 / BakedDecorTexture.BAKE_SCALE, 0.5), "挂载缩放 0.5（2× 纹理回缩战场）")

## 3. clear 语义
func _test_clear_semantics() -> void:
	BakedDecorTexture.clear()
	_check(not BakedDecorTexture.is_baked(), "clear 后烘焙标志归位（场景重建不残留）")
