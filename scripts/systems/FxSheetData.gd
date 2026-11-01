class_name FxSheetData
extends RefCounted

## pixelfx 贴图帧视觉特效静态配置数据库
## 集中管理离线导出的 2D 序列帧元数据、缩放尺度、锚点偏移、发光起辉档位与朝向特性。
## 与 tools/pixelfx_manifest.json 保持单一真话源同源。

const RES_BASE_PATH := "res://assets/art/fx_pixelfx/"

## 特效字典元数据定义
const CONFIGS: Dictionary = {
	&"lightning_strike": {
		"tres": "res://assets/art/fx_pixelfx/lightning_strike.tres",
		"scale": 0.85,
		"anchor": "bottom",
		"pivot": Vector2(120, 240),
		"frame_size": Vector2(240, 264),
		"loop": false,
		"hdr": true,
		"z_ground": false,
		"element": "lightning"
	},
	&"hit_spark": {
		"tres": "res://assets/art/fx_pixelfx/hit_spark.tres",
		"scale": 0.45,
		"anchor": "center",
		"pivot": Vector2(44, 64),
		"frame_size": Vector2(136, 80),
		"loop": false,
		"hdr": true,
		"z_ground": false,
		"element": "core"
	},
	&"crit_hit": {
		"tres": "res://assets/art/fx_pixelfx/crit_hit.tres",
		"scale": 0.55,
		"anchor": "center",
		"pivot": Vector2(84, 106),
		"frame_size": Vector2(216, 136),
		"loop": false,
		"hdr": true,
		"z_ground": false,
		"element": "crit"
	},
	&"ice_spikes": {
		"tres": "res://assets/art/fx_pixelfx/ice_spikes.tres",
		"scale": 0.75,
		"anchor": "bottom",
		"pivot": Vector2(132, 104),
		"frame_size": Vector2(264, 112),
		"loop": false,
		"hdr": true,
		"z_ground": false,
		"element": "water"
	},
	&"earth_spike": {
		"tres": "res://assets/art/fx_pixelfx/earth_spike.tres",
		"scale": 0.70,
		"anchor": "bottom",
		"pivot": Vector2(136, 132),
		"frame_size": Vector2(272, 150),
		"loop": false,
		"hdr": false,
		"z_ground": true,
		"element": "earth"
	},
	&"sword_slash": {
		"tres": "res://assets/art/fx_pixelfx/sword_slash.tres",
		"scale": 0.65,
		"anchor": "center",
		"pivot": Vector2(44, 92),
		"frame_size": Vector2(136, 104),
		"loop": false,
		"hdr": true,
		"z_ground": false,
		"element": "metal"
	},
	&"arcane_beam": {
		"tres": "res://assets/art/fx_pixelfx/arcane_beam.tres",
		"scale": 0.70,
		"anchor": "left",
		"pivot": Vector2(26, 84),
		"frame_size": Vector2(264, 100),
		"loop": true,
		"hdr": true,
		"z_ground": false,
		"element": "shadow"
	},
	&"fire_breath": {
		"tres": "res://assets/art/fx_pixelfx/fire_breath.tres",
		"scale": 0.75,
		"anchor": "left",
		"pivot": Vector2(12, 72),
		"frame_size": Vector2(160, 116),
		"loop": true,
		"hdr": true,
		"z_ground": false,
		"element": "fire"
	},
	&"chest_open": {
		"tres": "res://assets/art/fx_pixelfx/chest_open.tres",
		"scale": 0.80,
		"anchor": "bottom",
		"pivot": Vector2(88, 102),
		"frame_size": Vector2(176, 112),
		"loop": false,
		"hdr": true,
		"z_ground": false,
		"element": "gold"
	},
	&"collect_burst": {
		"tres": "res://assets/art/fx_pixelfx/collect_burst.tres",
		"scale": 0.60,
		"anchor": "center",
		"pivot": Vector2(56, 94),
		"frame_size": Vector2(112, 108),
		"loop": false,
		"hdr": true,
		"z_ground": false,
		"element": "gold"
	},
	&"loot_beam": {
		"tres": "res://assets/art/fx_pixelfx/loot_beam.tres",
		"scale": 0.70,
		"anchor": "bottom",
		"pivot": Vector2(48, 162),
		"frame_size": Vector2(96, 176),
		"loop": true,
		"hdr": true,
		"z_ground": false,
		"element": "gold"
	},
	&"zap_hit": {
		"tres": "res://assets/art/fx_pixelfx/zap_hit.tres",
		"scale": 0.55,
		"anchor": "center",
		"pivot": Vector2(76, 56),
		"frame_size": Vector2(144, 112),
		"loop": false,
		"hdr": true,
		"z_ground": false,
		"element": "lightning"
	}
}

## 缓存已加载的 SpriteFrames 资源，避免重复磁盘 I/O
static var _frames_cache: Dictionary = {}

static func get_config(id: StringName) -> Dictionary:
	return CONFIGS.get(id, {})

static func get_sprite_frames(id: StringName) -> SpriteFrames:
	if _frames_cache.has(id):
		return _frames_cache[id]
	var conf: Dictionary = get_config(id)
	if conf.is_empty():
		return null
	var path: String = conf.get("tres", "")
	if path == "" or not ResourceLoader.exists(path):
		return null
	var sf := load(path) as SpriteFrames
	if sf != null:
		_frames_cache[id] = sf
	return sf

## 根据锚点类型和元数据计算针对 AnimatedSprite2D 的 offset
## 使得 (0, 0) 正好对准实际受击点或地面落点
static func get_offset(id: StringName) -> Vector2:
	var conf: Dictionary = get_config(id)
	if conf.is_empty():
		return Vector2.ZERO
	var fw: float = conf["frame_size"].x
	var fh: float = conf["frame_size"].y
	var pivot: Vector2 = conf["pivot"]
	var anchor: String = conf.get("anchor", "center")

	match anchor:
		"center":
			# 中心对齐：补偿 pivot 与几何中心差距
			return (Vector2(fw * 0.5, fh * 0.5) - pivot)
		"bottom":
			# 脚底对齐：将 pivot 的 y 贴底对准
			return Vector2(fw * 0.5 - pivot.x, fh * 0.5 - pivot.y)
		"left":
			# 射出起点向右发射对齐
			return Vector2(fw * 0.5 - pivot.x, fh * 0.5 - pivot.y)
		_:
			return Vector2.ZERO

## 判定该效果在水平朝左时是否需要翻转（pixelfx 默认全部面朝右方）
static func should_flip_h(id: StringName, facing_dir: Vector2) -> bool:
	if facing_dir.x < -0.01:
		return true
	return false

static func clear_cache() -> void:
	_frames_cache.clear()
