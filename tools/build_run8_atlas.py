#!/usr/bin/env python3
"""把 run8_<char>_<dir>.raw.jpg 原图提取 5 格并拼装为 5x5 8方向图集。

行序：s=0, n=1, e=2, se=3, ne=4（与 RunMotion.DIR_ROW 一致）。
列序：0=待机, 1..4=4 帧跑步。
左/左下/左上方向由引擎 flip_h 补齐。

提取策略：直接读 raw.jpg 做品红抠图 + 智能去地面横线 + 在 1/5 附近找最窄列谷底
切开 5 个个体 + 边缘主连通域保留（擦掉邻居溢入的剑尖/碎块）+ 行内以待机身高定标 + 底对齐居中。
"""
from PIL import Image
import sys

CHARS = {
    "player":   {"tex": "pawn_blue",      "h": 116, "base": 128},
    "disciple": {"tex": "pawn_red",       "h": 110, "base": 126},
    "wolf":     {"tex": "warrior_red",    "h": 96,  "base": 128},
    "puppet":   {"tex": "warrior_purple", "h": 124, "base": 128},
}
DIRS = ["s", "n", "e", "se", "ne"]
CELL = 192
CX = 96

def extract_five_cells(raw_path: str):
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
            if a > 30:
                row[x] = 1
            if m > 0:
                r = max(0, r - m // 2)
                b = max(0, b - m // 2)
            out[x, y] = (r, g, b, a)

    # 去横贯地平线：仅当某一行出现单条连续非透明水平线段 > 35% 画面宽（真黑线无间断；5 只脚中间有空隙不会命中）
    for y in range(int(H * 0.6), H):
        run = 0
        max_run = 0
        for x in range(W):
            if mask[y][x]:
                run += 1
                if run > max_run:
                    max_run = run
            else:
                run = 0
        if max_run > W * 0.35:
            # 仅擦掉深色细线像素（保留脚面彩块）
            for dy in (-1, 0, 1):
                yy = y + dy
                if 0 <= yy < H:
                    for x in range(W):
                        if mask[yy][x] and sum(px[x, yy]) < 160:
                            mask[yy][x] = 0
                            out[x, yy] = (0, 0, 0, 0)

    # 左右边界与 4 刀
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

    cells = []
    for i in range(5):
        sub = rgba.crop((cuts[i], 0, cuts[i + 1], H))
        sub = _clean_blob(sub)
        b = sub.getbbox()
        cells.append(sub.crop(b) if b else sub)
    return cells

def _clean_blob(im: Image.Image) -> Image.Image:
    W, H = im.size
    px = im.load()
    vis = [[False] * W for _ in range(H)]
    blobs = []
    for y in range(H):
        for x in range(W):
            if not vis[y][x] and px[x, y][3] > 25:
                q = [(x, y)]
                vis[y][x] = True
                pts = []
                while q:
                    cx, cy = q.pop()
                    pts.append((cx, cy))
                    for nx, ny in ((cx+1,cy),(cx-1,cy),(cx,cy+1),(cx,cy-1)):
                        if 0 <= nx < W and 0 <= ny < H and not vis[ny][nx] and px[nx, ny][3] > 25:
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

def build(char: str, cfg: dict) -> None:
    atlas = Image.new("RGBA", (CELL * 5, CELL * 5), (0, 0, 0, 0))
    for r, d in enumerate(DIRS):
        cells = extract_five_cells(f"assets_raw/images/run8_{char}_{d}.raw.jpg")
        scale = cfg["h"] / cells[0].height
        for c, im in enumerate(cells):
            w = max(1, round(im.width * scale))
            h = max(1, round(im.height * scale))
            if h > cfg["base"]:
                k = cfg["base"] / h
                w, h = max(1, round(w * k)), cfg["base"]
            im = im.resize((w, h), Image.LANCZOS)
            atlas.alpha_composite(im, (c * CELL + CX - w // 2, r * CELL + cfg["base"] - h))
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