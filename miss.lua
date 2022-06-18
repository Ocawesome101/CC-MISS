--[[

MISS - the Mediocre Item Storage System

This will probably work much less well
on Minecraft versions before 1.13 - as
supporting them would be a lot of work.

]]

-- The ID of the computer on which MISS is running.  Only necessary for
-- autocrafting, when the turtle has to transfer items into its inventory.
local selfid = "computer_3"

-- Unless you intend to make an improvement,
-- don't touch anything below this line.

settings.define("miss.input_chest", {
  description = "The input chest MISS should use.",
  type = "string",
})

settings.define("miss.cache_index", {
  description = "Whether MISS should cache its chest index.  A manual index rebuild is necessary when chests are added or removed.",
  default = false,
  type = "boolean"
})

settings.define("miss.no_cache_warning", {
  description = "Disables the warning MISS prints while miss.cache_index is true.",
  default = false,
  type = "boolean"
})

-- The chest used for I/O.
local input = settings.get("miss.input_chest")
if not (input and peripheral.isPresent(input)) then
  error("you must set miss.input_chest to a valid peripheral name", 0)
end

-- This table's keys are item IDs, and its
-- values are tables of chests in which they
-- can be found, and how much of the item is
-- in that chest.
-- For now, this table is dynamically built
-- on startup.  If that's too slow I'll add
-- caching.
local locations = {}
-- This table stores a cache of peripheral
-- wrappers.
local wrappers = {}

local totalItems, maxItems = 0, 0

local stages = {[0]="/", "-", "\\", "|"}
local lstage = 0
local last = os.epoch("utc")
local function loader()
  if os.epoch("utc") - last >= 100 then last = os.epoch("utc") else return end
  lstage = lstage + 1
  term.setCursorPos(1, 1)
  term.write(stages[lstage%4])
end

local function save_index()
  if settings.get("miss.cache_index") and not skip_locate then
    locations.stored = totalItems
    term.setCursorPos(1, 1)
    term.clear()
    io.write("  Saving MISS item index...")
    local data = textutils.serialize(locations, {compact=true})
    io.open("/miss_cache", "wb"):write(data):close()
    io.write("done\n")
    locations.stored = nil
  end
end

local function rebuild_index(skip_locate)
  term.setCursorPos(1, 1)
  term.clear()
  io.write("  MISS is probing for chests...")

  wrappers = {}
  if not skip_locate then locations = {} end

  totalItems, maxItems = 0, 0

  local chests = peripheral.getNames()
  for i=#chests, 1, -1 do
    if chests[i] == input or not chests[i]:match("chest") then
      table.remove(chests, i)
    end
  end

  local parallels = {}
  local stage = 0

  for i=1, #chests, 1 do
    local chest = peripheral.wrap(chests[i])
    wrappers[chests[i]] = chest
    maxItems = maxItems + (chest.getItemLimit(1) * chest.size())
    loader()
    stage = stage + 1
    term.setCursorPos(33, 1)
    term.write(("(%d/%d) "):format(stage, #chests))

    if locations[chests[i]] and not skip_locate then
      parallels[#parallels+1] = function()
        local items = chest.list()

        locations[chests[i]] = {size = chest.size()}

        for slot in pairs(items) do
          loader()
          local detail = chest.getItemDetail(slot)
          detail.tags = detail.tags or {}
          totalItems = totalItems + detail.count
          locations[chests[i]][slot] = detail
        end
        stage = stage + 1
        term.setCursorPos(28, 1)
        term.write(("(%d/%d) "):format(stage, #chests))
      end
    end
  end

  stage = 0

  term.setCursorPos(1, 1)
  term.clear()
  io.write("  MISS is reading items...")

  parallel.waitForAll(table.unpack(parallels))

  if skip_locate then
    totalItems = locations.stored or 0
  end

  save_index()

  io.write("done\n")
end

local iochest = peripheral.wrap(input)

-- find a place where (item) can go
local function _find_location(item)
  for chest, slots in pairs(locations) do
    for slot, detail in pairs(slots) do
      if slot ~= "size" then
        if detail.name == item or detail.tags[item] then
          return chest, slot, detail.maxCount - detail.count, detail.count
        end
      end
    end
  end
end

-- withdraw (count) of (item)
local function withdraw(item, count)
  while count > 0 do
    loader()
    local chest, slot, _, _has = _find_location(item)
    if not chest then return nil end
    local has = math.min(count, _has)
    if count >= _has then
      locations[chest][slot] = nil
    else
      locations[chest][slot].count = locations[chest][slot].count - has
    end
    count = count - has
    totalItems = totalItems - has
    wrappers[chest].pushItems(input, slot, has)
  end
  return true
end

local function deposit(slot)
  local item = iochest.getItemDetail(slot)
  if not item then return nil end
  print("  Depositing", item.name)
  while item.count > 0 do
    for chest, slots in pairs(locations) do
      local deposited
      if item.count == 0 then break end
      for dslot, detail in pairs(slots) do
        if dslot ~= "size" then
          if detail.name == item.name and detail.count < detail.maxCount then
            loader()
            local todepo = math.min(item.count,
              detail.maxCount - detail.count)
            item.count = item.count - todepo
            detail.count = detail.count + todepo
            deposited = true
            totalItems = totalItems + todepo
            iochest.pushItems(chest, slot, todepo, dslot)
          end
          if item.count == 0 then break end
        end
      end

      if item.count == 0 then break end

      if item.count > 0 and not deposited then
        if #slots < slots.size then
          slots[#slots+1] = {
            count = 0, name = item.name,
            displayName = item.displayName,
            maxCount = item.maxCount
          }
        end
      end
    end
  end
end

local function writeAt(x, y, text)
  term.setCursorPos(x, y)
  io.write(text)
end

local function menu(title, opts)
  local scroll = 0
  local selected = 1
  local search = ""
  term.clear()
  local w, h = term.getSize()
  while true do
    writeAt(2, 1, title)
    if #search == 0 then
      writeAt(2, 2, "> (type to search)")
    else
      writeAt(2, 2, "> " .. search .. "_ ")
    end
    local filtered = {}
    for i=1, #opts, 1 do
      if opts[i]:lower():match(search:lower()) or #search == 0 then
        filtered[#filtered+1] = opts[i]
      end
    end
    for i=1+scroll, #filtered, 1 do
      if #filtered[i] + 5 >= w then
        filtered[i] = filtered[i]:sub(1, w - 9) .. "..."
      end
      writeAt(2, i - scroll + 3,
        (selected == i and "-> " or "   ") .. filtered[i])
    end
    writeAt(1, h, string.format("%"..w.."s",
      string.format("[%d%% full (%d/%d)]",
        math.ceil((totalItems/maxItems)*100), totalItems, maxItems)))
    local sig, cc = os.pullEvent()
    if sig == "char" then
      search = search .. cc
      selected = 1
      term.clear()
    elseif sig == "key" then
      if cc == keys.enter then
        term.clear()
        term.setCursorPos(1,1)
        for i=1, #opts, 1 do
          if opts[i] == filtered[selected] then
            return i
          end
        end
      elseif cc == keys.backspace then
        term.clear()
        if #search > 0 then search = search:sub(1, -2) end
      elseif cc == keys.up then
        selected = math.max(1, selected - 1)
      elseif cc == keys.down then
        selected = math.min(#filtered, selected + 1)
      elseif cc == keys.pageUp then
        selected = math.max(1, selected - (h - 8))
      elseif cc == keys.pageDown then
        selected = math.min(#filtered, selected + (h - 8))
      end
      if selected - scroll < 2 then
        scroll = math.max(0, selected - 2)
        term.clear()
      elseif selected - scroll > h - 5 then
        scroll = selected - (h - 5)
        term.clear()
      end
    end
  end
end

local function lengthprompt(title)
  local len = ""
  writeAt(2, 1, title)
  while true do
    writeAt(2, 3, "#> " .. len .. "_ ")
    local sig, a = os.pullEvent()
    if sig == "char" then
      if tonumber(a) then len = len .. a end
    elseif sig == "key" then
      if #len > 0 then
        if a == keys.backspace then
          len = len:sub(1, -2)
        elseif a == keys.enter then
          term.clear()
          return tonumber(len)
        end
      end
    end
  end
end

local function present(item, count)
  local counts = {}

  for _, slots in pairs(locations) do
    for dslot, detail in pairs(slots) do
      if dslot ~= "size" then
        counts[detail.name] = (counts[detail.name] or 0) + detail.count
        detail.tags = detail.tags or {}
        for tag in pairs(detail.tags) do
          counts[tag] = (counts[tag] or 0) + detail.count
        end
      end
    end
  end

  return counts[item] and counts[item] >= count
end

local function craft(recipe)
  recipe = recipe:gsub("[^a-zA-Z%-%_]", "-")
  print("crafting", recipe)
  local rdat = dofile("/recipes/"..recipe)

  local counts = {}
  for i=1, 9, 1 do
    local item = rdat.items[i]
    if item then
      counts[item] = (counts[item] or 0) + 1
    end
  end

  for item, count in pairs(counts) do
    if not present(item, count) then
      craft(item)
      if not present(item, count) then
        return
      end
    end
  end

  for item, count in pairs(counts) do
    withdraw(item, count)
  end

  local citems = iochest.list()
  for i=1, 9, 1 do
    if rdat.items[i] then
      if i > 6 then i = i + 2 elseif i > 3 then i = i + 1 end
      for slot, id in pairs(citems) do
        id.detail = id.detail or iochest.getItemDetail(slot)
        if id.name == rdat.items[i] or
            (id.detail.tags and id.detail.tags[rdat.items[i]]) then
          turtle.select(i)
          iochest.pushItems(selfid, slot, 1, i)
        end
      end
    end
  end

  os.sleep(3)
  turtle.select(1)
  turtle.craft()
  os.sleep(3)
  citems = iochest.list()
  local s = #citems + 1
  iochest.pullItems(selfid, 1, 64, s)
  deposit(s)
end

if turtle and not fs.exists("/recipes") then
  fs.makeDir("/recipes")
end

if settings.get("miss.cache_index") and fs.exists("/miss_cache") then
  if not settings.get("miss.no_cache_warning") then
    printError("WARNING: MISS is using a cached item index. Adding or removing chests from the network will require a manual index rebuild.")
    printError("Set miss.no_cache_warning to true to disable this warning.")
    sleep(5)
  end
  local handle = io.open("/miss_cache", "rb")
  local data = handle:read("a")
  handle:close()
  locations = textutils.unserialize(data)
  totalItems = locations.stored or 0
  rebuild_index(true)
  locations.stored = nil
else
  rebuild_index()
end

while true do
  local mmopts = {
    "Retrieve",
    "Deposit",
    "Rebuild Item Index",
    "Exit"
  }
  if turtle then table.insert(mmopts, 4, "Autocrafting") end
  local option = menu("MISS Main Menu", mmopts)

  if option == 1 then
    local items = {}
    for _, slots in pairs(locations) do
      for dslot, detail in pairs(slots) do
        if dslot ~= "size" then
          items[detail.name] = (items[detail.name] or 0) + detail.count
        end
      end
    end

    local options = {"------  (Cancel)"}
    local ritems = {}
    for k, v in pairs(items) do
      options[#options+1] = string.format("%6dx %s", v, k)
    end

    table.sort(options, function(a, b)
      if a == "------  (Cancel)" then
        return true
      elseif b == "------  (Cancel)" then
        return false
      else
        return a > b
      end
    end)

    for i=2, #options, 1 do
      ritems[i] = options[i]:match("x (.+)$")
    end

    if #options == 1 then
      printError("No available items")
      os.sleep(1)
    else
      local sel = menu("Select Item:", options)
      if sel > 1 then
        local maxn = items[ritems[sel]]
        local count = lengthprompt(("Enter amount of %s to withdraw (0-%d)")
          :format(ritems[sel], maxn))
        if count > 0 then
          writeAt(1, 1, "  Withdrawing " .. count .. " " .. ritems[sel])
          withdraw(ritems[sel], math.min(count, maxn))
        end
      end
    end
  elseif option == 2 then
    local items = {}
    for i, item in pairs(iochest.list()) do
      if not items[item.name] then
        items[item.name] = {0}
      end
      items[item.name][1] = items[item.name][1] + item.count
      items[item.name][#items[item.name]+1] = i
    end

    local options = {"------  (Cancel)", "------  (Everything)"}
    local slots = {}
    for k, v in pairs(items) do
      options[#options+1] = string.format("%6dx %s", v[1], k)
    end

    table.sort(options, function(a, b)
      if a == "------  (Everything)" and b == "------  (Cancel)" then
        return false
      elseif a == "------  (Cancel)" and b == "------  (Everything" then
        return true
      elseif a == "------  (Everything)" or a == "------  (Cancel)" then
        return true
      elseif b == "------  (Cancel)" or a == "------  (Everything)" then
        return false
      else
        return a > b
      end
    end)

    for i=3, #options, 1 do
      slots[i] = table.pack(table.unpack(
        items[options[i]:match("x (.+)$")], 2))
    end

    if #options < 3 then
      printError("No available items")
      os.sleep(1)
    else
      local sel = menu("Select Item", options)
      local parallels = {}
      if sel > 2 then
        for n, slot in pairs(slots[sel]) do
          if n ~= "n" then
            parallels[#parallels+1] = function()
              deposit(slot)
            end
          end
        end
      elseif sel == 2 then
        for i, item in pairs(iochest.list()) do
          parallels[#parallels+1] = function()
            deposit(i)
          end
        end
      end
      if #parallels > 0 then parallel.waitForAll(table.unpack(parallels)) end
    end
  elseif option == 3 then
    rebuild_index()
  elseif option == 4 and turtle then
    local recipes = fs.list("/recipes")
    table.sort(recipes)
    table.insert(recipes, 1, "(Add)")
    table.insert(recipes, 1, "(Cancel)")

    local option = menu("Autocrafting", recipes)
    if option == 2 then
      printError("Recipe adding not implemented yet")
      os.sleep(1)
    elseif option > 2 then
      craft(recipes[option])
    end
  else
    save_index()
    return
  end
end
