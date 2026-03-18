local component = require("component")
local event = require("event")
local keyboard = require("keyboard")
local computer = require("computer")
local unicode = require("unicode")

local gpu = component.gpu

local SW, SH = gpu.getResolution()
gpu.setBackground(0x000000)
gpu.setForeground(0xFFFFFF)
gpu.fill(1, 1, SW, SH, " ")

local SW, SH = gpu.getResolution()

local W, H = 10, 21
local MAX_LEVEL = 10

local BOARD_X = 24
local BOARD_Y = 4

local INFO_X = 2
local INFO_Y = 2

local NEXT_X = 2
local NEXT_Y = 10

local HELP_X = BOARD_X + 28
local HELP_Y = 2

local DIFF_X = BOARD_X + 4
local DIFF_Y = BOARD_Y + 8

local BLOCK = "[]"
local EMPTY = ". "
local LEFT_BORDER = "<!"
local RIGHT_BORDER = "!>"

local COLOR_BG = 0x000000
local COLOR_FG = 0xFFFFFF
local COLOR_DIM = 0x777777
local COLOR_BLOCK = 0x33FF99
local COLOR_GHOST = 0x444444
local COLOR_WARN = 0xFF6666
local COLOR_TITLE = 0x66CCFF
local COLOR_ACCENT = 0xFFFF66

local front = {}
local back = {}

local function initBuffers()
  for y = 1, SH do
    front[y] = {}
    back[y] = {}
    for x = 1, SW do
      front[y][x] = {ch = " ", fg = COLOR_FG, bg = COLOR_BG}
      back[y][x] = {ch = " ", fg = COLOR_FG, bg = COLOR_BG}
    end
  end
end

local function clearBack(bg, fg)
  bg = bg or COLOR_BG
  fg = fg or COLOR_FG
  for y = 1, SH do
    for x = 1, SW do
      local c = back[y][x]
      c.ch = " "
      c.fg = fg
      c.bg = bg
    end
  end
end

local function put(x, y, text, fg, bg)
  if not text then return end
  if y < 1 or y > SH then return end
  fg = fg or COLOR_FG
  bg = bg or COLOR_BG
  local len = unicode.len(text)
  for i = 1, len do
    local ch = unicode.sub(text, i, i)
    local xx = x + i - 1
    if xx >= 1 and xx <= SW then
      local c = back[y][xx]
      c.ch = ch
      c.fg = fg
      c.bg = bg
    end
  end
end

local function flush()
  local lastFg, lastBg = nil, nil
  for y = 1, SH do
    local x = 1
    while x <= SW do
      local b = back[y][x]
      local f = front[y][x]
      if b.ch ~= f.ch or b.fg ~= f.fg or b.bg ~= f.bg then
        local runFg, runBg = b.fg, b.bg
        local text = b.ch
        local x2 = x + 1
        while x2 <= SW do
          local bb = back[y][x2]
          local ff = front[y][x2]
          if bb.fg == runFg and bb.bg == runBg and (bb.ch ~= ff.ch or bb.fg ~= ff.fg or bb.bg ~= ff.bg) then
            text = text .. bb.ch
            x2 = x2 + 1
          else
            break
          end
        end
        if lastBg ~= runBg then gpu.setBackground(runBg) lastBg = runBg end
        if lastFg ~= runFg then gpu.setForeground(runFg) lastFg = runFg end
        gpu.set(x, y, text)
        for i = x, x2 - 1 do
          front[y][i].ch = back[y][i].ch
          front[y][i].fg = back[y][i].fg
          front[y][i].bg = back[y][i].bg
        end
        x = x2
      else
        x = x + 1
      end
    end
  end
end

local PIECES = {
  I = {
    cells = {{-1,0},{0,0},{1,0},{2,0}},
    pivot = {0.5, 0.5}
  },
  O = {
    cells = {{0,0},{1,0},{0,1},{1,1}},
    pivot = {0.5, 0.5}
  },
  T = {
    cells = {{-1,0},{0,0},{1,0},{0,1}},
    pivot = {0, 0}
  },
  S = {
    cells = {{0,0},{1,0},{-1,1},{0,1}},
    pivot = {0, 0}
  },
  Z = {
    cells = {{-1,0},{0,0},{0,1},{1,1}},
    pivot = {0, 0}
  },
  J = {
    cells = {{-1,0},{-1,1},{0,1},{1,1}},
    pivot = {0, 1}
  },
  L = {
    cells = {{1,0},{-1,1},{0,1},{1,1}},
    pivot = {0, 1}
  }
}

local BAG_KEYS = {"I","O","T","S","Z","J","L"}

local board = {}
local bag = {}
local current = nil
local nextPiece = nil

local score = 0
local lines = 0
local level = 1
local difficulty = 1

local running = false
local started = false
local paused = false
local gameOver = false
local inMenu = true

local lastFall = computer.uptime()
local lastRPress = 0
local titleTick = 0

local function clamp(v, a, b)
  if v < a then return a end
  if v > b then return b end
  return v
end

local function initBoard()
  board = {}
  for y = 1, H do
    board[y] = {}
    for x = 1, W do
      board[y][x] = 0
    end
  end
end

local function shuffleBag()
  bag = {}
  for i = 1, #BAG_KEYS do
    bag[i] = BAG_KEYS[i]
  end
  for i = #bag, 2, -1 do
    local j = math.random(i)
    bag[i], bag[j] = bag[j], bag[i]
  end
end

local function takeFromBag()
  if #bag == 0 then
    shuffleBag()
  end
  return table.remove(bag, 1)
end

local function newPiece(kind)
  return {
    kind = kind,
    rot = 0,
    x = 5,
    y = 1
  }
end

local function rotatePoint(x, y, px, py, rot)
  local rx, ry = x, y
  for _ = 1, rot do
    local dx = rx - px
    local dy = ry - py
    rx = px - dy
    ry = py + dx
  end
  return rx, ry
end

local function getCells(piece, rot, px, py)
  rot = rot or piece.rot
  px = px or piece.x
  py = py or piece.y

  local def = PIECES[piece.kind]
  local out = {}

  for i = 1, #def.cells do
    local cx, cy = def.cells[i][1], def.cells[i][2]
    local rx, ry

    if piece.kind == "O" then
      rx, ry = cx, cy
    else
      rx, ry = rotatePoint(cx, cy, def.pivot[1], def.pivot[2], rot)
    end

    out[#out + 1] = {
      x = px + rx,
      y = py + ry
    }
  end

  return out
end

local function valid(piece, rot, px, py)
  local cells = getCells(piece, rot, px, py)
  for i = 1, #cells do
    local x, y = cells[i].x, cells[i].y
    if x < 1 or x > W or y > H then
      return false
    end
    if y >= 1 and board[y][x] ~= 0 then
      return false
    end
  end
  return true
end

local function getDropInterval()
  local base = 1.15 - (difficulty - 1) * 0.11
  base = math.max(0.01, base)

  local speed = base - (level - 1) * 0.045
  return math.max(0.01, speed)
end

local function updateLevel()
  level = clamp(math.floor(lines / 10) + 1, 1, MAX_LEVEL)
end

local function spawnPiece()
  current = nextPiece or newPiece(takeFromBag())
  current.x = 5
  current.y = 1
  current.rot = 0
  nextPiece = newPiece(takeFromBag())
  if not valid(current, current.rot, current.x, current.y) then
    gameOver = true
    started = false
    running = false
  end
end

local function mergeCurrent()
  if not current then return end
  local cells = getCells(current)
  for i = 1, #cells do
    local x, y = cells[i].x, cells[i].y
    if y >= 1 and y <= H and x >= 1 and x <= W then
      board[y][x] = 1
    end
  end
end

local function clearLines()
  local fullRows = {}

  for y = 1, H do
    local full = true
    for x = 1, W do
      if board[y][x] == 0 then
        full = false
        break
      end
    end
    if full then
      fullRows[#fullRows + 1] = y
    end
  end

  local cleared = #fullRows
  if cleared == 0 then return end

  for i = cleared, 1, -1 do
    table.remove(board, fullRows[i])
  end

  for i = 1, cleared do
    local newRow = {}
    for x = 1, W do
      newRow[x] = 0
    end
    table.insert(board, 1, newRow)
  end

  lines = lines + cleared
  updateLevel()

  local add = ({100, 300, 500, 800})[cleared] or 0
  score = score + add * level
end

local function lockAndSpawn()
  mergeCurrent()
  clearLines()
  spawnPiece()
end

local function tryMove(dx, dy)
  if current and valid(current, current.rot, current.x + dx, current.y + dy) then
    current.x = current.x + dx
    current.y = current.y + dy
    return true
  end
  return false
end

local function tryRotate()
  if not current then return false end
  if current.kind == "O" then return true end

  local nr = (current.rot + 1) % 4

  local kicks = {
    {0,0}, {-1,0}, {1,0}, {-2,0}, {2,0}, {0,-1}
  }

  for i = 1, #kicks do
    local k = kicks[i]
    if valid(current, nr, current.x + k[1], current.y + k[2]) then
      current.rot = nr
      current.x = current.x + k[1]
      current.y = current.y + k[2]
      return true
    end
  end
  return false
end

local function hardDrop()
  if not current then return end
  local dist = 0
  while tryMove(0, 1) do
    dist = dist + 1
  end
  score = score + dist * 2
  lockAndSpawn()
end

local function softDrop()
  if not current then return end
  if not tryMove(0, 1) then
    lockAndSpawn()
  end
end

local function ghostY()
  if not current then return nil end
  local y = current.y
  while valid(current, current.rot, current.x, y + 1) do
    y = y + 1
  end
  return y
end

local function resetGame()
  score = 0
  lines = 0
  level = 1
  current = nil
  nextPiece = nil
  running = false
  started = false
  paused = false
  gameOver = false
  initBoard()
  bag = {}
  shuffleBag()
  nextPiece = newPiece(takeFromBag())
  lastFall = computer.uptime()
end

local function beginGame()
  resetGame()
  started = true
  running = true
  paused = false
  gameOver = false
  inMenu = false
  spawnPiece()
end

local function drawBoardFrame()
  for y = 1, H do
    put(BOARD_X, BOARD_Y + y - 1, LEFT_BORDER, COLOR_DIM)
    for x = 1, W do
      put(BOARD_X + 2 + (x - 1) * 2, BOARD_Y + y - 1, EMPTY, COLOR_DIM)
    end
    put(BOARD_X + 2 + W * 2, BOARD_Y + y - 1, RIGHT_BORDER, COLOR_DIM)
  end
  put(BOARD_X, BOARD_Y + H, "<!====================!>", COLOR_DIM)
  put(BOARD_X, BOARD_Y + H + 1, "  \\/\\/\\/\\/\\/\\/\\/\\/\\/\\/", COLOR_DIM)
end

local function drawBoardContent()
  for y = 1, H do
    for x = 1, W do
      if board[y][x] ~= 0 then
        put(BOARD_X + 2 + (x - 1) * 2, BOARD_Y + y - 1, BLOCK, COLOR_BLOCK)
      end
    end
  end

  if current and started and not paused and not gameOver then
    local gy = ghostY()
    if gy then
      local cells = getCells(current, current.rot, current.x, gy)
      for i = 1, #cells do
        local c = cells[i]
        if c.y >= 1 and board[c.y][c.x] == 0 then
          put(BOARD_X + 2 + (c.x - 1) * 2, BOARD_Y + c.y - 1, "()", COLOR_GHOST)
        end
      end
    end
  end

  if current then
    local cells = getCells(current)
    for i = 1, #cells do
      local c = cells[i]
      if c.y >= 1 then
        put(BOARD_X + 2 + (c.x - 1) * 2, BOARD_Y + c.y - 1, BLOCK, COLOR_BLOCK)
      end
    end
  end
end

local function drawInfo()
  put(INFO_X, INFO_Y,     "Score: " .. tostring(score), COLOR_FG)
  put(INFO_X, INFO_Y + 1, "Lines: " .. tostring(lines), COLOR_FG)
  put(INFO_X, INFO_Y + 2, "Level: " .. tostring(level) .. "/" .. tostring(MAX_LEVEL), COLOR_FG)
  put(INFO_X, INFO_Y + 4, "Difficulty:", COLOR_FG)
  put(INFO_X, INFO_Y + 5, tostring(difficulty), COLOR_ACCENT)
end

local function drawNext()
  put(NEXT_X, NEXT_Y, "Next:", COLOR_FG)
  for i = 1, 6 do
    put(NEXT_X, NEXT_Y + i, "            ", COLOR_FG)
  end
  if not nextPiece then return end
  local cells = getCells(nextPiece, 0, 3, 2)
  for i = 1, #cells do
    local c = cells[i]
    put(NEXT_X + (c.x - 1) * 2, NEXT_Y + c.y, BLOCK, COLOR_BLOCK)
  end
end

local function drawHelp()
  put(HELP_X, HELP_Y,     "Controls", COLOR_FG)
  put(HELP_X, HELP_Y + 1, "A/D   Move", COLOR_DIM)
  put(HELP_X, HELP_Y + 2, "W     Rotate", COLOR_DIM)
  put(HELP_X, HELP_Y + 3, "S     Soft Drop", COLOR_DIM)
  put(HELP_X, HELP_Y + 4, "Space Hard Drop", COLOR_DIM)
  put(HELP_X, HELP_Y + 5, "Q     Pause", COLOR_DIM)
  put(HELP_X, HELP_Y + 6, "R x2  Reset", COLOR_DIM)
end

local function drawOverlay()
  if inMenu then
    local pulse = (math.floor(titleTick * 3) % 2 == 0) and COLOR_TITLE or COLOR_ACCENT
    put(BOARD_X - 6, BOARD_Y + 3,  "████████╗███████╗████████╗██████╗ ██╗███████╗", pulse)
    put(BOARD_X - 6, BOARD_Y + 4,  "╚══██╔══╝██╔════╝╚══██╔══╝██╔══██╗██║██╔════╝", pulse)
    put(BOARD_X - 6, BOARD_Y + 5,  "   ██║   █████╗     ██║   ██████╔╝██║███████╗", pulse)
    put(BOARD_X - 6, BOARD_Y + 6,  "   ██║   ██╔══╝     ██║   ██╔══██╗██║╚════██║", pulse)
    put(BOARD_X - 6, BOARD_Y + 7,  "   ██║   ███████╗   ██║   ██║  ██║██║███████║", pulse)
    put(BOARD_X - 6, BOARD_Y + 8,  "   ╚═╝   ╚══════╝   ╚═╝   ╚═╝  ╚═╝╚═╝╚══════╝", pulse)

    put(BOARD_X - 4, BOARD_Y + 11, "Select Difficulty 1-10", COLOR_FG)
    put(BOARD_X - 5, BOARD_Y + 13, "[1]-[9] set level 1-9", difficulty <= 9 and COLOR_ACCENT or COLOR_DIM)
    put(BOARD_X - 5, BOARD_Y + 14, "[0] set level 10", difficulty == 10 and COLOR_ACCENT or COLOR_DIM)
    put(BOARD_X - 1, BOARD_Y + 16, "Current: " .. tostring(difficulty), COLOR_ACCENT)

    put(BOARD_X - 6, BOARD_Y + 18, "Press SPACE to START", COLOR_FG)
    put(BOARD_X - 8, BOARD_Y + 19, "Q pause, double R reset", COLOR_DIM)
  elseif paused then
    put(BOARD_X + 4, BOARD_Y + 10, "=== PAUSED ===", COLOR_ACCENT)
    put(BOARD_X + 1, BOARD_Y + 12, "Press SPACE to continue", COLOR_FG)
  elseif gameOver then
    put(BOARD_X + 3, BOARD_Y + 9, "=== GAME OVER ===", COLOR_WARN)
    put(BOARD_X + 2, BOARD_Y + 11, "Press SPACE to restart", COLOR_FG)
    put(BOARD_X + 1, BOARD_Y + 13, "Or double-tap R to reset", COLOR_DIM)
  elseif not started then
    put(BOARD_X + 2, BOARD_Y + 10, "Press SPACE to start", COLOR_FG)
  end
end

local function render()
  clearBack(COLOR_BG, COLOR_FG)
  drawInfo()
  drawNext()
  drawHelp()
  drawBoardFrame()
  drawBoardContent()
  drawOverlay()
  flush()
end

local function handleKey(code, char)
  if inMenu then
    if char == string.byte("1") then
      difficulty = 1
    elseif char == string.byte("2") then
      difficulty = 2
    elseif char == string.byte("3") then
      difficulty = 3
    elseif char == string.byte("4") then
      difficulty = 4
    elseif char == string.byte("5") then
      difficulty = 5
    elseif char == string.byte("6") then
      difficulty = 6
    elseif char == string.byte("7") then
      difficulty = 7
    elseif char == string.byte("8") then
      difficulty = 8
    elseif char == string.byte("9") then
      difficulty = 9
    elseif char == string.byte("0") then
      difficulty = 10
    elseif code == keyboard.keys.space then
      beginGame()
    end
    return
  end

  if code == keyboard.keys.r then
    local now = computer.uptime()
    if now - lastRPress <= 0.35 then
      resetGame()
      inMenu = true
    end
    lastRPress = now
    return
  end

  if code == keyboard.keys.q then
    if started and not gameOver then
      paused = not paused
      lastFall = computer.uptime()
    end
    return
  end

  if code == keyboard.keys.space then
    if gameOver then
      beginGame()
      return
    end
    if paused then
      paused = false
      lastFall = computer.uptime()
      return
    end
    if started and not paused then
      hardDrop()
      return
    end
  end

  if not started or paused or gameOver then return end

  if code == keyboard.keys.a then
    tryMove(-1, 0)
  elseif code == keyboard.keys.d then
    tryMove(1, 0)
  elseif code == keyboard.keys.w or code == keyboard.keys.up then
    tryRotate()
  elseif code == keyboard.keys.s or code == keyboard.keys.down then
    softDrop()
  end
end

math.randomseed(math.floor(computer.uptime() * 100000) % 2147483647)

initBuffers()
resetGame()
inMenu = true
render()

local function cleanup()
  gpu.setBackground(0x000000)
  gpu.setForeground(0xFFFFFF)
  gpu.fill(1, 1, SW, SH, " ")
  gpu.set(1, 1, "Tetris stopped.")
end

local ok, err = pcall(function()
  while true do
    titleTick = titleTick + 0.05
    local timeout = 0.05
    local ev = {event.pull(timeout)}
    local name = ev[1]

    if name == "interrupted" then
      break
    elseif name == "key_down" then
      local _, _, char, code = table.unpack(ev)
      handleKey(code, char)
    end

    if started and not paused and not gameOver then
      local now = computer.uptime()
      if now - lastFall >= getDropInterval() then
        if not tryMove(0, 1) then
          lockAndSpawn()
        end
        lastFall = now
      end
    end

    render()
  end
end)

cleanup()
if not ok and err then
  print("Error: " .. tostring(err))
end