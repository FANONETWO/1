-- 战斗立绘生成器 v4 · Aseprite Lua
--   aseprite -b --script tools/pixelart/gen_battle_sprites.lua
--
-- v4：不再凭想象画，而是**照着 FE-Repo 职业卡的结构**（docs/art_reference/ref_*.png）：
--   · 主角 ← 火纹「佣兵/剑士」：3/4 侧、宽肩收腰、蓝外套、尖发、武器斜举
--   · 丧尸 ← 「Revenant 尸鬼」：上身前倾、头埋肩里、细长垂臂垂到膝、膝外翻
--   · 爬行者 ← 「Mauthe Doog 地狱犬」：四足低伏、背脊隆起、长口鼻
--   · 尸王 ← 「Cyclops 独眼巨人」：巨躯溜肩、粗臂垂地、小头独眼
-- 配色照参考：魔物用「骨白 + 烂肉橙 + 破布靛」三色系。

local OUT = "D:/1/infinite_loop/assets/sprites/w1/battle/"
local W, H = 64, 96

local function C(r, g, b, a) return app.pixelColor.rgba(r, g, b, a or 255) end

local INK     = C(38, 34, 44)
local INK_D   = C(20, 18, 26)
local WHT     = C(255, 255, 255)
local SK_HI   = C(242, 220, 186)
local SK      = C(214, 172, 132)
local SK_SH   = C(166, 126, 96)
local CO_HI   = C(138, 178, 226)
local CO      = C(78, 118, 176)
local CO_SH   = C(42, 66, 114)
local CO_DK   = C(24, 38, 70)
local HR_HI   = C(120, 108, 136)
local HR      = C(66, 58, 86)
local HR_SH   = C(38, 32, 52)
local MT_HI   = C(236, 240, 244)
local MT      = C(158, 166, 178)
local MT_SH   = C(84, 92, 106)
local LEATHER = C(104, 82, 50)
local BONE_HI = C(232, 226, 206)
local BONE    = C(196, 190, 170)
local BONE_SH = C(148, 142, 124)
local FLESH_HI= C(226, 148, 84)
local FLESH   = C(196, 110, 56)
local FLESH_SH= C(140, 72, 38)
local RAG_HI  = C(96, 100, 150)
local RAG     = C(66, 70, 116)
local RAG_SH  = C(40, 44, 80)
local BLOOD   = C(186, 48, 44)
local BLOOD_D = C(112, 28, 30)
local EYE     = C(250, 214, 120)

local function canvas()
  local spr = Sprite(W, H, ColorMode.RGBA)
  local layer = spr:newLayer()
  layer.name = "art"
  local cel = spr:newCel(layer, 1)
  return spr, cel.image
end

local function rect(img, x, y, w, h, col)
  for j = 0, h - 1 do
    for i = 0, w - 1 do
      local px, py = x + i, y + j
      if px >= 0 and py >= 0 and px < W and py < H then img:drawPixel(px, py, col) end
    end
  end
end

local function ellipse(img, cx, cy, rx, ry, col)
  for y = -ry, ry do
    for x = -rx, rx do
      if (x * x) / (rx * rx) + (y * y) / (ry * ry) <= 1.0 then
        local px, py = cx + x, cy + y
        if px >= 0 and py >= 0 and px < W and py < H then img:drawPixel(px, py, col) end
      end
    end
  end
end

local function line(img, x0, y0, x1, y1, col, thick)
  thick = thick or 1
  local dx, dy = math.abs(x1 - x0), math.abs(y1 - y0)
  local sx = x0 < x1 and 1 or -1
  local sy = y0 < y1 and 1 or -1
  local err = dx - dy
  while true do
    for t = 0, thick - 1 do
      local px, py = x0 + t, y0
      if px >= 0 and py >= 0 and px < W and py < H then img:drawPixel(px, py, col) end
    end
    if x0 == x1 and y0 == y1 then break end
    local e2 = 2 * err
    if e2 > -dy then err = err - dy; x0 = x0 + sx end
    if e2 < dx then err = err + dx; y0 = y0 + sy end
  end
end

local function taper(img, x0, y0, x1, y1, w0, w1, base, hi, sh)
  local steps = math.max(math.abs(x1 - x0), math.abs(y1 - y0))
  if steps <= 0 then return end
  for s = 0, steps do
    local t = s / steps
    local cx = math.floor(x0 + (x1 - x0) * t + 0.5)
    local cy = math.floor(y0 + (y1 - y0) * t + 0.5)
    local w = math.floor(w0 + (w1 - w0) * t + 0.5)
    for k = 0, math.max(w - 1, 0) do
      local px = cx + k
      local col = base
      if k < 2 then col = hi elseif k >= w - 2 then col = sh end
      if px >= 0 and px < W and cy >= 0 and cy < H then img:drawPixel(px, cy, col) end
    end
  end
end

local function outline(img, col)
  local snap = {}
  for y = 0, H - 1 do
    for x = 0, W - 1 do snap[y * W + x] = img:getPixel(x, y) end
  end
  local function op(x, y)
    if x < 0 or y < 0 or x >= W or y >= H then return false end
    return app.pixelColor.rgbaA(snap[y * W + x]) > 0
  end
  for y = 0, H - 1 do
    for x = 0, W - 1 do
      if not op(x, y) and (op(x - 1, y) or op(x + 1, y) or op(x, y - 1) or op(x, y + 1)) then
        img:drawPixel(x, y, col)
      end
    end
  end
end

local function save(spr, name)
  spr:saveAs(OUT .. name .. ".aseprite")
  spr:saveCopyAs(OUT .. name .. ".png")
  print("[gen] " .. name)
end

-- ——— 主角：轮回者（照火纹佣兵：宽肩收腰 + 钢管斜举）———
local function gen_hero()
  local spr, img = canvas()

  taper(img, 29, 60, 25, 84, 10, 8, CO_SH, CO, CO_DK)
  rect(img, 21, 82, 13, 8, INK)
  rect(img, 21, 82, 13, 2, MT_SH)
  taper(img, 40, 58, 44, 84, 11, 9, CO, CO_HI, CO_DK)
  rect(img, 38, 82, 14, 8, INK)
  rect(img, 38, 82, 14, 2, MT_SH)
  rect(img, 39, 84, 12, 3, CO_DK)

  ellipse(img, 32, 42, 17, 12, CO)
  rect(img, 16, 32, 32, 12, CO)
  rect(img, 16, 32, 32, 3, CO_HI)
  rect(img, 16, 32, 5, 12, CO_HI)
  ellipse(img, 32, 54, 13, 10, CO)
  rect(img, 20, 52, 26, 8, CO)
  rect(img, 20, 52, 4, 8, CO_HI)
  rect(img, 43, 36, 4, 22, CO_DK)
  line(img, 28, 34, 33, 50, C(210, 216, 226), 5)
  line(img, 37, 34, 33, 50, C(210, 216, 226), 4)
  line(img, 33, 36, 33, 50, WHT, 1)
  line(img, 22, 44, 24, 54, CO_DK, 1)
  line(img, 42, 42, 40, 54, CO_DK, 1)
  rect(img, 20, 56, 26, 4, LEATHER)
  rect(img, 20, 56, 26, 1, C(160, 132, 88))
  rect(img, 40, 56, 5, 4, MT)
  rect(img, 40, 56, 5, 1, MT_HI)

  taper(img, 18, 34, 13, 50, 7, 6, CO_SH, CO, CO_DK)
  rect(img, 11, 48, 7, 7, SK_SH)
  taper(img, 46, 34, 50, 44, 9, 8, CO, CO_HI, CO_SH)
  taper(img, 50, 42, 52, 50, 8, 8, SK, SK_HI, SK_SH)
  rect(img, 48, 48, 9, 7, SK)
  rect(img, 48, 48, 9, 2, SK_HI)

  ellipse(img, 33, 20, 13, 14, SK)
  rect(img, 22, 18, 3, 12, SK_SH)
  ellipse(img, 39, 23, 6, 8, SK)
  rect(img, 44, 22, 3, 3, SK_SH)
  rect(img, 45, 24, 2, 2, SK_SH)
  ellipse(img, 33, 12, 14, 10, HR)
  rect(img, 19, 10, 28, 7, HR)
  rect(img, 28, 3, 12, 7, HR_HI)
  line(img, 25, 8, 16, 1, HR, 5)
  rect(img, 18, 14, 6, 8, HR_SH)
  line(img, 35, 4, 42, 0, HR, 4)
  rect(img, 42, 13, 5, 7, HR)
  rect(img, 36, 21, 7, 8, WHT)
  rect(img, 37, 23, 5, 6, CO_SH)
  rect(img, 37, 23, 5, 2, INK_D)
  rect(img, 38, 24, 2, 2, WHT)
  rect(img, 34, 20, 10, 2, HR_SH)
  rect(img, 39, 30, 6, 2, SK_SH)

  line(img, 52, 46, 60, 12, MT_SH, 6)
  line(img, 53, 46, 61, 13, MT, 4)
  line(img, 54, 45, 61, 13, MT_HI, 1)
  rect(img, 56, 6, 7, 8, MT)
  rect(img, 56, 6, 7, 2, MT_HI)
  rect(img, 54, 42, 9, 5, SK_SH)

  outline(img, INK)
  return spr
end

-- ——— 丧尸（照 Revenant）———
local function gen_zombie()
  local spr, img = canvas()

  taper(img, 24, 58, 20, 84, 10, 9, BONE, BONE_HI, BONE_SH)
  rect(img, 16, 82, 13, 8, INK)
  taper(img, 38, 56, 44, 84, 10, 9, BONE, BONE_HI, BONE_SH)
  rect(img, 40, 82, 12, 8, INK)
  rect(img, 40, 84, 10, 3, RAG_SH)
  rect(img, 19, 76, 4, 5, BONE_HI)
  rect(img, 43, 74, 4, 5, BONE_HI)

  ellipse(img, 32, 48, 15, 15, BONE)
  rect(img, 22, 34, 26, 24, BONE)
  rect(img, 22, 34, 5, 24, BONE_HI)
  rect(img, 44, 38, 4, 20, BONE_SH)
  ellipse(img, 28, 42, 9, 8, FLESH)
  rect(img, 24, 40, 8, 8, FLESH)
  rect(img, 24, 40, 8, 2, FLESH_HI)
  rect(img, 30, 50, 5, 8, FLESH_SH)
  rect(img, 26, 52, 10, 6, FLESH)
  line(img, 24, 44, 36, 46, BONE_SH, 1)
  line(img, 24, 48, 35, 50, BONE_SH, 1)
  rect(img, 22, 56, 26, 7, RAG)
  rect(img, 22, 56, 26, 2, RAG_HI)
  rect(img, 24, 61, 22, 4, RAG_SH)

  ellipse(img, 38, 26, 11, 11, BONE)
  rect(img, 29, 20, 20, 7, BONE_HI)
  rect(img, 28, 25, 4, 9, BONE_SH)
  ellipse(img, 44, 29, 5, 6, BONE)
  rect(img, 48, 28, 3, 3, BONE_SH)
  rect(img, 41, 24, 6, 5, INK_D)
  rect(img, 42, 25, 3, 3, EYE)
  rect(img, 33, 25, 4, 4, INK_D)
  rect(img, 41, 33, 8, 4, INK_D)
  rect(img, 42, 33, 2, 4, BONE_HI)
  rect(img, 46, 33, 2, 4, BONE_HI)

  taper(img, 22, 36, 16, 62, 7, 6, BONE, BONE_HI, BONE_SH)
  taper(img, 44, 38, 48, 64, 7, 6, BONE, BONE_HI, BONE_SH)
  rect(img, 13, 60, 6, 7, BONE_HI)
  rect(img, 13, 60, 6, 2, BONE)
  rect(img, 12, 63, 3, 2, BONE_SH)
  rect(img, 46, 62, 6, 7, BONE_HI)
  rect(img, 46, 62, 6, 2, BONE)
  rect(img, 50, 65, 3, 2, BONE_SH)

  rect(img, 28, 58, 5, 8, BLOOD_D)
  rect(img, 30, 60, 3, 4, BLOOD)

  outline(img, INK)
  return spr
end

-- ——— 爬行者（照 Mauthe Doog）———
local function gen_crawler()
  local spr, img = canvas()

  ellipse(img, 36, 70, 22, 13, BONE)
  rect(img, 16, 62, 34, 8, BONE_HI)
  ellipse(img, 42, 60, 14, 10, BONE_HI)
  rect(img, 22, 80, 28, 5, BONE_SH)
  ellipse(img, 40, 58, 10, 6, FLESH)
  rect(img, 34, 56, 12, 4, FLESH_HI)
  rect(img, 28, 64, 18, 5, FLESH_SH)

  ellipse(img, 15, 68, 12, 11, BONE)
  rect(img, 5, 62, 11, 8, BONE_HI)
  ellipse(img, 8, 72, 8, 6, BONE)
  rect(img, 2, 70, 8, 5, BONE_SH)
  rect(img, 1, 72, 5, 3, BONE)
  rect(img, 10, 65, 5, 4, INK_D)
  rect(img, 11, 66, 3, 2, EYE)
  line(img, 16, 60, 12, 54, BONE, 3)
  line(img, 20, 60, 22, 53, BONE, 3)
  rect(img, 2, 76, 7, 3, INK_D)
  rect(img, 3, 76, 2, 4, BONE_HI)
  rect(img, 6, 76, 2, 4, BONE_HI)

  taper(img, 24, 84, 18, 92, 5, 4, BONE, BONE_HI, BONE_SH)
  taper(img, 32, 85, 26, 94, 5, 4, BONE, BONE_HI, BONE_SH)
  taper(img, 44, 85, 40, 94, 5, 4, BONE, BONE_HI, BONE_SH)
  taper(img, 52, 82, 57, 92, 5, 4, BONE, BONE_HI, BONE_SH)
  rect(img, 16, 91, 4, 3, INK)
  rect(img, 25, 93, 4, 3, INK)
  rect(img, 39, 93, 4, 3, INK)
  rect(img, 56, 91, 4, 3, INK)
  taper(img, 56, 66, 63, 56, 5, 3, BONE, BONE_HI, BONE_SH)

  rect(img, 24, 74, 6, 5, BLOOD_D)
  rect(img, 46, 72, 5, 5, BLOOD_D)

  outline(img, INK)
  return spr
end

-- ——— 尸王（照 Cyclops）———
local function gen_brute()
  local spr, img = canvas()

  taper(img, 24, 56, 20, 82, 17, 15, FLESH, FLESH_HI, FLESH_SH)
  rect(img, 12, 80, 21, 9, INK)
  taper(img, 42, 58, 48, 82, 17, 15, FLESH, FLESH_HI, FLESH_SH)
  rect(img, 40, 80, 21, 9, INK)

  ellipse(img, 32, 42, 22, 18, FLESH)
  rect(img, 10, 32, 44, 26, FLESH)
  rect(img, 10, 32, 7, 24, FLESH_HI)
  rect(img, 50, 36, 4, 22, INK)
  ellipse(img, 18, 34, 13, 11, FLESH_HI)
  ellipse(img, 46, 34, 12, 10, FLESH)
  line(img, 14, 46, 22, 56, FLESH_SH, 2)
  line(img, 44, 44, 38, 56, FLESH_SH, 2)
  rect(img, 24, 40, 16, 5, FLESH_HI)
  line(img, 26, 52, 38, 54, BONE_SH, 1)
  line(img, 26, 56, 37, 58, BONE_SH, 1)
  rect(img, 10, 58, 44, 7, RAG)
  rect(img, 10, 58, 44, 2, RAG_HI)
  rect(img, 16, 62, 32, 4, RAG_SH)

  ellipse(img, 32, 20, 12, 12, FLESH)
  rect(img, 21, 14, 22, 8, FLESH_HI)
  rect(img, 20, 20, 4, 9, FLESH_SH)
  ellipse(img, 40, 24, 6, 6, FLESH)
  ellipse(img, 34, 20, 6, 6, INK_D)
  ellipse(img, 34, 20, 4, 4, WHT)
  rect(img, 32, 18, 5, 5, C(220, 90, 70))
  rect(img, 33, 19, 2, 2, WHT)
  rect(img, 30, 29, 12, 4, INK_D)
  rect(img, 30, 29, 12, 2, BLOOD_D)
  rect(img, 32, 29, 3, 6, BONE_HI)
  rect(img, 38, 29, 3, 6, BONE_HI)

  taper(img, 10, 34, 6, 50, 15, 13, FLESH, FLESH_HI, FLESH_SH)
  taper(img, 6, 48, 8, 74, 13, 12, FLESH, FLESH_HI, FLESH_SH)
  rect(img, 6, 72, 14, 9, FLESH_SH)
  rect(img, 6, 72, 14, 2, FLESH_HI)
  rect(img, 6, 79, 14, 2, INK)
  taper(img, 54, 36, 58, 54, 10, 9, FLESH_SH, FLESH, INK)

  line(img, 52, 32, 57, 22, BONE_HI, 5)
  line(img, 54, 44, 58, 36, BONE_HI, 5)
  rect(img, 48, 48, 9, 14, BLOOD_D)
  rect(img, 44, 36, 6, 9, BLOOD_D)

  outline(img, INK)
  return spr
end

save(gen_hero(), "hero")
save(gen_zombie(), "zombie")
save(gen_crawler(), "crawler")
save(gen_brute(), "brute")
print("[gen] 全部完成 -> " .. OUT)
