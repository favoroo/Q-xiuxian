#!/usr/bin/env python3
"""生成图 -> 游戏用 6x6 精灵表（192px/格，1152x1152）。

处理管线（针对 gemini 生图的已知行为）：
1. 定位品红背景矩形并裁剪（甩掉模型模仿参考图带上的边框/水印条）
2. magentaness=min(R,B)-G 软抠成 alpha（同 keyout.py 参数），去品红溢色
3. 连通域检测角色块（先膨胀把头/手脚并块，再按质心聚类分行、行内按 x 排序）
4. 每块缩放到目标像素高，脚底对齐统一基线，贴进 192x192 格
5. 输出 1152x1152 RGBA PNG；行 0=待机，行 1=奔跑（游戏代码只用这两行）

用法: make_spritesheet.py <raw图> <输出.png> --expected 12 --height 116 [--chunky 2]
      --expected 1 时退化为单图平铺：复制 6 份做程序化上下摆动当动画。
"""
import sys
import argparse
import numpy as np
from PIL import Image, ImageFilter

CELL = 192
COLS, ROWS = 6, 6
BASELINE = 128  # 脚底基线（格内 y），与旧素材一致：脚在中心下方 64px


def keyout_array(img):
    a = np.asarray(img.convert('RGB')).astype(np.int16)
    R, G, B = a[..., 0], a[..., 1], a[..., 2]
    mag = np.minimum(R, B) - G
    mask = (mag > 60) & (R > 140) & (B > 140)
    if mask.mean() > 0.04:
        ys, xs = np.where(mask)
        a = a[ys.min():ys.max() + 1, xs.min():xs.max() + 1]
        R, G, B = a[..., 0], a[..., 1], a[..., 2]
        mag = np.minimum(R, B) - G
    lo, hi = 30, 110
    alpha = (np.clip((hi - mag) / (hi - lo), 0, 1) * 255).astype(np.uint8)
    semi = (alpha > 0) & (alpha < 255)
    g = G.astype(np.int16)
    R2 = np.where(semi, np.minimum(R, g + 60), R)
    B2 = np.where(semi, np.minimum(B, g + 60), B)
    out = np.dstack([R2, G, B2, alpha]).astype(np.uint8)
    # alpha 腐蚀 1px 去品红晕边（同 keyout.py）
    a_img = Image.fromarray(out[..., 3]).filter(ImageFilter.MinFilter(3))
    out[..., 3] = np.asarray(a_img)
    return out


def blobs(rgba, min_area=400, min_w=48, min_h=64):
    """连通域（4邻接，先膨胀并块）。返回按行聚类、行内按 x 排序的 bbox 列表。"""
    # 检测用高阈值：格子间 JPEG 半透明品红残留(alpha<100)不构成块
    alpha = rgba[..., 3] > 100
    # 垂直膨胀 3px 让头/躯干/脚连成一个块
    dil = alpha.copy()
    for s in (1, 2, 3):
        dil[3:, :] |= alpha[:-3, :]
        dil[:-3, :] |= alpha[3:, :]
    lbl = np.zeros(dil.shape, np.int32)
    cur = 0
    comps = []
    H, W = dil.shape
    for y0 in range(H):
        for x0 in range(W):
            if dil[y0, x0] and lbl[y0, x0] == 0:
                cur += 1
                stack = [(y0, x0)]
                lbl[y0, x0] = cur
                ys, xs, n = [y0], [x0], 0
                while stack:
                    y, x = stack.pop()
                    n += 1
                    for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                        ny, nx = y + dy, x + dx
                        if 0 <= ny < H and 0 <= nx < W and dil[ny, nx] and lbl[ny, nx] == 0:
                            lbl[ny, nx] = cur
                            stack.append((ny, nx))
                            ys.append(ny)
                            xs.append(nx)
                comps.append((n, min(xs), min(ys), max(xs) + 1, max(ys) + 1))
    comps = [c for c in comps
             if c[0] >= min_area and (c[3] - c[1]) >= min_w and (c[4] - c[2]) >= min_h]
    # 丢弃高瘦的垃圾块（参考图残留把多行主体粘连成的竖条）
    if len(comps) > 1:
        comps = [c for c in comps if (c[4] - c[2]) <= (c[3] - c[1]) * 1.5] or comps
    boxes = [(x0, y0, x1, y1) for _, x0, y0, x1, y1 in comps]
    # 按质心 y 聚成 2 行
    cys = [ (y0 + y1) / 2 for x0, y0, x1, y1 in boxes ]
    order = np.argsort(cys)
    rows, cur_row = [], [order[0]]
    for i in order[1:]:
        if abs(cys[i] - np.mean([cys[j] for j in cur_row])) < (max(cys) - min(cys)) * 0.4:
            cur_row.append(i)
        else:
            rows.append(cur_row)
            cur_row = [i]
    rows.append(cur_row)
    out = []
    for r in rows:
        r = sorted(r, key=lambda i: boxes[i][0])
        out.append([boxes[i] for i in r])
    return out


def paste_cell(sheet, sprite, col, row, chunky):
    h = sprite.height
    scale = min((CELL - 48) / h, 1.0) if h > CELL - 48 else 1.0
    if scale < 1.0:
        sprite = sprite.resize((max(1, int(sprite.width * scale)), max(1, int(h * scale))), Image.LANCZOS)
    if chunky > 1:
        w2, h2 = sprite.width // chunky, sprite.height // chunky
        sprite = sprite.resize((max(1, w2), max(1, h2)), Image.NEAREST).resize(
            (w2 * chunky, h2 * chunky), Image.NEAREST)
    x = col * CELL + (CELL - sprite.width) // 2
    y = row * CELL + BASELINE - sprite.height
    sheet.alpha_composite(sprite, (x, y))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('src')
    ap.add_argument('dst')
    ap.add_argument('--expected', type=int, default=12)
    ap.add_argument('--height', type=int, default=116, help='单角色在格内的目标像素高')
    ap.add_argument('--chunky', type=int, default=2, help='像素块大小（1=不块化）')
    ap.add_argument('--rows', default='', help='指定用第几个行组，如 "0,2"；每行不足6格时循环补齐')
    args = ap.parse_args()

    img = Image.open(args.src)
    rgba = keyout_array(img)
    im = Image.fromarray(rgba)

    groups = blobs(rgba)
    flat = [b for g in groups for b in g]
    print(f'检出角色块: {len(flat)}（分{len(groups)}行）期望 {args.expected}')

    sheet = Image.new('RGBA', (CELL * COLS, CELL * ROWS), (0, 0, 0, 0))
    if args.rows:
        picked = []
        for ri in [int(s) for s in args.rows.split(',')]:
            grp = groups[ri][:]
            if not grp:
                print(f'ERROR: 行组 {ri} 为空', file=sys.stderr)
                sys.exit(2)
            while len(grp) < 6:
                grp.append(grp[len(picked) % len(grp)])
            picked.append(grp[:6])
        for r, grp in enumerate(picked):
            for c, (x0, y0, x1, y1) in enumerate(grp):
                sp = im.crop((x0, y0, x1, y1))
                sp = sp.resize((int(sp.width * args.height / sp.height), args.height), Image.LANCZOS)
                paste_cell(sheet, sp, c, r, args.chunky)
        print(f'行组 {args.rows} -> 行0待机/行1奔跑')
    elif args.expected == 1:
        x0, y0, x1, y1 = flat[0]
        sp = im.crop((x0, y0, x1, y1))
        h = args.height
        sp = sp.resize((int(sp.width * h / sp.height), h), Image.LANCZOS)
        if args.chunky > 1:
            sp = sp.resize((sp.width // args.chunky, sp.height // args.chunky), Image.NEAREST).resize(
                (sp.width * args.chunky, sp.height * args.chunky), Image.NEAREST)
        idle = [0, -2, 0, 2, 0, -2]
        run = [0, -5, 0, 5, 0, -5]
        for c in range(6):
            paste_cell(sheet, sp, c, 0, 1) if False else None
            s = Image.new('RGBA', sp.size, (0, 0, 0, 0))
            s.alpha_composite(sp, (0, idle[c]))
            sheet.alpha_composite(s, (c * CELL + (CELL - sp.width) // 2, 0 * CELL + BASELINE - sp.height - min(idle)))
        for c in range(6):
            s = Image.new('RGBA', sp.size, (0, 0, 0, 0))
            s.alpha_composite(sp, (0, run[c]))
            sheet.alpha_composite(s, (c * CELL + (CELL - sp.width) // 2, 1 * CELL + BASELINE - sp.height - min(run)))
    else:
        idx = 0
        for r, grp in enumerate(groups):
            for c, (x0, y0, x1, y1) in enumerate(grp[:6]):
                sp = im.crop((x0, y0, x1, y1))
                sp = sp.resize((int(sp.width * args.height / sp.height), args.height), Image.LANCZOS)
                paste_cell(sheet, sp, c, r, args.chunky)
                idx += 1
        print(f'排布 {idx} 块 -> 行0待机/行1奔跑（其余行留空）')

    sheet.save(args.dst)
    print('DONE', args.dst, sheet.size)


if __name__ == '__main__':
    main()
