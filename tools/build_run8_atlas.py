#!/usr/bin/env python3
"""把 run8_<char>_<dir>.raw.jpg 原图提取 5 格并拼装为 5x5 8方向图集。

行序：s=0, n=1, e=2, se=3, ne=4（与 RunMotion.DIR_ROW 一致）。
列序：0=待机, 1..4=4 帧跑步。
左/左下/左上方向由引擎 flip_h 补齐。

核心管线（参考 pixel-asset-master 规范优化）：
1. 纯净二值化 Alpha 抠图 + 孤立杂点清洗（消除帧间半透明边缘闪烁）。
2. 智能检测并完整剥离底部横贯黑线/分段地面线。
3. 统一地面水平基准线（Fixed Ground Baseline）：以整行统一地面线作为 Y 轴锚点，
   支撑脚严格踩在基准线上，迈步腾空脚自然离地，杜绝单帧独立贴底导致的头部剧烈上下抽搐。
4. 躯干重心水平对齐（Torso Centroid X）：消除兵器/手臂摆动引起的身体左右晃动。
5. 采用 Image.NEAREST 像素硬边采样，杜绝 Lanczos 插值导致的羽化伪影。
"""
from PIL import Image
import sys

CHARS = {
    # player 走 static 单姿势模式：御剑飞行无步态，每方向一张单图（fly_player_<dir>.raw.jpg），
    # 程序复制满 5 列；浮沉/前倾等动感由 RunMotion.apply_hover 程序驱动（2026-10-09）
    "player":   {"tex": "pawn_blue",      "h": 116, "base": 128, "src": "fly_player", "mode": "static"},
    # 以下全部角色同日切换为 static 单姿势模式（fly_<char>_<dir>.raw.jpg）：
    # 修士 8 名御物飞行（RunMotion.apply_hover），敌人按怪种 hover/slither（见各 .tscn 的 locomotion_mode）
    "disciple": {"tex": "pawn_red",       "h": 110, "base": 126, "src": "fly_disciple", "mode": "static"},
    "wolf":     {"tex": "warrior_red",    "h": 96,  "base": 128, "src": "fly_wolf", "mode": "static"},
    "puppet":   {"tex": "warrior_purple", "h": 124, "base": 128, "src": "fly_puppet", "mode": "static"},
    # 批二：9 名修士的独立形象（jianchi 沿用 pawn_blue，以下 8 套为新增）
    "shiyue":    {"tex": "cultivator_shiyue",    "h": 128, "base": 130, "src": "fly_shiyue", "mode": "static"},
    "fuzhen":    {"tex": "cultivator_fuzhen",    "h": 92,  "base": 126, "src": "fly_fuzhen", "mode": "static"},
    "jinsuanpan":{"tex": "cultivator_jinsuanpan","h": 112, "base": 126, "src": "fly_jinsuanpan", "mode": "static"},
    "meiying":   {"tex": "cultivator_meiying",   "h": 116, "base": 128, "src": "fly_meiying", "mode": "static"},
    "dubi":      {"tex": "cultivator_dubi",      "h": 126, "base": 130, "src": "fly_dubi", "mode": "static"},
    "kuangzhan": {"tex": "cultivator_kuangzhan", "h": 124, "base": 130, "src": "fly_kuangzhan", "mode": "static"},
    "duoshe":    {"tex": "cultivator_duoshe",    "h": 110, "base": 126, "src": "fly_duoshe", "mode": "static"},
    "duobao":    {"tex": "cultivator_duobao",    "h": 114, "base": 126, "src": "fly_duobao", "mode": "static"},
    # 批三：新妖种的独立形象
    "fengqun":   {"tex": "monster_fengqun", "h": 56,  "base": 120, "src": "fly_fengqun", "mode": "static"},
    "xueyong":   {"tex": "monster_xueyong", "h": 100, "base": 126, "src": "fly_xueyong", "mode": "static"},
    "guyao":     {"tex": "monster_guyao",   "h": 96,  "base": 126, "src": "fly_guyao", "mode": "static"},
    "yingmei":   {"tex": "monster_yingmei", "h": 104, "base": 126, "src": "fly_yingmei", "mode": "static"},
    "zhumu":     {"tex": "monster_zhumu",   "h": 110, "base": 130, "src": "fly_zhumu", "mode": "static"},
    # 批四：共用图集拆分出的专属怪种（史莱姆/丹爆傀儡/花妖）
    "slime":     {"tex": "monster_slime",   "h": 64,  "base": 130, "src": "fly_slime", "mode": "static"},
    "danbao":    {"tex": "monster_danbao",  "h": 100, "base": 128, "src": "fly_danbao", "mode": "static"},
    "flower":    {"tex": "monster_flower",  "h": 110, "base": 128, "src": "fly_flower", "mode": "static"},
}
DIRS = ["s", "n", "e", "se", "ne"]
CELL = 192
CX = 96

# 【历史保留】两足角色步态镜像修复：仅 extract_five_cells（多帧步态管线）使用。
# 2026-10-09 起全部角色已切 static 单姿势模式（extract_single_cell），本集合当前无实际作用，
# 保留给将来可能回归的多帧步态管线。
BIPED_MIRROR = {
    "disciple", "puppet",
    "shiyue", "fuzhen", "jinsuanpan", "meiying",
    "dubi", "kuangzhan", "duoshe", "duobao",
}


def _clean_blob(im: Image.Image) -> Image.Image:
    W, H = im.size
    px = im.load()
    vis = [[False] * W for _ in range(H)]
    blobs = []
    for y in range(H):
        for x in range(W):
            if not vis[y][x] and px[x, y][3] > 0:
                q = [(x, y)]
                vis[y][x] = True
                pts = []
                while q:
                    cx, cy = q.pop()
                    pts.append((cx, cy))
                    for nx, ny in ((cx + 1, cy), (cx - 1, cy), (cx, cy + 1), (cx, cy - 1)):
                        if 0 <= nx < W and 0 <= ny < H and not vis[ny][nx] and px[nx, ny][3] > 0:
                            vis[ny][nx] = True
                            q.append((nx, ny))
                blobs.append(pts)
    if len(blobs) <= 1:
        return im
    blobs.sort(key=len, reverse=True)
    main_len = len(blobs[0])
    for pts in blobs[1:]:
        xs = [p[0] for p in pts]
        near_edge = (min(xs) <= 4) or (max(xs) >= W - 5)
        if len(pts) < main_len * 0.06 or near_edge:
            for cx, cy in pts:
                px[cx, cy] = (0, 0, 0, 0)
    return im


def _clean_orphan_pixels(im: Image.Image) -> Image.Image:
    """清除四周 4 邻域全透明的孤立单像素杂点（pixel-asset-master clean 规范）。"""
    W, H = im.size
    px = im.load()
    to_clear = []
    for y in range(H):
        for x in range(W):
            if px[x, y][3] == 0:
                continue
            has_neighbor = False
            for nx, ny in ((x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)):
                if 0 <= nx < W and 0 <= ny < H and px[nx, ny][3] > 0:
                    has_neighbor = True
                    break
            if not has_neighbor:
                to_clear.append((x, y))
    for x, y in to_clear:
        px[x, y] = (0, 0, 0, 0)
    return im


def _keyout(raw_path: str):
    """品红底抠图：硬边二值化 Alpha（消除半透明抗锯齿边缘频闪），返回 (RGBA, mask)。"""
    im = Image.open(raw_path).convert("RGB")
    W, H = im.size
    px = im.load()
    rgba = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    out = rgba.load()
    mask = [[0] * W for _ in range(H)]
    for y in range(H):
        row = mask[y]
        for x in range(W):
            r, g, b = px[x, y]
            m = (r if r < b else b) - g
            if m >= 105:
                continue
            a = 255 if m <= 30 else int(255 * (105 - m) / 75)
            if a > 80:
                row[x] = 1
                if m > 0:
                    r = max(0, r - m // 2)
                    b = max(0, b - m // 2)
                out[x, y] = (r, g, b, 255)
    return rgba, mask, im


def extract_single_cell(raw_path: str):
    """static 单姿势模式：整图只有一个主体（御剑悬浮等无步态姿势），
    抠出唯一主体后复制满 5 列，帧间零差异、动感全部交给程序驱动。"""
    rgba, _mask, _im = _keyout(raw_path)
    sub = _clean_blob(rgba)
    sub = _clean_orphan_pixels(sub)
    b = sub.getbbox()
    if not b:
        raise RuntimeError(f"static 原图抠不出主体: {raw_path}")
    return [sub] * 5, [b] * 5, b[3]


def extract_five_cells(raw_path: str, char: str = "", d: str = ""):
    rgba, mask, im = _keyout(raw_path)
    W, H = im.size
    px = im.load()
    out = rgba.load()

    # 检测并完整剥离底部横贯地面黑线（或 5 段底线）
    ys_non_empty = [y for y in range(H) if any(mask[y])]
    max_y = max(ys_non_empty) if ys_non_empty else H - 1
    ground_rows = []
    for y in range(max(0, max_y - 25), max_y + 1):
        runs = []
        r_len = 0
        dark_cnt = 0
        for x in range(W):
            if mask[y][x]:
                r_len += 1
                if sum(px[x, y]) < 180:
                    dark_cnt += 1
            else:
                if r_len > 0:
                    runs.append(r_len)
                r_len = 0
        if r_len > 0:
            runs.append(r_len)
        max_run = max(runs) if runs else 0
        if max_run > W * 0.35 or dark_cnt > W * 0.65:
            ground_rows.append(y)

    if ground_rows:
        ground_top = min(ground_rows)
        for y in range(ground_top, min(H, max(ground_rows) + 3)):
            for x in range(W):
                mask[y][x] = 0
                out[x, y] = (0, 0, 0, 0)
        baseline_y = ground_top
    else:
        baseline_y = -1

    # 左右边界与 4 刀切格
    col_cnt = [sum(mask[y][x] for y in range(H)) for x in range(W)]
    non_empty = [x for x in range(W) if col_cnt[x] > 2]
    L, R = non_empty[0], non_empty[-1] + 1
    span = R - L
    cuts = [L]
    win = max(8, int(span * 0.08))
    for k in range(1, 5):
        expect = L + int(span * k / 5.0)
        best_x = expect
        best_score = (10**9, 10**9)
        for x in range(max(L + 5, expect - win), min(R - 5, expect + win + 1)):
            s = col_cnt[x - 1] + col_cnt[x] + col_cnt[x + 1]
            score = (s, abs(x - expect))
            if score < best_score:
                best_score = score
                best_x = x
        cuts.append(best_x)
    cuts.append(R)

    raw_cells = []
    bboxes = []
    for i in range(5):
        sub = rgba.crop((cuts[i], 0, cuts[i + 1], H))
        sub = _clean_blob(sub)
        sub = _clean_orphan_pixels(sub)
        b = sub.getbbox()
        raw_cells.append(sub)
        bboxes.append(b)

    # 两足角色：用干净的前两帧水平镜像构成完整对称 4 帧步态
    # （wolf 最初因正面原图后两帧粘连与侧偏引入此修复，后推广到全部两足角色）
    if char in BIPED_MIRROR or (char == "wolf" and d == "s"):
        raw_cells[3] = raw_cells[1].transpose(Image.FLIP_LEFT_RIGHT)
        bboxes[3] = raw_cells[3].getbbox()
        raw_cells[4] = raw_cells[2].transpose(Image.FLIP_LEFT_RIGHT)
        bboxes[4] = raw_cells[4].getbbox()

    if baseline_y == -1:
        baseline_y = max(b[3] for b in bboxes if b)

    return raw_cells, bboxes, baseline_y


def build(char: str, cfg: dict) -> None:
    atlas = Image.new("RGBA", (CELL * 5, CELL * 5), (0, 0, 0, 0))
    src = cfg.get("src", f"run8_{char}")
    for r, d in enumerate(DIRS):
        raw_path = f"assets_raw/images/{src}_{d}.raw.jpg"
        if cfg.get("mode") == "static":
            raw_cells, bboxes, baseline_y = extract_single_cell(raw_path)
        else:
            raw_cells, bboxes, baseline_y = extract_five_cells(raw_path, char, d)
        idle_b = bboxes[0]
        idle_h = max(1, idle_b[3] - idle_b[1])
        scale = cfg["h"] / idle_h

        for c in range(5):
            sub = raw_cells[c]
            b = bboxes[c]
            if not b:
                continue
            cropped = sub.crop(b)
            cW, cH = cropped.size
            c_px = cropped.load()

            # 躯干重心水平对齐（取躯干核心区 15%~65% 高度的像素水平重心，消除兵器/手臂摆动造成的左右晃动）
            xs_torso = [
                x
                for y in range(int(cH * 0.15), int(cH * 0.65))
                for x in range(cW)
                if c_px[x, y][3] > 0
            ]
            centroid_x = (sum(xs_torso) / len(xs_torso)) if xs_torso else (cW / 2.0)

            w = max(1, round(cW * scale))
            h = max(1, round(cH * scale))
            im_scaled = cropped.resize((w, h), Image.NEAREST)
            im_scaled = _clean_orphan_pixels(im_scaled)

            # 统一地面基准线对齐：计算当前帧脚底相对于地面基准线的真实抬升量
            foot_offset_unscaled = max(0, baseline_y - b[3])
            foot_offset_scaled = round(foot_offset_unscaled * scale)
            foot_y_in_cell = cfg["base"] - foot_offset_scaled

            cell_x = c * CELL + CX - round(centroid_x * scale)
            cell_y = r * CELL + max(0, foot_y_in_cell - h)
            atlas.alpha_composite(im_scaled, (cell_x, cell_y))

    out = f"assets/art/{cfg['tex']}_8dir.png"
    atlas.save(out)
    print(f"DONE {out}")


def contact_sheet() -> None:
    for char, cfg in CHARS.items():
        im = Image.open(f"assets/art/{cfg['tex']}_8dir.png")
        H = 150
        sheet = Image.new("RGB", (5 * (H + 6) + 10, 5 * (H + 6) + 10), (34, 38, 54))
        for r in range(5):
            for c in range(5):
                cell = im.crop((c * 192, r * 192, (c + 1) * 192, (r + 1) * 192)).resize((H, H), Image.NEAREST)
                sheet.paste(cell, (10 + c * (H + 6), 10 + r * (H + 6)), cell)
        sheet.save(f"/tmp/run8_{char}_clean.png")
    print("DONE clean sheets in /tmp/run8_*_clean.png")


if __name__ == "__main__":
    targets = sys.argv[1:] or list(CHARS)
    for char in targets:
        build(char, CHARS[char])
    contact_sheet()
