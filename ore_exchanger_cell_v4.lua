-- v4.0 CELL - GUI ORE EXCHANGER: обмен всей руды непосредственно внутри ME-ячейки
-- Интерфейс автоматически использует максимальное разрешение видеокарты.
-- BUILD: ORE_EXCHANGER_GUI_6LINE_15ORES_3M

local unicode = require("unicode")
local computer = require("computer")
local com = require("component")
local event = require("event")
local fs = require("filesystem")
local shell = require("shell")
-- ============================================================
-- ТОЧНЫЕ АДРЕСА ПРОВЕРЕННОЙ СХЕМЫ
-- ============================================================
local CELL_ME_ADDRESS = "b2f2b6b2-1543-4659-b4e5-e8236fc27871"
local MAIN_ME_ADDRESS = "7867903d-0c1c-43cf-85fb-6437973e1e99"
local TRANSPOSER_ADDRESS = "1e889179-3120-45ae-b698-5c760ef1f744"

local function requireAddress(address, expectedType, label)
    local okType, actualType = pcall(com.type, address)
    if not okType or actualType ~= expectedType then
        error(
            tostring(label)
            .. " не найден. Адрес: "
            .. tostring(address)
            .. ", тип: "
            .. tostring(actualType)
        )
    end

    local proxy = com.proxy(address)
    if not proxy then
        error("Не удалось подключиться к " .. tostring(label))
    end

    return proxy
end

local cellMe = requireAddress(CELL_ME_ADDRESS, "me_interface", "ME Interface ячейки")
local mainMe = requireAddress(MAIN_ME_ADDRESS, "me_interface", "Основной ME Interface")
local bridge = requireAddress(TRANSPOSER_ADDRESS, "transposer", "Transposer")
local pim = com.isAvailable("pim") and com.pim or error("PIM не подключен")
local gpu = com.gpu

-- ============================================================
-- МАКСИМАЛЬНОЕ РАЗРЕШЕНИЕ ЭКРАНА
-- ============================================================
local WIDTH, HEIGHT = gpu.getResolution()
local maxW, maxH = gpu.maxResolution()
if WIDTH < maxW or HEIGHT < maxH then
    gpu.setResolution(maxW, maxH)
    WIDTH, HEIGHT = gpu.getResolution()
end

local w, h = WIDTH, HEIGHT
local defBG, defFG = gpu.getBackground(), gpu.getForeground()

-- ============================================================
-- НАСТРОЙКИ ОБМЕННИКА
-- ============================================================
-- Направления уже проверены реальными тестами на этой установке.
local CELL_CHEST_DIRECTION = "NORTH"
local MAIN_CHEST_DIRECTION = "SOUTH"

-- Стороны сундуков относительно Transposer.
local FIRST_CHEST_SIDE = 3  -- FRONT: сундук возле ME Interface ячейки
local SECOND_CHEST_SIDE = 2 -- BACK: сундук возле основного ME Interface

-- За один проход передаём небольшие партии. Так сундуки не переполняются.
local MAX_BATCH_ITEMS = 768

local STATS_FILE = "exchanger_stats.txt"
local TOTAL_FILE = "total_ore.txt"

-- ============================================================
-- ЦВЕТА GUI
-- ============================================================
local C = {
    bg          = 0x0C0C0C,
    logo        = 0x00E5C9,
    border      = 0x55FFFF,
    title       = 0x55FFFF,
    white       = 0xFFFFFF,
    gray        = 0x8A9499,
    darkGray    = 0x30383D,
    green       = 0x55FF55,
    yellow      = 0xFFFF55,
    red         = 0xFF5555,
    cyan        = 0x55FFFF,
    barEmpty    = 0x30383D,
    ratio       = 0xFFD75F,
    stock       = 0xFFFFFF
}
-- ============================================================
-- СПИСОК РУД
-- ============================================================
local ore_list = {
    { take = { label = "Алмазная руда", name = "minecraft:diamond_ore", amount = 1 }, give = { label = "Алмаз", name = "minecraft:diamond", amount = 2 } },
    { take = { label = "Железная руда", name = "minecraft:iron_ore", amount = 3 }, give = { label = "Железный слиток", name = "minecraft:iron_ingot", amount = 7 } },
    { take = { label = "Золотая руда", name = "minecraft:gold_ore", amount = 3 }, give = { label = "Золотой слиток", name = "minecraft:gold_ingot", amount = 7 } },
    { take = { label = "Лазуритовая руда", name = "minecraft:lapis_ore", amount = 1 }, give = { label = "Лазурит", name = "minecraft:dye", damage = 4.0, amount = 7 } },
    { take = { label = "Красная руда", name = "minecraft:redstone_ore", amount = 1 }, give = { label = "Блок красного камня", name = "minecraft:redstone_block", amount = 1 } },
    { take = { label = "Угольная руда", name = "minecraft:coal_ore", amount = 1 }, give = { label = "Уголь", name = "minecraft:coal", amount = 3 } },
    { take = { label = "Руда истинного кварца", name = "appliedenergistics2:tile.OreQuartz", amount = 1 }, give = { label = "Кристалл ист. кварца", name = "appliedenergistics2:item.ItemMultiMaterial", amount = 3 } },
    { take = { label = "Заряж. руда ист. квар", name = "appliedenergistics2:tile.OreQuartzCharged", amount = 1 }, give = { label = "Заряж. крист. кварца", name = "appliedenergistics2:item.ItemMultiMaterial", damage = 1.0, amount = 3 } },
    { take = { label = "Кварцевая руда", name = "minecraft:quartz_ore", amount = 1 }, give = { label = "Кварц", name = "minecraft:quartz", amount = 4 } },
    { take = { label = "Медная руда", name = "IC2:blockOreCopper", amount = 3 }, give = { label = "Медный слиток", name = "IC2:itemIngot", amount = 7 } },
    { take = { label = "Оловянная руда", name = "IC2:blockOreTin", amount = 3 }, give = { label = "Оловянный слиток", name = "IC2:itemIngot", damage = 1.0, amount = 7 } },
    { take = { label = "Серебряная руда", name = "ThermalFoundation:Ore", damage = 2.0, amount = 1 }, give = { label = "Серебрянный слиток", name = "IC2:itemIngot", damage = 6.0, amount = 2 } },
    { take = { label = "Платиновая руда", name = "ThermalFoundation:Ore", damage = 5.0, amount = 1 }, give = { label = "Измельчённая платина", name = "ThermalFoundation:material", damage = 37.0, amount = 2 } },
    { take = { label = "Никелевая руда", name = "ThermalFoundation:Ore", damage = 4.0, amount = 1 }, give = { label = "Никелевый слиток", name = "ThermalFoundation:material", damage = 68.0, amount = 2 } },
    { take = { label = "Дракониевая руда", name = "DraconicEvolution:draconiumOre", amount = 1 }, give = { label = "Дракониевая пыль", name = "DraconicEvolution:draconiumDust", amount = 2 } }
}

-- Целевой запас для каждой шкалы заполнения.
-- Поле limit в exchanger_ores.txt может переопределить значение для отдельной позиции.
local DEFAULT_STOCK_LIMIT = 3000000

local SHORT_NAMES = {
    ["minecraft:diamond_ore"] = "Алмаз",
    ["minecraft:iron_ore"] = "Железо",
    ["minecraft:gold_ore"] = "Золото",
    ["minecraft:lapis_ore"] = "Лазур",
    ["minecraft:redstone_ore"] = "Редст",
    ["minecraft:coal_ore"] = "Уголь",
    ["appliedenergistics2:tile.OreQuartz"] = "Ист.кв.",
    ["appliedenergistics2:tile.OreQuartzCharged"] = "Зар.кв.",
    ["minecraft:quartz_ore"] = "Кварц",
    ["IC2:blockOreCopper"] = "Медь",
    ["IC2:blockOreTin"] = "Олово",
    ["ThermalFoundation:Ore:2"] = "Серебро",
    ["ThermalFoundation:Ore:5"] = "Платина",
    ["ThermalFoundation:Ore:4"] = "Никель",
    ["DraconicEvolution:draconiumOre"] = "Дракон"
}


-- Индивидуальные цвета полос для стандартных руд.
local BAR_COLORS = {
    ["minecraft:diamond_ore"] = 0x55FFFF,
    ["minecraft:iron_ore"] = 0xD8D8D8,
    ["minecraft:gold_ore"] = 0xFFFF55,
    ["minecraft:lapis_ore"] = 0x3366FF,
    ["minecraft:redstone_ore"] = 0xFF3333,
    ["minecraft:coal_ore"] = 0x666666,
    ["appliedenergistics2:tile.OreQuartz"] = 0xE8F8FF,
    ["appliedenergistics2:tile.OreQuartzCharged"] = 0x00AFFF,
    ["minecraft:quartz_ore"] = 0xFFF4D6,
    ["IC2:blockOreCopper"] = 0xFF9A3C,
    ["IC2:blockOreTin"] = 0xAADDFF,
    ["ThermalFoundation:Ore:2"] = 0xC0C0C0,
    ["ThermalFoundation:Ore:5"] = 0x66E0D0,
    ["ThermalFoundation:Ore:4"] = 0xD4C060,
    ["DraconicEvolution:draconiumOre"] = 0xAA55FF
}

-- Запасная палитра для руд, добавленных через админское сканирование.
local BAR_PALETTE = {
    0x55FFFF, 0xFFFF55, 0x55FF55, 0xFF5555, 0xAA55FF,
    0xFF9A3C, 0x3366FF, 0xAADDFF, 0xFF55FF, 0xD8D8D8
}

-- ============================================================
-- ВСПОМОГАТЕЛЬНЫЕ ФУНКЦИИ
-- ============================================================
local function clamp(value, minValue, maxValue)
    if value < minValue then return minValue end
    if value > maxValue then return maxValue end
    return value
end

local function itemKey(name, damage)
    damage = tonumber(damage) or 0
    if damage ~= 0 then
        return tostring(name) .. ":" .. tostring(math.floor(damage))
    end
    return tostring(name)
end

local function fitText(text, width)
    text = tostring(text or "")
    width = math.max(0, width or 0)

    if unicode.len(text) <= width then
        return text
    end

    if width <= 1 then
        return unicode.sub(text, 1, width)
    end

    return unicode.sub(text, 1, width - 1) .. "…"
end

local function padRight(text, width)
    text = fitText(text, width)
    return text .. string.rep(" ", math.max(0, width - unicode.len(text)))
end

local function centeredX(startX, width, text)
    return startX + math.max(0, math.floor((width - unicode.len(text)) / 2))
end

local function setText(x, y, text, color, background)
    if background then gpu.setBackground(background) end
    if color then gpu.setForeground(color) end
    gpu.set(x, y, text)
end

local function formatNumber(num)
    num = tonumber(num) or 0
    local symbols = { "", "K", "M", "B", "T" }
    local symbolIndex = 1
    local value = math.abs(num)

    while value >= 1000 and symbolIndex < #symbols do
        value = value / 1000
        symbolIndex = symbolIndex + 1
    end

    local result
    if symbolIndex == 1 then
        result = tostring(math.floor(value + 0.5))
    else
        result = string.format("%.1f", value)
        if result:sub(-2) == ".0" then
            result = result:sub(1, -3)
        end
    end

    if num < 0 then result = "-" .. result end
    return result .. symbols[symbolIndex]
end

local function getOreName(ore)
    if ore.shortName and ore.shortName ~= "" then
        return ore.shortName
    end

    local key = itemKey(ore.take.name, ore.take.damage)
    return SHORT_NAMES[key] or SHORT_NAMES[ore.take.name] or ore.take.label or ore.take.name
end

local function getStockLimit(ore)
    return DEFAULT_STOCK_LIMIT
end

local function getBarColor(ore, index)
    local key = itemKey(ore.take.name, ore.take.damage)
    return BAR_COLORS[key]
        or BAR_COLORS[ore.take.name]
        or BAR_PALETTE[((index - 1) % #BAR_PALETTE) + 1]
end


-- ============================================================
-- РАБОТА С ДВУМЯ МЭ-СЕТЯМИ И СЕРВИСНЫМИ СУНДУКАМИ
-- ============================================================
local function stackName(stack)
    if not stack then return nil end
    return stack.name or stack.id
end

local function stackDamage(stack)
    if not stack then return 0 end
    return tonumber(stack.damage or stack.dmg or stack.meta) or 0
end

local function stackAmount(stack)
    if not stack then return 0 end
    return math.max(0, math.floor(tonumber(
        stack.size or stack.qty or stack.amount or stack.count
    ) or 0))
end

local function returnedAmount(primary, secondary)
    local function read(value)
        if type(value) == "number" then
            return math.max(0, math.floor(value))
        end

        if type(value) == "table" then
            return math.max(0, math.floor(tonumber(
                value.size
                or value.qty
                or value.amount
                or value.count
                or value.exported
                or value[1]
            ) or 0))
        end

        return 0
    end

    local first = read(primary)
    if first > 0 then return first end
    return read(secondary)
end

local function getNetworkItems(address)
    local ok, items = pcall(com.invoke, address, "getItemsInNetwork")
    if not ok then
        return nil, tostring(items)
    end

    if type(items) ~= "table" then
        return nil, "getItemsInNetwork вернул " .. type(items)
    end

    return items, nil
end

local function buildNetworkIndex(items)
    local index = {}

    for _, item in pairs(items or {}) do
        if type(item) == "table" then
            local name = stackName(item)
            local damage = stackDamage(item)
            local amount = stackAmount(item)

            if name and amount > 0 then
                local key = itemKey(name, damage)
                local entry = index[key]

                if not entry then
                    entry = {
                        item = item,
                        name = name,
                        damage = damage,
                        amount = 0
                    }
                    index[key] = entry
                end

                entry.amount = entry.amount + amount
            end
        end
    end

    return index
end

local function getNetworkEntry(index, name, damage)
    return index[itemKey(name, damage)]
end

local function makeFingerprint(item, fallbackName, fallbackDamage)
    local fingerprint = {
        id = stackName(item) or fallbackName,
        dmg = stackDamage(item)
    }

    if fingerprint.dmg == nil then
        fingerprint.dmg = tonumber(fallbackDamage) or 0
    end

    if item and item.nbt_hash ~= nil then
        fingerprint.nbt_hash = item.nbt_hash
    end

    return fingerprint
end

local function getChestSize(side)
    local ok, size = pcall(bridge.getInventorySize, side)
    if not ok or not tonumber(size) then
        return nil
    end

    return math.floor(tonumber(size))
end

local function countChestItem(side, name, damage)
    local size = getChestSize(side)
    if not size then return 0 end

    local total = 0
    for slot = 1, size do
        local ok, stack = pcall(bridge.getStackInSlot, side, slot)
        if ok
            and stack
            and stackName(stack) == name
            and stackDamage(stack) == (tonumber(damage) or 0) then
            total = total + stackAmount(stack)
        end
    end

    return total
end

local function countChestAll(side)
    local size = getChestSize(side)
    if not size then return nil end

    local total = 0
    for slot = 1, size do
        local ok, stack = pcall(bridge.getStackInSlot, side, slot)
        if ok and stack then
            total = total + stackAmount(stack)
        end
    end

    return total
end

local function findChestSlot(side, name, damage)
    local size = getChestSize(side)
    if not size then return nil, 0 end

    for slot = 1, size do
        local ok, stack = pcall(bridge.getStackInSlot, side, slot)
        if ok
            and stack
            and stackName(stack) == name
            and stackDamage(stack) == (tonumber(damage) or 0)
            and stackAmount(stack) > 0 then
            return slot, stackAmount(stack)
        end
    end

    return nil, 0
end

local function serviceChestsEmpty()
    local first = countChestAll(FIRST_CHEST_SIDE)
    local second = countChestAll(SECOND_CHEST_SIDE)

    if first == nil or second == nil then
        return false, "Один из сервисных сундуков не найден Transposer-ом."
    end

    if first > 0 or second > 0 then
        return false, string.format(
            "Сервисные сундуки должны быть пустыми. В первом: %d, во втором: %d.",
            first,
            second
        )
    end

    return true
end

local function exportToChest(address, direction, networkItem, name, damage, amount, chestSide)
    local total = 0
    local fingerprint = makeFingerprint(networkItem, name, damage)

    while total < amount do
        local request = math.min(amount - total, MAX_BATCH_ITEMS)
        local before = countChestItem(chestSide, name, damage)

        local ok, result, extra = pcall(
            com.invoke,
            address,
            "exportItem",
            fingerprint,
            direction,
            request
        )

        if not ok then
            return false, total, "exportItem: " .. tostring(result)
        end

        os.sleep(0.15)

        local after = countChestItem(chestSide, name, damage)
        local actual = math.max(0, after - before)
        local reported = returnedAmount(result, extra)
        local moved = actual > 0 and actual or reported

        if moved <= 0 then
            return false, total, string.format(
                "ME Interface не выдал %s (%s:%d).",
                tostring(name),
                tostring(direction),
                tonumber(damage) or 0
            )
        end

        moved = math.min(moved, amount - total)
        total = total + moved
    end

    return true, total
end

local function transferBetweenChests(fromSide, toSide, name, damage, amount)
    local total = 0

    while total < amount do
        local slot, available = findChestSlot(fromSide, name, damage)
        if not slot then
            return false, total, "Предмет исчез из исходного сундука."
        end

        local request = math.min(amount - total, available)
        local ok, moved = pcall(
            bridge.transferItem,
            fromSide,
            toSide,
            request,
            slot
        )

        moved = ok and math.floor(tonumber(moved) or 0) or 0
        if moved <= 0 then
            return false, total, "Transposer не смог перенести предмет между сундуками."
        end

        total = total + moved
        os.sleep(0.05)
    end

    return true, total
end

local function pullFromChest(address, direction, chestSide, name, damage, amount)
    local total = 0

    while total < amount do
        local slot, available = findChestSlot(chestSide, name, damage)
        if not slot then
            return false, total, "Предмет не найден в сундуке назначения."
        end

        local request = math.min(amount - total, available)
        local before = countChestItem(chestSide, name, damage)

        local ok, result, extra = pcall(
            com.invoke,
            address,
            "pullItem",
            direction,
            slot,
            request
        )

        if not ok then
            return false, total, "pullItem: " .. tostring(result)
        end

        os.sleep(0.15)

        local after = countChestItem(chestSide, name, damage)
        local actual = math.max(0, before - after)
        local reported = returnedAmount(result, extra)
        local moved = actual > 0 and actual or reported

        if moved <= 0 then
            return false, total, string.format(
                "ME Interface не забрал %s из сундука (%s).",
                tostring(name),
                tostring(direction)
            )
        end

        moved = math.min(moved, amount - total)
        total = total + moved
    end

    return true, total
end

-- ============================================================
-- ЗАГРУЗКА И СОХРАНЕНИЕ ДАННЫХ
-- ============================================================
local total_ores_global = 0

local function loadTotalOres()
    if fs.exists(TOTAL_FILE) then
        local f = io.open(TOTAL_FILE, "r")
        if f then
            local content = f:read("*all")
            f:close()
            total_ores_global = tonumber(content) or 0
        end
    else
        total_ores_global = 0
    end
end

local function saveTotalOres()
    local f = io.open(TOTAL_FILE, "w")
    if f then
        f:write(tostring(total_ores_global))
        f:close()
    end
end

loadTotalOres()

local currDir = shell.getWorkingDirectory()
local oresPath = currDir .. "/exchanger_ores.txt"

-- Встроенная сериализация нужна только для сохранения админской таблицы руд.
-- Внешний inspect.lua больше не требуется, поэтому программа не зависит от wget.
local function serializeLua(value, indent)
    indent = indent or 0
    local valueType = type(value)

    if valueType == "nil" then
        return "nil"
    end

    if valueType == "number" or valueType == "boolean" then
        return tostring(value)
    end

    if valueType == "string" then
        return string.format("%q", value)
    end

    if valueType ~= "table" then
        error("Нельзя сохранить значение типа " .. valueType)
    end

    local nextIndent = indent + 2
    local parts = { "{" }
    local keys = {}

    for key in pairs(value) do
        keys[#keys + 1] = key
    end

    table.sort(keys, function(a, b)
        if type(a) == type(b) then
            return tostring(a) < tostring(b)
        end
        return type(a) < type(b)
    end)

    for _, key in ipairs(keys) do
        local keyText
        if type(key) == "string" and key:match("^[%a_][%w_]*$") then
            keyText = key
        else
            keyText = "[" .. serializeLua(key, nextIndent) .. "]"
        end

        parts[#parts + 1] = "\n"
            .. string.rep(" ", nextIndent)
            .. keyText
            .. " = "
            .. serializeLua(value[key], nextIndent)
            .. ","
    end

    if #keys > 0 then
        parts[#parts + 1] = "\n" .. string.rep(" ", indent)
    end

    parts[#parts + 1] = "}"
    return table.concat(parts)
end

if fs.exists(oresPath) then
    local file = io.open(oresPath, "r")
    if file then
        local content = file:read("*all")
        file:close()

        local loader, loadError = load("return " .. content)
        if not loader then
            error("Ошибка чтения таблицы " .. oresPath .. ": " .. tostring(loadError))
        end

        local success, oreTable = pcall(loader)
        if not success or type(oreTable) ~= "table" then
            error("Ошибка в таблице " .. oresPath .. ": " .. tostring(oreTable))
        end

        ore_list = oreTable
    end
end

local function saveOres(ores)
    local file = io.open(oresPath, "w")
    if not file then
        return false
    end

    file:write(serializeLua(ores))
    file:close()
    return true
end

-- ============================================================
-- GUI ORE EXCHANGER
-- ============================================================
local LOGO_LINES = {
    "░█████╗░██████╗░███████╗  ███████╗██╗░░██╗░█████╗░██╗░░██╗░█████╗░███╗░░██╗░██████╗░███████╗██████╗░",
    "██╔══██╗██╔══██╗██╔════╝  ██╔════╝╚██╗██╔╝██╔══██╗██║░░██║██╔══██╗████╗░██║██╔════╝░██╔════╝██╔══██╗",
    "██║░░██║██████╔╝█████╗░░  █████╗░░░╚███╔╝░██║░░╚═╝███████║███████║██╔██╗██║██║░░██╗░█████╗░░██████╔╝",
    "██║░░██║██╔══██╗██╔══╝░░  ██╔══╝░░░██╔██╗░██║░░██╗██╔══██║██╔══██║██║╚████║██║░░╚██╗██╔══╝░░██╔══██╗",
    "╚█████╔╝██║░░██║███████╗  ███████╗██╔╝╚██╗╚█████╔╝██║░░██║██║░░██║██║░╚███║╚██████╔╝███████╗██║░░██║",
    "░╚════╝░╚═╝░░╚═╝╚══════╝  ╚══════╝╚═╝░░╚═╝░╚════╝░╚═╝░░╚═╝╚═╝░░╚═╝╚═╝░░╚══╝░╚═════╝░╚══════╝╚═╝░░╚═╝"
}

local UI = {}

local function calculateLayout()
    UI.logoY = 1
    UI.logoW = 0
    for _, line in ipairs(LOGO_LINES) do
        UI.logoW = math.max(UI.logoW, unicode.len(line))
    end
    UI.logoX = math.max(1, math.floor((w - UI.logoW) / 2) + 1)

    UI.titleY = UI.logoY + #LOGO_LINES + 1
    UI.tableTopY = UI.titleY + 2

    UI.nameW = 8
    UI.stockW = 10
    UI.ratioW = 12

    -- На экране 160×50 ширина прогресса будет ровно 52 символа, как в макете.
    local desiredProgressW = 52
    local fixedWidth = 1 + UI.nameW + 1 + UI.stockW + 1 + UI.ratioW + 1
    UI.progressW = math.min(desiredProgressW, math.max(18, w - fixedWidth - 2))

    UI.tableW = 1 + UI.nameW + 1 + UI.progressW + 1 + UI.stockW + 1 + UI.ratioW + 1
    UI.tableX = math.max(1, math.floor((w - UI.tableW) / 2) + 1)
    UI.tableRight = UI.tableX + UI.tableW - 1

    UI.sep1 = UI.tableX + UI.nameW + 1
    UI.sep2 = UI.sep1 + UI.progressW + 1
    UI.sep3 = UI.sep2 + UI.stockW + 1

    UI.nameX = UI.tableX + 1
    UI.progressX = UI.sep1 + 1
    UI.stockX = UI.sep2 + 1
    UI.ratioX = UI.sep3 + 1

    UI.headerY = UI.tableTopY + 1
    UI.headerSeparatorY = UI.tableTopY + 2
    UI.firstRowY = UI.tableTopY + 3

    -- Одна строка руды + одна пустая строка. После таблицы оставляем две строки статуса.
    local maxVisible = math.floor((h - UI.firstRowY - 2) / 2)
    UI.visibleRows = math.max(1, math.min(#ore_list, maxVisible))
    UI.tableBottomY = UI.firstRowY + UI.visibleRows * 2 - 1
    UI.statusY = UI.tableBottomY + 2
    UI.hintY = UI.statusY + 1
end

calculateLayout()

local currentStatus = {
    text = "Вставьте ячейку в ME Chest и встаньте на PIM.",
    color = C.white,
    marker = C.green
}

local function makeBorder(left, middle1, middle2, middle3, right)
    return left
        .. string.rep("─", UI.nameW)
        .. middle1
        .. string.rep("─", UI.progressW)
        .. middle2
        .. string.rep("─", UI.stockW)
        .. middle3
        .. string.rep("─", UI.ratioW)
        .. right
end

local function makeRow(name, progress, stock, ratio)
    return "│"
        .. padRight(name, UI.nameW)
        .. "│"
        .. padRight(progress, UI.progressW)
        .. "│"
        .. padRight(stock, UI.stockW)
        .. "│"
        .. padRight(ratio, UI.ratioW)
        .. "│"
end

local function drawLogo()
    gpu.setBackground(C.bg)
    gpu.setForeground(C.logo)

    for index, line in ipairs(LOGO_LINES) do
        local visible = fitText(line, w)
        local x = math.max(1, math.floor((w - unicode.len(visible)) / 2) + 1)
        gpu.fill(1, UI.logoY + index - 1, w, 1, " ")
        gpu.set(x, UI.logoY + index - 1, visible)
    end
end

local function drawHeader()
    calculateLayout()
    gpu.setBackground(C.bg)
    gpu.fill(1, UI.titleY, w, 1, " ")

    local title = "↻ ORE EXCHANGER v4.0 CELL"
    local total = "[Общий счёт: " .. formatNumber(total_ores_global) .. " руды]"
    local combined = title .. "  " .. total

    setText(UI.tableX, UI.titleY, fitText(combined, UI.tableW), C.title, C.bg)
end

local function drawTableFrame()
    gpu.setBackground(C.bg)
    gpu.setForeground(C.border)

    gpu.set(UI.tableX, UI.tableTopY, makeBorder("┌", "┬", "┬", "┬", "┐"))
    gpu.set(UI.tableX, UI.headerY, makeRow(" РУДА", " ПРОГРЕСС", " В МЭ", " КУРС"))
    gpu.set(UI.tableX, UI.headerSeparatorY, makeBorder("├", "┼", "┼", "┼", "┤"))
end

local function drawOreRow(ore, index)
    local y = UI.firstRowY + (index - 1) * 2
    if y >= UI.tableBottomY then return end

    local stock = math.max(0, tonumber(ore.size) or 0)
    local limit = math.max(1, getStockLimit(ore))
    local fraction = clamp(stock / limit, 0, 1)

    -- Внутри прогресс-колонки: пробел, [, шкала, ], пробел.
    local barWidth = math.max(1, UI.progressW - 4)
    local filled = math.floor(barWidth * fraction + 0.5)
    if stock > 0 and filled == 0 then filled = 1 end
    filled = clamp(filled, 0, barWidth)
    local empty = barWidth - filled

    gpu.setBackground(C.bg)
    gpu.fill(UI.tableX, y, UI.tableW, 1, " ")

    gpu.setForeground(C.border)
    gpu.set(UI.tableX, y, "│")
    gpu.set(UI.sep1, y, "│")
    gpu.set(UI.sep2, y, "│")
    gpu.set(UI.sep3, y, "│")
    gpu.set(UI.tableRight, y, "│")

    setText(UI.nameX, y, padRight(" " .. getOreName(ore), UI.nameW), C.white, C.bg)

    local bracketX = UI.progressX + 1
    setText(bracketX, y, "[", C.gray, C.bg)
    if filled > 0 then
        setText(bracketX + 1, y, string.rep("█", filled), getBarColor(ore, index), C.bg)
    end
    if empty > 0 then
        setText(bracketX + 1 + filled, y, string.rep("░", empty), C.barEmpty, C.bg)
    end
    setText(bracketX + 1 + barWidth, y, "]", C.gray, C.bg)

    local stockText = formatNumber(stock) .. "/" .. formatNumber(limit)
    setText(UI.stockX, y, padRight(" " .. stockText, UI.stockW), C.stock, C.bg)

    local ratioText = tostring(ore.take.amount or 0) .. " → " .. tostring(ore.give.amount or 0)
    setText(UI.ratioX, y, padRight(" " .. ratioText, UI.ratioW), C.ratio, C.bg)

    -- Пустая строка между позициями, как в макете.
    local blankY = y + 1
    if blankY < UI.tableBottomY then
        gpu.fill(UI.tableX, blankY, UI.tableW, 1, " ")
        gpu.setForeground(C.border)
        gpu.set(UI.tableX, blankY, "│")
        gpu.set(UI.sep1, blankY, "│")
        gpu.set(UI.sep2, blankY, "│")
        gpu.set(UI.sep3, blankY, "│")
        gpu.set(UI.tableRight, blankY, "│")
    end
end

local function drawRows()
    calculateLayout()
    drawTableFrame()

    for index = 1, UI.visibleRows do
        drawOreRow(ore_list[index], index)
    end

    gpu.setBackground(C.bg)
    gpu.setForeground(C.border)
    gpu.set(UI.tableX, UI.tableBottomY, makeBorder("└", "┴", "┴", "┴", "┘"))
end

local function drawStatus()
    calculateLayout()
    gpu.setBackground(C.bg)

    if UI.statusY <= h then
        gpu.fill(1, UI.statusY, w, 1, " ")
        setText(UI.tableX + 2, UI.statusY, "[", C.gray, C.bg)
        setText(UI.tableX + 3, UI.statusY, "●", currentStatus.marker, C.bg)
        setText(UI.tableX + 4, UI.statusY, "]", C.gray, C.bg)
        setText(
            UI.tableX + 6,
            UI.statusY,
            fitText(currentStatus.text, math.max(0, UI.tableW - 8)),
            currentStatus.color,
            C.bg
        )
    end

    if UI.hintY <= h then
        gpu.fill(1, UI.hintY, w, 1, " ")
        setText(
            UI.tableX + 2,
            UI.hintY,
            fitText("[Вставьте ячейку в ME Chest, встаньте на PIM и не забирайте её до завершения]", UI.tableW - 4),
            C.gray,
            C.bg
        )
    end
end

local function setStatus(text, color, marker)
    currentStatus.text = tostring(text or "")
    currentStatus.color = color or C.white
    currentStatus.marker = marker or C.green
    drawStatus()
end

local function drawInterface()
    calculateLayout()
    gpu.setBackground(C.bg)
    gpu.setForeground(C.white)
    gpu.fill(1, 1, w, h, " ")

    drawLogo()
    drawHeader()
    drawRows()
    drawStatus()
end

-- Обновляет только строку общего счёта после принятия руды.
local function drawTotalLine()
    drawHeader()
end

-- ============================================================
-- ОБНОВЛЕНИЕ ОСТАТКОВ В ОСНОВНОЙ МЭ
-- ============================================================
local function updIngotsSize()
    if #ore_list < 1 then return false end

    local items, readError = getNetworkItems(MAIN_ME_ADDRESS)
    if not items then
        for _, ore in ipairs(ore_list) do
            ore.size = 0
            ore.maxSize = 64
        end
        return false, readError
    end

    local networkIndex = buildNetworkIndex(items)

    for _, ore in ipairs(ore_list) do
        local entry = getNetworkEntry(
            networkIndex,
            ore.give.name,
            ore.give.damage or 0
        )

        ore.size = entry and entry.amount or 0
        ore.maxSize = entry and tonumber(entry.item.maxSize or entry.item.max_size) or 64
    end

    return true
end

local function drawInfo(drawType)
    if drawType == "full" then
        drawInterface()
    else
        drawHeader()
        drawRows()
        drawStatus()
    end
end

local function updInfo(drawType)
    drawType = drawType or "full"
    local connected, readError = updIngotsSize()
    drawInfo(drawType)

    if not connected then
        setStatus(
            "Нет соединения с основной МЭ: " .. tostring(readError or "неизвестная ошибка"),
            C.red,
            C.red
        )
    end

    return connected
end

-- ============================================================
-- СТАТИСТИКА ОБМЕНА
-- ============================================================
local stats = { ores = 0, ingots = 0 }

local function saveStats()
    local f = io.open(STATS_FILE, "a")
    if f then
        f:write(string.format(
            "[%s] Переработано руды: %d, выдано слитков: %d\n",
            os.date("%Y-%m-%d %H:%M:%S"),
            stats.ores,
            stats.ingots
        ))
        f:close()
    end
end

-- ============================================================
-- ЛОГИКА ОБМЕНА ВСЕЙ РУДЫ ВНУТРИ МЭ-ЯЧЕЙКИ
-- ============================================================
local function playerIsOnPim()
    local success, inventoryName = pcall(pim.getInventoryName)
    return success and inventoryName and inventoryName ~= "pim"
end

local function createExchangePlan()
    local cellItems, cellError = getNetworkItems(CELL_ME_ADDRESS)
    if not cellItems then
        return nil, "Не удалось прочитать ячейку: " .. tostring(cellError)
    end

    local mainItems, mainError = getNetworkItems(MAIN_ME_ADDRESS)
    if not mainItems then
        return nil, "Не удалось прочитать основную МЭ: " .. tostring(mainError)
    end

    local cellIndex = buildNetworkIndex(cellItems)
    local mainIndex = buildNetworkIndex(mainItems)
    local plan = {}
    local totalRewardNeeds = {}
    local rewardDefinitions = {}

    for index, ore in ipairs(ore_list) do
        local takeAmount = math.max(1, math.floor(tonumber(ore.take.amount) or 1))
        local giveAmount = math.max(1, math.floor(tonumber(ore.give.amount) or 1))
        local takeDamage = tonumber(ore.take.damage) or 0
        local giveDamage = tonumber(ore.give.damage) or 0
        local takeEntry = getNetworkEntry(cellIndex, ore.take.name, takeDamage)
        local available = takeEntry and takeEntry.amount or 0
        local groups = math.floor(available / takeAmount)

        if groups > 0 then
            local oreAmount = groups * takeAmount
            local rewardAmount = groups * giveAmount
            local rewardKey = itemKey(ore.give.name, giveDamage)

            if itemKey(ore.take.name, takeDamage) == rewardKey then
                return nil, "Небезопасная конфигурация: руда и награда совпадают у "
                    .. tostring(ore.take.label or ore.take.name)
            end

            totalRewardNeeds[rewardKey] = (totalRewardNeeds[rewardKey] or 0) + rewardAmount
            rewardDefinitions[rewardKey] = {
                name = ore.give.name,
                damage = giveDamage,
                label = ore.give.label
            }

            plan[#plan + 1] = {
                index = index,
                ore = ore,
                groups = groups,
                oreAmount = oreAmount,
                rewardAmount = rewardAmount,
                takeAmount = takeAmount,
                giveAmount = giveAmount
            }
        end
    end

    if #plan == 0 then
        return {}, nil
    end

    for rewardKey, needed in pairs(totalRewardNeeds) do
        local definition = rewardDefinitions[rewardKey]
        local entry = getNetworkEntry(mainIndex, definition.name, definition.damage)
        local available = entry and entry.amount or 0

        if available < needed then
            return nil, string.format(
                "Недостаточно награды: %s — в МЭ %d, требуется %d.",
                tostring(definition.label or definition.name),
                available,
                needed
            )
        end
    end

    return plan, nil
end

local function rollbackUnpaidBatch(ore, oreAmount, rewardAmount)
    local takeDamage = tonumber(ore.take.damage) or 0
    local giveDamage = tonumber(ore.give.damage) or 0

    -- Если руда ещё не ушла в основную МЭ, возвращаем её в ячейку.
    local oreInSecond = countChestItem(
        SECOND_CHEST_SIDE,
        ore.take.name,
        takeDamage
    )

    if oreInSecond > 0 then
        transferBetweenChests(
            SECOND_CHEST_SIDE,
            FIRST_CHEST_SIDE,
            ore.take.name,
            takeDamage,
            math.min(oreInSecond, oreAmount)
        )
    end

    local oreInFirst = countChestItem(
        FIRST_CHEST_SIDE,
        ore.take.name,
        takeDamage
    )

    if oreInFirst > 0 then
        pullFromChest(
            CELL_ME_ADDRESS,
            CELL_CHEST_DIRECTION,
            FIRST_CHEST_SIDE,
            ore.take.name,
            takeDamage,
            math.min(oreInFirst, oreAmount)
        )
    end

    -- Зарезервированную награду возвращаем в основную МЭ.
    local rewardInFirst = countChestItem(
        FIRST_CHEST_SIDE,
        ore.give.name,
        giveDamage
    )

    if rewardInFirst > 0 then
        transferBetweenChests(
            FIRST_CHEST_SIDE,
            SECOND_CHEST_SIDE,
            ore.give.name,
            giveDamage,
            math.min(rewardInFirst, rewardAmount)
        )
    end

    local rewardInSecond = countChestItem(
        SECOND_CHEST_SIDE,
        ore.give.name,
        giveDamage
    )

    if rewardInSecond > 0 then
        pullFromChest(
            MAIN_ME_ADDRESS,
            MAIN_CHEST_DIRECTION,
            SECOND_CHEST_SIDE,
            ore.give.name,
            giveDamage,
            math.min(rewardInSecond, rewardAmount)
        )
    end
end

local function processBatch(planEntry, batchGroups)
    local ore = planEntry.ore
    local takeDamage = tonumber(ore.take.damage) or 0
    local giveDamage = tonumber(ore.give.damage) or 0
    local oreAmount = batchGroups * planEntry.takeAmount
    local rewardAmount = batchGroups * planEntry.giveAmount

    local chestsOk, chestError = serviceChestsEmpty()
    if not chestsOk then
        return false, chestError
    end

    -- Перед каждой партией перечитываем обе сети, чтобы получить актуальные
    -- предметы и не работать со старым fingerprint.
    local mainItems, mainError = getNetworkItems(MAIN_ME_ADDRESS)
    if not mainItems then
        return false, "Основная МЭ недоступна: " .. tostring(mainError)
    end

    local cellItems, cellError = getNetworkItems(CELL_ME_ADDRESS)
    if not cellItems then
        return false, "Ячейка недоступна: " .. tostring(cellError)
    end

    local mainEntry = getNetworkEntry(
        buildNetworkIndex(mainItems),
        ore.give.name,
        giveDamage
    )

    local cellEntry = getNetworkEntry(
        buildNetworkIndex(cellItems),
        ore.take.name,
        takeDamage
    )

    if not mainEntry or mainEntry.amount < rewardAmount then
        return false, string.format(
            "В основной МЭ не хватает %s: есть %d, нужно %d.",
            tostring(ore.give.label),
            mainEntry and mainEntry.amount or 0,
            rewardAmount
        )
    end

    if not cellEntry or cellEntry.amount < oreAmount then
        return false, string.format(
            "В ячейке изменилось количество %s: есть %d, нужно %d.",
            tostring(ore.take.label),
            cellEntry and cellEntry.amount or 0,
            oreAmount
        )
    end

    -- 1. Сначала резервируем награду. Пока награда не получена,
    --    руда игрока не забирается.
    local ok, _, actionError = exportToChest(
        MAIN_ME_ADDRESS,
        MAIN_CHEST_DIRECTION,
        mainEntry.item,
        ore.give.name,
        giveDamage,
        rewardAmount,
        SECOND_CHEST_SIDE
    )

    if not ok then
        rollbackUnpaidBatch(ore, oreAmount, rewardAmount)
        return false, "Не удалось зарезервировать награду: " .. tostring(actionError)
    end

    -- 2. Вынимаем рассчитанное количество руды из ячейки.
    ok, _, actionError = exportToChest(
        CELL_ME_ADDRESS,
        CELL_CHEST_DIRECTION,
        cellEntry.item,
        ore.take.name,
        takeDamage,
        oreAmount,
        FIRST_CHEST_SIDE
    )

    if not ok then
        rollbackUnpaidBatch(ore, oreAmount, rewardAmount)
        return false, "Не удалось получить руду из ячейки: " .. tostring(actionError)
    end

    -- 3. Первый сундук -> второй сундук.
    ok, _, actionError = transferBetweenChests(
        FIRST_CHEST_SIDE,
        SECOND_CHEST_SIDE,
        ore.take.name,
        takeDamage,
        oreAmount
    )

    if not ok then
        rollbackUnpaidBatch(ore, oreAmount, rewardAmount)
        return false, "Не удалось передать руду: " .. tostring(actionError)
    end

    -- 4. Второй сундук -> основная МЭ. После этого руда считается принятой.
    ok, _, actionError = pullFromChest(
        MAIN_ME_ADDRESS,
        MAIN_CHEST_DIRECTION,
        SECOND_CHEST_SIDE,
        ore.take.name,
        takeDamage,
        oreAmount
    )

    if not ok then
        rollbackUnpaidBatch(ore, oreAmount, rewardAmount)
        return false, "Основная МЭ не приняла руду: " .. tostring(actionError)
    end

    -- 5. Зарезервированная награда -> первый сундук.
    ok, _, actionError = transferBetweenChests(
        SECOND_CHEST_SIDE,
        FIRST_CHEST_SIDE,
        ore.give.name,
        giveDamage,
        rewardAmount
    )

    if not ok then
        return false,
            "Руда уже принята, но награда осталась во втором сундуке: "
            .. tostring(actionError)
    end

    -- 6. Первый сундук -> ME Chest -> та же ячейка игрока.
    ok, _, actionError = pullFromChest(
        CELL_ME_ADDRESS,
        CELL_CHEST_DIRECTION,
        FIRST_CHEST_SIDE,
        ore.give.name,
        giveDamage,
        rewardAmount
    )

    if not ok then
        return false,
            "Руда уже принята, но награда осталась в первом сундуке. "
            .. "Освободите место в ячейке: "
            .. tostring(actionError)
    end

    return true, nil, oreAmount, rewardAmount
end

local function processCellExchange()
    setStatus("Считываю содержимое ячейки...", C.cyan, C.cyan)
    os.sleep(0.3)

    local chestsOk, chestError = serviceChestsEmpty()
    if not chestsOk then
        setStatus(chestError, C.red, C.red)
        return false
    end

    local plan, planError = createExchangePlan()
    if not plan then
        setStatus(planError, C.red, C.red)
        return false
    end

    if #plan == 0 then
        setStatus(
            "В ячейке нет руды в количестве, достаточном для обмена.",
            C.yellow,
            C.yellow
        )
        return true
    end

    local sessionOres = 0
    local sessionRewards = 0

    for _, entry in ipairs(plan) do
        local remainingGroups = entry.groups

        while remainingGroups > 0 do
            if not playerIsOnPim() then
                setStatus("Вы сошли с PIM. Обмен остановлен.", C.red, C.red)
                return false
            end

            local maxByOre = math.max(1, math.floor(MAX_BATCH_ITEMS / entry.takeAmount))
            local maxByReward = math.max(1, math.floor(MAX_BATCH_ITEMS / entry.giveAmount))
            local batchGroups = math.min(remainingGroups, maxByOre, maxByReward)
            local batchOre = batchGroups * entry.takeAmount
            local batchReward = batchGroups * entry.giveAmount

            setStatus(
                string.format(
                    "%s: забираю %d, возвращаю %d × %s",
                    getOreName(entry.ore),
                    batchOre,
                    batchReward,
                    tostring(entry.ore.give.label)
                ),
                C.yellow,
                C.yellow
            )

            local ok, batchError, accepted, rewarded = processBatch(entry, batchGroups)
            if not ok then
                updInfo("ingots")
                saveStats()
                setStatus("ОШИБКА: " .. tostring(batchError), C.red, C.red)
                return false
            end

            accepted = tonumber(accepted) or batchOre
            rewarded = tonumber(rewarded) or batchReward
            remainingGroups = remainingGroups - batchGroups
            sessionOres = sessionOres + accepted
            sessionRewards = sessionRewards + rewarded
            stats.ores = stats.ores + accepted
            stats.ingots = stats.ingots + rewarded
            total_ores_global = total_ores_global + accepted
            saveTotalOres()
            drawTotalLine()
        end
    end

    updInfo("ingots")
    saveStats()

    setStatus(
        string.format(
            "Готово! Из ячейки принято %d руды, возвращено %d предметов. Заберите ячейку.",
            sessionOres,
            sessionRewards
        ),
        C.green,
        C.green
    )

    return true
end

-- ============================================================
-- АДМИНИСТРАТОРСКОЕ СКАНИРОВАНИЕ
-- ============================================================
local function isAdmin(user)
    local users = table.pack(computer.users())
    for _, adminUser in pairs(users) do
        if adminUser == user then
            return true
        end
    end
    return false
end

local function scanExchangeConfiguration()
    computer.beep(1500, 0.1)

    for i = 5, 1, -1 do
        setStatus(
            string.format("Сканирование конфигурации через %d сек...", i),
            C.yellow,
            C.yellow
        )
        os.sleep(1)
    end

    setStatus("Сканирую пары предметов в инвентаре...", C.cyan, C.cyan)
    computer.beep(1500, 0.8)

    if playerIsOnPim() then
        ore_list = {}
        local success, data = pcall(pim.getAllStacks, 0)

        if not success or not data then
            setStatus("Не удалось получить содержимое инвентаря.", C.red, C.red)
            return
        end

        local i = 10
        while i ~= 9 do
            if i == 18 or i == 27 then
                i = i + 1
            elseif i == 36 then
                i = 1
            end

            if data[i] and data[i + 1] then
                table.insert(ore_list, {
                    take = {
                        label = data[i].display_name,
                        name = data[i].id,
                        damage = data[i].dmg,
                        amount = math.floor(data[i].qty)
                    },
                    give = {
                        label = data[i + 1].display_name,
                        name = data[i + 1].id,
                        damage = data[i + 1].dmg,
                        amount = math.floor(data[i + 1].qty)
                    }
                })
            end

            i = i + 2
        end

        saveOres(ore_list)
        computer.beep(500, 0.2)
        updInfo("full")
        setStatus("Новая конфигурация обмена сохранена.", C.green, C.green)
    else
        setStatus("Не найден инвентарь для сканирования.", C.red, C.red)
        computer.beep(2000, 0.2)
        computer.beep(2000, 0.2)
    end

    os.sleep(1)

    for i = 5, 1, -1 do
        setStatus(string.format("Возобновление работы через %d сек...", i), C.gray, C.yellow)
        os.sleep(1)
    end

    setStatus("Вставьте ячейку в ME Chest и встаньте на PIM.", C.white, C.green)
end

-- ============================================================
-- СОБЫТИЯ
-- ============================================================
local function handleEvent(eventName, ...)
    local args = { ... }

    if eventName == "interrupted" then
        gpu.setBackground(defBG)
        gpu.setForeground(defFG)
        gpu.fill(1, 1, w, h, " ")
        os.exit()
        return true
    end

    if eventName == "player_on" then
        if not updInfo("ingots") then return end

        stats.ores = 0
        stats.ingots = 0

        setStatus(
            string.format(
                "Игрок %s на PIM. Считываю ячейку из ME Chest.",
                tostring(args[1] or "")
            ),
            C.green,
            C.green
        )

        processCellExchange()
        return
    end

    if eventName == "player_off" then
        if not updInfo("ingots") then return end
        setStatus(
            "Вставьте ячейку в ME Chest и встаньте на PIM.",
            C.white,
            C.green
        )
        return
    end

    -- Скрытая админ-зона находится справа от двух строк состояния.
    if eventName == "touch"
        and args[2] >= UI.tableRight - 38
        and args[3] >= UI.statusY
        and args[3] <= UI.hintY
        and isAdmin(args[5]) then
        scanExchangeConfiguration()
    end
end

-- ============================================================
-- ЗАПУСК
-- ============================================================
local function main()
    drawInterface()

    if updInfo("full") then
        setStatus("Вставьте ячейку в ME Chest и встаньте на PIM.", C.white, C.green)
    end

    while true do
        handleEvent(event.pull(1))
    end
end

while true do
    local success, err = pcall(main)

    if not success then
        local errorText = tostring(err or "Неизвестная ошибка")
        local errorFile = io.open(currDir .. "/exchanger_errors.txt", "ab")
        if errorFile then
            errorFile:write(errorText .. "\n")
            errorFile:close()
        end

        computer.beep(2000, 3)
    else
        break
    end
end
