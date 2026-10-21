class_name BakedDecorTexture
extends RefCounted

## 战场静态装饰层烘焙（2026-10-17 真机 42fps GPU 专项）：
## GroundDecorLayer（±522 地面微细节，~116 小点曾吃 14.6k 图元）与 ArenaVisualLayer
## 的 StaticDecor（±568 砌缝/符印底座/镇魂阵角，~340 条指令）都是「纯色无纹理采样 +
## 固定种子确定性 + 零重绘」的静态矢量——GPU bound 下每帧重放指令缓冲纯属浪费。
## 本工具把它们离屏渲染成一张 2× 分辨率 ImageTexture，挂一张 Sprite2D 代替两层矢量；
## 动态部分（ArenaVisual 的太极阵自转/灵脉呼吸/灵枢脉冲）不在烘焙范围，照走矢量层。
## 回退保底：headless（dummy 渲染器读不回像素，同 EnemyIconCapture 先例）或抓帧异常
## 时返回 null，调用方保持原两层矢量绘制——烘焙失败视觉零差异，只是省不了图元。
## 烘焙点：Main._ready 一局一次（场景重建随 _ready 重跑，静态缓存随场景 _exit_tree 清）。

const CANVAS_HALF := 568.0        ## 画布半边（包住 StaticDecor 的 ±568）
const BAKE_SCALE := 2             ## 离屏 2× 分辨率（2240²）：缩回战场后小点密度不变
const SPRITE_POS := -568.0        ## 挂载 Sprite2D 的左上角世界坐标

static var _texture: ImageTexture = null

## 烘焙成功标志（判据与调用方回退判定用）
static func is_baked() -> bool:
	return _texture != null

static func clear() -> void:
	_texture = null

## 异步烘焙：返回挂载用 Sprite2D（成功）或 null（失败→调用方回退矢量层）。
	## half 传战场半边长（480），烘焙内容与原两层几何完全一致。
static func bake(half: float) -> Sprite2D:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return null
	# headless 用 dummy 渲染后端，SubViewport 纹理读不回像素（同 EnemyIconCapture 先例）
	if DisplayServer.get_name() == "headless":
		return null
	var size := int(CANVAS_HALF * 2.0 * BAKE_SCALE)
	var host := Node2D.new()
	var vp := SubViewport.new()
	vp.size = Vector2i(size, size)
	vp.transparent_bg = true
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	host.add_child(vp)
	# 内容装配：坐标平移到画布中心（离屏相机原点=画布中心），2× 缩放保小点密度
	var content := Node2D.new()
	content.position = Vector2(size, size) * 0.5
	content.scale = Vector2(BAKE_SCALE, BAKE_SCALE)
	vp.add_child(content)
	var decor := GroundDecorLayer.new()
	decor.half_extent = half
	content.add_child(decor)
	var static_decor := ArenaVisualLayer.StaticDecor.new()
	static_decor.half = half
	content.add_child(static_decor)
	# 注意（2026-10-21）：调用方在 Main._ready 期间经 await 进来，此时 root 可能仍处于
	# 「正在装配子节点」状态，直接 add_child 会报 "Parent node is busy setting up children"
	# 并静默失败（烘焙永不生效、装饰层回退矢量）。先等一拍让装配结束再挂离屏宿主。
	await tree.process_frame
	if not is_instance_valid(tree.root):
		return null
	tree.root.add_child(host)
	# UPDATE_ONCE 的绘制在帧尾落纹理：等 3 帧（同 EnemyIconCapture 口径）
	for i in range(3):
		await tree.process_frame
	var img: Image = null
	if is_instance_valid(vp):
		var tex := vp.get_texture()
		if tex != null:
			img = tex.get_image()
	if img == null or img.is_empty() or not img.get_used_rect().has_area():
		if is_instance_valid(host):
			host.queue_free()
		return null
	# 桌面抓出来是 RGBA8 行序，直接建纹理；压缩交给导入/驱动，运行时不压
	_texture = ImageTexture.create_from_image(img)
	host.queue_free()
	if _texture == null:
		return null
	var sprite := Sprite2D.new()
	sprite.name = "BakedDecor"
	sprite.texture = _texture
	sprite.centered = false
	sprite.position = Vector2(SPRITE_POS, SPRITE_POS)
	sprite.scale = Vector2.ONE / float(BAKE_SCALE)
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	sprite.z_index = 0
	return sprite
