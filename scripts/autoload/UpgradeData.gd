class_name UpgradeData
extends RefCounted

const UPGRADES: Array[Dictionary] = [
    {
        "id": "add_sword",
        "title": "圣银重剑",
        "desc": "[center]在周身新增 [color=#4ade80][b]+1 把[/b][/color] 悬浮近战重剑\n• 自动斩击近身敌人，造成 [color=#fbbf24][b]135%[/b][/color] 范围伤害\n• 附带 [color=#38bdf8][b]强力击退[/b][/color] 效果[/center]",
        "rarity": "rare",
        "rarity_label": "稀有武装",
        "border_color": Color(0.35, 0.72, 0.98),
        "tag": "新武器·近战",
        "icon": "res://assets/art/weapon_sword.png"
    },
    {
        "id": "add_staff",
        "title": "苍穹法杖",
        "desc": "[center]在周身新增 [color=#4ade80][b]+1 把[/b][/color] 悬浮远程法杖\n• 独立索敌发射奥术光刃\n• 远距离压制怪潮，射程 [color=#38bdf8][b]420[/b][/color][/center]",
        "rarity": "rare",
        "rarity_label": "稀有武装",
        "border_color": Color(0.35, 0.72, 0.98),
        "tag": "新武器·远程",
        "icon": "res://assets/art/weapon_staff.png"
    },
    {
        "id": "blade_damage",
        "title": "奥术锋芒",
        "desc": "[center]所有悬浮武器的基础伤害提升\n• 武器总伤害 [color=#fbbf24][b]+35%[/b][/color]\n• 适用于全部远程法杖与近战重剑[/center]",
        "rarity": "common",
        "rarity_label": "普通强化",
        "border_color": Color(0.75, 0.78, 0.84),
        "tag": "全体武器强化",
        "icon": "res://assets/art/blade.png"
    },
    {
        "id": "blade_amount",
        "title": "多重咏唱",
        "desc": "[center]所有远程法杖每次齐射数量增加\n• 发射弹道数 [color=#4ade80][b]+1 枚[/b][/color]\n• 形成扇形密集弹幕覆盖[/center]",
        "rarity": "rare",
        "rarity_label": "稀有强化",
        "border_color": Color(0.35, 0.72, 0.98),
        "tag": "弹道裂变",
        "icon": "res://assets/art/weapon_staff.png"
    },
    {
        "id": "blade_cooldown",
        "title": "急速神恩",
        "desc": "[center]大幅加快所有悬浮武器的攻击频率\n• 攻击冷却时间 [color=#38bdf8][b]-22%[/b][/color]\n• 显著提升法杖射速与重剑挥砍频率[/center]",
        "rarity": "common",
        "rarity_label": "普通强化",
        "border_color": Color(0.75, 0.78, 0.84),
        "tag": "疾速攻速",
        "icon": "res://assets/art/blade.png"
    },
    {
        "id": "sun_orb_add",
        "title": "曜日共鸣",
        "desc": "[center]召唤护体圣物环绕周身旋转\n• 曜日光球数量 [color=#4ade80][b]+1 颗[/b][/color]\n• 持续灼烧并弹开贴身敌人[/center]",
        "rarity": "rare",
        "rarity_label": "稀有圣物",
        "border_color": Color(0.35, 0.72, 0.98),
        "tag": "环绕护卫",
        "icon": "res://assets/art/sun_orb.png"
    },
    {
        "id": "sun_orb_damage",
        "title": "耀斑烈阳",
        "desc": "[center]强化环绕光球的神圣灼烧威力\n• 光球碰撞伤害 [color=#fbbf24][b]+45%[/b][/color]\n• 击退冲击力提升 [color=#38bdf8][b]+25%[/b][/color][/center]",
        "rarity": "common",
        "rarity_label": "普通强化",
        "border_color": Color(0.75, 0.78, 0.84),
        "tag": "护卫强化",
        "icon": "res://assets/art/sun_orb.png"
    },
    {
        "id": "move_speed",
        "title": "晨风迅步",
        "desc": "[center]旅者获得轻盈的风之加护\n• 基础移动速度 [color=#38bdf8][b]+18%[/b][/color]\n• 更加从容地穿梭于敌群之间[/center]",
        "rarity": "common",
        "rarity_label": "普通特质",
        "border_color": Color(0.75, 0.78, 0.84),
        "tag": "机动走位",
        "icon": "res://assets/art/gem_blue.png"
    },
    {
        "id": "max_hp",
        "title": "晨露圣杯",
        "desc": "[center]沐浴神圣甘露，强化生命本源\n• 最大生命上限 [color=#4ade80][b]+30 点[/b][/color]\n• 立即恢复 [color=#4ade80][b]+40 点[/b][/color] 生命值[/center]",
        "rarity": "rare",
        "rarity_label": "稀有圣物",
        "border_color": Color(0.35, 0.72, 0.98),
        "tag": "生存续航",
        "icon": "res://assets/art/icon_chalice.png"
    },
    {
        "id": "pickup_range",
        "title": "星光引力",
        "desc": "[center]扩展星界共鸣磁场\n• 晶石磁吸范围 [color=#38bdf8][b]+45%[/b][/color]\n• 远距离自动汲取散落的辉晶[/center]",
        "rarity": "common",
        "rarity_label": "普通特质",
        "border_color": Color(0.75, 0.78, 0.84),
        "tag": "采集效率",
        "icon": "res://assets/art/gem_gold.png"
    },
    {
        "id": "synergy_radiance",
        "title": "晨曦神圣冠冕",
        "desc": "[center][color=#c084fc][b]【神圣协同质变】[/b][/color]\n• 光刃命中时有 [color=#c084fc][b]28% 概率[/b][/color] 触发耀斑爆破\n• 对周围敌群造成 [color=#fbbf24][b]85%[/b][/color] 范围真实伤害[/center]",
        "rarity": "epic",
        "rarity_label": "史诗协同",
        "border_color": Color(0.82, 0.45, 0.98),
        "tag": "神圣协同",
        "icon": "res://assets/art/icon_chalice.png"
    }
]

static func get_random_upgrades(count: int = 3) -> Array[Dictionary]:
    var pool = UPGRADES.duplicate()
    pool.shuffle()
    var result: Array[Dictionary] = []
    for i in range(mini(count, pool.size())):
        result.append(pool[i])
    return result
