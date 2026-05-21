--v2.2
--[[
    https://pastebin.com/jaYhuD0k - serafim7 version
    https://pastebin.com/JXdK09U7 - Rijen version
 
    https://i.imgur.com/UCfMoT7.png - обустройство
    Адаптер подключен к интерфесу на котором стоит PIM. В адаптере стоит настроенный МФУ для общения с самим PIM'ом
 
    https://i.imgur.com/0YMfy7h.png - порядок выставления руд в инвентаре для автоматической настройки
    https://i.imgur.com/QuqiGbi.png - результат
    https://youtu.be/YoQVaSJRicc
]]
--
 
local unicode = require("unicode")
local computer = require("computer")
local com = require("component")
local event = require("event")
local fs = require("filesystem")
local shell = require("shell")
local inspect = {}
if not fs.exists("/lib/inspect.lua") then
    shell.execute("wget -q https://raw.githubusercontent.com/kikito/inspect.lua/master/inspect.lua /lib/inspect.lua")
end
inspect = require("inspect")
 
local me = com.isAvailable("me_interface") and com.me_interface or error("Интерфейс не подключен")
local pim = com.isAvailable("pim") and com.pim or error("PIM не подключен")
local gpu = com.gpu
 
local w, h = 80, 50
local defBG, defFG = gpu.getBackground(), gpu.getForeground()
gpu.setResolution(w, h)
 
-- Таблица обмена (оставляем как есть, но добавим возможность динамической замены)
local ore_list = {
    {
        take = { label = "Алмазная руда", name = "minecraft:diamond_ore", amount = 1 },
        give = { label = "Алмаз", name = "minecraft:diamond", amount = 2 }
    },
    {
        take = { label = "Железная руда", name = "minecraft:iron_ore", amount = 9 },
        give = { label = "Железный слиток", name = "minecraft:iron_ingot", amount = 22 }
    },
    {
        take = { label = "Золотая руда", name = "minecraft:gold_ore", amount = 9 },
        give = { label = "Золотой слиток", name = "minecraft:gold_ingot", amount = 22 }
    },
    {
        take = { label = "Лазуритовая руда", name = "minecraft:lapis_ore", amount = 1 },
        give = { label = "Лазурит", name = "minecraft:dye", damage = 4.0, amount = 12 }
    },
    {
        take = { label = "Красная руда", name = "minecraft:redstone_ore", amount = 1 },
        give = { label = "Блок красного камня", name = "minecraft:redstone_block", amount = 1 }
    },
    {
        take = { label = "Угольная руда", name = "minecraft:coal_ore", amount = 1 },
        give = { label = "Уголь", name = "minecraft:coal", amount = 3 }
    },
    {
        take = { label = "Руда истинного кварца", name = "appliedenergistics2:tile.OreQuartz", amount = 1 },
        give = { label = "Кристалл ист. кварца", name = "appliedenergistics2:item.ItemMultiMaterial", amount = 3 }
    },
    {
        take = { label = "Заряж. руда ист. квар", name = "appliedenergistics2:tile.OreQuartzCharged", amount = 1 },
        give = { label = "Заряж. крист. кварца", name = "appliedenergistics2:item.ItemMultiMaterial", damage = 1.0, amount = 3 }
    },
    {
        take = { label = "Кварцевая руда", name = "minecraft:quartz_ore", amount = 1 },
        give = { label = "Кварц", name = "minecraft:quartz", amount = 4 }
    },
    {
        take = { label = "Медная руда", name = "IC2:blockOreCopper", amount = 9 },
        give = { label = "Медный слиток", name = "IC2:itemIngot", damage = 0.0, amount = 22 }
    },
    {
        take = { label = "Оловянная руда", name = "IC2:blockOreTin", amount = 9 },
        give = { label = "Оловянный слиток", name = "IC2:itemIngot", damage = 1.0, amount = 22 }
    },
    {
        take = { label = "Серебряная руда", name = "ThermalFoundation:Ore", damage = 2.0, amount = 7 },
        give = { label = "Серебрянный слиток", name = "IC2:itemIngot", damage = 6.0, amount = 22 }
    },
    {
        take = { label = "Платиновая руда", name = "ThermalFoundation:Ore", damage = 5.0, amount = 1 },
        give = { label = "Измельчённая платина", name = "ThermalFoundation:material", damage = 37.0, amount = 2 }
    },
    {
        take = { label = "Никелевая руда", name = "ThermalFoundation:Ore", damage = 4.0, amount = 1 },
        give = { label = "Никелевый слиток", name = "ThermalFoundation:material", damage = 68.0, amount = 2 }
    },
    {
        take = { label = "Дракониевая руда", name = "DraconicEvolution:draconiumOre", amount = 1 },
        give = { label = "Дракониевая пыль", name = "DraconicEvolution:draconiumDust", amount = 2 }
    }
}
local currDir = shell.getWorkingDirectory()
local oresPath = currDir .. "/exchanger_ores.txt"
 
if fs.exists(oresPath) then
    local file = io.open(oresPath, "r")
    ore_list = file:read("*all")
    file:close()
    local success, ore_table = pcall(load("return " .. ore_list))
    if not success then
        return error(string.format(
            "Ошибка в таблице %s\nНеобходимо исправить или создать заново, удалив текущую\nУдалить - rm exchanger_ores.txt",
            oresPath))
    end
    ore_list = ore_table
end
 
local function saveOres(ores)
    io.open(oresPath, "w"):write(inspect(ores)):close()
end
 
local function center(height, text, color)
    gpu.fill(1, height, w, 1, " ")
    gpu.setForeground(color)
    gpu.set(math.floor(w / 2 - unicode.len(text) / 2), height, text)
end
 
local function formatNumber(num)
    local symbols = { "", "K", "M", "B", "T" }
    local formattedNum = num
    local symbolIndex = 1
 
    while formattedNum >= 1000 do
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
    local totalOre = 0
 
    for _, ore in ipairs(ore_list) do
        local success, item = pcall(function()
            return me.getItemDetail({ id = ore.give.name, dmg = ore.give.damage }).basic()
        end)
 
        if success and item ~= nil then
            ore.size = item.qty
            totalOre = totalOre + item.qty
            ore.maxSize = item.max_size
        else
            ore.size = 0
            ore.maxSize = 1
        end
    end
 
    if totalOre == 0 then
        return false
    end
 
    return true
end
 
local function drawInfo(type)
    local line = 2
 
    if type == "full" then
        gpu.fill(1, 1, w, h - 16, " ")
    end
 
    for i, ore in pairs(ore_list) do
        local print_row = line + i
 
        if type == "full" then
            gpu.setForeground(0xFF00FF)
            local takeAmount = formatNumber(ore.take.amount)
            gpu.set(29 - #takeAmount, print_row, takeAmount)
            gpu.set(33, print_row, formatNumber(ore.give.amount))
 
            gpu.setForeground(0x00ff00)
            gpu.set(5, print_row, ore.take.label)
            gpu.set(42, print_row, ore.give.label)
 
            gpu.setForeground(0xFFFF00)
            gpu.set(30, print_row, unicode.char(0xFF1E))
            gpu.set(63, print_row, "Доступно:")
            gpu.setForeground(0x202020)
            gpu.set(2, print_row + 1, string.rep("═", w - 2))
        end
 
        if type == "full" or type == "ingots" then
            gpu.fill(73, print_row, w - 73, 1, " ")
            gpu.setForeground(0xFF00FF)
            gpu.set(73, print_row, formatNumber(ore.size or 0))
        end
 
        line = line + 1
    end
end
 
local function updInfo(type)
    type = type or "full"
    local check = updIngotsSize()
 
    if not check then
        center(h - 15, "Нет соединения с МЭ или руды не настроены", 0xff0000)
    end
    drawInfo(type)
 
    return check
end
 
 
local function giveIngot(toGive, ore, index)
    local totalGive = 0
    while totalGive < toGive do
        local giveSize = math.min(toGive - totalGive, ore.maxSize)
        local success, res = pcall(me.exportItem, { id = ore.give.name, dmg = ore.give.damage }, "UP", giveSize)
 
        if success and res.size > 0 then
            totalGive = totalGive + res.size
            ore_list[index].size = ore_list[index].size - giveSize
        else
            center(h - 15, "Oсвободите место в инвентаре", 0xff0000)
            center(h - 14, string.format("Ожидаю выдать %d %s", toGive - totalGive, ore.give.label), 0xFFFFFF)
            os.sleep(1)
        end
    end
end
 
 
local function exchangeOre(slot, ore, index)
    local curSlot = pim.getStackInSlot(slot)
    if curSlot == nil then
        center(h - 14, "Вы сошли с PIM, обмен прерван. (Не удалось прочесть слот)", 0xff0000)
        os.sleep(1)
        gpu.fill(1, h - 14, w, 1, " ")
        return false
    end
 
    local userOreSize = curSlot.qty
    local takeSize = userOreSize - math.fmod(userOreSize, ore.take.amount)
    if takeSize == 0 or userOreSize < takeSize then
        return true
    end
    local giveSize = userOreSize * ore.give.amount
 
    if ore.size < giveSize then
        center(h - 14, string.format("%s недостаточно для обмена", ore.give.label), 0xff0000)
        os.sleep(2)
        gpu.fill(1, h - 14, w, 1, " ")
        return false
    end
 
    local takedOre = pim.pushItem("DOWN", slot, takeSize)
 
    if takedOre == nil then
        center(h - 14, "Вы сошли с PIM, обмен прерван. (Не удалось извлечь руду)", 0xff0000)
        os.sleep(1)
        return false
    elseif takedOre == 0 then
        center(h - 14, "В выбраном слоте руды нет.. А была.. Хмм...", 0x505050)
        os.sleep(1)
    else
        giveSize = math.floor(takedOre / ore.take.amount) * ore.give.amount
        center(h - 14, string.format("Меняю %d %s на %d %s", takedOre, ore.take.label, giveSize, ore.give.label),
            0xffffff)
        giveIngot(giveSize, ore, index)
    end
    gpu.fill(1, h - 14, w, 1, " ")
    return true
end
 
local function checkInventory()
    local wait = 2
    for i = wait, 1, -1 do
        center(h - 14, string.format("Обмен через %d сек...", i), 0x505050)
        os.sleep(1)
    end
    local size = pim.getInventorySize()
    local data = pim.getAllStacks(0)
    local forceBreak = false
 
    for slot = 1, size do
        if forceBreak then
            break
        elseif data[slot] then
            for index, ore in pairs(ore_list) do
                if data[slot].id == ore.take.name and data[slot].dmg == ore.take.damage then
                    local check = exchangeOre(slot, ore, index)
                    if not check then
                        forceBreak = true
                        break
                    end
                end
            end
        end
    end
 
    drawInfo("ingots")
 
    if pim.getInventoryName() ~= "pim" then
        center(h - 15, "Обмен окончен! Приходите ещё!", 0xffffff)
        return checkInventory()
    else
        event.push("player_off")
    end
end
 
local function isAdmin(user)
    local adminUsers = table.pack(computer.users())
    local check = false
    for _, adminUser in pairs(adminUsers) do
        if adminUser == user then
            check = true
            break
        end
    end
    return check
end
 
local function handleEvent(eventName, ...)
    local args = { ... }
    if eventName == "interrupted" then
        gpu.setBackground(defBG)
        gpu.setForeground(defFG)
        gpu.fill(1, 1, w, h, " ")
        os.exit()
        return true
    elseif eventName == "player_on" then
        local check = updInfo("ingots")
        if not check then
            return
        end
        center(h - 15, string.format("Приветствую, %s! Начинаю обмен", args[1]), 0xffffff)
        checkInventory()
    elseif eventName == "player_off" then
        local check = updInfo("ingots")
        if not check then
            return
        end
        center(h - 15, "Для обмена встаньте на PIM и не сходите до окончания обмена", 0xffffff)
        center(h - 14, "Обновлю доступные руды и связь с МЭ как только наступите", 0x505050)
    elseif eventName == "touch" then
        if args[2] >= w - 38 and args[3] >= h - 1 then
            local admin = isAdmin(args[5])
            if not admin then
                return
            end
 
            computer.beep(1500, 0.1)
            local wait = 5
            for i = wait, 1, -1 do
                center(h - 14, string.format("Начну сканировать инвентарь через %d сек...", i), 0x505050)
                os.sleep(1)
            end
 
            center(h - 14, "Сканирую...", 0xffffff)
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
                            take = { label = data[i].display_name, name = data[i].id, damage = data[i].dmg, amount = math.floor(data[i].qty) },
                            give = { label = data[i + 1].display_name, name = data[i + 1].id, damage = data[i + 1].dmg, amount = math.floor(data[i + 1].qty) }
                        })
                    end
                    i = i + 2
                end
                saveOres(ore_list)
                center(h - 14, "Обмен записан!", 0x00ff00)
                computer.beep(500, 0.2)
                updInfo()
            else
                center(h - 14, "Не увидел инвентарь!", 0xff0000)
                computer.beep(2000, 0.2)
                computer.beep(2000, 0.2)
            end
            os.sleep(1)
 
            local wait = 9
            for i = wait, 1, -1 do
                center(h - 14, string.format("Заработаю через %d сек...", i), 0x505050)
                os.sleep(1)
            end
            center(h - 14, "Обновлю доступные руды и связь с МЭ как только наступите", 0x505050)
        end
    end
end
 
local function drawDescription(x, y, fore, back)
    local img = [[
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢀⡐⢆⠆⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠀⠀⠀⠀⡀⠀⠀⠀⠀⠀⠀⠀⢀⠀⠠⡐⣄⢢⡐⢄⢢⡐⣄⠂⡄⠀⠀⢄⢢⢰⣀⢦⡐⣄⢢⡐⠄⣂⠆⠀⠀⢀⡐⢦⠹⠌⠀⢀⡰⢠⠀⠐⣠⠀⠀⠀⠀⠀⠀⠀⠀⠄⡐⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠀⠀⠀⠀⢡⠂⡄⠀⠀⠀⠀⠌⡤⠃⠀⢳⡌⠃⠘⠈⠂⠑⠈⠑⠀⠀⡜⡢⠍⠂⠑⠈⠑⠈⠃⠀⠐⣌⠎⢀⡐⠦⣜⠂⠁⠀⠀⠀⡜⡡⠂⠘⠤⡁⠀⠀⠀⠀⠀⠀⠀⢂⠱⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠀⠀⠀⠀⢢⠑⡌⢢⠀⠤⣉⡜⣰⠁⠀⡣⢝⠀⠀⠀⠀⠀⠀⠀⠀⢀⠳⣹⢌⡱⢢⡱⢌⢲⢰⡀⠀⢎⠺⣤⣙⠳⣀⠀⠀⠀⠀⠠⣙⠦⠁⢨⣑⠂⠀⠀⠀⠀⠀⠀⠀⢌⠳⡀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠀⠀⠀⠀⢢⡑⠈⠒⡭⠒⠌⠸⣡⠃⠀⣙⠮⡄⠀⠀⠀⠀⠀⠀⠀⠀⠁⠀⠈⠁⠁⠉⣈⠞⡢⠄⠈⢎⡳⠂⠉⠳⢆⡆⣀⠀⠀⠐⡌⠦⠁⠠⣃⠎⠀⠀⠀⠀⠀⠀⠀⠌⢒⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠒⡄⠁⠀⠀⠁⠀⠰⣡⠂⠀⠈⠸⣑⢋⢆⢳⡘⣔⠣⢆⢠⠱⣊⡕⣎⢖⡱⢎⠞⠁⠀⠈⣎⠱⠀⠀⠀⠈⠲⣡⠢⠄⠀⡜⡡⠂⠐⡥⢊⡴⢡⠎⡤⢁⠆⠀⠘⡀⠎⡐⢂⠰⠀⠆⡀⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠁⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠈⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠹⢌⡁⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠐⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
    ]]
    fore = fore or 0xffffff
    back = back or 0x0
    gpu.setForeground(fore)
    local i = 0
    for line in img:gmatch("([^\n]*)\n?") do
        gpu.set(x, y + i, line)
        i = i + 1
    end
 
    gpu.setForeground(0x444444)
    gpu.set(w - 38, h - 1, "Авторы: ")
    gpu.setForeground(0x64fff2)
    gpu.set(w - 30, h - 1, "serafim7, Rijen, VishelPokurit")
    gpu.setBackground(defBG)
    gpu.setForeground(defFG)
end
 
 
local function main()
    gpu.fill(1, 1, w, h, " ")
    local check = updInfo()
    if check then
        center(h - 15, "Для обмена встаньте на PIM и не сходите до окончания обмена", 0xffffff)
    end
    center(h - 14, "Обновлю доступные руды и связь с МЭ как только наступите", 0x505050)
    drawDescription(1, h - 13, 0x00a400)
 
    while true do
        handleEvent(event.pull(1))
    end
end
 
while true do
    local success, err = pcall(main)
    if not success then
        if #err == 0 then
            break
        else
            io.open(currDir .. "/exchanger_errors.txt", "ab"):write(err .. "\n"):close()
            computer.beep(2000, 3)
        end
    end
end
