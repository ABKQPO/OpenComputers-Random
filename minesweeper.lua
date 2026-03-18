local component = require("component")
local event = require("event")
local keyboard = require("keyboard")
local computer = require("computer")
local unicode = require("unicode")

local gpu = component.gpu
local SW, SH = gpu.getResolution()

----------------------------------------------------------------
-- 基础常量
----------------------------------------------------------------
local COLOR_BG          = 0x101114
local COLOR_PANEL       = 0x171A20
local COLOR_PANEL2      = 0x1E232B
local COLOR_TEXT        = 0xE6E6E6
local COLOR_DIM         = 0x7A7F8A
local COLOR_RED         = 0xFF5555
local COLOR_GREEN       = 0x66FF99
local COLOR_YELLOW      = 0xFFFF66
local COLOR_CYAN        = 0x66CCFF
local COLOR_ORANGE      = 0xFFAA44
local COLOR_WHITE       = 0xFFFFFF
local COLOR_BLACK       = 0x000000
local COLOR_CURSOR_BG   = 0x2B3240
local COLOR_HILITE      = 0x334455
local COLOR_COVERED_BG  = 0x2A2F39
local COLOR_OPEN_BG      = 0x191D24
local COLOR_GRID_LINE   = 0x0E1015
local COLOR_MINE         = 0xFF4444
local COLOR_FLAG        = 0xFF6666
local COLOR_QMARK       = 0x66CCFF
local COLOR_MENU_A      = 0x66CCFF
local COLOR_MENU_B      = 0xB388FF
local COLOR_MENU_C      = 0x66FFCC

local NUM_COLORS = {
  [1] = 0x66CCFF, [2] = 0x66FF66, [3] = 0xFF6666, [4] = 0x6666FF,
  [5] = 0xAA5500, [6] = 0x33CCCC, [7] = 0xDDDDDD, [8] = 0x999999
}

local CELL_W = 2
local MIN_W, MIN_H = 9, 9
local MAX_W, MAX_H = 128, 64
local MAX_MINES = 5120

----------------------------------------------------------------
-- 多语言支持
----------------------------------------------------------------
local lang = "en"
local TEXTS = {
  en = {
    ver = "OpenComputers 1.7.10 Edition",
    mode = "Mode:",
    m_classic = "Classic",
    m_noguess = "No-Guess",
    p1 = "1. Beginner  9x9  10 Mines",
    p2 = "2. Intermed 16x16 40 Mines",
    p3 = "3. Expert   30x16 99 Mines",
    p4 = "4. Custom",
    menu_hint = "Enter/Space: Start  Tab: Mode  C: Custom  L: Lang  R: Quick Restart",
    custom_title = "Custom Parameters",
    label_w = "Width (9-128)",
    label_h = "Height (9-64)",
    label_m = "Mines (1+)",
    custom_hint = "Click/Tab: Switch  Digits: Input  Enter: Start",
    mine_limit = "Limit: Must be less than (W*H - 9)",
    game_title = "Minesweeper",
    win = "YOU WIN",
    boom = "BOOM",
    hud_hint = "WSAD: Move  E: Open  Q: Mark  F: Chord  Double R: Restart  BS: Menu",
  },
  cn = {
    ver = "OpenComputers 1.7.10 版本",
    mode = "模式：",
    m_classic = "经典模式",
    m_noguess = "无猜模式",
    p1 = "1. 初级   9x9   10雷",
    p2 = "2. 中级  16x16  40雷",
    p3 = "3. 高级  30x16  99雷",
    p4 = "4. 自定义",
    menu_hint = "回车/空格开始  Tab切换模式  C自定义  L切换语言  R快速重开",
    custom_title = "自定义参数",
    label_w = "宽度 (9-128)",
    label_h = "高度 (9-64)",
    label_m = "地雷数 (1+)",
    custom_hint = "鼠标点击或Tab切换   数字键直接输入   Enter开始",
    mine_limit = "雷数限制：必须小于 (宽*高 - 9)",
    game_title = "扫雷",
    win = "胜利",
    boom = "起爆",
    hud_hint = "WSAD移动  E开格  Q标记  F和弦  双击R重开  Backspace返回菜单",
  }
}

local function t(key) return TEXTS[lang][key] or key end

----------------------------------------------------------------
-- 双缓冲
----------------------------------------------------------------
local front = {}
local back = {}

local function initBuffers()
  front = {}
  back = {}
  for y = 1, SH do
    front[y] = {}
    back[y] = {}
    for x = 1, SW do
      front[y][x] = {ch = "", fg = -1, bg = -1} 
      back[y][x] = {ch = " ", fg = COLOR_TEXT, bg = COLOR_BG}
    end
  end
  gpu.setBackground(COLOR_BG)
  gpu.fill(1, 1, SW, SH, " ")
end

local function clearBack(bg, fg)
  bg = bg or COLOR_BG
  fg = fg or COLOR_TEXT
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
  fg = fg or COLOR_TEXT
  bg = bg or COLOR_BG
  local len = unicode.len(text)
  for i = 1, len do
    local xx = x + i - 1
    if xx >= 1 and xx <= SW then
      local ch = unicode.sub(text, i, i)
      local c = back[y][xx]
      c.ch = ch
      c.fg = fg
      c.bg = bg
    end
  end
end

local function fillRect(x, y, w, h, ch, fg, bg)
  ch = ch or " "
  fg = fg or COLOR_TEXT
  bg = bg or COLOR_BG
  for yy = y, y + h - 1 do
    if yy >= 1 and yy <= SH then
      for xx = x, x + w - 1 do
        if xx >= 1 and xx <= SW then
          local c = back[yy][xx]
          c.ch = ch
          c.fg = fg
          c.bg = bg
        end
      end
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

----------------------------------------------------------------
-- 工具函数
----------------------------------------------------------------
local function clamp(v, a, b)
  if v < a then return a end
  if v > b then return b end
  return v
end

local function shuffle(t)
  for i = #t, 2, -1 do
    local j = math.random(i)
    t[i], t[j] = t[j], t[i]
  end
end

----------------------------------------------------------------
-- 游戏数据
----------------------------------------------------------------
local state = "menu"
local difficultyIndex = 1
local modeIndex = 1

local presets = {
  {name = "初级", w = 9,  h = 9,  mines = 10},
  {name = "中级", w = 16, h = 16, mines = 40},
  {name = "高级", w = 30, h = 16, mines = 99},
  {name = "自定义", w = 20, h = 12, mines = 40}
}

local custom = {
  w = 20, h = 12, mines = 40, focus = 1,
  inputBuffers = {"20", "12", "40"}
}

local game = {
  w = 9, h = 9, mines = 10, modeNoGuess = false,
  boardX = 1, boardY = 1,
  minesMap = {}, nums = {}, open = {}, mark = {}, 
  cursorX = 1, cursorY = 1,
  generated = false, gameOver = false, win = false,
  startTime = 0, elapsed = 0,
  pressLeft = false, lastR = 0
}

local function switchState(newState)
  state = newState
  for y = 1, SH do
    for x = 1, SW do
      front[y][x].ch = ""
      front[y][x].fg = -1
      front[y][x].bg = -1
    end
  end
  gpu.setBackground(COLOR_BG)
  gpu.fill(1, 1, SW, SH, " ")
  if newState == "custom" then
      custom.inputBuffers[1] = tostring(custom.w)
      custom.inputBuffers[2] = tostring(custom.h)
      custom.inputBuffers[3] = tostring(custom.mines)
  end
end

----------------------------------------------------------------
-- 棋盘逻辑
----------------------------------------------------------------
local function allocBoard(w, h, init)
  local t = {}
  for y = 1, h do t[y] = {} for x = 1, w do t[y][x] = init end end
  return t
end

local function resetGameData(w, h, mines, noGuess)
  game.w, game.h, game.mines, game.modeNoGuess = w, h, math.max(1, mines), noGuess
  game.minesMap = allocBoard(w, h, false)
  game.nums = allocBoard(w, h, 0)
  game.open = allocBoard(w, h, false)
  game.mark = allocBoard(w, h, 0)
  game.cursorX, game.cursorY = math.floor((w + 1) / 2), math.floor((h + 1) / 2)
  game.generated, game.gameOver, game.win = false, false, false
  game.startTime, game.elapsed, game.pressLeft = computer.uptime(), 0, false
end

local function inBoard(x, y) return x >= 1 and x <= game.w and y >= 1 and y <= game.h end

local dirs = {}
for dy = -1, 1 do
  for dx = -1, 1 do
    if not (dx == 0 and dy == 0) then dirs[#dirs + 1] = {dx, dy} end
  end
end

local function countAdjMinesMap(minesMap, w, h, x, y)
  local c = 0
  for i = 1, #dirs do
    local nx, ny = x + dirs[i][1], y + dirs[i][2]
    if nx >= 1 and nx <= w and ny >= 1 and ny <= h and minesMap[ny][nx] then c = c + 1 end
  end
  return c
end

local function rebuildNumsFrom(minesMap, nums, w, h)
  for y = 1, h do
    for x = 1, w do
      if minesMap[y][x] then nums[y][x] = -1
      else nums[y][x] = countAdjMinesMap(minesMap, w, h, x, y) end
    end
  end
end

local function countFlagsAround(x, y)
  local c = 0
  for i = 1, #dirs do
    local nx, ny = x + dirs[i][1], y + dirs[i][2]
    if inBoard(nx, ny) and game.mark[ny][nx] == 1 then c = c + 1 end
  end
  return c
end

local function floodOpen(x, y)
  local q = {{x, y}}
  local head = 1
  while head <= #q do
    local cx, cy = q[head][1], q[head][2]
    head = head + 1
    if inBoard(cx, cy) and not game.open[cy][cx] and game.mark[cy][cx] ~= 1 then
      game.open[cy][cx] = true
      if game.nums[cy][cx] == 0 then
        for i = 1, #dirs do
          local nx, ny = cx + dirs[i][1], cy + dirs[i][2]
          if inBoard(nx, ny) and not game.open[ny][nx] and game.mark[ny][nx] ~= 1 then
            q[#q + 1] = {nx, ny}
          end
        end
      end
    end
  end
end

local function countOpened()
  local n = 0
  for y = 1, game.h do
    for x = 1, game.w do if game.open[y][x] then n = n + 1 end end
  end
  return n
end

local function checkWin()
  local need = game.w * game.h - game.mines
  if countOpened() >= need and not game.gameOver then
    game.win = true
    game.gameOver = true
    for y = 1, game.h do
      for x = 1, game.w do if game.minesMap[y][x] then game.mark[y][x] = 1 end end
    end
  end
end

----------------------------------------------------------------
-- 无猜求解器
----------------------------------------------------------------
local function solverCanProgress(openMap, markMap, nums, w, h)
  local changed = false
  for y = 1, h do
    for x = 1, w do
      if openMap[y][x] and nums[y][x] > 0 then
        local flags, unknown = 0, {}
        for i = 1, #dirs do
          local nx, ny = x + dirs[i][1], y + dirs[i][2]
          if nx >= 1 and nx <= w and ny >= 1 and ny <= h then
            if markMap[ny][nx] == 1 then flags = flags + 1
            elseif not openMap[ny][nx] then unknown[#unknown + 1] = {nx, ny} end
          end
        end
        local need = nums[y][x] - flags
        if #unknown > 0 then
          if need == 0 then
            for i = 1, #unknown do local u = unknown[i] openMap[u[2]][u[1]] = true changed = true end
          elseif need == #unknown then
            for i = 1, #unknown do local u = unknown[i] if markMap[u[2]][u[1]] ~= 1 then markMap[u[2]][u[1]] = 1 changed = true end end
          end
        end
      end
    end
  end
  return changed
end

local function solverExpandZeros(openMap, nums, w, h)
  local changed, q, head = false, {}, 1
  for y = 1, h do for x = 1, w do if openMap[y][x] and nums[y][x] == 0 then q[#q + 1] = {x, y} end end end
  while head <= #q do
    local x, y = q[head][1], q[head][2]
    head = head + 1
    for i = 1, #dirs do
      local nx, ny = x + dirs[i][1], y + dirs[i][2]
      if nx >= 1 and nx <= w and ny >= 1 and ny <= h and not openMap[ny][nx] then
        openMap[ny][nx] = true
        changed = true
        if nums[ny][nx] == 0 then q[#q + 1] = {nx, ny} end
      end
    end
  end
  return changed
end

local function boardSolvedByLogic(minesMap, nums, w, h, sx, sy)
  local openMap, markMap = allocBoard(w, h, false), allocBoard(w, h, 0)
  openMap[sy][sx] = true
  if nums[sy][sx] == 0 then solverExpandZeros(openMap, nums, w, h) end
  local changed = true
  while changed do
    changed = false
    if solverExpandZeros(openMap, nums, w, h) then changed = true end
    if solverCanProgress(openMap, markMap, nums, w, h) then changed = true end
    if solverExpandZeros(openMap, nums, w, h) then changed = true end
  end
  local opened = 0
  for y = 1, h do for x = 1, w do if openMap[y][x] then opened = opened + 1 end end end
  return opened == (w * h - game.mines)
end

local function placeMinesAvoidSafe(w, h, mines, sx, sy, noGuess)
  local safe = {}
  for yy = sy - 1, sy + 1 do
    for xx = sx - 1, sx + 1 do if xx >= 1 and xx <= w and yy >= 1 and yy <= h then safe[yy * 1000 + xx] = true end end
  end
  local function tryOnce()
    local minesMap, cells = allocBoard(w, h, false), {}
    for y = 1, h do for x = 1, w do if not safe[y * 1000 + x] then cells[#cells + 1] = {x, y} end end end
    if mines > #cells then return nil end
    shuffle(cells)
    for i = 1, mines do local c = cells[i] minesMap[c[2]][c[1]] = true end
    local nums = allocBoard(w, h, 0)
    rebuildNumsFrom(minesMap, nums, w, h)
    if noGuess and not boardSolvedByLogic(minesMap, nums, w, h, sx, sy) then return nil end
    return minesMap, nums
  end
  local maxRetry = noGuess and 300 or 50
  for _ = 1, maxRetry do
    local m, n = tryOnce()
    if m then return m, n end
  end
  return nil
end

local function ensureGeneratedAt(x, y)
  if game.generated then return true end
  local m, n = placeMinesAvoidSafe(game.w, game.h, game.mines, x, y, game.modeNoGuess)
  if not m then return false end
  game.minesMap, game.nums, game.generated = m, n, true
  game.startTime = computer.uptime()
  return true
end

----------------------------------------------------------------
-- 游戏操作
----------------------------------------------------------------
local function openCell(x, y)
  if not inBoard(x, y) or game.gameOver or game.mark[y][x] == 1 then return end
  if not game.generated then if not ensureGeneratedAt(x, y) then return end end
  if game.open[y][x] then return end
  if game.minesMap[y][x] then
    game.open[y][x] = true
    game.gameOver = true
    for yy = 1, game.h do
      for xx = 1, game.w do if game.minesMap[yy][xx] then game.open[yy][xx] = true end end
    end
    return
  end
  floodOpen(x, y)
  checkWin()
end

local function toggleMark(x, y)
  if not inBoard(x, y) or game.gameOver or game.open[y][x] then return end
  game.mark[y][x] = (game.mark[y][x] + 1) % 3
end

local function chordOpen(x, y)
  if not inBoard(x, y) or game.gameOver or not game.open[y][x] then return end
  local n = game.nums[y][x]
  if n <= 0 or countFlagsAround(x, y) ~= n then return end
  for i = 1, #dirs do
    local nx, ny = x + dirs[i][1], y + dirs[i][2]
    if inBoard(nx, ny) and not game.open[ny][nx] and game.mark[ny][nx] ~= 1 then
      openCell(nx, ny)
      if game.gameOver then return end
    end
  end
  checkWin()
end

local function remainingMines()
  local flags = 0
  for y = 1, game.h do
    for x = 1, game.w do if game.mark[y][x] == 1 then flags = flags + 1 end end
  end
  return game.mines - flags
end

local function restartCurrent()
  resetGameData(game.w, game.h, game.mines, game.modeNoGuess)
  switchState("game")
end

local function beginFromPreset(idx)
  local noGuess = (modeIndex == 2)
  if idx == 4 then resetGameData(custom.w, custom.h, custom.mines, noGuess)
  else local p = presets[idx] resetGameData(p.w, p.h, p.mines, noGuess) end
  switchState("game")
end

----------------------------------------------------------------
-- 坐标/渲染
----------------------------------------------------------------
local function calcBoardPos()
  local bw, bh = game.w * CELL_W + 2, game.h + 2
  game.boardX = math.max(2, math.floor((SW - bw) / 2) + 1)
  game.boardY = math.max(4, math.floor((SH - bh) / 2) + 1)
end

local function screenToCell(px, py)
  local x0, y0 = game.boardX + 1, game.boardY + 1
  if py < y0 or py >= y0 + game.h or px < x0 or px >= x0 + game.w * CELL_W then return nil end
  local cx, cy = math.floor((px - x0) / CELL_W) + 1, (py - y0) + 1
  return inBoard(cx, cy) and cx or nil, cy
end

local function drawBox(x, y, w, h, bg)
  fillRect(x, y, w, h, " ", COLOR_TEXT, bg)
  put(x, y, "┌" .. string.rep("─", w - 2) .. "┐", COLOR_DIM, bg)
  for yy = y + 1, y + h - 2 do
    put(x, yy, "│", COLOR_DIM, bg)
    put(x + w - 1, yy, "│", COLOR_DIM, bg)
  end
  put(x, y + h - 1, "└" .. string.rep("─", w - 2) .. "┘", COLOR_DIM, bg)
end

local function drawCentered(y, text, fg, bg)
  local x = math.floor((SW - unicode.len(text)) / 2) + 1
  put(x, y, text, fg, bg)
end

local function drawMenu()
  clearBack(COLOR_BG, COLOR_TEXT)
  local pulse = (math.floor(computer.uptime() * 4) % 3)
  local c = (pulse == 0 and COLOR_MENU_A) or (pulse == 1 and COLOR_MENU_B) or COLOR_MENU_C
  drawCentered(2,  "███╗   ███╗██╗███╗   ██╗███████╗███████╗██╗    ██╗███████╗███████╗██████╗ ", c)
  drawCentered(3,  "████╗ ████║██║████╗  ██║██╔════╝██╔════╝██║    ██║██╔════╝██╔════╝██╔══██╗", c)
  drawCentered(4,  "██╔████╔██║██║██╔██╗ ██║█████╗  ███████╗██║ █╗ ██║█████╗  █████╗  ██████╔╝", c)
  drawCentered(5,  "██║╚██╔╝██║██║██║╚██╗██║██╔══╝  ╚════██║██║███╗██║██╔══╝  ██╔══╝  ██╔══██╗", c)
  drawCentered(6,  "██║ ╚═╝ ██║██║██║ ╚████║███████╗███████║╚███╔███╔╝███████╗███████╗██║  ██║", c)
  drawCentered(7,  " ╚═╝     ╚═╝╚═╝╚═╝  ╚═══╝╚══════╝╚══════╝ ╚══╝╚══╝ ╚══════╝╚══════╝╚═╝  ╚═╝", c)
  drawCentered(9, t("ver"), COLOR_DIM)
  
  local boxW, boxH, boxX, boxY = 48, 12, math.floor((SW - 48) / 2) + 1, 13
  drawBox(boxX, boxY, boxW, boxH, COLOR_PANEL)
  put(boxX + 3, boxY + 2, t("mode"), COLOR_TEXT, COLOR_PANEL)
  local modes = {t("m_classic"), t("m_noguess")}
  for i = 1, 2 do
    local fg = (modeIndex == i) and COLOR_YELLOW or COLOR_DIM
    put(boxX + 12 + (i - 1) * 16, boxY + 2, modes[i], fg, COLOR_PANEL)
  end
  local items = {t("p1"), t("p2"), t("p3"), t("p4")}
  for i = 1, #items do
    local fg = (difficultyIndex == i) and COLOR_CYAN or COLOR_TEXT
    put(boxX + 4, boxY + 4 + i, items[i], fg, COLOR_PANEL)
  end
  drawCentered(boxY + boxH + 2, t("menu_hint"), COLOR_DIM)
end

local function drawCustom()
  clearBack(COLOR_BG, COLOR_TEXT)
  drawCentered(3, t("custom_title"), COLOR_CYAN)
  local w, h, x, y = 44, 11, math.floor((SW - 44) / 2) + 1, 7
  drawBox(x, y, w, h, COLOR_PANEL)
  local labels = {t("label_w"), t("label_h"), t("label_m")}
  for i = 1, 3 do
    local isFocus = (custom.focus == i)
    local fg = isFocus and COLOR_YELLOW or COLOR_TEXT
    local bg = isFocus and COLOR_CURSOR_BG or COLOR_PANEL
    put(x + 4, y + 1 + i * 2, labels[i] .. "：", fg, COLOR_PANEL)
    local valStr = custom.inputBuffers[i] .. (isFocus and "_" or " ")
    put(x + 22, y + 1 + i * 2, valStr, isFocus and COLOR_WHITE or COLOR_DIM, bg)
  end
  put(x + 4, y + 9, t("custom_hint"), COLOR_DIM, COLOR_PANEL)
  drawCentered(y + h + 2, t("mine_limit"), COLOR_DIM)
end

local function drawHUD()
  if not game.gameOver and game.generated then game.elapsed = math.floor(computer.uptime() - game.startTime) end
  local left, right = string.format("TIME %04d", clamp(game.elapsed, 0, 9999)), string.format("MINES %04d", remainingMines())
  put(2, 2, left, COLOR_RED, COLOR_BG)
  put(SW - unicode.len(right), 2, right, COLOR_RED, COLOR_BG)
  drawCentered(2, string.format("%dx%d  %d %s", game.w, game.h, game.mines, game.modeNoGuess and t("m_noguess") or t("m_classic")), COLOR_DIM)
  put(2, SH - 1, t("hud_hint"), COLOR_DIM, COLOR_BG)
end

local function getCellDisplay(x, y)
  local isCursor = (x == game.cursorX and y == game.cursorY and not game.gameOver)
  local bg, fg, text = COLOR_COVERED_BG, COLOR_TEXT, "· "
  if game.open[y][x] then
    bg = COLOR_OPEN_BG
    if game.minesMap[y][x] then text, fg = "※ ", COLOR_MINE
    else
      local n = game.nums[y][x]
      if n == 0 then text = "  "
      else text, fg = tostring(n) .. " ", NUM_COLORS[n] or COLOR_WHITE end
    end
  else
    if game.mark[y][x] == 1 then text, fg = "⚑ ", COLOR_FLAG
    elseif game.mark[y][x] == 2 then text, fg = "? ", COLOR_QMARK
    else text, fg = "□ ", COLOR_TEXT end
  end
  if isCursor then bg, fg = COLOR_YELLOW, COLOR_BLACK end
  return text, fg, bg
end

local function drawBoard()
  calcBoardPos()
  drawBox(game.boardX, game.boardY, game.w * CELL_W + 2, game.h + 2, COLOR_PANEL2)
  for y = 1, game.h do
    for x = 1, game.w do
      local sx, sy = game.boardX + 1 + (x - 1) * CELL_W, game.boardY + y
      local text, fg, bg = getCellDisplay(x, y)
      put(sx, sy, text, fg, bg)
    end
  end
end

local function render()
  if state == "menu" then drawMenu()
  elseif state == "custom" then drawCustom()
  elseif state == "game" then
    clearBack(COLOR_BG, COLOR_TEXT)
    drawHUD()
    drawBoard()
    if game.win then drawCentered(game.boardY - 1, t("win"), COLOR_GREEN)
    elseif game.gameOver then drawCentered(game.boardY - 1, t("boom"), COLOR_RED)
    else drawCentered(game.boardY - 1, t("game_title"), COLOR_CYAN) end
  end
  flush()
end

----------------------------------------------------------------
-- 输入处理
----------------------------------------------------------------
local function validateCustom()
    custom.w = clamp(tonumber(custom.inputBuffers[1]) or 9, MIN_W, MAX_W)
    custom.h = clamp(tonumber(custom.inputBuffers[2]) or 9, MIN_H, MAX_H)
    local maxM = math.max(1, custom.w * custom.h - 9)
    custom.mines = clamp(tonumber(custom.inputBuffers[3]) or 10, 1, math.min(MAX_MINES, maxM))
    custom.inputBuffers[1], custom.inputBuffers[2], custom.inputBuffers[3] = tostring(custom.w), tostring(custom.h), tostring(custom.mines)
end

local function handleCustomKey(code, char)
  if code == keyboard.keys.back then
      if #custom.inputBuffers[custom.focus] > 0 then
          custom.inputBuffers[custom.focus] = custom.inputBuffers[custom.focus]:sub(1, -2)
      else switchState("menu") end
  elseif code == keyboard.keys.tab then custom.focus = custom.focus % 3 + 1
  elseif code == keyboard.keys.enter then validateCustom() beginFromPreset(4)
  elseif char >= 48 and char <= 57 then
      local s = custom.inputBuffers[custom.focus]
      if #s < 5 then custom.inputBuffers[custom.focus] = s .. string.char(char) end
  elseif code == keyboard.keys.up or code == keyboard.keys.down or code == keyboard.keys.left or code == keyboard.keys.right then
      validateCustom()
      local delta = (code == keyboard.keys.up or code == keyboard.keys.right) and 1 or -1
      if custom.focus == 1 then custom.w = clamp(custom.w + delta, MIN_W, MAX_W)
      elseif custom.focus == 2 then custom.h = clamp(custom.h + delta, MIN_H, MAX_H)
      else custom.mines = clamp(custom.mines + delta, 1, MAX_MINES) end
      custom.inputBuffers[custom.focus] = tostring(custom.focus == 1 and custom.w or (custom.focus == 2 and custom.h or custom.mines))
  end
end

local function handleKey(code, char)
  if state == "menu" then
    if code == keyboard.keys.tab then modeIndex = 3 - modeIndex
    elseif code == keyboard.keys.l then lang = (lang == "en" and "cn" or "en")
    elseif char == string.byte("1") or char == string.byte("2") or char == string.byte("3") or char == string.byte("4") then
      difficultyIndex = char - 48
    elseif code == keyboard.keys.c then difficultyIndex = 4 switchState("custom")
    elseif code == keyboard.keys.enter or code == keyboard.keys.space then
      if difficultyIndex == 4 then switchState("custom") else beginFromPreset(difficultyIndex) end
    end
  elseif state == "custom" then handleCustomKey(code, char)
  elseif state == "game" then
    if code == keyboard.keys.back then switchState("menu")
    elseif code == keyboard.keys.r then 
      local now = computer.uptime()
      if now - game.lastR <= 0.35 then restartCurrent() end
      game.lastR = now
    elseif not game.gameOver then
      if code == keyboard.keys.w or code == keyboard.keys.up then game.cursorY = clamp(game.cursorY - 1, 1, game.h)
      elseif code == keyboard.keys.s or code == keyboard.keys.down then game.cursorY = clamp(game.cursorY + 1, 1, game.h)
      elseif code == keyboard.keys.a or code == keyboard.keys.left then game.cursorX = clamp(game.cursorX - 1, 1, game.w)
      elseif code == keyboard.keys.d or code == keyboard.keys.right then game.cursorX = clamp(game.cursorX + 1, 1, game.w)
      elseif code == keyboard.keys.e or code == keyboard.keys.space then openCell(game.cursorX, game.cursorY)
      elseif code == keyboard.keys.q then toggleMark(game.cursorX, game.cursorY)
      elseif code == keyboard.keys.f then chordOpen(game.cursorX, game.cursorY) end
    elseif code == keyboard.keys.enter or code == keyboard.keys.space then restartCurrent() end
  end
end

local function handleTouch(screen, x, y, button, player)
  if state == "menu" then
    local bx, by = math.floor((SW - 48) / 2) + 1, 13
    if y == by + 2 then
      if x >= bx + 12 and x <= bx + 24 then modeIndex = 1 elseif x >= bx + 28 and x <= bx + 40 then modeIndex = 2 end
    end
    for i = 1, 4 do
      if y == by + 4 + i then
        difficultyIndex = i
        if button == 0 then if i == 4 then switchState("custom") else beginFromPreset(i) end end
      end
    end
  elseif state == "custom" then
    local cx, cy = math.floor((SW - 44) / 2) + 1, 7
    for i = 1, 3 do if y == cy + 1 + i * 2 and x >= cx + 4 and x <= cx + 40 then custom.focus = i end end
  elseif state == "game" then
    local cx, cy = screenToCell(x, y)
    if cx then
      game.cursorX, game.cursorY = cx, cy
      if button == 0 then game.pressLeft = true openCell(cx, cy)
      elseif button == 1 then if game.pressLeft then chordOpen(cx, cy) else toggleMark(cx, cy) end
      elseif button == 2 then chordOpen(cx, cy) end
    end
  end
end

----------------------------------------------------------------
-- 启动
----------------------------------------------------------------
math.randomseed(math.floor(computer.uptime() * 100000) % 2147483647)
initBuffers()

local ok, err = pcall(function()
  while true do
    render()
    local ev = {event.pull(0.05)}
    if ev[1] == "interrupted" then break
    elseif ev[1] == "key_down" then handleKey(ev[4], ev[3])
    elseif ev[1] == "touch" then handleTouch(ev[2], ev[3], ev[4], ev[5], ev[6])
    elseif ev[1] == "drop" then game.pressLeft = false
    elseif ev[1] == "drag" then
        local cx, cy = screenToCell(ev[3], ev[4])
        if cx then game.cursorX, game.cursorY = cx, cy end
    end
  end
end)

gpu.setBackground(0x000000)
gpu.setForeground(0xFFFFFF)
gpu.fill(1, 1, SW, SH, " ")
if not ok then print("Error: " .. tostring(err)) end