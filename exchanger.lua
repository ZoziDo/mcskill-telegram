local component = require("component")
local computer = require("computer")

local sidesOk, sides = pcall(require, "sides")
if not sidesOk or type(sides) ~= "table" then
  sides = {
    bottom = 0,
    top = 1,
    back = 2,
    front = 3,
    right = 4,
    left = 5,
    down = 0,
    up = 1,
  }
end

local REPORT_PATH = "/home/me_dual_system_report.txt"
local SAMPLE_ITEMS = 12
local SAMPLE_CRAFTABLES = 8

local output = {}

local function writeLine(value)
  value = tostring(value or "")
  output[#output + 1] = value
  print(value)
end

local function saveReport()
  local file, err = io.open(REPORT_PATH, "w")
  if not file then
    print("Не удалось сохранить отчёт: " .. tostring(err))
    return false
  end

  file:write(table.concat(output, "\n"))
  file:write("\n")
  file:close()
  return true
end

local function separator(title)
  writeLine("")
  writeLine("============================================================")
  writeLine(title)
  writeLine("============================================================")
end

local function shortAddress(address)
  address = tostring(address or "")
  if #address <= 12 then return address end
  return address:sub(1, 8) .. "..." .. address:sub(-4)
end

local function countTable(tbl)
  if type(tbl) ~= "table" then return 0 end
  local count = 0
  for _ in pairs(tbl) do
    count = count + 1
  end
  return count
end

local function sortedKeys(tbl)
  local result = {}
  if type(tbl) ~= "table" then return result end

  for key in pairs(tbl) do
    result[#result + 1] = tostring(key)
  end

  table.sort(result)
  return result
end

local function safeType(address)
  local ok, value = pcall(component.type, address)
  if ok then return tostring(value or "unknown") end
  return "unknown"
end

local function safeMethods(address)
  local ok, value = pcall(component.methods, address)
  if ok and type(value) == "table" then
    return value
  end
  return {}
end

local function hasMethod(methods, name)
  return type(methods) == "table" and methods[name] ~= nil
end

local function invoke(address, methodName, ...)
  local ok, a, b, c, d = pcall(
    component.invoke,
    address,
    methodName,
    ...
  )

  if not ok then
    return false, tostring(a)
  end

  return true, a, b, c, d
end

local function getDoc(address, methodName)
  local ok, value = pcall(component.doc, address, methodName)
  if ok and value then return tostring(value) end
  return nil
end

local function normalizeItem(item)
  if type(item) ~= "table" then
    return nil
  end

  local fingerprint =
    type(item.fingerprint) == "table"
    and item.fingerprint
    or item

  local id =
    fingerprint.id
    or fingerprint.name
    or item.id
    or item.name
    or item.internalName

  local damage = tonumber(
    fingerprint.dmg
    or fingerprint.damage
    or item.dmg
    or item.damage
  ) or 0

  local amount = tonumber(
    item.size
    or item.qty
    or item.count
    or item.amount
    or fingerprint.size
    or fingerprint.qty
    or fingerprint.count
  ) or 0

  local displayName =
    item.label
    or item.displayName
    or fingerprint.label
    or fingerprint.displayName

  return {
    id = id and tostring(id) or nil,
    damage = damage,
    amount = amount,
    label = displayName and tostring(displayName) or nil,
    craftable =
      item.isCraftable == true
      or fingerprint.isCraftable == true,
  }
end

local function summarizeNetworkItems(items)
  if type(items) ~= "table" then
    return {
      entries = 0,
      nonZeroEntries = 0,
      totalAmount = 0,
      samples = {},
    }
  end

  local summary = {
    entries = 0,
    nonZeroEntries = 0,
    totalAmount = 0,
    samples = {},
  }

  for _, rawItem in pairs(items) do
    summary.entries = summary.entries + 1

    local item = normalizeItem(rawItem)
    if item then
      if item.amount > 0 then
        summary.nonZeroEntries =
          summary.nonZeroEntries + 1
      end

      summary.totalAmount =
        summary.totalAmount + item.amount

      if #summary.samples < SAMPLE_ITEMS then
        summary.samples[#summary.samples + 1] = item
      end
    end
  end

  return summary
end

local function printNetworkSummary(methodName, ok, result)
  writeLine("")
  writeLine("Проверка " .. methodName .. ":")

  if not ok then
    writeLine("  ОШИБКА: " .. tostring(result))
    return nil
  end

  if type(result) ~= "table" then
    writeLine(
      "  Метод вернул не таблицу: "
      .. tostring(result)
      .. " ["
      .. type(result)
      .. "]"
    )
    return nil
  end

  local summary = summarizeNetworkItems(result)

  writeLine(
    "  Записей в ответе: "
    .. tostring(summary.entries)
  )
  writeLine(
    "  Записей с количеством > 0: "
    .. tostring(summary.nonZeroEntries)
  )
  writeLine(
    "  Суммарное количество предметов: "
    .. tostring(summary.totalAmount)
  )

  if #summary.samples == 0 then
    writeLine("  Примеры предметов: нет")
  else
    writeLine("  Первые предметы:")

    for index, item in ipairs(summary.samples) do
      writeLine(string.format(
        "    %02d. %s:%d | qty=%s | %s%s",
        index,
        tostring(item.id or "<нет id>"),
        tonumber(item.damage) or 0,
        tostring(item.amount or 0),
        tostring(item.label or "без названия"),
        item.craftable and " | craftable" or ""
      ))
    end
  end

  return summary
end

local function callCraftableGetItemStack(craftable)
  if type(craftable) ~= "table"
    or type(craftable.getItemStack) ~= "function"
  then
    return false, "getItemStack отсутствует"
  end

  local ok, result = pcall(craftable.getItemStack)
  if ok then return true, result end

  ok, result = pcall(
    craftable.getItemStack,
    craftable
  )
  if ok then return true, result end

  return false, tostring(result)
end

local function inspectCraftables(address, methods)
  if not hasMethod(methods, "getCraftables") then
    writeLine("")
    writeLine("Проверка getCraftables:")
    writeLine("  Метод отсутствует")
    return 0
  end

  local ok, craftables = invoke(
    address,
    "getCraftables"
  )

  writeLine("")
  writeLine("Проверка getCraftables:")

  if not ok then
    writeLine("  ОШИБКА: " .. tostring(craftables))
    return 0
  end

  if type(craftables) ~= "table" then
    writeLine(
      "  Вернулся тип "
      .. type(craftables)
      .. ": "
      .. tostring(craftables)
    )
    return 0
  end

  local total = countTable(craftables)
  writeLine("  Найдено шаблонов: " .. tostring(total))

  local shown = 0
  for _, craftable in pairs(craftables) do
    if shown >= SAMPLE_CRAFTABLES then break end
    shown = shown + 1

    local stackOk, stack =
      callCraftableGetItemStack(craftable)

    if stackOk and type(stack) == "table" then
      local item = normalizeItem(stack)
      if item then
        writeLine(string.format(
          "    %02d. %s:%d | %s",
          shown,
          tostring(item.id or "<нет id>"),
          tonumber(item.damage) or 0,
          tostring(item.label or "без названия")
        ))
      else
        writeLine(
          "    "
          .. tostring(shown)
          .. ". getItemStack вернул таблицу без id"
        )
      end
    else
      writeLine(
        "    "
        .. tostring(shown)
        .. ". "
        .. tostring(stack)
      )
    end
  end

  return total
end

local sideOrder = {
  {"bottom/down", 0},
  {"top/up", 1},
  {"back", 2},
  {"front", 3},
  {"right", 4},
  {"left", 5},
}

local function callSideMethod(
  address,
  methods,
  methodName,
  sideNumber,
  sideLabel
)
  if not hasMethod(methods, methodName) then
    return nil
  end

  local attempts = {
    sideNumber,
    sideLabel,
  }

  if sideNumber == 0 then
    attempts[#attempts + 1] = "down"
    attempts[#attempts + 1] = "bottom"
  elseif sideNumber == 1 then
    attempts[#attempts + 1] = "up"
    attempts[#attempts + 1] = "top"
  end

  for _, argument in ipairs(attempts) do
    local ok, value = invoke(
      address,
      methodName,
      argument
    )

    if ok and value ~= nil then
      return tostring(value), tostring(argument)
    end
  end

  return nil
end

local function inspectSides(address, methods)
  separator("ПОДКЛЮЧЁННЫЕ СТОРОНЫ")

  writeLine(
    "Стандартная нумерация OpenComputers:"
  )

  for _, side in ipairs(sideOrder) do
    writeLine(
      "  "
      .. tostring(side[2])
      .. " = "
      .. tostring(side[1])
    )
  end

  local supportsInventory =
    hasMethod(methods, "getInventoryName")
    or hasMethod(methods, "getInventorySize")

  if not supportsInventory then
    writeLine("")
    writeLine(
      "У компонента нет getInventoryName/getInventorySize."
    )
    writeLine(
      "Определить подключённую сторону пассивно невозможно."
    )
    writeLine(
      "Смотрите документацию exportItem/importItem ниже."
    )
    return
  end

  writeLine("")
  writeLine("Проверка соседних инвентарей:")

  for _, side in ipairs(sideOrder) do
    local label = side[1]
    local number = side[2]

    local inventoryName, nameArg = callSideMethod(
      address,
      methods,
      "getInventoryName",
      number,
      label
    )

    local inventorySize, sizeArg = callSideMethod(
      address,
      methods,
      "getInventorySize",
      number,
      label
    )

    writeLine(string.format(
      "  side %d (%s): name=%s; size=%s; args=%s/%s",
      number,
      label,
      tostring(inventoryName or "-"),
      tostring(inventorySize or "-"),
      tostring(nameArg or "-"),
      tostring(sizeArg or "-")
    ))
  end
end

local importantDocs = {
  "getItemsInNetwork",
  "getAvailableItems",
  "getCraftables",
  "getItemDetail",
  "exportItem",
  "importItem",
  "getInventoryName",
  "getInventorySize",
  "listSources",
}

local function inspectInterface(
  number,
  address,
  primaryAddress
)
  local componentType = safeType(address)
  local methods = safeMethods(address)

  separator(
    "МЭ-СИСТЕМА #"
    .. tostring(number)
    .. " | "
    .. componentType
    .. " | "
    .. address
  )

  writeLine(
    "Короткий адрес: "
    .. shortAddress(address)
  )
  writeLine(
    "Выбрана через component.me_interface: "
    .. (
      address == primaryAddress
      and "ДА — именно её сейчас берёт магазин"
      or "НЕТ"
    )
  )

  local methodNames = sortedKeys(methods)

  writeLine(
    "Количество методов: "
    .. tostring(#methodNames)
  )

  if #methodNames > 0 then
    writeLine("Методы:")
    local currentLine = "  "

    for _, methodName in ipairs(methodNames) do
      local addition = methodName .. ", "

      if #currentLine + #addition > 100 then
        writeLine(currentLine)
        currentLine = "  " .. addition
      else
        currentLine = currentLine .. addition
      end
    end

    if currentLine ~= "  " then
      writeLine(currentLine)
    end
  end

  writeLine("")
  writeLine("Документация важных методов:")

  for _, methodName in ipairs(importantDocs) do
    if hasMethod(methods, methodName) then
      writeLine(
        "  "
        .. methodName
        .. ": "
        .. tostring(
          getDoc(address, methodName)
          or "<документация отсутствует>"
        )
      )
    end
  end

  local bestSummary = nil
  local bestMethod = nil

  if hasMethod(methods, "getItemsInNetwork") then
    local ok, result = invoke(
      address,
      "getItemsInNetwork"
    )

    local summary = printNetworkSummary(
      "getItemsInNetwork()",
      ok,
      result
    )

    if summary then
      bestSummary = summary
      bestMethod = "getItemsInNetwork"
    end
  else
    writeLine("")
    writeLine("Проверка getItemsInNetwork:")
    writeLine("  Метод отсутствует")
  end

  if hasMethod(methods, "getAvailableItems") then
    local ok, result = invoke(
      address,
      "getAvailableItems",
      "NONE"
    )

    if not ok then
      ok, result = invoke(
        address,
        "getAvailableItems"
      )
    end

    local summary = printNetworkSummary(
      "getAvailableItems(\"NONE\") / без аргументов",
      ok,
      result
    )

    if summary
      and (
        not bestSummary
        or summary.nonZeroEntries
          > bestSummary.nonZeroEntries
      )
    then
      bestSummary = summary
      bestMethod = "getAvailableItems"
    end
  else
    writeLine("")
    writeLine("Проверка getAvailableItems:")
    writeLine("  Метод отсутствует")
  end

  local craftableCount =
    inspectCraftables(address, methods)

  inspectSides(address, methods)

  separator("ИТОГ ПО МЭ-СИСТЕМЕ #" .. tostring(number))

  writeLine(
    "Рабочий метод чтения предметов: "
    .. tostring(bestMethod or "НЕ НАЙДЕН")
  )

  if bestSummary then
    writeLine(
      "Видимых ненулевых позиций: "
      .. tostring(bestSummary.nonZeroEntries)
    )
    writeLine(
      "Суммарное количество: "
      .. tostring(bestSummary.totalAmount)
    )
  else
    writeLine("Предметы прочитать не удалось")
  end

  writeLine(
    "Количество шаблонов: "
    .. tostring(craftableCount)
  )

  return {
    address = address,
    componentType = componentType,
    primary = address == primaryAddress,
    method = bestMethod,
    nonZeroEntries =
      bestSummary and bestSummary.nonZeroEntries or 0,
    totalAmount =
      bestSummary and bestSummary.totalAmount or 0,
    craftables = craftableCount,
  }
end

local function collectMEComponents()
  local found = {}
  local addresses = {}

  local acceptedTypes = {
    me_interface = true,
    me_bridge = true,
    me_controller = true,
  }

  for address, componentType in component.list() do
    componentType = tostring(componentType or "")

    if acceptedTypes[componentType]
      or componentType:find("me_", 1, true)
      or componentType:find("ae", 1, true)
    then
      if not addresses[address] then
        addresses[address] = true
        found[#found + 1] = {
          address = address,
          componentType = componentType,
        }
      end
    end
  end

  table.sort(
    found,
    function(a, b)
      if a.componentType == b.componentType then
        return a.address < b.address
      end
      return a.componentType < b.componentType
    end
  )

  return found
end

separator("ДИАГНОСТИКА ДВУХ МЭ-СИСТЕМ")

writeLine(
  "Компьютер: "
  .. tostring(computer.address())
)
writeLine(
  "Uptime: "
  .. tostring(computer.uptime())
)
writeLine(
  "Отчёт: "
  .. REPORT_PATH
)

local primaryAddress = nil

if component.isAvailable("me_interface") then
  local ok, proxy = pcall(
    function()
      return component.me_interface
    end
  )

  if ok and type(proxy) == "table" then
    primaryAddress = proxy.address
  end
end

writeLine(
  "component.me_interface сейчас указывает на: "
  .. tostring(primaryAddress or "НЕ НАЙДЕН")
)

local meComponents = collectMEComponents()

writeLine(
  "Найдено МЭ-компонентов: "
  .. tostring(#meComponents)
)

if #meComponents == 0 then
  writeLine("")
  writeLine("ОШИБКА: МЭ-интерфейсы не обнаружены.")
  writeLine(
    "Проверьте адаптер, компонентную шину и соединение кабелем."
  )
else
  local summaries = {}

  for index, entry in ipairs(meComponents) do
    summaries[#summaries + 1] =
      inspectInterface(
        index,
        entry.address,
        primaryAddress
      )
  end

  separator("ОБЩЕЕ СРАВНЕНИЕ")

  local recommended = nil

  for index, summary in ipairs(summaries) do
    writeLine(string.format(
      "#%d %s | %s | primary=%s | items=%d | total=%s | craftables=%d | method=%s",
      index,
      summary.componentType,
      summary.address,
      summary.primary and "YES" or "NO",
      summary.nonZeroEntries,
      tostring(summary.totalAmount),
      summary.craftables,
      tostring(summary.method or "-")
    ))

    if not recommended
      or summary.nonZeroEntries
        > recommended.nonZeroEntries
      or (
        summary.nonZeroEntries
          == recommended.nonZeroEntries
        and summary.craftables
          > recommended.craftables
      )
    then
      recommended = summary
    end
  end

  writeLine("")

  if recommended then
    writeLine(
      "Предположительно основной интерфейс магазина:"
    )
    writeLine(
      "ME_INTERFACE_ADDRESS = \""
      .. tostring(recommended.address)
      .. "\""
    )

    if primaryAddress
      and recommended.address ~= primaryAddress
    then
      writeLine("")
      writeLine("ВАЖНО:")
      writeLine(
        "component.me_interface выбрал другой компонент."
      )
      writeLine(
        "Это объясняет нулевое количество и пустые шкалы."
      )
      writeLine(
        "В магазине нужно использовать component.proxy по точному адресу."
      )
    end
  end
end

separator("ПОЧЕМУ ШКАЛЫ МОГУТ БЫТЬ ПУСТЫМИ")

writeLine(
  "1. При двух me_interface магазин использует только component.me_interface."
)
writeLine(
  "   OpenComputers может выбрать не ту МЭ-сеть."
)
writeLine(
  "2. Код магазина читает getItemsInNetwork()."
)
writeLine(
  "   На другой реализации рабочим может быть getAvailableItems()."
)
writeLine(
  "3. Активная сеть может определяться как me_bridge, а не me_interface."
)
writeLine(
  "4. Интерфейс виден как компонент, но не подключён к рабочей МЭ-сети."
)
writeLine(
  "5. ID или damage отслеживаемого предмета не совпадает с данными МЭ."
)
writeLine(
  "6. При значении 0 из 5M заполненная часть шкалы закономерно имеет длину 0."
)

separator("СЛЕДУЮЩИЙ ШАГ")

writeLine(
  "Отправьте содержимое этого файла:"
)
writeLine(
  REPORT_PATH
)
writeLine("")
writeLine(
  "Команда просмотра:"
)
writeLine(
  "cat " .. REPORT_PATH
)

if saveReport() then
  writeLine("")
  writeLine("ГОТОВО: отчёт сохранён.")
else
  writeLine("")
  writeLine("ОШИБКА: отчёт не удалось сохранить.")
end
