-- SaveMyItems Core
-- Addon namespace
local addonName, IT = ...

-- Expose namespace globally for other files
_G.SaveMyItemsNS = IT

-- Defaults (v2 schema with categories)
IT.defaults = {
    dbVersion = 2,
    activeCategory = "general",
    categoryOrder = { "general" },
    categories = {
        ["general"] = { name = "General", items = {} },
    },
    framePos = nil,
    frameShown = true,
}

-- Cache of resolved item data: { [itemID] = { name, link, quality, icon } }
IT.itemCache = {}

-- Ordered list of item IDs for display (active category only)
IT.sortedItems = {}

-- Queued item IDs waiting for server data
IT.pendingItems = {}

-- Active category key (mirrors db.activeCategory)
IT.activeCategory = "general"

------------------------------------------------------------
-- Saved Variables + Migration
------------------------------------------------------------
function IT:InitDB()
    if not SaveMyItemsDB then
        SaveMyItemsDB = {}
    end

    -- Migration: v1 (flat items) -> v2 (categories)
    if not SaveMyItemsDB.dbVersion then
        local oldItems = SaveMyItemsDB.items or {}
        SaveMyItemsDB.dbVersion = 2
        SaveMyItemsDB.activeCategory = "general"
        SaveMyItemsDB.categoryOrder = { "general" }
        SaveMyItemsDB.categories = {
            ["general"] = {
                name = "General",
                items = oldItems,
            },
        }
        SaveMyItemsDB.items = nil
    end

    -- Apply defaults for missing keys
    for k, v in pairs(self.defaults) do
        if SaveMyItemsDB[k] == nil then
            if type(v) == "table" then
                SaveMyItemsDB[k] = {}
                for k2, v2 in pairs(v) do
                    SaveMyItemsDB[k][k2] = v2
                end
            else
                SaveMyItemsDB[k] = v
            end
        end
    end

    -- Ensure General category always exists
    if not SaveMyItemsDB.categories["general"] then
        SaveMyItemsDB.categories["general"] = { name = "General", items = {} }
    end
    local hasGeneral = false
    for _, k in ipairs(SaveMyItemsDB.categoryOrder) do
        if k == "general" then hasGeneral = true; break end
    end
    if not hasGeneral then
        table.insert(SaveMyItemsDB.categoryOrder, 1, "general")
    end

    self.db = SaveMyItemsDB

    -- Validate active category
    if not self.db.categories[self.db.activeCategory] then
        self.db.activeCategory = self.db.categoryOrder[1] or "general"
    end
    self.activeCategory = self.db.activeCategory
end

------------------------------------------------------------
-- Item data helpers
------------------------------------------------------------
local QUALITY_COLORS = {
    [0] = { 0.62, 0.62, 0.62 }, -- Poor
    [1] = { 1.00, 1.00, 1.00 }, -- Common
    [2] = { 0.12, 1.00, 0.00 }, -- Uncommon
    [3] = { 0.00, 0.44, 0.87 }, -- Rare
    [4] = { 0.64, 0.21, 0.93 }, -- Epic
    [5] = { 1.00, 0.50, 0.00 }, -- Legendary
    [6] = { 0.90, 0.80, 0.50 }, -- Artifact
}

function IT:GetQualityColor(quality)
    return QUALITY_COLORS[quality] or QUALITY_COLORS[1]
end

function IT:CacheItem(itemID)
    local name, link, quality, _, _, _, _, _, _, icon, vendorPrice = GetItemInfo(itemID)
    if name then
        self.itemCache[itemID] = {
            name = name,
            link = link,
            quality = quality,
            icon = icon,
            vendorPrice = vendorPrice or 0,
        }
        return true
    end
    return false
end

------------------------------------------------------------
-- Active category helpers
------------------------------------------------------------
function IT:GetActiveItems()
    local cat = self.db.categories[self.activeCategory]
    if cat then return cat.items end
    -- Fallback if active category is invalid
    self.activeCategory = self.db.categoryOrder[1] or "general"
    self.db.activeCategory = self.activeCategory
    return self.db.categories[self.activeCategory].items
end

function IT:GetActiveCategoryName()
    local cat = self.db.categories[self.activeCategory]
    return cat and cat.name or "General"
end

------------------------------------------------------------
-- Item add / remove (operates on active category)
------------------------------------------------------------
function IT:AddItem(itemID)
    itemID = tonumber(itemID)
    if not itemID then return false, "Invalid item ID." end

    local items = self:GetActiveItems()
    if items[itemID] then
        return false, "Item " .. itemID .. " is already in this category."
    end

    items[itemID] = true

    if not self:CacheItem(itemID) then
        self.pendingItems[itemID] = true
    end

    self:RebuildSortedList()
    self:RefreshUI()
    return true
end

function IT:RemoveItem(itemID)
    itemID = tonumber(itemID)
    if not itemID then return false, "Invalid item ID." end

    local items = self:GetActiveItems()
    if not items[itemID] then
        return false, "Item " .. itemID .. " is not in this category."
    end

    items[itemID] = nil
    self.pendingItems[itemID] = nil
    -- Don't clear itemCache; item may exist in other categories

    self:RebuildSortedList()
    self:RefreshUI()
    return true
end

function IT:RebuildSortedList()
    wipe(self.sortedItems)
    local items = self:GetActiveItems()
    for id in pairs(items) do
        table.insert(self.sortedItems, id)
    end
    table.sort(self.sortedItems, function(a, b)
        local ca, cb = self.itemCache[a], self.itemCache[b]
        if ca and cb then return ca.name < cb.name end
        if ca then return true end
        if cb then return false end
        return a < b
    end)
end

------------------------------------------------------------
-- Category management
------------------------------------------------------------
function IT:SlugifyName(name)
    name = name:lower():gsub("[^%w]+", "-"):gsub("^%-+", ""):gsub("%-+$", "")
    if name == "" then name = "category" end
    return name
end

function IT:UniqueKey(baseKey)
    local key = baseKey
    local n = 1
    while self.db.categories[key] do
        n = n + 1
        key = baseKey .. "-" .. n
    end
    return key
end

function IT:FindCategoryByName(name)
    local lowerName = name:lower()
    for _, key in ipairs(self.db.categoryOrder) do
        local cat = self.db.categories[key]
        if cat and cat.name:lower() == lowerName then
            return key
        end
    end
    return nil
end

function IT:AddCategory(displayName)
    displayName = (displayName or ""):match("^%s*(.-)%s*$")
    if displayName == "" then
        return false, "Category name cannot be empty."
    end
    if #self.db.categoryOrder >= 20 then
        return false, "Maximum of 20 categories reached."
    end

    local key = self:UniqueKey(self:SlugifyName(displayName))

    self.db.categories[key] = {
        name = displayName,
        items = {},
    }
    table.insert(self.db.categoryOrder, key)

    if self.RefreshTabs then self:RefreshTabs() end
    return true, key
end

function IT:RemoveCategory(key)
    if key == "general" then
        return false, "Cannot delete the General category."
    end
    if not self.db.categories[key] then
        return false, "Category not found."
    end

    self.db.categories[key] = nil

    for i, k in ipairs(self.db.categoryOrder) do
        if k == key then
            table.remove(self.db.categoryOrder, i)
            break
        end
    end

    if self.activeCategory == key then
        self:SetActiveCategory("general")
    else
        if self.RefreshTabs then self:RefreshTabs() end
    end

    return true
end

function IT:RenameCategory(key, newName)
    newName = (newName or ""):match("^%s*(.-)%s*$")
    if newName == "" then
        return false, "Name cannot be empty."
    end
    local cat = self.db.categories[key]
    if not cat then
        return false, "Category not found."
    end

    cat.name = newName
    if self.RefreshTabs then self:RefreshTabs() end
    return true
end

function IT:SetActiveCategory(key)
    if not self.db.categories[key] then return end
    self.activeCategory = key
    self.db.activeCategory = key
    self:RebuildSortedList()
    if self.RefreshTabs then self:RefreshTabs() end
    self:RefreshUI()
end

------------------------------------------------------------
-- Price / Count helpers
------------------------------------------------------------

function IT:FormatMoney(copper)
    if not copper or copper <= 0 then return nil end
    local gold = math.floor(copper / 10000)
    local silver = math.floor((copper % 10000) / 100)
    local cop = copper % 100

    local parts = {}
    if gold > 0 then
        table.insert(parts, "|cffffd700" .. gold .. "g|r")
    end
    if silver > 0 then
        table.insert(parts, "|cffc7c7cf" .. silver .. "s|r")
    end
    if cop > 0 or #parts == 0 then
        table.insert(parts, "|cffeda55f" .. cop .. "c|r")
    end
    return table.concat(parts, " ")
end

function IT:HasAuctionator()
    return Auctionator and Auctionator.API and Auctionator.API.v1
end

function IT:GetAuctionPrice(itemID)
    if self:HasAuctionator() then
        local ok, price = pcall(Auctionator.API.v1.GetAuctionPriceByItemID, "SaveMyItems", itemID)
        if ok and price then return price end
    end
    return nil
end

function IT:GetItemPrice(itemID)
    local data = self.itemCache[itemID]
    if not data then return nil end
    -- Gray (Poor quality) items: use vendor sell price
    if data.quality == 0 then
        local vp = data.vendorPrice
        if vp and vp > 0 then return vp end
        return nil
    end
    -- All other qualities: use AH price
    return self:GetAuctionPrice(itemID)
end

function IT:GetOwnedCount(itemID)
    local bags = GetItemCount(itemID) or 0
    local total = GetItemCount(itemID, true) or 0
    return bags, total
end

------------------------------------------------------------
-- Bootstrap
------------------------------------------------------------
local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("GET_ITEM_INFO_RECEIVED")
frame:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" and arg1 == addonName then
        IT:InitDB()

        -- Pre-cache items from ALL categories
        for _, catData in pairs(IT.db.categories) do
            for id in pairs(catData.items) do
                if not IT:CacheItem(id) then
                    IT.pendingItems[id] = true
                end
            end
        end

        IT:RebuildSortedList()
        IT:CreateMainFrame()
        IT:RegisterSlashCommands()

        if IT.db.frameShown then
            IT.frame:Show()
        end

        print("|cff00ccffSave My Items|r loaded. Type |cff00ff00/smi help|r for commands.")
    end

    if event == "GET_ITEM_INFO_RECEIVED" then
        local itemID = tonumber(arg1)
        if itemID and IT.pendingItems[itemID] then
            if IT:CacheItem(itemID) then
                IT.pendingItems[itemID] = nil
                local activeItems = IT:GetActiveItems()
                if activeItems[itemID] then
                    IT:RebuildSortedList()
                    IT:RefreshUI()
                end
            end
        end
    end
end)
