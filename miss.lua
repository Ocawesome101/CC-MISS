--[[

MISS - the Mediocre Item Storage System

This will probably work much less well
on Minecraft versions before 1.13 - as
supporting them would be a lot of work.

]]

-- Configure this.
local input = "minecraft:chest_21"

-- Unless you intend to make an improvement,
-- don't touch anything below this line.

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

local function rebuild_index()
  io.write("Reading chests...")

  locations, wrappers = {}, {}

  local chests = peripheral.getNames()
  for i=#chests, 1, -1 do
    if chests[i] == input or not chests[i]:match("chest") then
      table.remove(chests, i)
    end
  end

  local parallels = {}
  for i=1, #chests, 1 do
    parallels[#parallels+1] = function()
      local chest = peripheral.wrap(chests[i])
      wrappers[chests[i]] = chest

      local items = chest.list()

      locations[chests[i]] = {size = chest.size()}

      for slot in pairs(items) do
        locations[chests[i]][slot] = chest.getItemDetail(slot)
      end
    end
  end

  parallel.waitForAll(table.unpack(parallels))

  io.write("done\n")
end

local iochest = peripheral.wrap(input)

local stages = {[0]="/", "-", "\\", "|"}
local lstage = 0
local function loader()
  lstage = lstage + 1
  term.setCursorPos(1, 1)
  term.write(stages[lstage%4])
end

-- find a place where (item) can go
local function _find_location(item)
  for chest, slots in pairs(locations) do
    for slot, detail in pairs(slots) do
      if slot ~= "size" then
        if detail.name == item then
          return chest, slot, detail.maxCount - detail.count, detail.count
        end
      end
    end
  end
end

-- withdraw (count) of (item)
local function withdraw(item, count)
  while count > 0 do
    local chest, slot, _, has = _find_location(item)
    if not chest then return nil end
    has = math.min(count, has)
    if count >= has then
      locations[chest][slot] = nil
    else
      locations[chest][slot].count = locations[chest][slot].count - count
    end
    count = count - has
    wrappers[chest].pushItems(input, slot, has)
  end
  return true
end

local function deposit(slot)
  local item = iochest.getItemDetail(slot)
  print("Depositing", item.name)
  while item.count > 0 do
    for chest, slots in pairs(locations) do
      local deposited
      if item.count == 0 then break end
      for dslot, detail in pairs(slots) do
        if dslot ~= "size" then
          if detail.name == item.name and detail.count < detail.maxCount then
            local todepo = math.min(item.count,
              detail.maxCount - detail.count)
            item.count = item.count - todepo
            detail.count = detail.count + todepo
            deposited = true
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
      writeAt(2, i - scroll + 3,
        (selected == i and "-> " or "   ") .. filtered[i])
    end
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
        if selected < scroll + 1 then
          scroll = selected - 1
          term.clear()
        end
      elseif cc == keys.down then
        selected = math.min(#filtered, selected + 1)
        if selected > h - 4 then
          scroll = selected - (h - 4)
          term.clear()
        end
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

while true do
  rebuild_index()
  local option = menu("MISS Main Menu", {
    "Retrieve",
    "Deposit",
    "Exit"
  })

  if option == 1 then
    local items = {}
    for _, slots in pairs(locations) do
      for dslot, detail in pairs(slots) do
        if dslot ~= "size" then
          items[detail.name] = (items[detail.name] or 0) + detail.count
        end
      end
    end

    local options = {"----  (Cancel)"}
    local ritems = {}
    for k, v in pairs(items) do
      options[#options+1] = string.format("%4dx %s", v, k)
    end

    table.sort(options, function(a, b)
      if a == "----  (Cancel)" then
        return true
      elseif b == "----  (Cancel)" then
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

    local options = {"----  (Cancel)", "----  (Everything)"}
    local slots = {}
    for k, v in pairs(items) do
      options[#options+1] = string.format("%4dx %s", v[1], k)
      slots[#options] = table.pack(table.unpack(v, 2))
    end

    table.sort(options, function(a, b)
      if a == "----  (Everything)" and b == "----  (Cancel)" then
        return false
      elseif a == "----  (Cancel)" and b == "----  (Everything" then
        return true
      elseif a == "----  (Everything)" or a == "----  (Cancel)" then
        return true
      elseif b == "----  (Cancel)" or a == "----  (Everything)" then
        return false
      else
        return a > b
      end
    end)

    for i=3, #options, 1 do
      slots[i] = table.pack(table.unpack(options[i]:match("x (.+)$"), 2))
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
    return
  end
end
