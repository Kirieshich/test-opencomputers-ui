-- stargate.lua
-- STARGATE Command Interface v1.1.0
-- Layout: 4 floors, logo + status panel pinned right

local component = require("component")
local term = require("term")
local event = require("event")
local keyboard = require("keyboard")
local computer = require("computer")
local filesystem = require("filesystem")
local gpu = component.gpu

local INSTALL_DIR = "/stargate"
local logoPath = INSTALL_DIR .. "/logo.ff"
if not filesystem.exists(logoPath) then
    io.stderr:write("Missing " .. logoPath .. "\n")
    os.exit(1)
end
dofile(logoPath)

local C = {
    black=0x000000, white=0xFFFFFF, red=0xFF3333, green=0x33DD33,
    yellow=0xFFEE22, cyan=0x22DDDD, gray=0x606060, lgray=0xB0B0B0,
    dblue=0x001844, dgray=0x2A2A2A, darkgreen=0x006600,
    panel=0x0A1A30, teal=0x00A0A0, slate=0x1A2838,
    gold=0xFFD700, orange=0xFF8C00, bronze=0x8B4513,
}

local W, H = gpu.getResolution()
if W < 80 or H < 25 then
    gpu.setResolution(80, 25)
    W, H = 80, 25
end

local hasRedstone = component.isAvailable("redstone")
local redstone = hasRedstone and component.redstone or nil

-- ============================================================
-- ЭТАЖИ (FLOORS)
-- ============================================================
-- Floor 1: Header           y = 1..3
-- Floor 2: Main             y = 4..19
-- Floor 3: Log              y = 20..23
-- Floor 4: Footer           y = 24..25

local F_HEADER_TOP   = 1
local F_MAIN_TOP     = 4
local F_MAIN_BOTTOM  = 19
local F_LOG_TOP      = 20
local F_LOG_BOTTOM   = 23
local F_FOOTER_TOP   = 24
local F_FOOTER_BOTTOM= H

-- Кнопки (левая колонка FLOOR 2)
local BTN_COL1 = 2
local BTN_COL2 = 22
local BTN_W    = 18
local BTN_ROWS = {5, 9, 13, 17}     -- top y каждой кнопки

-- Логотип (правая колонка FLOOR 2, верх)
local LOGO_X = 60   -- центр правой части
local LOGO_Y = 5

-- Панель статуса (правая колонка FLOOR 2, низ)
local ST_X = 44
local ST_Y = 17
local ST_W = W - ST_X - 1    -- до правой рамки
local ST_H = 4

-- Лог (FLOOR 3)
local LOG_X = 3
local LOG_Y = F_LOG_TOP + 1
local LOG_W = W - 6

-- ============================================================
-- КНОПКИ
-- ============================================================
local buttons = {
    {label="GATE",      key="1", side=0,  state=false, kind="toggle"},
    {label="LIGHTS",    key="2", side=1,  state=false, kind="toggle"},
    {label="SHIELD",    key="3", side=2,  state=false, kind="toggle"},
    {label="IRIS",      key="4", side=3,  state=false, kind="toggle"},
    {label="POWER",     key="5", side=4,  state=false, kind="toggle"},
    {label="DIAL",      key="6", side=-1, state=false, kind="dial"},
    {label="EMERGENCY", key="7", side=-1, state=false, kind="emergency"},
    {label="EXIT",      key="Q", side=-1, state=false, kind="exit"},
}

local S = {
    log = {},
    chevrons = 0,
    dialing = false,
    dialTimer = 0,
    activations = 0,
    bootTime = computer.uptime(),
}

local function addLog(msg, color)
    table.insert(S.log, 1, {msg=msg, color=color or C.lgray})
    while #S.log > 3 do table.remove(S.log) end
end
addLog("System initialized", C.green)

-- ============================================================
-- ЛОГОТИП
-- ============================================================
local function drawLogo(cx, cy)
    -- cx, cy — координаты верхнего левого угла
    for i, line in ipairs(LogoStar) do
        local y = cy + i - 1
        if y >= 1 and y <= H then
            for j = 1, #line do
                local x = cx + j - 1
                if x >= 1 and x <= W then
                    local ch = line:sub(j, j)
                    if ch ~= " " then
                        local color = LogoColors[ch] or C.white
                        gpu.setBackground(color)
                        gpu.setForeground(color)
                        gpu.set(x, y, " ")
                    end
                end
            end
        end
    end
    gpu.setBackground(C.black)
    gpu.setForeground(C.white)
end

-- ============================================================
-- FLOOR 1: HEADER
-- ============================================================
local function drawBorder()
    gpu.setBackground(C.dblue)
    gpu.setForeground(C.cyan)
    gpu.set(1, 1, string.rep("=", W))
    gpu.set(1, H, string.rep("=", W))
    for y = 2, H - 1 do
        gpu.set(1, y, "|")
        gpu.set(W, y, "|")
    end
end

local function drawHeader()
    gpu.setBackground(C.dblue)
    gpu.setForeground(C.gold)
    gpu.set(4, 2, "STARGATE COMMAND INTERFACE")
    gpu.setForeground(C.cyan)
    gpu.set(3, 3, string.rep("-", W - 4))
end

local function drawClock()
    gpu.setBackground(C.dblue)
    gpu.setForeground(C.cyan)
    local clock = os.date and os.date("%H:%M:%S") or "00:00:00"
    gpu.set(W - #clock - 3, 2, clock)
end

-- ============================================================
-- FLOOR 2: BUTTONS (слева)
-- ============================================================
local function drawButton(btn, x, y, w)
    local bg = btn.state and C.darkgreen or C.dgray
    gpu.setBackground(bg)
    gpu.setForeground(btn.state and C.white or C.lgray)
    gpu.fill(x, y, w, 3, " ")
    gpu.set(x + 2, y + 1, "[" .. btn.key .. "]")
    gpu.setForeground(btn.state and C.green or C.red)
    gpu.set(x + w - 4, y + 1, btn.state and "ON " or "OFF")
    gpu.setForeground(C.white)
    local label = btn.label
    local lbl_x = x + 6 + math.floor((w - 12 - #label) / 2)
    gpu.set(lbl_x, y + 1, label)
end

local function drawButtons()
    for i = 1, 4 do
        drawButton(buttons[i], BTN_COL1, BTN_ROWS[i], BTN_W)
        drawButton(buttons[i + 4], BTN_COL2, BTN_ROWS[i], BTN_W)
    end
end

-- ============================================================
-- FLOOR 2: STATUS PANEL (справа, под логотипом)
-- ============================================================
local function drawStatusPanel()
    -- фон панели
    gpu.setBackground(C.panel)
    gpu.setForeground(C.panel)
    gpu.fill(ST_X, ST_Y, ST_W, ST_H, " ")

    -- заголовок панели
    gpu.setForeground(C.teal)
    gpu.set(ST_X + 1, ST_Y, "╡ STARGATE STATUS ╞")
    gpu.fill(ST_X + 19, ST_Y, ST_W - 20, 1, " ")

    -- Строки статуса
    local labelX = ST_X + 2
    local valueX = ST_X + 14

    -- UPTIME
    gpu.setForeground(C.teal)
    gpu.set(labelX, ST_Y + 1, "UPTIME:")
    gpu.setForeground(C.white)
    local sec = math.floor(computer.uptime() - S.bootTime)
    local h = math.floor(sec / 3600)
    local m = math.floor((sec % 3600) / 60)
    local s = sec % 60
    gpu.set(valueX, ST_Y + 1, string.format("%02d:%02d:%02d", h, m, s))

    -- ACTIVE
    local active = 0
    for _, b in ipairs(buttons) do
        if b.state and b.kind == "toggle" then active = active + 1 end
    end
    gpu.setForeground(C.teal)
    gpu.set(labelX, ST_Y + 2, "ACTIVE:")
    gpu.setForeground(C.white)
    gpu.set(valueX, ST_Y + 2, tostring(active) .. " / 6    ")

    -- STATUS
    gpu.setForeground(C.teal)
    gpu.set(labelX, ST_Y + 3, "STATUS:")
    if S.dialing then
        gpu.setForeground(C.yellow)
        gpu.set(valueX, ST_Y + 3, "DIALING...   ")
    elseif buttons[1].state then
        gpu.setForeground(C.green)
        gpu.set(valueX, ST_Y + 3, "GATE OPEN    ")
    else
        gpu.setForeground(C.lgray)
        gpu.set(valueX, ST_Y + 3, "STANDBY      ")
    end
end

-- ============================================================
-- FLOOR 3: LOG
-- ============================================================
local function drawLog()
    local y = F_LOG_TOP

    -- Разделитель с надписью LOG
    gpu.setBackground(C.black)
    gpu.setForeground(C.teal)
    gpu.set(3, y, "──── LOG ")
    gpu.set(11, y, string.rep("─", W - 13))

    -- Строки лога
    for i = 1, 3 do
        gpu.setBackground(C.black)
        gpu.setForeground(C.black)
        gpu.fill(LOG_X, y + i, LOG_W, 1, " ")
        if S.log[i] then
            gpu.setForeground(C.gray)
            gpu.set(LOG_X, y + i, "> ")
            gpu.setForeground(S.log[i].color)
            gpu.set(LOG_X + 2, y + i, S.log[i].msg)
        end
    end
end

-- ============================================================
-- FLOOR 4: FOOTER
-- ============================================================
local function drawStatusBar()
    local y = F_FOOTER_BOTTOM
    gpu.setBackground(C.dblue)
    gpu.setForeground(C.lgray)
    gpu.fill(2, y, W - 2, 1, " ")
    gpu.setForeground(C.teal)
    gpu.set(3, y, "REDSTONE: ")
    gpu.setForeground(hasRedstone and C.green or C.red)
    gpu.set(13, y, hasRedstone and "ONLINE" or "OFFLINE")
    gpu.setForeground(C.teal)
    gpu.set(W - 25, y, "KEYS: 1-7 / Q=EXIT")
end

-- ============================================================
-- ПОЛНАЯ / ЧАСТИЧНАЯ ПЕРЕРИСОВКА
-- ============================================================
local function redrawAll()
    gpu.setBackground(C.black)
    gpu.setForeground(C.white)
    gpu.fill(1, 1, W, H, " ")
    drawBorder()
    drawHeader()
    drawClock()
    drawButtons()
    drawLogo(LOGO_X, LOGO_Y)
    drawStatusPanel()
    drawLog()
    drawStatusBar()
end

local function refreshDynamic()
    drawClock()
    drawStatusPanel()
end

-- ============================================================
-- ДЕЙСТВИЯ
-- ============================================================
local function setRedstoneOutput(idx)
    local btn = buttons[idx]
    if redstone and btn.side >= 0 then
        redstone.setOutput(btn.side, btn.state and 15 or 0)
    end
end

local function startDialing()
    if S.dialing then return end
    S.dialing = true
    S.dialTimer = 0
    S.chevrons = 0
    addLog("Dialing sequence started", C.yellow)
    drawLog()
    drawStatusPanel()
end

local function updateDialing(dt)
    if not S.dialing then return false end
    S.dialTimer = S.dialTimer + dt
    if S.dialTimer >= 0.35 then
        S.dialTimer = 0
        S.chevrons = S.chevrons + 1
        if S.chevrons >= 9 then
            S.dialing = false
            buttons[1].state = true
            setRedstoneOutput(1)
            S.activations = S.activations + 1
            addLog("Gate activated", C.green)
            drawButton(buttons[1], BTN_COL1, BTN_ROWS[1], BTN_W)
        else
            addLog("Chevron " .. S.chevrons .. " locked", C.gold)
        end
        drawLog()
        drawStatusPanel()
        return true
    end
    return false
end

local function emergencyShutdown()
    for i, btn in ipairs(buttons) do
        if btn.kind == "toggle" then
            btn.state = false
            setRedstoneOutput(i)
        end
    end
    S.dialing = false
    S.chevrons = 0
    addLog("EMERGENCY SHUTDOWN!", C.red)
    drawButtons()
    drawLog()
    drawStatusPanel()
end

local function handleButton(idx)
    local btn = buttons[idx]
    if btn.kind == "exit" then
        return "exit"
    elseif btn.kind == "dial" then
        startDialing()
        addLog("Dial command issued", C.cyan)
        drawLog()
    elseif btn.kind == "emergency" then
        emergencyShutdown()
    else
        btn.state = not btn.state
        setRedstoneOutput(idx)
        addLog(btn.label .. ": " .. (btn.state and "ON" or "OFF"),
               btn.state and C.green or C.gray)
        -- перерисовываем только нажатую кнопку
        for i = 1, 4 do
            if i == idx then
                drawButton(buttons[i], BTN_COL1, BTN_ROWS[i], BTN_W)
            end
            if i + 4 == idx then
                drawButton(buttons[i + 4], BTN_COL2, BTN_ROWS[i], BTN_W)
            end
        end
        drawLog()
        drawStatusPanel()
    end
    return nil
end

-- ============================================================
-- ЗАГРУЗОЧНЫЙ ЭКРАН
-- ============================================================
local function loadingScreen()
    gpu.setBackground(C.black)
    gpu.setForeground(C.white)
    gpu.fill(1, 1, W, H, " ")

    local logoW = #LogoStar[1]
    local logoH = #LogoStar
    local cx = math.floor((W - logoW) / 2) + 1
    local cy = math.floor((H - logoH) / 2) - 3
    drawLogo(cx, cy)

    local title = "S T A R G A T E"
    gpu.setBackground(C.black)
    gpu.setForeground(C.gold)
    gpu.set(math.floor((W - #title) / 2), cy + logoH + 1, title)
    local sub = "COMMAND SYSTEMS"
    gpu.setForeground(C.cyan)
    gpu.set(math.floor((W - #sub) / 2), cy + logoH + 2, sub)

    local msgs = {
        "Initializing kernel...",
        "Loading drivers...",
        "Checking redstone interface...",
        "Calibrating sensors...",
        "Establishing network link...",
        "Ready.",
    }
    local barW = 40
    local barX = math.floor((W - barW) / 2)
    local barY = H - 4
    for i, msg in ipairs(msgs) do
        gpu.setBackground(C.black)
        gpu.setForeground(C.lgray)
        gpu.fill(math.floor((W - 40) / 2), barY - 1, 40, 1, " ")
        gpu.set(math.floor((W - #msg) / 2), barY - 1, msg)
        local filled = math.floor(barW * i / #msgs)
        gpu.setBackground(C.green)
        gpu.fill(barX, barY, filled, 1, " ")
        gpu.setBackground(C.slate)
        gpu.fill(barX + filled, barY, barW - filled, 1, " ")
        os.sleep(0.3)
    end
    os.sleep(0.5)
end

-- ============================================================
-- ГЛАВНЫЙ ЦИКЛ
-- ============================================================
term.clear()
loadingScreen()
redrawAll()

local lastTick = 0

while true do
    local e = {event.pull(0.1)}

    if e[1] == "key_down" then
        local code = e[4]
        for i, btn in ipairs(buttons) do
            if keyboard.keys[btn.key:lower()] == code then
                local r = handleButton(i)
                if r == "exit" then goto done end
                break
            end
        end
    elseif e[1] == "touch" then
        local tx, ty = e[3], e[4]
        for i = 1, 4 do
            local y = BTN_ROWS[i]
            if ty >= y and ty < y + 3 then
                if tx >= BTN_COL1 and tx < BTN_COL1 + BTN_W then
                    local r = handleButton(i)
                    if r == "exit" then goto done end
                elseif tx >= BTN_COL2 and tx < BTN_COL2 + BTN_W then
                    local r = handleButton(i + 4)
                    if r == "exit" then goto done end
                end
            end
        end
    end

    updateDialing(0.1)

    local now = computer.uptime()
    if now - lastTick >= 1 then
        lastTick = now
        refreshDynamic()
    end
end

::done::
term.clear()
term.setCursor(1, 1)