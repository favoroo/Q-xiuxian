class_name UpgradeData
extends RefCounted

const UPGRADES: Array[Dictionary] = [
    {
        "id": "add_sword",
        "title": "铝制球棒",
        "desc": "[center]在周身新增 [color=#7ce860][b]+1 根[/b][/color] 悬浮近战球棒\n• 自动抡击近身敌人，造成 [color=#ffd400][b]135%[/b][/color] 范围伤害\n• 附带 [color=#6fd6ff][b]强力击退[/b][/color] 效果[/center]",
        "rarity": "rare",
        "rarity_label": "稀有装备",
        "border_color": Color(1, 0.83, 0, 1),
        "tag": "新武器·近战",
        "icon": "res://assets/art/icon_bat.png"
    },
    {
        "id": "add_staff",
        "title": "自制弹弓",
        "desc": "[center]在周身新增 [color=#7ce860][b]+1 把[/b][/color] 悬浮远程弹弓\n• 独立索敌发射钢珠弹丸\n• 远距离压制狱警潮，射程 [color=#6fd6ff][b]420[/b][/color][/center]",
        "rarity": "rare",
        "rarity_label": "稀有装备",
        "border_color": Color(1, 0.83, 0, 1),
        "tag": "新武器·远程",
        "icon": "res://assets/art/icon_sling.png"
    },
    {
        "id": "blade_damage",
        "title": "加重打击",
        "desc": "[center]所有悬浮武器的基础伤害提升\n• 武器总伤害 [color=#ffd400][b]+35%[/b][/color]\n• 适用于全部弹弓与近战球棒[/center]",
        "rarity": "common",
        "rarity_label": "普通强化",
        "border_color": Color(0.96, 0.95, 0.92, 1),
        "tag": "全体武器强化",
        "icon": "res://assets/art/icon_wrench.png"
    },
    {
        "id": "blade_amount",
        "title": "多重弹丸",
        "desc": "[center]所有远程弹弓每次齐射数量增加\n• 发射弹丸数 [color=#7ce860][b]+1 枚[/b][/color]\n• 形成扇形密集弹幕覆盖[/center]",
        "rarity": "rare",
        "rarity_label": "稀有强化",
        "border_color": Color(1, 0.83, 0, 1),
        "tag": "弹道裂变",
        "icon": "res://assets/art/icon_pellets.png"
    },
    {
        "id": "blade_cooldown",
        "title": "顺滑机油",
        "desc": "[center]给武器关节上点油，攻击手感顺滑\n• 攻击冷却时间 [color=#6fd6ff][b]-22%[/b][/color]\n• 显著提升弹弓射速与球棒抡击频率[/center]",
        "rarity": "common",
        "rarity_label": "普通强化",
        "border_color": Color(0.96, 0.95, 0.92, 1),
        "tag": "疾速攻速",
        "icon": "res://assets/art/icon_oil.png"
    },
    {
        "id": "sun_orb_add",
        "title": "增援无人机",
        "desc": "[center]呼叫护体无人机环绕周身巡逻\n• 巡逻无人机数量 [color=#7ce860][b]+1 台[/b][/color]\n• 电击并撞飞贴身敌人[/center]",
        "rarity": "rare",
        "rarity_label": "稀有装备",
        "border_color": Color(1, 0.83, 0, 1),
        "tag": "环绕护卫",
        "icon": "res://assets/art/icon_drone.png"
    },
    {
        "id": "sun_orb_damage",
        "title": "螺旋桨加固",
        "desc": "[center]强化巡逻无人机的电击威力\n• 无人机碰撞伤害 [color=#ffd400][b]+45%[/b][/color]\n• 撞击冲击力提升 [color=#6fd6ff][b]+25%[/b][/color][/center]",
        "rarity": "common",
        "rarity_label": "普通强化",
        "border_color": Color(0.96, 0.95, 0.92, 1),
        "tag": "护卫强化",
        "icon": "res://assets/art/icon_drone.png"
    },
    {
        "id": "move_speed",
        "title": "越狱跑鞋",
        "desc": "[center]换上藏进囚服的轻便跑鞋\n• 基础移动速度 [color=#6fd6ff][b]+18%[/b][/color]\n• 更加从容地穿梭于狱警之间[/center]",
        "rarity": "common",
        "rarity_label": "普通特质",
        "border_color": Color(0.96, 0.95, 0.92, 1),
        "tag": "机动走位",
        "icon": "res://assets/art/icon_sneaker.png"
    },
    {
        "id": "max_hp",
        "title": "冰镇汽水",
        "desc": "[center]灌下一罐小卖部的冰镇汽水\n• 最大生命上限 [color=#7ce860][b]+30 点[/b][/color]\n• 立即恢复 [color=#7ce860][b]+40 点[/b][/color] 生命值[/center]",
        "rarity": "rare",
        "rarity_label": "稀有补给",
        "border_color": Color(1, 0.83, 0, 1),
        "tag": "生存续航",
        "icon": "res://assets/art/icon_soda.png"
    },
    {
        "id": "pickup_range",
        "title": "磁力手套",
        "desc": "[center]戴上从工坊顺来的磁力手套\n• 硬币磁吸范围 [color=#6fd6ff][b]+45%[/b][/color]\n• 远距离自动吸附散落的硬币[/center]",
        "rarity": "common",
        "rarity_label": "普通特质",
        "border_color": Color(0.96, 0.95, 0.92, 1),
        "tag": "采集效率",
        "icon": "res://assets/art/icon_magnet.png"
    },
    {
        "id": "synergy_radiance",
        "title": "越狱大师计划",
        "desc": "[center][color=#ff5a5a][b]【史诗级协同质变】[/b][/color]\n• 弹丸命中时有 [color=#ff5a5a][b]28% 概率[/b][/color] 触发过载冲击\n• 对周围狱警造成 [color=#ffd400][b]85%[/b][/color] 范围真实伤害[/center]",
        "rarity": "epic",
        "rarity_label": "史诗协同",
        "border_color": Color(0.902, 0, 0.0706, 1),
        "tag": "史诗协同",
        "icon": "res://assets/art/icon_plan.png"
    }
]

static func get_random_upgrades(count: int = 3) -> Array[Dictionary]:
    var pool = UPGRADES.duplicate()
    pool.shuffle()
    var result: Array[Dictionary] = []
    for i in range(mini(count, pool.size())):
        result.append(pool[i])
    return result
