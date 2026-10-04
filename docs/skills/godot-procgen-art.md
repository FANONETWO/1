---
name: godot-procgen-art
description: "用 Python/PIL 程序化生成 2D 像素游戏美术（16×16 tile、地板/砖墙/门/家具、血迹/纸箱/碎玻璃等地面装饰 sprite），保证平铺无缝、调色板统一、可复现。适用于 tile 需要清晰结构（砖缝、错缝、明暗层次）、AI 生图在低分辨率下只产出噪点的场景。当用户要生成或重做 tile、地砖、墙壁、装饰物、像素素材，或抱怨'AI 生成的 tile 看不清''墙和地板分不清''每格都一样'时，使用本 skill。"
argument-hint: "[素材类型：tile / 装饰 / 图标]"
version: "1.0.0"
user-invocable: true
---

# godot-procgen-art.skill

> **核心洞察**：**AI 生图在小尺寸像素素材上不可用**。
>
> 扩散模型在 **16×16** 这个尺寸只会产出**噪点** —— 实测生成的 "wall.png" 是一片随机灰点，
> 生成的 "floor.png" 只有一个空方框，**墙和地板色调几乎一样，玩家分不清哪里能走**。
>
> **但 tile 恰恰是"规则几何 + 有限调色板"，程序化能精确控制**：
> 砖缝在哪个像素、错缝偏移几格、每一阶明暗是多少 —— AI 做不到，代码可以。
>
> **结论：分辨率越低，程序化越有优势。**

---

## 触发条件

- 用户要生成/重做 **tile、地砖、墙壁、门、家具、装饰物**
- 抱怨「AI 生成的 tile 看不清」「墙和地板分不清」「每格都一样，像棋盘」
- 需要**平铺无缝**的贴图
- 需要**与已有调色板统一**的新素材

---

## 一、tile 生成的设计原则

### 1. 墙与地板必须"一眼区分"（最重要）

靠**明度差**，不是靠花纹：

| 素材 | 相对明度 | 结构 |
|---|---|---|
| 地板 | 基准（如 88） | 方格砖缝 + 三阶明暗 + 稀疏污渍 |
| 墙 | **暗 35%**（如 60） | **错缝砖块 + 勾缝** + 上亮下暗做出凸起感 |

> 实测：只改色调不改结构，玩家仍然分不清；**明度差拉到 35% 后一眼可辨**。

### 2. 每个 tile 都要能平铺

- 砖缝画在 `x % 8 == 0` / `y % 8 == 0`（对称位置）
- 错缝用 `(row % 2) * (BW // 2)` 做偏移
- **生成后必须做平铺预览验证**（见下方"预览"一节）

### 3. 三阶明暗 + 有限调色板

每个材质给 **亮 / 中 / 暗** 三色，全部 ≤16 色：

```python
FLOOR_HI = (108, 112, 122, 255)
FLOOR    = (88,  92,  102, 255)
FLOOR_LO = (68,  72,  82,  255)
```

### 4. 固定随机种子

```python
rng = random.Random(seed)     # 而不是 random.seed() 全局污染
```

**同一份代码必须每次产出同一张图** —— 否则每跑一次素材全变，没法做版本管理。

---

## 二、核心代码骨架

```python
from PIL import Image
import random, os

S = 16      # tile 尺寸

def new():
    return Image.new("RGBA", (S, S), (0, 0, 0, 0))

def _noise(px, x, y, base, hi, lo, rng, amount=0.22):
    """在底色上加像素噪点，避免平面死板"""
    r = rng.random()
    if r < amount * 0.5:   px[x, y] = hi
    elif r < amount:       px[x, y] = lo
    else:                  px[x, y] = base

def wall_tile(seed=21):
    """砖墙：8×4 错缝砖 + 勾缝，整体比地板暗 —— 一眼区分"""
    rng = random.Random(seed)
    im = new(); px = im.load()
    BH, BW, MORTAR = 4, 8, 1
    for y in range(S):
        row = y // BH
        off = (BW // 2) if (row % 2) else 0      # ★ 错缝
        for x in range(S):
            bx, by = (x + off) % BW, y % BH
            if by < MORTAR or bx < MORTAR:
                px[x, y] = WALL_MORTAR            # 勾缝（最深）
            elif by == 1:
                _noise(px, x, y, WALL_HI, WALL_HI, WALL, rng, 0.15)   # 砖面受光
            elif by == BH - 1:
                px[x, y] = WALL_LO                # 砖面阴影 → 凸起感
            else:
                _noise(px, x, y, WALL, WALL_HI, WALL_LO, rng, 0.20)
    return im
```

---

## 三、装饰 sprite（消除"棋盘感"）

**症状**：地图铺满后是一片纯色网格，非常像棋盘，不像房间。

**解法**：生成一批小装饰，随机撒在地板上。**装饰物全是简单图形，程序化远好过 AI**：

| 装饰 | 画法 |
|---|---|
| 血泊 | 多个交叠椭圆（深红底 + 中层红 + 少量亮红）+ 随机溅点 |
| 拖痕 | 一条带随机抖动的横向血带 |
| 纸箱 | 矩形 + 顶面高光 + 底面暗边 + 折痕线 + 翘角多边形 |
| 碎玻璃 | 随机位置的小菱形 + 几根细线 |
| 尸体 | 躯干椭圆 + 头部 + 张开的双臂 + 身下血泊 |
| 水渍 | 交叠的深蓝半透明椭圆 |

**两个关键手法**：

1. **装饰要比格子略小（~94%）并加随机偏移**
   ```python
   s = tile_size * 0.94
   off = Vector2(rng.randf_range(-3, 3), rng.randf_range(-3, 3))
   ```
   否则整齐得像贴图，一眼假。

2. **按房间语义分层投放**
   ```gdscript
   # 走廊稀疏、储物间杂乱、客房有血泊和尸体
   "corridor_n": 0.05,   # 密度
   "storage":    0.16,
   # 类型池也按房间换：storage → 纸箱权重最高；guest_room → 血泊 + 尸体
   ```
   并且**用房间 id 当随机种子**，保证同一间房每次进入布置一致。

---

## 四、预览：一定要验证平铺

```python
# 每个 tile 横向平铺 12 个，拼成一张总览图
Z, cols = 8, 12
out = Image.new("RGBA", (cols * S * Z, len(TILES) * S * Z), (30, 32, 40, 255))
for r, name in enumerate(TILES):
    t = Image.open(os.path.join(OUT, name + ".png"))
    for c in range(cols):
        out.alpha_composite(t.resize((S*Z, S*Z), Image.NEAREST), (c*S*Z, r*S*Z))
out.save("assets/raw/_probe/tiles_sheet.png")
```

**然后用 `read_image` 真的去看这张预览** —— 接缝连不连续、会不会有规律性重复，
一眼就能发现。**不要只看单个 tile**。

---

## 五、接入 Godot

材质素材放 `assets/tiles/<world>/*.png`，在渲染器的 `tile_paths` 里登记：

```gdscript
var tile_paths: Dictionary = {
    ".": "res://assets/tiles/w1/floor.png",
    "#": "res://assets/tiles/w1/wall.png",
    ...
}
```

**必须容错**：素材缺失时回退为色块，保证美术未铺满时游戏仍能跑。

```gdscript
func _load_textures() -> void:
    for ch in tile_paths:
        if ResourceLoader.exists(p):
            _tex[ch] = load(p)
        else:
            _missing.append(ch)      # 回退时用 FALLBACK 色块
```

**工程设置**：`default_texture_filter = Nearest`，缩放用**整数倍**（如 16×16 ×3 = 48px 格）。

---

## 常见坑速查

| 现象 | 原因 | 解法 |
|---|---|---|
| AI 生成的 tile 全是噪点 | 扩散模型在 16×16 尺寸下无结构可言 | **改程序化** |
| 墙和地板分不清 | 只改了色调没改明度差 | **明度差拉到 30%+，并给墙加砖块结构** |
| 平铺后有可见接缝 | 图案不对称 | 砖缝画在 `x % BW == 0`，错缝用行号偏移 |
| 地砖排得太整齐像棋盘 | 每格完全相同 | 加 2~3 种变体 + 随机污渍 |
| 每次生成素材都在变 | 用了全局 `random.seed()` | 每个 tile 用独立 `random.Random(seed)` |
| 装饰整齐得像贴纸 | 铺满整格且无偏移 | 缩到 94% + 随机偏移 ±3px |
| 不同房间装饰一样 | 密度和类型池没按房间分 | 按房间 id 定密度 + 类型池 + 随机种子 |
| Godot 里图糊了 | 纹理过滤不是 Nearest | 项目设置改 `default_texture_filter = Nearest` |
