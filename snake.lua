local component = require("component")
local event = require("event")
local keyboard = require("keyboard")
local computer = require("computer")

local gpu = component.gpu

-- =========================
-- 基础设置
-- =========================
local CELL_W = 2           -- 每个格子占 2 个字符宽，画面更像方块
local TICK = 0.12          -- 游戏速度，数值越小越快

local bgColor = 0x000000
local borderColor = 0xAAAAAA
local snakeColor = 0x00FF00
local headColor = 0x55FF55
local foodColor = 0xFF4444
local textColor = 0xFFFFFF
local gameOverColor = 0xFFAA00

local running = true
local interrupted = false

local oldBg = gpu.getBackground()
local oldFg = gpu.getForeground()
local oldW, oldH = gpu.getResolution()

-- =========================
-- 安全退出相关
-- =========================
local function onInterrupted()
  interrupted = true
  running = false
end

event.listen("interrupted", onInterrupted)

local function cleanup()
  pcall(function()
    event.ignore("interrupted", onInterrupted)
  end)
  pcall(function()
    gpu.setBackground(oldBg)
    gpu.setForeground(oldFg)
  end)
end

-- =========================
-- 分辨率与棋盘计算
-- =========================
local sw, sh = gpu.getResolution()

-- 给上下留一行文本区域和边框
local boardW = math.max(10, math.floor((sw - 2) / CELL_W))
local boardH = math.max(10, sh - 4)

local offsetX = math.floor((sw - (boardW * CELL_W + 2)) / 2) + 1
local offsetY = math.floor((sh - (boardH + 2)) / 2) + 2

if offsetX < 1 then offsetX = 1 end
if offsetY < 2 then offsetY = 2 end

-- =========================
-- 绘图函数
-- =========================
local function clearScreen()
  gpu.setBackground(bgColor)
  gpu.setForeground(textColor)
  gpu.fill(1, 1, sw, sh, " ")
end

local function drawText(x, y, text, fg, bg)
  if bg then gpu.setBackground(bg) else gpu.setBackground(bgColor) end
  if fg then gpu.setForeground(fg) else gpu.setForeground(textColor) end
  gpu.set(x, y, tostring(text))
end

local function drawCell(x, y, color, char)
  char = char or "  "
  gpu.setBackground(color)
  gpu.setForeground(color)
  gpu.set(offsetX + 1 + (x - 1) * CELL_W, offsetY + y, char)
end

local function drawBorder()
  gpu.setBackground(bgColor)
  gpu.setForeground(borderColor)

  local top = "┌" .. string.rep("─", boardW * CELL_W) .. "┐"
  local mid = "│" .. string.rep(" ", boardW * CELL_W) .. "│"
  local bot = "└" .. string.rep("─", boardW * CELL_W) .. "┘"

  gpu.set(offsetX, offsetY, top)
  for y = 1, boardH do
    gpu.set(offsetX, offsetY + y, mid)
  end
  gpu.set(offsetX, offsetY + boardH + 1, bot)
end

local function drawHUD(score)
  gpu.setBackground(bgColor)
  gpu.setForeground(textColor)
  gpu.fill(1, 1, sw, 1, " ")
  local msg = string.format("Snake  |  Score: %d  |  WASD / ↑↓←→ 控制  |  Q 退出", score)
  gpu.set(1, 1, msg:sub(1, sw))
end

-- =========================
-- 游戏数据
-- =========================
local snake = {
  {x = math.floor(boardW / 2), y = math.floor(boardH / 2)},
  {x = math.floor(boardW / 2) - 1, y = math.floor(boardH / 2)},
  {x = math.floor(boardW / 2) - 2, y = math.floor(boardH / 2)}
}

local dirX, dirY = 1, 0
local nextDirX, nextDirY = 1, 0
local food = nil
local score = 0
local gameOver = false

local function samePos(a, b)
  return a.x == b.x and a.y == b.y
end

local function snakeOccupies(x, y)
  for i = 1, #snake do
    if snake[i].x == x and snake[i].y == y then
      return true
    end
  end
  return false
end

local function spawnFood()
  local free = {}
  for y = 1, boardH do
    for x = 1, boardW do
      if not snakeOccupies(x, y) then
        free[#free + 1] = {x = x, y = y}
      end
    end
  end

  if #free == 0 then
    return nil
  end

  local idx = math.random(1, #free)
  return free[idx]
end

local function drawFood()
  if food then
    drawCell(food.x, food.y, foodColor, "  ")
  end
end

local function drawSnake()
  for i = 1, #snake do
    local part = snake[i]
    if i == 1 then
      drawCell(part.x, part.y, headColor, "  ")
    else
      drawCell(part.x, part.y, snakeColor, "  ")
    end
  end
end

local function eraseTail(tail)
  drawCell(tail.x, tail.y, bgColor, "  ")
end

local function resetBoard()
  clearScreen()
  drawHUD(score)
  drawBorder()
  drawFood()
  drawSnake()
end

-- =========================
-- 输入处理
-- =========================
local function setDirection(nx, ny)
  -- 禁止直接反向
  if #snake > 1 and nx == -dirX and ny == -dirY then
    return
  end
  nextDirX, nextDirY = nx, ny
end

local function handleKey(code)
  if code == keyboard.keys.w or code == keyboard.keys.up then
    setDirection(0, -1)
  elseif code == keyboard.keys.s or code == keyboard.keys.down then
    setDirection(0, 1)
  elseif code == keyboard.keys.a or code == keyboard.keys.left then
    setDirection(-1, 0)
  elseif code == keyboard.keys.d or code == keyboard.keys.right then
    setDirection(1, 0)
  elseif code == keyboard.keys.q then
    running = false
  end
end

-- =========================
-- 游戏逻辑
-- =========================
local function step()
  dirX, dirY = nextDirX, nextDirY

  local newHead = {
    x = snake[1].x + dirX,
    y = snake[1].y + dirY
  }

  -- 撞墙
  if newHead.x < 1 or newHead.x > boardW or newHead.y < 1 or newHead.y > boardH then
    gameOver = true
    running = false
    return
  end

  -- 撞自己
  for i = 1, #snake do
    if snake[i].x == newHead.x and snake[i].y == newHead.y then
      gameOver = true
      running = false
      return
    end
  end

  table.insert(snake, 1, newHead)

  if food and samePos(newHead, food) then
    score = score + 1
    food = spawnFood()
    if not food then
      -- 填满全图，算通关
      running = false
      gameOver = false
      return
    end
    drawHUD(score)
    drawFood()
  else
    local tail = table.remove(snake)
    eraseTail(tail)
  end

  drawSnake()
end

-- =========================
-- 主程序
-- =========================
math.randomseed(computer.uptime() * 1000 % 2147483647)

food = spawnFood()
resetBoard()

local lastTick = computer.uptime()

while running do
  local timeout = math.max(0, TICK - (computer.uptime() - lastTick))
  local ev = {event.pull(timeout)}

  if ev[1] == "key_down" then
    -- key_down: signal, keyboardAddress, char, code, playerName
    handleKey(ev[4])
  end

  local now = computer.uptime()
  if now - lastTick >= TICK then
    step()
    lastTick = now
  end
end

-- =========================
-- 结束界面
-- =========================
gpu.setBackground(bgColor)
gpu.setForeground(gameOverColor)

local msg
if interrupted then
  msg = "已中断退出"
elseif gameOver then
  msg = "游戏结束！最终分数: " .. score
else
  msg = "你赢了！最终分数: " .. score
end

local tip = "按任意键返回"
local x1 = math.max(1, math.floor((sw - #msg) / 2))
local x2 = math.max(1, math.floor((sw - #tip) / 2))
local y = math.floor(sh / 2)

gpu.fill(1, y - 1, sw, 3, " ")
gpu.set(x1, y, msg:sub(1, sw))
gpu.setForeground(textColor)
gpu.set(x2, y + 1, tip:sub(1, sw))

event.pull("key_down")
cleanup()
clearScreen()