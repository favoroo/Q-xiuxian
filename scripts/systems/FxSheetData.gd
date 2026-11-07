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
		# 2026-11-01 缩到 0.60（原 0.85）：原画幅 204×224 是身位光柱的 4 倍高、接近半屏，
		# 天罚每次暴击都劈一道，多把武器同开时几道巨雷叠起来就是「雷很乱」。
		# 0.60 ⇒ 画幅 144×158，仍是全场最大的一击，但不再压住半个战场。
		"scale": 0.60,
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
	## 已下线（2026-11-01）：WeaponArcRenderer 自己画的就是月牙刀光（六层锥形弧带 + 短拖尾），
	## 再叠这张 crescent 序列帧就是同一记挥砍出现两弯月牙（用户反馈「有点重复」）。
	## 近战/横扫的刀光读数只认判定同源的矢量弧（铁律 7），这张图不再接任何挥砍。
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
	## 已下线（2026-11-01）：这张 sheet 是「一整只匣子 + 一排骨币铺地」的独立小剧场，
	## 叠在真匣子上会出现第二只完好的箱子与一条假金币长条，与真实掉落对不上。
	## 破匣/祭坛都不再播它；要复用必须先在导出侧裁掉匣体与地排币，只留上方光爆。
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
	&"spirit_flame": {
		"tres": "res://assets/art/fx_pixelfx/spirit_flame.tres",
		# 2026-11-02 祭坛环绕灵火：每次成功召唤 +1 枚，围绕祭坛基座慢速环绕。
		# 80×124 源画幅，0.30 缩放到 ~24×37，单枚不压水晶；loop 常驻，不走一次性回收。
		"scale": 0.30,
		"anchor": "center",
		"pivot": Vector2(40, 94),
		"frame_size": Vector2(80, 124),
		"loop": true,
		"hdr": true,
		"z_ground": false,
		"element": "gold"
	},
	&"sunburst": {
		"tres": "res://assets/art/fx_pixelfx/sunburst.tres",
		# 2026-11-02 祭坛水晶灵光：垫在水晶背后的金白日轮，阶数越高越大越亮。
		# 128×128 源画幅，0.55 缩放到 ~70px；loop 常驻，由祭坛宿主控 alpha。
		"scale": 0.55,
		"anchor": "center",
		"pivot": Vector2(64, 64),
		"frame_size": Vector2(128, 128),
		"loop": true,
		"hdr": true,
		"z_ground": false,
		"element": "gold"
	},
	&"rune_circle": {
		"tres": "res://assets/art/fx_pixelfx/rune_circle.tres",
		# 2026-11-07 金符环（金色调，符文游转 + 追光扫环 + 浮尘上升，loop 常驻）。
		# 136×100 源画幅 ×1.8 ⇒ 符环半径 ≈83px。使用方：炮塔阵盘 / 敌环 / 刷怪预告
		# （祭坛、玩家光环曾用，2026-11-07「去花」下线——常驻件不挂循环特效，素材库保留他处照用）。
		"scale": 1.8,
		"anchor": "center",
		"pivot": Vector2(68, 80),
		"frame_size": Vector2(136, 100),
		"loop": true,
		"hdr": true,
		"z_ground": true,
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
		},
		## Boss 招式：炉君地火柱、赤炎起手
		&"flame_pillar": {
			"tres": "res://assets/art/fx_pixelfx/flame_pillar.tres",
			"scale": 0.60,
			"anchor": "bottom",
			"pivot": Vector2(92, 232),
			"frame_size": Vector2(184, 256),
			"loop": false,
			"hdr": true,
			"z_ground": false,
			"element": "fire"
		},
		## Boss 招式：陨火落地
		&"meteor_fall": {
			"tres": "res://assets/art/fx_pixelfx/meteor_fall.tres",
			"scale": 0.65,
			"anchor": "bottom",
			"pivot": Vector2(150, 208),
			"frame_size": Vector2(272, 232),
			"loop": false,
			"hdr": true,
			"z_ground": false,
			"element": "fire"
		},
		## Boss 招式：炉爆、凤皇涅槃
		&"fire_ring": {
			"tres": "res://assets/art/fx_pixelfx/fire_ring.tres",
			"scale": 0.70,
			"anchor": "center",
			"pivot": Vector2(112, 92),
			"frame_size": Vector2(224, 128),
			"loop": false,
			"hdr": true,
			"z_ground": false,
			"element": "fire"
		},
		## Boss 招式：雷劫震地
		&"thunderclap": {
			"tres": "res://assets/art/fx_pixelfx/thunderclap.tres",
			"scale": 0.65,
			"anchor": "bottom",
			"pivot": Vector2(144, 124),
			"frame_size": Vector2(288, 156),
			"loop": false,
			"hdr": true,
			"z_ground": false,
			"element": "lightning"
		},
		## Boss 招式：召唤、换桩、镜影
		&"summon_circle": {
			"tres": "res://assets/art/fx_pixelfx/summon_circle.tres",
			"scale": 0.65,
			"anchor": "center",
			"pivot": Vector2(100, 192),
			"frame_size": Vector2(200, 220),
			"loop": false,
			"hdr": true,
			"z_ground": false,
			"element": "shadow"
		},
		## Boss 招式：心魔/天魔起手
		&"hex_sigil": {
			"tres": "res://assets/art/fx_pixelfx/hex_sigil.tres",
			"scale": 0.65,
			"anchor": "center",
			"pivot": Vector2(84, 112),
			"frame_size": Vector2(168, 128),
			"loop": false,
			"hdr": true,
			"z_ground": false,
			"element": "shadow"
		},
		## Boss 招式：子母弹内爆
		&"void_implosion": {
			"tres": "res://assets/art/fx_pixelfx/void_implosion.tres",
			"scale": 0.65,
			"anchor": "center",
			"pivot": Vector2(104, 92),
			"frame_size": Vector2(208, 184),
			"loop": false,
			"hdr": true,
			"z_ground": false,
			"element": "shadow"
		},
		## Boss 招式：震地/俯冲落地
		&"ground_slam": {
			"tres": "res://assets/art/fx_pixelfx/ground_slam.tres",
			"scale": 0.65,
			"anchor": "bottom",
			"pivot": Vector2(144, 164),
			"frame_size": Vector2(288, 208),
			"loop": false,
			"hdr": false,
			"z_ground": false,
			"element": "earth"
		},
		## Boss 招式：激光充能（会被 follow 到 Boss 身上）
		&"cast_charge": {
			"tres": "res://assets/art/fx_pixelfx/cast_charge.tres",
			"scale": 0.70,
			"anchor": "bottom",
			"pivot": Vector2(44, 80),
			"frame_size": Vector2(120, 86),
			"loop": false,
			"hdr": true,
			"z_ground": false,
			"element": "shadow"
		},
		## 2026-11-07 线条圈通刷：刷怪预警妖气裂隙（地面撕开再拧灭，shadow 紫黑）。
		## 挂地面档，垫在预警红环之下；精英/Boss 必播，普通怪随帧闸自然丢弃（红环仍是主体）。
		&"spawn_portal": {
			"tres": "res://assets/art/fx_pixelfx/spawn_portal.tres",
			"scale": 0.70,
			"anchor": "bottom",
			"pivot": Vector2(104, 122),
			"frame_size": Vector2(208, 150),
			"loop": false,
			"hdr": true,
			"z_ground": true,
			"element": "shadow"
		},
		## 2026-11-07 线条圈通刷：音波环（音笛落点）——thunderclap 环段改烟紫冷调。
		## 替换 BurstKindFx._draw_sonic 三重矢量音波环；半径经 scale_mult 对齐判定。
		&"sonic_ring": {
			"tres": "res://assets/art/fx_pixelfx/sonic_ring.tres",
			"scale": 0.65,
			"anchor": "bottom",
			"pivot": Vector2(144, 124),
			"frame_size": Vector2(288, 156),
			"loop": false,
			"hdr": true,
			"z_ground": false,
			"element": "shadow"
		},
		## 2026-11-07 线条圈通刷：击杀爆炸（裂魂铃系）——等离子灵爆（ember 绯金）。
		## 替换 ExplosionFx 矢量主冲击环；碎块/烟粒子保留。
		&"kill_blast": {
			"tres": "res://assets/art/fx_pixelfx/kill_blast.tres",
			"scale": 0.60,
			"anchor": "center",
			"pivot": Vector2(112, 100),
			"frame_size": Vector2(224, 200),
			"loop": false,
			"hdr": true,
			"z_ground": false,
			"element": "fire"
		},
		## 2026-11-07 线条圈通刷：毒潭液面（沥青潭体+黄绿光脉+气泡，loop 常驻）。
		## 挂地面档，缩放经 scale_mult 与毒潭判定半径同步；不挂 HDR（常驻地面件省起辉）。
		&"toxic_puddle": {
			"tres": "res://assets/art/fx_pixelfx/toxic_puddle.tres",
			"scale": 0.90,
			"anchor": "center",
			"pivot": Vector2(88, 86),
			"frame_size": Vector2(176, 100),
			"loop": true,
			"hdr": false,
			"z_ground": true,
			"element": "water"
		},
		## 2026-11-07 线条圈通刷：火池液面——toxic-puddle 同源火调色板，与毒潭同缩放口径。
		&"ember_pool": {
			"tres": "res://assets/art/fx_pixelfx/ember_pool.tres",
			"scale": 0.90,
			"anchor": "center",
			"pivot": Vector2(88, 86),
			"frame_size": Vector2(176, 100),
			"loop": true,
			"hdr": false,
			"z_ground": true,
			"element": "fire"
		},
		## 2026-11-07 线条圈通刷：血海护盾罩——金球罩面改 ember 血调，球面经线+扫光 loop。
		## pivot(44,68)=罩体中心在画幅中偏上（原以假人身位为基准），挂玩家身位后罩心自然高于脚底。
		&"blood_ward": {
			"tres": "res://assets/art/fx_pixelfx/blood_ward.tres",
			"scale": 1.0,
			"anchor": "center",
			"pivot": Vector2(44, 68),
			"frame_size": Vector2(88, 84),
			"loop": true,
			"hdr": true,
			"z_ground": false,
			"element": "fire"
		},
		## 2026-11-07 线条圈通刷：治疗法阵——灵种落地青环滚开+十字光浮起（one-shot）。
		## 回春术青莲阵矢量环替换与灵医脉冲共用；挂地面档。
		&"heal_aoe": {
			"tres": "res://assets/art/fx_pixelfx/heal_aoe.tres",
			"scale": 0.90,
			"anchor": "center",
			"pivot": Vector2(128, 104),
			"frame_size": Vector2(256, 136),
			"loop": false,
			"hdr": true,
			"z_ground": true,
			"element": "heal"
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
