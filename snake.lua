local component = require("component")
local event = require("event")
local keyboard = require("keyboard")
local computer = require("computer")

local gpu = component.gpu

-- =========================
-- 基础设置
-- =========================
local CELL_W = 2
local BASE_TICK = 0.14
local MIN_TICK = 0.05
local SPEED_UP = 0.003

local bgColor = 0x000000
local borderColor = 0xAAAAAA
local snakeColor = 0x00FF00
local headColor = 0xAAFFAA
local foodColor = 0xFF4444
local textColor = 0xFFFFFF
local gameOverColor = 0xFFAA00
local titleColor = 0x00FFFF

local running = true
local interrupted = false

local oldBg = gpu.getBackground()
local oldFg = gpu.getForeground()

local wrapMode = false

-- =========================
-- 安全退出
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
  gpu.setBackground(oldBg)
  gpu.setForeground(oldFg)
end

-- =========================
-- 分辨率
-- =========================
local sw, sh = gpu.getResolution()
local boardW = math.max(10, math.floor((sw - 2) / CELL_W))
local boardH = math.max(10, sh - 6)

local offsetX = math.floor((sw - (boardW * CELL_W + 2)) / 2) + 1
local offsetY = math.floor((sh - (boardH + 2)) / 2) + 3

-- =========================
-- 绘图
-- =========================
local function clearScreen()
  gpu.setBackground(bgColor)
  gpu.fill(1, 1, sw, sh, " ")
end

local function drawText(x, y, text, fg)
  gpu.setForeground(fg or textColor)
  gpu.set(x, y, text)
end

local function drawCell(x, y, color, char)
  gpu.setBackground(color)
  gpu.setForeground(color)
  gpu.set(offsetX + 1 + (x - 1) * CELL_W, offsetY + y, char or "  ")
end

local function drawBorder()
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

local function drawHUD(score, speed, paused)
  gpu.setForeground(textColor)
  gpu.fill(1, 1, sw, 1, " ")
  local mode = wrapMode and "Wrap: ON " or "Wrap: OFF"
  local p = paused and " | PAUSED" or ""
  local msg = string.format("Snake | Score: %d | Speed: %.2f | %s%s", score, 1/speed, mode, p)
  gpu.set(1, 1, msg:sub(1, sw))
end

-- =========================
-- 主菜单
-- =========================
local function showMenu()
  clearScreen()

  local title = "== SNAKE =="
  local startText = "[ START ]"
  local quitText = "[ QUIT ]"

  while true do
    local wrapText = wrapMode and "[ Wrap Mode: ON  ]" or "[ Wrap Mode: OFF ]"

    local cx = math.floor(sw/2)

    local titleY = math.floor(sh/2) - 3
    local wrapY = titleY + 2
    local startY = wrapY + 2
    local quitY = startY + 2

    drawText(cx - #title//2, titleY, title, titleColor)
    drawText(cx - #wrapText//2, wrapY, wrapText, textColor)
    drawText(cx - #startText//2, startY, startText, textColor)
    drawText(cx - #quitText//2, quitY, quitText, textColor)

    local ev = {event.pull()}

    if ev[1] == "key_down" then
      if ev[4] == keyboard.keys.enter then
        return true
      elseif ev[4] == keyboard.keys.q then
        return false
      elseif ev[4] == keyboard.keys.space then
        wrapMode = not wrapMode
      end
    elseif ev[1] == "touch" then
      local x, y = ev[3], ev[4]

      if y == wrapY and x >= cx - #wrapText//2 and x <= cx + #wrapText//2 then
        wrapMode = not wrapMode
      end

      if y == startY and x >= cx - #startText//2 and x <= cx + #startText//2 then
        return true
      end

      if y == quitY and x >= cx - #quitText//2 and x <= cx + #quitText//2 then
        return false
      end
    end
  end
end

-- =========================
-- 游戏逻辑
-- =========================
local snake, food, score
local dirX, dirY, nextDirX, nextDirY
local gameOver
local tick

local function initGame()
  snake = {
    {x = math.floor(boardW/2), y = math.floor(boardH/2)},
    {x = math.floor(boardW/2)-1, y = math.floor(boardH/2)},
  }

  dirX, dirY = 1, 0
  nextDirX, nextDirY = 1, 0
  score = 0
  gameOver = false
  tick = BASE_TICK
end

local function snakeOccupies(x,y)
  for i=1,#snake do
    if snake[i].x==x and snake[i].y==y then return true end
  end
end

local function spawnFood()
  while true do
    local x = math.random(1, boardW)
    local y = math.random(1, boardH)
    if not snakeOccupies(x,y) then
      return {x=x,y=y}
    end
  end
end

local function drawSnake()
  for i=1,#snake do
    local p = snake[i]
    if i==1 then
      drawCell(p.x,p.y,headColor,"@@")
    else
      drawCell(p.x,p.y,snakeColor,"  ")
    end
  end
end

local function step()
  dirX, dirY = nextDirX, nextDirY

  local head = {
    x = snake[1].x + dirX,
    y = snake[1].y + dirY
  }

  if wrapMode then
    if head.x < 1 then head.x = boardW end
    if head.x > boardW then head.x = 1 end
    if head.y < 1 then head.y = boardH end
    if head.y > boardH then head.y = 1 end
  else
    if head.x<1 or head.x>boardW or head.y<1 or head.y>boardH then
      gameOver = true
      return false
    end
  end

  for i=1,#snake do
    if snake[i].x==head.x and snake[i].y==head.y then
      gameOver = true
      return false
    end
  end

  table.insert(snake,1,head)

  if head.x==food.x and head.y==food.y then
    score = score + 1
    tick = math.max(MIN_TICK, tick - SPEED_UP)
    food = spawnFood()
  else
    local tail = table.remove(snake)
    drawCell(tail.x,tail.y,bgColor,"  ")
  end

  drawSnake()
  drawCell(food.x,food.y,foodColor,"  ")
  drawHUD(score, tick, false)

  return true
end

local function setDir(x,y)
  if #snake>1 and x==-dirX and y==-dirY then return end
  nextDirX,nextDirY=x,y
end

-- =========================
-- 主流程
-- =========================
math.randomseed(computer.uptime()*1000)

while running do
  if not showMenu() then break end

  initGame()
  food = spawnFood()

  clearScreen()
  drawBorder()
  drawSnake()
  drawCell(food.x,food.y,foodColor,"  ")

  local last = computer.uptime()
  local paused = false

  while true do
    local ev = {event.pull(0.01)}

    if ev[1]=="key_down" then
      local k = ev[4]

      if k==keyboard.keys.q then
        paused = not paused
        drawHUD(score, tick, paused)
      elseif not paused then
        if k==keyboard.keys.w then setDir(0,-1)
        elseif k==keyboard.keys.s then setDir(0,1)
        elseif k==keyboard.keys.a then setDir(-1,0)
        elseif k==keyboard.keys.d then setDir(1,0)
        end
      end
    end

    if not paused and computer.uptime()-last >= tick then
      if not step() then break end
      last = computer.uptime()
    end
  end

  local msg = "Game Over! Score: "..score
  local tip = "Press any key to return"

  drawText(math.floor((sw-#msg)/2), math.floor(sh/2), msg, gameOverColor)
  drawText(math.floor((sw-#tip)/2), math.floor(sh/2)+2, tip, textColor)

  event.pull("key_down")
end

cleanup()
clearScreen()
