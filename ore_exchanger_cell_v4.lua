-- v4.1 CELL ULTRAFAST
-- Интерфейс сохранён в стиле v2.5 пользователя.
-- Обмен выполняется напрямую с ME Chest, в котором стоит ячейка игрока.

local unicode = require("unicode")
local computer = require("computer")
local com = require("component")
local event = require("event")
local fs = require("filesystem")
local shell = require("shell")

-- ============================================================
-- ПРОВЕРЕННЫЕ АДРЕСА И СТОРОНЫ
-- ============================================================
local CELL_ME_ADDRESS = "b2f2b6b2-1543-4659-b4e5-e8236fc27871"
local MAIN_ME_ADDRESS = "7867903d-0c1c-43cf-85fb-6437973e1e99"
local TRANSPOSER_ADDRESS = "1e889179-3120-45ae-b698-5c760ef1f744"

local CELL_CHEST_DIRECTION = "NORTH"
local MAIN_CHEST_DIRECTION = "SOUTH"

local FIRST_CHEST_SIDE = 3  -- FRONT: возле ME Interface ячейки
local SECOND_CHEST_SIDE = 2 -- BACK: возле основного ME Interface

-- Один слот оставляем свободным для безопасной работы.
-- Код сам определяет объём сундуков. Если поставить сундуки больше,
-- размер партии автоматически увеличится.
local CHEST_SLOT_RESERVE = 1
local MAX_INTERFACE_REQUEST = 4096
local ERROR_RETRY_DELAY = 0.03

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
-- ИНТЕРФЕЙС v2.5: 80 x 50
-- ============================================================
local w, h = 80, 50
local defBG, defFG = gpu.getBackground(), gpu.getForeground()
gpu.setResolution(w, h)

-- ============================================================
-- НАСТРОЙКИ
-- ============================================================
local STATS_FILE = "exchanger_stats.txt"
local TOTAL_FILE = "total_ore.txt"
local accent = 0x00E5C9
local TOTAL_OFFSET = 7

-- Таблица с рудами (damage не указан -> 0)
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

-- ============================================================
-- БАЗОВЫЕ ФУНКЦИИ ПРЕДМЕТОВ
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

local function stackMaxSize(stack)
    if not stack then return 64 end
    return math.max(1, math.floor(tonumber(
        stack.maxSize or stack.max_size or stack.maxStackSize
    ) or 64))
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

local function itemKey(name, damage)
    return tostring(name) .. ":" .. tostring(math.floor(tonumber(damage) or 0))
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
                        amount = 0,
                        maxSize = stackMaxSize(item)
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

-- ============================================================
-- СУНДУКИ И TRANSPOSER
-- ============================================================
local function getChestSize(side)
    local ok, size = pcall(bridge.getInventorySize, side)
    if not ok or not tonumber(size) then
        return nil
    end
    return math.floor(tonumber(size))
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

local function exportToChest(address, direction, fingerprint, amount)
    local total = 0

    while total < amount do
        local request = math.min(amount - total, MAX_INTERFACE_REQUEST)
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

        local moved = returnedAmount(result, extra)
        if moved <= 0 then
            os.sleep(ERROR_RETRY_DELAY)
            return false, total, "ME Interface ничего не выдал."
        end

        total = total + math.min(moved, amount - total)
    end

    return true, total
end

local function transferBetweenChests(fromSide, toSide, name, damage, amount)
    local total = 0
    local size = getChestSize(fromSide)

    if not size then
        return false, total, "Исходный сундук не найден."
    end

    -- Один линейный проход по слотам. Повторного полного сканирования нет.
    for slot = 1, size do
        while total < amount do
            local okStack, stack = pcall(bridge.getStackInSlot, fromSide, slot)
            if not okStack
                or not stack
                or stackName(stack) ~= name
                or stackDamage(stack) ~= (tonumber(damage) or 0) then
                break
            end

            local available = stackAmount(stack)
            if available <= 0 then break end

            local request = math.min(amount - total, available)
            local okMove, moved = pcall(
                bridge.transferItem,
                fromSide,
                toSide,
                request,
                slot
            )

            moved = okMove and math.floor(tonumber(moved) or 0) or 0
            if moved <= 0 then
                return false, total, "Transposer не смог перенести предмет между сундуками."
            end

            total = total + moved
        end

        if total >= amount then
            return true, total
        end
    end

    return false, total, "Не удалось найти всё количество предмета в сундуке."
end

local function pullFromChest(address, direction, chestSide, name, damage, amount)
    local total = 0
    local size = getChestSize(chestSide)

    if not size then
        return false, total, "Сундук не найден."
    end

    -- Один линейный проход по слотам.
    for slot = 1, size do
        while total < amount do
            local okStack, stack = pcall(bridge.getStackInSlot, chestSide, slot)
            if not okStack
                or not stack
                or stackName(stack) ~= name
                or stackDamage(stack) ~= (tonumber(damage) or 0) then
                break
            end

            local available = stackAmount(stack)
            if available <= 0 then break end

            local request = math.min(amount - total, available)
            local okPull, result, extra = pcall(
                com.invoke,
                address,
                "pullItem",
                direction,
                slot,
                request
            )

            if not okPull then
                return false, total, "pullItem: " .. tostring(result)
            end

            local moved = returnedAmount(result, extra)
            if moved <= 0 then
                os.sleep(ERROR_RETRY_DELAY)
                return false, total, "ME Interface не смог забрать предмет из сундука."
            end

            total = total + math.min(moved, amount - total)
        end

        if total >= amount then
            return true, total
        end
    end

    return false, total, "Не удалось забрать всё количество предмета из сундука."
end

local function stacksNeeded(amount, maxStack)
    amount = math.max(0, math.floor(tonumber(amount) or 0))
    maxStack = math.max(1, math.floor(tonumber(maxStack) or 64))
    if amount == 0 then return 0 end
    return math.ceil(amount / maxStack)
end

-- Рассчитывает максимально большую безопасную партию по реальному размеру
-- сундуков и размерам стаков руды/награды.
local function getMaxBatchGroups(entry, remainingGroups)
    local firstSlots = getChestSize(FIRST_CHEST_SIDE)
    local secondSlots = getChestSize(SECOND_CHEST_SIDE)

    if not firstSlots or not secondSlots then
        return 0
    end

    local usableSlots = math.max(
        1,
        math.min(firstSlots, secondSlots) - CHEST_SLOT_RESERVE
    )

    local low = 1
    local high = math.max(1, math.floor(remainingGroups))
    local best = 0

    while low <= high do
        local middle = math.floor((low + high) / 2)
        local oreAmount = middle * entry.takeAmount
        local rewardAmount = middle * entry.giveAmount

        -- Во втором сундуке одновременно лежат награда и руда.
        local usedSlots = stacksNeeded(oreAmount, entry.takeMaxSize)
            + stacksNeeded(rewardAmount, entry.giveMaxSize)

        if usedSlots <= usableSlots then
            best = middle
            low = middle + 1
        else
            high = middle - 1
        end
    end

    return math.max(1, best)
end

-- ============================================================
-- ЗАГРУЗКА / СОХРАНЕНИЕ
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

local function serializeLua(value, indent)
    indent = indent or 0
    local valueType = type(value)

    if valueType == "nil" then return "nil" end
    if valueType == "number" or valueType == "boolean" then return tostring(value) end
    if valueType == "string" then return string.format("%q", value) end
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
    if not file then return false end
    file:write(serializeLua(ores))
    file:close()
    return true
end

-- ============================================================
-- ТОЧНЫЙ ИНТЕРФЕЙС v2.5
-- ============================================================
local function center(y, text, color)
    gpu.fill(1, y, w, 1, " ")
    gpu.setForeground(color)
    gpu.set(math.floor(w / 2 - unicode.len(text) / 2), y, text)
end

local function formatNumber(num)
    local symbols = { "", "K", "M", "B", "T" }
    local formattedNum = tonumber(num) or 0
    local symbolIndex = 1

    while formattedNum >= 1000 and symbolIndex < #symbols do
        formattedNum = formattedNum / 1000
        symbolIndex = symbolIndex + 1
    end

    formattedNum = string.format("%.1f", formattedNum)
    if formattedNum:sub(-2) == ".0" then
        formattedNum = formattedNum:sub(1, -3)
    end

    return formattedNum .. symbols[symbolIndex]
end

local function updIngotsSize()
    if #ore_list < 1 then return false end

    local items = getNetworkItems(MAIN_ME_ADDRESS)
    if not items then
        for _, ore in ipairs(ore_list) do
            ore.size = 0
            ore.maxSize = 64
        end
        return false
    end

    local networkIndex = buildNetworkIndex(items)
    local totalOre = 0

    for _, ore in ipairs(ore_list) do
        local entry = getNetworkEntry(
            networkIndex,
            ore.give.name,
            ore.give.damage or 0
        )

        if entry then
            ore.size = entry.amount
            ore.maxSize = entry.maxSize or 64
            totalOre = totalOre + entry.amount
        else
            ore.size = 0
            ore.maxSize = 64
        end
    end

    return totalOre > 0
end

local function drawTotalLine()
    local totalRow = 2 + #ore_list + 2 + TOTAL_OFFSET
    if totalRow < h then
        gpu.fill(1, totalRow, w, 1, " ")
        gpu.setForeground(0xFFFFFF)
        local text = "Общее: " .. formatNumber(total_ores_global) .. " руды"
        gpu.set(5, totalRow, text)
    end
end

local function drawInfo(drawType)
    local line = 2

    if drawType == "full" then
        gpu.fill(1, 1, w, h - 16, " ")
    end

    for i, ore in pairs(ore_list) do
        local printRow = line + i

        if drawType == "full" then
            gpu.setForeground(0xFF00FF)
            local takeAmount = formatNumber(ore.take.amount)
            gpu.set(29 - #takeAmount, printRow, takeAmount)
            gpu.set(33, printRow, formatNumber(ore.give.amount))

            gpu.setForeground(0x00FF00)
            gpu.set(5, printRow, ore.take.label)
            gpu.set(42, printRow, ore.give.label)

            gpu.setForeground(0xFFFF00)
            gpu.set(30, printRow, unicode.char(0xFF1E))
            gpu.set(63, printRow, "Доступно:")

            gpu.setForeground(0x00E5C9)
            gpu.set(2, printRow + 1, string.rep("═", w - 2))
        end

        if drawType == "full" or drawType == "ingots" then
            gpu.fill(73, printRow, w - 73, 1, " ")
            gpu.setForeground(0xFF00FF)
            gpu.set(73, printRow, formatNumber(ore.size or 0))
        end

        line = line + 1
    end

    drawTotalLine()
end

local function updInfo(drawType)
    drawType = drawType or "full"
    local check = updIngotsSize()

    if not check then
        center(h - 15, "Нет соединения с МЭ или руды не настроены", 0xFF0000)
    end

    drawInfo(drawType)
    return check
end

local function setStatus(text, color)
    center(h - 14, tostring(text or ""), color or 0xFFFFFF)
end

local function drawLogo(x, y, color)
    local dragonX = 9
    local exchangerX = 4

    local dragonLines = {
        "  ██████╗ ██████╗  █████╗ ██████╗ ██╗  ██╗ ██████╗ ███╗   ██╗",
        "  ██╔══██╗██╔══██╗██╔══██╗██╔══██╗██║ ██╔╝██╔═══██╗████╗  ██║",
        "  ██║  ██║██████╔╝███████║██║  ██║█████╔╝ ██║   ██║██╔██╗ ██║",
        "  ██║  ██║██╔══██╗██╔══██║██║  ██║██╔═██╗ ██║   ██║██║╚██╗██║",
        "  ██████╔╝██║  ██║██║  ██║██████╔╝██║  ██╗╚██████╔╝██║ ╚████║",
        "  ╚═════╝ ╚═╝  ╚═╝╚═╝  ╚═╝╚═════╝ ╚═╝  ╚═╝ ╚═════╝ ╚═╝  ╚═══╝"
    }

    local exchangerLines = {
        "███████╗██╗  ██╗ ██████╗██╗  ██╗ █████╗ ███╗   ██╗ ██████╗ ███████╗██████╗ ",
        "██╔════╝╚██╗██╔╝██╔════╝██║  ██║██╔══██╗████╗  ██║██╔════╝ ██╔════╝██╔══██╗",
        "█████╗   ╚███╔╝ ██║     ███████║███████║██╔██╗ ██║██║  ███╗█████╗  ██████╔╝",
        "██╔══╝   ██╔██╗ ██║     ██╔══██║██╔══██║██║╚██╗██║██║   ██║██╔══╝  ██╔══██╗",
        "███████╗██╔╝ ██╗╚██████╗██║  ██║██║  ██║██║ ╚████║╚██████╔╝███████╗██║  ██║",
        "╚══════╝╚═╝  ╚═╝ ╚═════╝╚═╝  ╚═╝╚═╝  ╚═╝╚═╝  ╚═══╝ ╚═════╝ ╚══════╝╚═╝  ╚═╝"
    }

    gpu.setForeground(color)

    for i, line in ipairs(dragonLines) do
        gpu.set(dragonX, y + i - 1, line)
    end

    for i, line in ipairs(exchangerLines) do
        gpu.set(exchangerX, y + 6 + i - 1, line)
    end
end

-- ============================================================
-- СТАТИСТИКА
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
-- УСКОРЕННАЯ ЛОГИКА ОБМЕНА
-- ============================================================
local function playerIsOnPim()
    local success, inventoryName = pcall(pim.getInventoryName)
    return success and inventoryName and inventoryName ~= "pim"
end

local function createExchangePlan()
    -- Каждая сеть читается только ОДИН раз на весь обмен.
    -- Основная сеть пользователя содержит тысячи типов предметов,
    -- поэтому это даёт большой прирост скорости.
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
            local rewardEntry = getNetworkEntry(mainIndex, ore.give.name, giveDamage)
            local rewardKey = itemKey(ore.give.name, giveDamage)
            local oreKey = itemKey(ore.take.name, takeDamage)

            if oreKey == rewardKey then
                return nil, "Небезопасная настройка: руда и награда совпадают у "
                    .. tostring(ore.take.label or ore.take.name)
            end

            totalRewardNeeds[rewardKey] = (totalRewardNeeds[rewardKey] or 0)
                + groups * giveAmount

            rewardDefinitions[rewardKey] = {
                name = ore.give.name,
                damage = giveDamage,
                label = ore.give.label,
                entry = rewardEntry
            }

            plan[#plan + 1] = {
                index = index,
                ore = ore,
                groups = groups,
                takeAmount = takeAmount,
                giveAmount = giveAmount,
                takeDamage = takeDamage,
                giveDamage = giveDamage,
                takeFingerprint = makeFingerprint(
                    takeEntry.item,
                    ore.take.name,
                    takeDamage
                ),
                giveFingerprint = rewardEntry and makeFingerprint(
                    rewardEntry.item,
                    ore.give.name,
                    giveDamage
                ) or nil,
                takeMaxSize = takeEntry.maxSize or 64,
                giveMaxSize = rewardEntry and rewardEntry.maxSize or 64
            }
        end
    end

    if #plan == 0 then
        return {}, nil
    end

    for rewardKey, needed in pairs(totalRewardNeeds) do
        local definition = rewardDefinitions[rewardKey]
        local available = definition.entry and definition.entry.amount or 0

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

local function rollbackUnpaidBatch(entry, oreAmount, rewardAmount)
    local ore = entry.ore

    local oreInSecond = countChestItem(
        SECOND_CHEST_SIDE,
        ore.take.name,
        entry.takeDamage
    )

    if oreInSecond > 0 then
        transferBetweenChests(
            SECOND_CHEST_SIDE,
            FIRST_CHEST_SIDE,
            ore.take.name,
            entry.takeDamage,
            math.min(oreInSecond, oreAmount)
        )
    end

    local oreInFirst = countChestItem(
        FIRST_CHEST_SIDE,
        ore.take.name,
        entry.takeDamage
    )

    if oreInFirst > 0 then
        pullFromChest(
            CELL_ME_ADDRESS,
            CELL_CHEST_DIRECTION,
            FIRST_CHEST_SIDE,
            ore.take.name,
            entry.takeDamage,
            math.min(oreInFirst, oreAmount)
        )
    end

    local rewardInFirst = countChestItem(
        FIRST_CHEST_SIDE,
        ore.give.name,
        entry.giveDamage
    )

    if rewardInFirst > 0 then
        transferBetweenChests(
            FIRST_CHEST_SIDE,
            SECOND_CHEST_SIDE,
            ore.give.name,
            entry.giveDamage,
            math.min(rewardInFirst, rewardAmount)
        )
    end

    local rewardInSecond = countChestItem(
        SECOND_CHEST_SIDE,
        ore.give.name,
        entry.giveDamage
    )

    if rewardInSecond > 0 then
        pullFromChest(
            MAIN_ME_ADDRESS,
            MAIN_CHEST_DIRECTION,
            SECOND_CHEST_SIDE,
            ore.give.name,
            entry.giveDamage,
            math.min(rewardInSecond, rewardAmount)
        )
    end
end

local function processBatch(entry, batchGroups)
    local ore = entry.ore
    local oreAmount = batchGroups * entry.takeAmount
    local rewardAmount = batchGroups * entry.giveAmount

    -- Никакого повторного чтения 2400+ предметов основной сети здесь нет.
    -- Используются fingerprint, полученные в начале операции.

    -- 1. Резервируем всю награду во втором сундуке.
    local ok, _, actionError = exportToChest(
        MAIN_ME_ADDRESS,
        MAIN_CHEST_DIRECTION,
        entry.giveFingerprint,
        rewardAmount
    )

    if not ok then
        rollbackUnpaidBatch(entry, oreAmount, rewardAmount)
        return false, "Не удалось зарезервировать награду: " .. tostring(actionError)
    end

    -- 2. Извлекаем всю рассчитанную руду в первый сундук.
    ok, _, actionError = exportToChest(
        CELL_ME_ADDRESS,
        CELL_CHEST_DIRECTION,
        entry.takeFingerprint,
        oreAmount
    )

    if not ok then
        rollbackUnpaidBatch(entry, oreAmount, rewardAmount)
        return false, "Не удалось получить руду из ячейки: " .. tostring(actionError)
    end

    -- 3. Руда: первый сундук -> второй.
    ok, _, actionError = transferBetweenChests(
        FIRST_CHEST_SIDE,
        SECOND_CHEST_SIDE,
        ore.take.name,
        entry.takeDamage,
        oreAmount
    )

    if not ok then
        rollbackUnpaidBatch(entry, oreAmount, rewardAmount)
        return false, "Не удалось передать руду: " .. tostring(actionError)
    end

    -- 4. Руда: второй сундук -> основная МЭ.
    ok, _, actionError = pullFromChest(
        MAIN_ME_ADDRESS,
        MAIN_CHEST_DIRECTION,
        SECOND_CHEST_SIDE,
        ore.take.name,
        entry.takeDamage,
        oreAmount
    )

    if not ok then
        rollbackUnpaidBatch(entry, oreAmount, rewardAmount)
        return false, "Основная МЭ не приняла руду: " .. tostring(actionError)
    end

    -- 5. Награда: второй сундук -> первый.
    ok, _, actionError = transferBetweenChests(
        SECOND_CHEST_SIDE,
        FIRST_CHEST_SIDE,
        ore.give.name,
        entry.giveDamage,
        rewardAmount
    )

    if not ok then
        return false,
            "Руда уже принята, но награда осталась во втором сундуке: "
            .. tostring(actionError)
    end

    -- 6. Награда: первый сундук -> ME Chest -> ячейка.
    ok, _, actionError = pullFromChest(
        CELL_ME_ADDRESS,
        CELL_CHEST_DIRECTION,
        FIRST_CHEST_SIDE,
        ore.give.name,
        entry.giveDamage,
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
    local chestsOk, chestError = serviceChestsEmpty()
    if not chestsOk then
        setStatus(chestError, 0xFF0000)
        return false
    end

    setStatus("Считываю содержимое ячейки...", 0xFFFFFF)

    local plan, planError = createExchangePlan()
    if not plan then
        setStatus(planError, 0xFF0000)
        return false
    end

    if #plan == 0 then
        setStatus("В ячейке нет руды в количестве для обмена.", 0xFFFF00)
        return true
    end

    local sessionOres = 0
    local sessionRewards = 0

    for _, entry in ipairs(plan) do
        local remainingGroups = entry.groups

        while remainingGroups > 0 do
            if not playerIsOnPim() then
                setStatus("Вы сошли с PIM. Обмен остановлен.", 0xFF0000)
                return false
            end

            local batchGroups = math.min(
                remainingGroups,
                getMaxBatchGroups(entry, remainingGroups)
            )

            local batchOre = batchGroups * entry.takeAmount
            local batchReward = batchGroups * entry.giveAmount

            setStatus(
                string.format(
                    "Меняю %d %s на %d %s",
                    batchOre,
                    entry.ore.take.label,
                    batchReward,
                    entry.ore.give.label
                ),
                0xFFFFFF
            )

            local ok, batchError, accepted, rewarded = processBatch(
                entry,
                batchGroups
            )

            if not ok then
                setStatus("ОШИБКА: " .. tostring(batchError), 0xFF0000)
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
        end
    end

    -- Диск и экран обновляются только один раз после всей операции.
    saveTotalOres()
    saveStats()
    updInfo("ingots")

    setStatus(
        string.format(
            "Обмен окончен! Переработано: %d руды → %d слитков",
            sessionOres,
            sessionRewards
        ),
        0xFFFFFF
    )

    return true
end

-- ============================================================
-- АДМИНИСТРАТОРСКОЕ СКАНИРОВАНИЕ
-- ============================================================
local function isAdmin(user)
    for _, adminUser in pairs(table.pack(computer.users())) do
        if adminUser == user then return true end
    end
    return false
end

local function scanExchangeConfiguration()
    computer.beep(1500, 0.1)

    for i = 5, 1, -1 do
        center(h - 14, string.format(
            "Начну сканировать инвентарь через %d сек...",
            i
        ), 0x505050)
        os.sleep(1)
    end

    center(h - 14, "Сканирую...", 0xFFFFFF)
    computer.beep(1500, 0.8)

    if pim.getInventoryName() ~= "pim" then
        ore_list = {}
        local data = pim.getAllStacks(0)
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
        center(h - 14, "Обмен записан!", 0x00FF00)
        computer.beep(500, 0.2)
        updInfo()
    else
        center(h - 14, "Не увидел инвентарь!", 0xFF0000)
        computer.beep(2000, 0.2)
        computer.beep(2000, 0.2)
    end

    os.sleep(1)

    for i = 5, 1, -1 do
        center(h - 14, string.format("Заработаю через %d сек...", i), 0x505050)
        os.sleep(1)
    end

    center(h - 14, "Обновлю доступные руды и связь с МЭ как только наступите", 0x505050)
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
    elseif eventName == "player_on" then
        if not updInfo("ingots") then return end

        center(
            h - 15,
            string.format("Приветствую, %s! Начинаю обмен", args[1]),
            0xFFFFFF
        )

        stats.ores = 0
        stats.ingots = 0
        processCellExchange()
    elseif eventName == "player_off" then
        if not updInfo("ingots") then return end

        center(
            h - 15,
            "Для обмена встаньте на PIM и не сходите до окончания обмена",
            0xFFFFFF
        )

        center(
            h - 14,
            "Обновлю доступные руды и связь с МЭ как только наступите",
            0x505050
        )
    elseif eventName == "touch"
        and args[2] >= w - 38
        and args[3] >= h - 1
        and isAdmin(args[5]) then
        scanExchangeConfiguration()
    end
end

-- ============================================================
-- ЗАПУСК
-- ============================================================
local function main()
    gpu.fill(1, 1, w, h, " ")

    if updInfo() then
        center(
            h - 15,
            "Для обмена встаньте на PIM и не сходите до окончания обмена",
            0xFFFFFF
        )
    end

    center(
        h - 14,
        "Обновлю доступные руды и связь с МЭ как только наступите",
        0x505050
    )

    drawLogo(8, h - 12, accent)

    while true do
        handleEvent(event.pull(1))
    end
end

while true do
    local success, err = pcall(main)

    if not success and #tostring(err) > 0 then
        local errorFile = io.open(currDir .. "/exchanger_errors.txt", "ab")
        if errorFile then
            errorFile:write(tostring(err) .. "\n")
            errorFile:close()
        end
        computer.beep(2000, 3)
    elseif not success then
        break
    end
end
