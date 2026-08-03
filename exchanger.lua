-- terminal_hardware_scan.lua
-- Безопасный сканер оборудования терминала обменника.
-- Записывает адреса компонентов, стороны сундуков, направления ME Interface
-- и готовый блок настроек в terminal_hardware_report.txt.
--
-- ПОДГОТОВКА ПЕРЕД ЗАПУСКОМ:
-- 1. В ПЕРВЫЙ сундук положить ровно 1 блок земли.
-- 2. Во ВТОРОЙ сундук положить ровно 1 блок булыжника.
-- 3. В ячейке ME Chest должна быть минимум 1 железная руда.
-- 4. В основной МЭ должен быть минимум 1 железный слиток.
-- 5. Настроечные слоты обоих ME Interface должны быть пустыми.
--
-- Активный тест переносит максимум по одному тестовому предмету
-- и сразу пытается вернуть его обратно в исходную МЭ-сеть.

local component = require("component")
local computer = require("computer")
local shell = require("shell")
local serialization = require("serialization")
local sides = require("sides")

local REPORT_FILE =
    shell.getWorkingDirectory() .. "/terminal_hardware_report.txt"

-- true  = определить точные направления exportItem/pullItem;
-- false = только пассивное сканирование без перемещения предметов.
local ACTIVE_DIRECTION_TEST = true

local FIRST_CHEST_MARKER = {
    id = "minecraft:dirt",
    damage = 0,
    label = "Земля"
}

local SECOND_CHEST_MARKER = {
    id = "minecraft:cobblestone",
    damage = 0,
    label = "Булыжник"
}

local CELL_TEST_ITEM = {
    id = "minecraft:iron_ore",
    damage = 0,
    label = "Железная руда"
}

local MAIN_TEST_ITEM = {
    id = "minecraft:iron_ingot",
    damage = 0,
    label = "Железный слиток"
}

local DIRECTIONS = {
    "DOWN",
    "UP",
    "NORTH",
    "SOUTH",
    "WEST",
    "EAST"
}

local SIDE_NAMES = {
    [sides.bottom] = "BOTTOM",
    [sides.top] = "TOP",
    [sides.back] = "BACK",
    [sides.front] = "FRONT",
    [sides.right] = "RIGHT",
    [sides.left] = "LEFT"
}

local report = {}

local function add(text)
    text = tostring(text or "")
    report[#report + 1] = text
    print(text)
end

local function separator()
    add(string.rep("=", 64))
end

local function subSeparator()
    add(string.rep("-", 64))
end

local function safeSerialize(value)
    local ok, result = pcall(serialization.serialize, value)
    if ok then
        return result
    end
    return "<ошибка сериализации: " .. tostring(result) .. ">"
end

local function sleep(seconds)
    local deadline = computer.uptime() + (tonumber(seconds) or 0)
    while computer.uptime() < deadline do
        computer.pullSignal(math.max(0, deadline - computer.uptime()))
    end
end

local function methodExists(address, methodName)
    local methods = component.methods(address) or {}
    return methods[methodName] ~= nil
end

local function invoke(address, methodName, ...)
    return pcall(component.invoke, address, methodName, ...)
end

local function stackName(stack)
    if not stack then
        return nil
    end
    return stack.name or stack.id or stack.internalName
end

local function stackDamage(stack)
    if not stack then
        return 0
    end
    return tonumber(stack.damage or stack.dmg or stack.meta) or 0
end

local function stackAmount(stack)
    if not stack then
        return 0
    end
    return math.max(
        0,
        math.floor(
            tonumber(
                stack.size
                or stack.qty
                or stack.amount
                or stack.count
            ) or 0
        )
    )
end

local function resultAmount(result, extraResult)
    local function read(value)
        if type(value) == "number" then
            return math.max(0, math.floor(value))
        end

        if type(value) == "table" then
            return math.max(
                0,
                math.floor(
                    tonumber(
                        value.size
                        or value.qty
                        or value.amount
                        or value.count
                        or value.exported
                        or value[1]
                    ) or 0
                )
            )
        end

        return 0
    end

    local amount = read(result)
    if amount > 0 then
        return amount
    end

    return read(extraResult)
end

local function getInventorySize(transposer, side)
    local ok, size = pcall(transposer.getInventorySize, side)

    if not ok or not tonumber(size) then
        return nil
    end

    return math.floor(tonumber(size))
end

local function getInventoryName(transposer, side)
    local ok, name = pcall(transposer.getInventoryName, side)

    if ok then
        return name
    end

    return nil
end

local function countItemInInventory(
    transposer,
    side,
    itemId,
    damage
)
    local size = getInventorySize(transposer, side)

    if not size then
        return 0
    end

    local total = 0

    for slot = 1, size do
        local ok, stack = pcall(
            transposer.getStackInSlot,
            side,
            slot
        )

        if ok
            and stack
            and stackName(stack) == itemId
            and stackDamage(stack) == (damage or 0) then

            total = total + stackAmount(stack)
        end
    end

    return total
end

local function findItemSlot(
    transposer,
    side,
    itemId,
    damage
)
    local size = getInventorySize(transposer, side)

    if not size then
        return nil
    end

    for slot = 1, size do
        local ok, stack = pcall(
            transposer.getStackInSlot,
            side,
            slot
        )

        if ok
            and stack
            and stackName(stack) == itemId
            and stackDamage(stack) == (damage or 0)
            and stackAmount(stack) > 0 then

            return slot, stackAmount(stack)
        end
    end

    return nil
end

local function getNetworkItems(address)
    local methods = component.methods(address) or {}
    local methodOrder = {
        "getItemsInNetwork",
        "getAvailableItems"
    }

    for _, methodName in ipairs(methodOrder) do
        if methods[methodName] ~= nil then
            local ok, items = invoke(address, methodName)

            if ok and type(items) == "table" then
                return items, methodName, nil
            end
        end
    end

    return nil, nil, "не удалось получить список предметов"
end

local function readNetworkInfo(address)
    local items, usedMethod, readError = getNetworkItems(address)

    local info = {
        address = address,
        items = items,
        usedMethod = usedMethod,
        error = readError,
        recordCount = 0,
        totalAmount = 0,
        sample = {},
        amounts = {}
    }

    if not items then
        return info
    end

    for _, item in pairs(items) do
        if type(item) == "table" then
            local name = stackName(item)
            local damage = stackDamage(item)
            local amount = stackAmount(item)

            info.recordCount = info.recordCount + 1
            info.totalAmount = info.totalAmount + amount

            if name then
                local key = tostring(name)
                    .. ":"
                    .. tostring(math.floor(damage))

                info.amounts[key] =
                    (info.amounts[key] or 0) + amount

                if #info.sample < 12 then
                    info.sample[#info.sample + 1] = {
                        name = name,
                        damage = damage,
                        amount = amount
                    }
                end
            end
        end
    end

    return info
end

local function networkAmount(info, itemId, damage)
    if not info then
        return 0
    end

    local key = tostring(itemId)
        .. ":"
        .. tostring(math.floor(tonumber(damage) or 0))

    return math.floor(tonumber(info.amounts[key]) or 0)
end

local function makeFingerprint(item)
    local fingerprint = {
        id = stackName(item),
        dmg = stackDamage(item)
    }

    if type(item) == "table"
        and item.nbt_hash ~= nil then

        fingerprint.nbt_hash = item.nbt_hash
    end

    return fingerprint
end

local function findNetworkItem(info, itemId, damage)
    if not info or type(info.items) ~= "table" then
        return nil
    end

    for _, item in pairs(info.items) do
        if type(item) == "table"
            and stackName(item) == itemId
            and stackDamage(item) == (damage or 0)
            and stackAmount(item) > 0 then

            return item
        end
    end

    return nil
end

local function scanTransposers()
    local results = {}

    separator()
    add("TRANSPOSER И СОСЕДНИЕ ИНВЕНТАРИ")
    separator()

    local number = 0

    for address in component.list("transposer") do
        number = number + 1

        local transposer = component.proxy(address)
        local result = {
            address = address,
            proxy = transposer,
            firstChestSide = nil,
            secondChestSide = nil,
            inventories = {}
        }

        add("")
        add("TRANSPOSER №" .. tostring(number))
        add("Адрес: " .. tostring(address))

        for side = 0, 5 do
            local size = getInventorySize(transposer, side)

            if size then
                local inventoryName =
                    getInventoryName(transposer, side)

                local entry = {
                    side = side,
                    sideName = SIDE_NAMES[side] or tostring(side),
                    inventoryName = inventoryName,
                    size = size
                }

                result.inventories[#result.inventories + 1] =
                    entry

                add("")
                add(
                    "Сторона: "
                    .. tostring(entry.sideName)
                    .. " ("
                    .. tostring(side)
                    .. ")"
                )
                add(
                    "Инвентарь: "
                    .. tostring(inventoryName)
                )
                add("Размер: " .. tostring(size))

                local firstMarkerAmount =
                    countItemInInventory(
                        transposer,
                        side,
                        FIRST_CHEST_MARKER.id,
                        FIRST_CHEST_MARKER.damage
                    )

                local secondMarkerAmount =
                    countItemInInventory(
                        transposer,
                        side,
                        SECOND_CHEST_MARKER.id,
                        SECOND_CHEST_MARKER.damage
                    )

                if firstMarkerAmount > 0 then
                    result.firstChestSide = side
                    add(
                        ">>> ПЕРВЫЙ СУНДУК: найдена метка "
                        .. FIRST_CHEST_MARKER.label
                    )
                end

                if secondMarkerAmount > 0 then
                    result.secondChestSide = side
                    add(
                        ">>> ВТОРОЙ СУНДУК: найдена метка "
                        .. SECOND_CHEST_MARKER.label
                    )
                end

                local shown = 0

                for slot = 1, size do
                    local ok, stack = pcall(
                        transposer.getStackInSlot,
                        side,
                        slot
                    )

                    if ok and stack and shown < 10 then
                        shown = shown + 1

                        add(
                            "Слот "
                            .. tostring(slot)
                            .. ": "
                            .. tostring(stackName(stack))
                            .. " | damage="
                            .. tostring(stackDamage(stack))
                            .. " | количество="
                            .. tostring(stackAmount(stack))
                        )
                    end
                end

                if shown == 0 then
                    add("Содержимое: пусто")
                elseif shown >= 10 then
                    add(
                        "Показаны первые 10 занятых слотов."
                    )
                end
            end
        end

        results[#results + 1] = result

        subSeparator()
    end

    if number == 0 then
        add("TRANSPOSER НЕ НАЙДЕН")
    end

    return results
end

local function chooseBridgeTransposer(results)
    for _, result in ipairs(results) do
        if result.firstChestSide ~= nil
            and result.secondChestSide ~= nil then

            return result
        end
    end

    return nil
end

local function scanInterfaces()
    local results = {}

    separator()
    add("ME INTERFACE")
    separator()

    local number = 0

    for address in component.list("me_interface") do
        number = number + 1

        local info = readNetworkInfo(address)
        results[#results + 1] = info

        add("")
        add("ME INTERFACE №" .. tostring(number))
        add("Адрес: " .. tostring(address))
        add(
            "Метод чтения сети: "
            .. tostring(info.usedMethod or info.error)
        )
        add(
            "Видов предметов: "
            .. tostring(info.recordCount)
        )
        add(
            "Общее количество предметов: "
            .. tostring(info.totalAmount)
        )

        add(
            "Железной руды: "
            .. tostring(
                networkAmount(
                    info,
                    CELL_TEST_ITEM.id,
                    CELL_TEST_ITEM.damage
                )
            )
        )

        add(
            "Железных слитков: "
            .. tostring(
                networkAmount(
                    info,
                    MAIN_TEST_ITEM.id,
                    MAIN_TEST_ITEM.damage
                )
            )
        )

        if #info.sample > 0 then
            add("")
            add("Пример предметов сети:")

            for _, item in ipairs(info.sample) do
                add(
                    "- "
                    .. tostring(item.name)
                    .. " | damage="
                    .. tostring(item.damage)
                    .. " | количество="
                    .. tostring(item.amount)
                )
            end
        end

        add("")
        add("canExport:")

        for _, direction in ipairs(DIRECTIONS) do
            local ok, result = invoke(
                address,
                "canExport",
                direction
            )

            add(
                "- "
                .. direction
                .. ": вызов="
                .. tostring(ok)
                .. ", результат="
                .. tostring(result)
            )
        end

        add("")
        add("Конфигурация интерфейса:")

        if methodExists(
            address,
            "getInterfaceConfiguration"
        ) then
            local ok, config = invoke(
                address,
                "getInterfaceConfiguration"
            )

            if ok then
                add(safeSerialize(config))
            else
                add("Ошибка: " .. tostring(config))
            end
        else
            add("Метод отсутствует")
        end

        add("")
        add("Ключевые методы:")

        local importantMethods = {
            "exportItem",
            "pullItem",
            "canExport",
            "getItemsInNetwork",
            "getAvailableItems",
            "getItemDetail",
            "getInterfaceConfiguration",
            "setInterfaceConfiguration",
            "getInventorySize",
            "getStackInSlot"
        }

        for _, methodName in ipairs(importantMethods) do
            add(
                "- "
                .. methodName
                .. ": "
                .. tostring(
                    methodExists(address, methodName)
                )
            )
        end

        subSeparator()
    end

    if number == 0 then
        add("ME INTERFACE НЕ НАЙДЕН")
    end

    return results
end

local function classifyInterfaces(interfaceResults)
    if #interfaceResults < 2 then
        return nil, nil, "найдено меньше двух ME Interface"
    end

    local sorted = {}

    for _, info in ipairs(interfaceResults) do
        sorted[#sorted + 1] = info
    end

    table.sort(
        sorted,
        function(a, b)
            if a.recordCount == b.recordCount then
                return a.totalAmount < b.totalAmount
            end

            return a.recordCount < b.recordCount
        end
    )

    local cellInfo = sorted[1]
    local mainInfo = sorted[#sorted]

    if cellInfo.address == mainInfo.address then
        return nil, nil, "не удалось разделить интерфейсы"
    end

    return cellInfo, mainInfo, nil
end

local function activeDirectionTest(
    interfaceInfo,
    bridge,
    testItem,
    expectedChestSide
)
    local result = {
        direction = nil,
        chestSide = nil,
        rollback = false,
        message = nil
    }

    if not ACTIVE_DIRECTION_TEST then
        result.message = "активный тест выключен"
        return result
    end

    if not interfaceInfo then
        result.message = "интерфейс не определён"
        return result
    end

    if not bridge then
        result.message =
            "не найден Transposer с двумя сундуками-метками"
        return result
    end

    local networkItem = findNetworkItem(
        interfaceInfo,
        testItem.id,
        testItem.damage
    )

    if not networkItem then
        result.message =
            "в сети нет тестового предмета: "
            .. tostring(testItem.label)
        return result
    end

    local fingerprint = makeFingerprint(networkItem)

    local firstSide = bridge.firstChestSide
    local secondSide = bridge.secondChestSide
    local transposer = bridge.proxy

    for _, direction in ipairs(DIRECTIONS) do
        local okCan, canExport = invoke(
            interfaceInfo.address,
            "canExport",
            direction
        )

        if okCan and canExport == true then
            local firstBefore =
                countItemInInventory(
                    transposer,
                    firstSide,
                    testItem.id,
                    testItem.damage
                )

            local secondBefore =
                countItemInInventory(
                    transposer,
                    secondSide,
                    testItem.id,
                    testItem.damage
                )

            local okExport, exportResult, extraResult =
                invoke(
                    interfaceInfo.address,
                    "exportItem",
                    fingerprint,
                    direction,
                    1
                )

            if okExport then
                sleep(0.3)

                local firstAfter =
                    countItemInInventory(
                        transposer,
                        firstSide,
                        testItem.id,
                        testItem.damage
                    )

                local secondAfter =
                    countItemInInventory(
                        transposer,
                        secondSide,
                        testItem.id,
                        testItem.damage
                    )

                local foundSide = nil

                if firstAfter > firstBefore then
                    foundSide = firstSide
                elseif secondAfter > secondBefore then
                    foundSide = secondSide
                end

                if foundSide ~= nil then
                    result.direction = direction
                    result.chestSide = foundSide

                    local slot = findItemSlot(
                        transposer,
                        foundSide,
                        testItem.id,
                        testItem.damage
                    )

                    if slot then
                        local okPull, pullResult =
                            invoke(
                                interfaceInfo.address,
                                "pullItem",
                                direction,
                                slot,
                                1
                            )

                        sleep(0.3)

                        local remaining =
                            countItemInInventory(
                                transposer,
                                foundSide,
                                testItem.id,
                                testItem.damage
                            )

                        local before =
                            foundSide == firstSide
                            and firstBefore
                            or secondBefore

                        result.rollback =
                            okPull
                            and resultAmount(pullResult) > 0
                            and remaining <= before
                    end

                    if foundSide ~= expectedChestSide then
                        result.message =
                            "предмет попал не в ожидаемый сундук"
                    elseif not result.rollback then
                        result.message =
                            "направление найдено, но возврат предмета не подтверждён"
                    else
                        result.message = "успешно"
                    end

                    return result
                end

                local reported =
                    resultAmount(exportResult, extraResult)

                if reported > 0 then
                    result.message =
                        "интерфейс сообщил о перемещении, "
                        .. "но предмет не найден в двух сундуках"

                    return result
                end
            end
        end
    end

    result.message = "рабочее направление не найдено"
    return result
end

local function scanPim()
    separator()
    add("PIM")
    separator()

    local found = 0

    for address in component.list("pim") do
        found = found + 1
        add("Адрес: " .. tostring(address))

        local methods = {
            "getInventoryName",
            "getInventorySize",
            "getAllStacks",
            "getStackInSlot",
            "pushItem"
        }

        for _, methodName in ipairs(methods) do
            add(
                "- "
                .. methodName
                .. ": "
                .. tostring(
                    methodExists(address, methodName)
                )
            )
        end

        if methodExists(address, "getInventoryName") then
            local ok, name = invoke(
                address,
                "getInventoryName"
            )

            add(
                "Текущий инвентарь: "
                .. tostring(ok and name or "ошибка")
            )
        end

        subSeparator()
    end

    if found == 0 then
        add("PIM НЕ НАЙДЕН")
    end
end

local function scanGpu()
    separator()
    add("ЭКРАН И ВИДЕОКАРТА")
    separator()

    if component.isAvailable("gpu") then
        local gpu = component.gpu
        local width, height = gpu.getResolution()
        local maxWidth, maxHeight = gpu.maxResolution()

        add(
            "Текущее разрешение: "
            .. tostring(width)
            .. "x"
            .. tostring(height)
        )

        add(
            "Максимальное разрешение: "
            .. tostring(maxWidth)
            .. "x"
            .. tostring(maxHeight)
        )
    else
        add("GPU НЕ НАЙДЕНА")
    end
end

local function scanAllComponents()
    separator()
    add("ВСЕ КОМПОНЕНТЫ КОМПЬЮТЕРА")
    separator()

    local list = {}

    for address, componentType in component.list() do
        list[#list + 1] = {
            address = address,
            componentType = componentType
        }
    end

    table.sort(
        list,
        function(a, b)
            if a.componentType == b.componentType then
                return a.address < b.address
            end

            return a.componentType < b.componentType
        end
    )

    for _, entry in ipairs(list) do
        add(
            tostring(entry.componentType)
            .. " = "
            .. tostring(entry.address)
        )
    end
end

local function saveReport()
    local file, openError = io.open(REPORT_FILE, "w")

    if not file then
        error(
            "Не удалось открыть отчёт: "
            .. tostring(openError)
        )
    end

    file:write(table.concat(report, "\n"))
    file:write("\n")
    file:close()
end

-- ============================================================
-- ЗАПУСК
-- ============================================================

separator()
add("ОТЧЁТ ОБОРУДОВАНИЯ ТЕРМИНАЛА ОБМЕННИКА")
separator()
add("Компьютер: " .. tostring(computer.address()))
add("Uptime: " .. tostring(computer.uptime()))
add("Файл отчёта: " .. REPORT_FILE)
add(
    "Активный тест направлений: "
    .. tostring(ACTIVE_DIRECTION_TEST)
)
add("")

scanAllComponents()
scanGpu()
scanPim()

local transposerResults = scanTransposers()
local bridge = chooseBridgeTransposer(
    transposerResults
)

local interfaceResults = scanInterfaces()

local cellInfo, mainInfo, classifyError =
    classifyInterfaces(interfaceResults)

separator()
add("АВТООПРЕДЕЛЕНИЕ ДВУХ МЭ-СЕТЕЙ")
separator()

if classifyError then
    add("Ошибка: " .. tostring(classifyError))
else
    add(
        "Предполагаемая сеть ME Chest: "
        .. tostring(cellInfo.address)
    )
    add(
        "Видов предметов: "
        .. tostring(cellInfo.recordCount)
    )

    add("")
    add(
        "Предполагаемая основная МЭ-сеть: "
        .. tostring(mainInfo.address)
    )
    add(
        "Видов предметов: "
        .. tostring(mainInfo.recordCount)
    )
end

local cellTest = activeDirectionTest(
    cellInfo,
    bridge,
    CELL_TEST_ITEM,
    bridge and bridge.firstChestSide or nil
)

local mainTest = activeDirectionTest(
    mainInfo,
    bridge,
    MAIN_TEST_ITEM,
    bridge and bridge.secondChestSide or nil
)

separator()
add("РЕЗУЛЬТАТ АКТИВНОГО ТЕСТА НАПРАВЛЕНИЙ")
separator()

add("Сеть ME Chest:")
add(
    "- направление: "
    .. tostring(cellTest.direction or "UNKNOWN")
)
add(
    "- сундук у Transposer: "
    .. tostring(
        cellTest.chestSide ~= nil
        and (
            tostring(
                SIDE_NAMES[cellTest.chestSide]
                or cellTest.chestSide
            )
            .. " ("
            .. tostring(cellTest.chestSide)
            .. ")"
        )
        or "UNKNOWN"
    )
)
add("- возврат предмета: " .. tostring(cellTest.rollback))
add("- результат: " .. tostring(cellTest.message))

add("")
add("Основная МЭ-сеть:")
add(
    "- направление: "
    .. tostring(mainTest.direction or "UNKNOWN")
)
add(
    "- сундук у Transposer: "
    .. tostring(
        mainTest.chestSide ~= nil
        and (
            tostring(
                SIDE_NAMES[mainTest.chestSide]
                or mainTest.chestSide
            )
            .. " ("
            .. tostring(mainTest.chestSide)
            .. ")"
        )
        or "UNKNOWN"
    )
)
add("- возврат предмета: " .. tostring(mainTest.rollback))
add("- результат: " .. tostring(mainTest.message))

separator()
add("ГОТОВЫЙ БЛОК НАСТРОЕК")
separator()

add(
    'local CELL_ME_ADDRESS = "'
    .. tostring(
        cellInfo and cellInfo.address or "UNKNOWN"
    )
    .. '"'
)

add(
    'local MAIN_ME_ADDRESS = "'
    .. tostring(
        mainInfo and mainInfo.address or "UNKNOWN"
    )
    .. '"'
)

add(
    'local TRANSPOSER_ADDRESS = "'
    .. tostring(
        bridge and bridge.address or "UNKNOWN"
    )
    .. '"'
)

add(
    "local FIRST_CHEST_SIDE = "
    .. tostring(
        bridge
        and bridge.firstChestSide
        or "UNKNOWN"
    )
    .. " -- "
    .. tostring(
        bridge
        and bridge.firstChestSide ~= nil
        and SIDE_NAMES[bridge.firstChestSide]
        or "UNKNOWN"
    )
)

add(
    "local SECOND_CHEST_SIDE = "
    .. tostring(
        bridge
        and bridge.secondChestSide
        or "UNKNOWN"
    )
    .. " -- "
    .. tostring(
        bridge
        and bridge.secondChestSide ~= nil
        and SIDE_NAMES[bridge.secondChestSide]
        or "UNKNOWN"
    )
)

add(
    'local CELL_CHEST_DIRECTION = "'
    .. tostring(cellTest.direction or "UNKNOWN")
    .. '"'
)

add(
    'local MAIN_CHEST_DIRECTION = "'
    .. tostring(mainTest.direction or "UNKNOWN")
    .. '"'
)

separator()
add("ВАЖНЫЕ ПРЕДУПРЕЖДЕНИЯ")
separator()

if not bridge then
    add(
        "- Не найден Transposer, возле которого "
        .. "одновременно лежат земля и булыжник."
    )
end

if cellTest.direction == nil then
    add(
        "- Не определено направление интерфейса ME Chest."
    )
end

if mainTest.direction == nil then
    add(
        "- Не определено направление основного интерфейса."
    )
end

if cellTest.direction
    and not cellTest.rollback then

    add(
        "- Проверь первый сундук: тестовый предмет "
        .. "мог остаться внутри."
    )
end

if mainTest.direction
    and not mainTest.rollback then

    add(
        "- Проверь второй сундук: тестовый предмет "
        .. "мог остаться внутри."
    )
end

add("")
add("После запуска отправь мне файл:")
add(REPORT_FILE)

saveReport()

add("")
separator()
add("СКАНИРОВАНИЕ ЗАВЕРШЕНО")
separator()
add("Отчёт сохранён:")
add(REPORT_FILE)
