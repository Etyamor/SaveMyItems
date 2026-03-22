-- SaveMyItems UI
local _, IT = ...

local FRAME_WIDTH = 420
local FRAME_HEIGHT = 550
local ROW_HEIGHT = 52
local ICON_SIZE = 24
local VISIBLE_ROWS = 7
local TAB_HEIGHT = 24
local TAB_PADDING = 2
local TAB_MAX_WIDTH = 80
local TAB_MIN_WIDTH = 40
local ADD_TAB_WIDTH = 26

------------------------------------------------------------
-- Main Frame
------------------------------------------------------------
function IT:CreateMainFrame()
    local f = CreateFrame("Frame", "SaveMyItemsFrame", UIParent, "BasicFrameTemplateWithInset")
    f:SetSize(FRAME_WIDTH, FRAME_HEIGHT)
    f:SetPoint("CENTER")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:SetClampedToScreen(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, relPoint, x, y = self:GetPoint()
        IT.db.framePos = { point, relPoint, x, y }
    end)

    -- Restore position
    if IT.db.framePos then
        local p = IT.db.framePos
        f:ClearAllPoints()
        f:SetPoint(p[1], UIParent, p[2], p[3], p[4])
    end

    -- Title
    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    f.title:SetPoint("TOP", f.TitleBg, "TOP", 0, -3)
    f.title:SetText("Save My Items")

    -- Track visibility
    f:SetScript("OnShow", function() IT.db.frameShown = true end)
    f:SetScript("OnHide", function() IT.db.frameShown = false end)

    self.frame = f

    -- Hook Shift+Click on any item to add it when tracker is open
    local origHandleModifiedItemClick = HandleModifiedItemClick
    HandleModifiedItemClick = function(link, ...)
        if f:IsShown() and link then
            local itemID = link:match("item:(%d+)")
            if itemID then
                local chatActive = false
                for i = 1, NUM_CHAT_WINDOWS do
                    local eb = _G["ChatFrame" .. i .. "EditBox"]
                    if eb and eb:HasFocus() then
                        chatActive = true
                        break
                    end
                end
                if not chatActive then
                    local ok, msg = IT:AddItem(itemID)
                    if ok then
                        local data = IT.itemCache[tonumber(itemID)]
                        print("|cff00ccffSave My Items|r: Added " .. (data and data.link or ("item " .. itemID)) .. " to " .. IT:GetActiveCategoryName() .. ".")
                    else
                        print("|cff00ccffSave My Items|r: " .. (msg or "Failed."))
                    end
                    return true
                end
            end
        end
        return origHandleModifiedItemClick(link, ...)
    end

    -- Item count label (bottom-left, below input)
    local countLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    countLabel:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 12, 8)
    countLabel:SetTextColor(0.5, 0.5, 0.5)
    self.countLabel = countLabel

    -- Grand total value label (bottom-right, same line as count)
    local totalLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    totalLabel:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -12, 8)
    totalLabel:SetJustifyH("RIGHT")
    self.totalLabel = totalLabel

    -- Tab bar
    self:CreateTabBar(f)

    -- Column headers (shifted down by TAB_HEIGHT)
    local hdrItem = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hdrItem:SetPoint("TOPLEFT", f.InsetBg or f.Inset, "TOPLEFT", 34, -6 - TAB_HEIGHT)
    hdrItem:SetText("Item")
    hdrItem:SetTextColor(0.7, 0.7, 0.7)

    local hdrOwned = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hdrOwned:SetPoint("TOPRIGHT", f.InsetBg or f.Inset, "TOPRIGHT", -148, -6 - TAB_HEIGHT)
    hdrOwned:SetText("Have")
    hdrOwned:SetTextColor(0.7, 0.7, 0.7)

    local hdrPrice = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hdrPrice:SetPoint("TOPRIGHT", f.InsetBg or f.Inset, "TOPRIGHT", -44, -6 - TAB_HEIGHT)
    hdrPrice:SetText("Price / Value")
    hdrPrice:SetTextColor(0.7, 0.7, 0.7)

    self:CreateScrollArea(f)
    self:CreateAddBox(f)
    self:RefreshUI()

    -- Refresh periodically to update counts
    local ticker = CreateFrame("Frame")
    ticker.elapsed = 0
    ticker:SetScript("OnUpdate", function(self, elapsed)
        self.elapsed = self.elapsed + elapsed
        if self.elapsed >= 2 then
            self.elapsed = 0
            if IT.frame and IT.frame:IsShown() then
                IT:RefreshUI()
            end
        end
    end)
end

------------------------------------------------------------
-- Tab Bar
------------------------------------------------------------
function IT:CreateTabBar(parent)
    local tabBar = CreateFrame("Frame", nil, parent)
    tabBar:SetPoint("TOPLEFT", parent.InsetBg or parent.Inset, "TOPLEFT", 0, 0)
    tabBar:SetPoint("TOPRIGHT", parent.InsetBg or parent.Inset, "TOPRIGHT", 0, 0)
    tabBar:SetHeight(TAB_HEIGHT)
    self.tabBar = tabBar
    self.tabButtons = {}

    -- "+" button to add a new category
    local addBtn = CreateFrame("Button", nil, tabBar, "UIPanelButtonTemplate")
    addBtn:SetSize(ADD_TAB_WIDTH, TAB_HEIGHT - 4)
    addBtn:SetPoint("RIGHT", tabBar, "RIGHT", -4, 0)
    addBtn:SetText("+")
    addBtn:SetScript("OnClick", function()
        IT:ShowCategoryNameDialog("", function(name)
            local ok, result = IT:AddCategory(name)
            if ok then
                IT:SetActiveCategory(result)
                print("|cff00ccffSave My Items|r: Created category \"" .. name .. "\".")
            else
                print("|cff00ccffSave My Items|r: " .. result)
            end
        end)
    end)
    self.addTabBtn = addBtn

    self:RefreshTabs()
end

function IT:RefreshTabs()
    if not self.tabBar then return end

    -- Hide old tab buttons
    for _, btn in ipairs(self.tabButtons) do
        btn:Hide()
        btn:SetParent(nil)
    end
    wipe(self.tabButtons)

    local tabBar = self.tabBar
    local order = self.db.categoryOrder
    local numTabs = #order

    local availWidth = (tabBar:GetWidth() or (FRAME_WIDTH - 16)) - ADD_TAB_WIDTH - 12
    local tabWidth = math.floor(availWidth / math.max(numTabs, 1))
    tabWidth = math.max(TAB_MIN_WIDTH, math.min(tabWidth, TAB_MAX_WIDTH))

    local xOffset = 4
    for i, key in ipairs(order) do
        local catData = self.db.categories[key]
        if catData then
            local btn = CreateFrame("Button", nil, tabBar)
            btn:SetSize(tabWidth, TAB_HEIGHT - 4)
            btn:SetPoint("LEFT", tabBar, "LEFT", xOffset, 0)

            local bg = btn:CreateTexture(nil, "BACKGROUND")
            bg:SetAllPoints()
            btn.bg = bg

            local label = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            label:SetPoint("CENTER")
            label:SetWidth(tabWidth - 8)
            label:SetWordWrap(false)
            label:SetText(catData.name)
            btn.label = label

            if key == self.activeCategory then
                bg:SetColorTexture(0.2, 0.2, 0.35, 0.9)
                label:SetTextColor(1, 1, 1)
            else
                bg:SetColorTexture(0.12, 0.12, 0.18, 0.7)
                label:SetTextColor(0.6, 0.6, 0.6)
            end

            btn.categoryKey = key
            btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
            btn:SetScript("OnClick", function(_, mouseButton)
                if mouseButton == "LeftButton" then
                    IT:SetActiveCategory(key)
                elseif mouseButton == "RightButton" then
                    IT:ShowTabContextMenu(btn, key)
                end
            end)

            btn:SetScript("OnEnter", function(self)
                if key ~= IT.activeCategory then
                    self.bg:SetColorTexture(0.18, 0.18, 0.28, 0.85)
                end
            end)
            btn:SetScript("OnLeave", function(self)
                if key ~= IT.activeCategory then
                    self.bg:SetColorTexture(0.12, 0.12, 0.18, 0.7)
                end
            end)

            btn:Show()
            table.insert(self.tabButtons, btn)

            xOffset = xOffset + tabWidth + TAB_PADDING
        end
    end
end

------------------------------------------------------------
-- Context Menu (custom frame, created once)
------------------------------------------------------------
local contextMenu
local function GetContextMenu()
    if contextMenu then return contextMenu end

    local f = CreateFrame("Frame", "SaveMyItemsContextMenu", UIParent, "BackdropTemplate")
    f:SetFrameStrata("DIALOG")
    f:SetSize(100, 10)
    f:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f:Hide()

    f.buttons = {}
    contextMenu = f

    -- Close when clicking elsewhere
    f:SetScript("OnShow", function()
        f:RegisterEvent("GLOBAL_MOUSE_DOWN")
    end)
    f:SetScript("OnHide", function()
        f:UnregisterEvent("GLOBAL_MOUSE_DOWN")
    end)
    f:SetScript("OnEvent", function(self, event)
        if event == "GLOBAL_MOUSE_DOWN" then
            if not self:IsMouseOver() then
                self:Hide()
            end
        end
    end)

    return f
end

function IT:ShowTabContextMenu(anchorFrame, categoryKey)
    local menu = GetContextMenu()

    -- Clear old buttons
    for _, btn in ipairs(menu.buttons) do
        btn:Hide()
    end
    wipe(menu.buttons)

    local items = {}
    table.insert(items, {
        text = "Rename",
        func = function()
            menu:Hide()
            local cat = IT.db.categories[categoryKey]
            IT:ShowCategoryNameDialog(cat and cat.name or "", function(newName)
                local ok, err = IT:RenameCategory(categoryKey, newName)
                if ok then
                    print("|cff00ccffSave My Items|r: Renamed to \"" .. newName .. "\".")
                else
                    print("|cff00ccffSave My Items|r: " .. err)
                end
            end)
        end,
    })
    if categoryKey ~= "general" then
        table.insert(items, {
            text = "|cffff4444Delete|r",
            func = function()
                menu:Hide()
                IT:ShowDeleteConfirm(categoryKey)
            end,
        })
    end

    local yOffset = -4
    for i, item in ipairs(items) do
        local btn = CreateFrame("Button", nil, menu)
        btn:SetSize(94, 20)
        btn:SetPoint("TOPLEFT", menu, "TOPLEFT", 3, yOffset)
        btn:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")

        local label = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        label:SetPoint("LEFT", 8, 0)
        label:SetText(item.text)
        btn:SetScript("OnClick", item.func)
        btn:Show()

        table.insert(menu.buttons, btn)
        yOffset = yOffset - 20
    end

    menu:SetSize(100, (#items * 20) + 8)
    menu:ClearAllPoints()
    menu:SetPoint("TOPLEFT", anchorFrame, "BOTTOMLEFT", 0, 0)
    menu:Show()
end

------------------------------------------------------------
-- Delete Confirmation (custom frame)
------------------------------------------------------------
local deleteConfirm
function IT:ShowDeleteConfirm(categoryKey)
    if not deleteConfirm then
        local f = CreateFrame("Frame", "SaveMyItemsDeleteConfirm", UIParent, "BackdropTemplate")
        f:SetFrameStrata("DIALOG")
        f:SetSize(260, 90)
        f:SetPoint("CENTER")
        f:SetBackdrop({
            bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
            edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
            tile = true, tileSize = 32, edgeSize = 32,
            insets = { left = 8, right = 8, top = 8, bottom = 8 },
        })
        f:EnableMouse(true)
        f:SetMovable(true)
        f:RegisterForDrag("LeftButton")
        f:SetScript("OnDragStart", f.StartMoving)
        f:SetScript("OnDragStop", f.StopMovingOrSizing)

        f.text = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        f.text:SetPoint("TOP", 0, -16)
        f.text:SetWidth(230)

        local yesBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        yesBtn:SetSize(80, 22)
        yesBtn:SetPoint("BOTTOMRIGHT", f, "BOTTOM", -4, 12)
        yesBtn:SetText("Delete")
        f.yesBtn = yesBtn

        local noBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        noBtn:SetSize(80, 22)
        noBtn:SetPoint("BOTTOMLEFT", f, "BOTTOM", 4, 12)
        noBtn:SetText("Cancel")
        noBtn:SetScript("OnClick", function() f:Hide() end)

        f:SetScript("OnKeyDown", function(self, key)
            if key == "ESCAPE" then
                self:SetPropagateKeyboardInput(false)
                self:Hide()
            else
                self:SetPropagateKeyboardInput(true)
            end
        end)

        deleteConfirm = f
    end

    local catName = IT.db.categories[categoryKey]
        and IT.db.categories[categoryKey].name or categoryKey
    deleteConfirm.text:SetText("Delete category \"" .. catName .. "\"?\nItems in it will be lost.")
    deleteConfirm.yesBtn:SetScript("OnClick", function()
        deleteConfirm:Hide()
        local ok, err = IT:RemoveCategory(categoryKey)
        if ok then
            print("|cff00ccffSave My Items|r: Deleted category \"" .. catName .. "\".")
        else
            print("|cff00ccffSave My Items|r: " .. err)
        end
    end)
    deleteConfirm:Show()
end

------------------------------------------------------------
-- Category Name Dialog (custom frame)
------------------------------------------------------------
local nameDialog
function IT:ShowCategoryNameDialog(defaultText, onAccept)
    if not nameDialog then
        local f = CreateFrame("Frame", "SaveMyItemsNameDialog", UIParent, "BackdropTemplate")
        f:SetFrameStrata("DIALOG")
        f:SetSize(260, 100)
        f:SetPoint("CENTER")
        f:SetBackdrop({
            bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
            edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
            tile = true, tileSize = 32, edgeSize = 32,
            insets = { left = 8, right = 8, top = 8, bottom = 8 },
        })
        f:EnableMouse(true)
        f:SetMovable(true)
        f:RegisterForDrag("LeftButton")
        f:SetScript("OnDragStart", f.StartMoving)
        f:SetScript("OnDragStop", f.StopMovingOrSizing)

        local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        title:SetPoint("TOP", 0, -14)
        title:SetText("Enter category name:")

        local editBox = CreateFrame("EditBox", "SaveMyItemsNameDialogEditBox", f, "InputBoxTemplate")
        editBox:SetSize(200, 20)
        editBox:SetPoint("TOP", title, "BOTTOM", 0, -8)
        editBox:SetAutoFocus(true)
        editBox:SetMaxLetters(24)
        f.editBox = editBox

        local okBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        okBtn:SetSize(80, 22)
        okBtn:SetPoint("BOTTOMRIGHT", f, "BOTTOM", -4, 10)
        okBtn:SetText("OK")
        f.okBtn = okBtn

        local cancelBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        cancelBtn:SetSize(80, 22)
        cancelBtn:SetPoint("BOTTOMLEFT", f, "BOTTOM", 4, 10)
        cancelBtn:SetText("Cancel")
        cancelBtn:SetScript("OnClick", function() f:Hide() end)

        editBox:SetScript("OnEscapePressed", function() f:Hide() end)

        f:SetScript("OnKeyDown", function(self, key)
            if key == "ESCAPE" then
                self:SetPropagateKeyboardInput(false)
                self:Hide()
            else
                self:SetPropagateKeyboardInput(true)
            end
        end)

        nameDialog = f
    end

    nameDialog.editBox:SetText(defaultText or "")
    nameDialog.editBox:HighlightText()

    -- Wire up the accept action with the current callback
    local function doAccept()
        local text = nameDialog.editBox:GetText()
        if text and text:match("%S") then
            nameDialog:Hide()
            onAccept(text)
        end
    end

    nameDialog.okBtn:SetScript("OnClick", doAccept)
    nameDialog.editBox:SetScript("OnEnterPressed", doAccept)

    nameDialog:Show()
    nameDialog.editBox:SetFocus()
end

------------------------------------------------------------
-- Scroll Area
------------------------------------------------------------
function IT:CreateScrollArea(parent)
    local scrollFrame = CreateFrame("ScrollFrame", "SaveMyItemsScroll", parent, "FauxScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", parent.InsetBg or parent.Inset, "TOPLEFT", 4, -22 - TAB_HEIGHT)
    scrollFrame:SetPoint("BOTTOMRIGHT", parent.InsetBg or parent.Inset, "BOTTOMRIGHT", -26, 52)

    self.scrollFrame = scrollFrame

    self.rows = {}
    for i = 1, VISIBLE_ROWS do
        self.rows[i] = self:CreateItemRow(scrollFrame, i)
    end

    scrollFrame:SetScript("OnVerticalScroll", function(sf, offset)
        FauxScrollFrame_OnVerticalScroll(sf, offset, ROW_HEIGHT, function() IT:RefreshUI() end)
    end)
end

------------------------------------------------------------
-- Item Row
------------------------------------------------------------
function IT:CreateItemRow(parent, index)
    local row = CreateFrame("Button", nil, parent:GetParent())
    row:SetSize(FRAME_WIDTH - 50, ROW_HEIGHT)
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", 2, -((index - 1) * ROW_HEIGHT))

    local hl = row:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.1)

    local icon = row:CreateTexture(nil, "ARTWORK")
    icon:SetSize(ICON_SIZE, ICON_SIZE)
    icon:SetPoint("LEFT", 4, 0)
    row.icon = icon

    -- Remove button (rightmost)
    local removeBtn = CreateFrame("Button", nil, row, "UIPanelCloseButton")
    removeBtn:SetSize(20, 20)
    removeBtn:SetPoint("RIGHT", 0, 0)
    removeBtn:SetScript("OnClick", function()
        if row.itemID then
            IT:RemoveItem(row.itemID)
        end
    end)
    row.removeBtn = removeBtn

    -- Unit price text (top line, dimmer)
    local priceUnit = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    priceUnit:SetPoint("RIGHT", row, "RIGHT", -22, 5)
    priceUnit:SetWidth(100)
    priceUnit:SetJustifyH("RIGHT")
    row.priceUnit = priceUnit

    -- Total value text (bottom line)
    local price = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    price:SetPoint("RIGHT", row, "RIGHT", -22, -8)
    price:SetWidth(100)
    price:SetJustifyH("RIGHT")
    row.price = price

    -- Count text (centered vertically)
    local count = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    count:SetPoint("RIGHT", row, "RIGHT", -124, 0)
    count:SetWidth(40)
    count:SetJustifyH("CENTER")
    row.count = count

    -- Item name
    local name = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    name:SetPoint("LEFT", icon, "RIGHT", 6, 0)
    name:SetPoint("RIGHT", row, "RIGHT", -168, 0)
    name:SetJustifyH("LEFT")
    name:SetWordWrap(false)
    row.name = name

    -- Tooltip on hover
    row:SetScript("OnEnter", function(self)
        local data = IT.itemCache[self.itemID]
        if data and data.link then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetHyperlink(data.link)
            local bags, total = IT:GetOwnedCount(self.itemID)
            GameTooltip:AddLine(" ")
            if total > bags then
                GameTooltip:AddDoubleLine("Owned (bags/total):", bags .. " / " .. total, 0.5, 0.8, 1, 1, 1, 1)
            else
                GameTooltip:AddDoubleLine("Owned:", bags, 0.5, 0.8, 1, 1, 1, 1)
            end
            local data = IT.itemCache[self.itemID]
            local itemPrice = IT:GetItemPrice(self.itemID)
            if itemPrice then
                local priceLabel = (data and data.quality == 0) and "Vendor Price:" or "AH Price:"
                GameTooltip:AddDoubleLine(priceLabel, IT:FormatMoney(itemPrice), 0.5, 0.8, 1)
                if total > 0 then
                    GameTooltip:AddDoubleLine("Total Value:", IT:FormatMoney(itemPrice * total), 0.5, 0.8, 1)
                end
            elseif data and data.quality ~= 0 and IT:HasAuctionator() then
                GameTooltip:AddDoubleLine("AH Price:", "No data", 0.5, 0.8, 1, 0.5, 0.5, 0.5)
            end
            GameTooltip:Show()
        end
    end)
    row:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    -- Click to link in chat
    row:SetScript("OnClick", function(self, button)
        local data = IT.itemCache[self.itemID]
        if data and data.link then
            if IsModifiedClick("CHATLINK") then
                ChatEdit_InsertLink(data.link)
            elseif button == "LeftButton" then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetHyperlink(data.link)
                GameTooltip:Show()
            end
        end
    end)

    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    row:Hide()
    return row
end

------------------------------------------------------------
-- Add Item Box
------------------------------------------------------------
function IT:CreateAddBox(parent)
    local box = CreateFrame("EditBox", "SaveMyItemsAddBox", parent, "InputBoxTemplate")
    box:SetSize(FRAME_WIDTH - 80, 20)
    box:SetPoint("BOTTOMLEFT", parent.InsetBg or parent.Inset, "BOTTOMLEFT", 12, 24)
    box:SetAutoFocus(false)
    box:SetMaxLetters(10)
    box:SetNumeric(true)

    local label = box:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("LEFT", box, "LEFT", 0, 0)

    box:SetScript("OnEnterPressed", function(self)
        local text = self:GetText()
        if text and text ~= "" then
            local ok, msg = IT:AddItem(text)
            if ok then
                print("|cff00ccffSave My Items|r: Added item " .. text .. " to " .. IT:GetActiveCategoryName() .. ".")
            else
                print("|cff00ccffSave My Items|r: " .. (msg or "Failed."))
            end
        end
        self:SetText("")
        self:ClearFocus()
    end)

    box:SetScript("OnEscapePressed", function(self)
        self:SetText("")
        self:ClearFocus()
    end)

    -- Placeholder text
    box.Instructions = box:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    box.Instructions:SetPoint("LEFT", 6, 0)
    box.Instructions:SetText("Enter Item ID and press Enter")
    box:SetScript("OnEditFocusGained", function(self) self.Instructions:Hide() end)
    box:SetScript("OnEditFocusLost", function(self)
        if self:GetText() == "" then self.Instructions:Show() end
    end)

    -- Add button
    local addBtn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    addBtn:SetSize(50, 22)
    addBtn:SetPoint("LEFT", box, "RIGHT", 4, 0)
    addBtn:SetText("Add")
    addBtn:SetScript("OnClick", function()
        local text = box:GetText()
        if text and text ~= "" then
            local ok, msg = IT:AddItem(text)
            if ok then
                print("|cff00ccffSave My Items|r: Added item " .. text .. " to " .. IT:GetActiveCategoryName() .. ".")
            else
                print("|cff00ccffSave My Items|r: " .. (msg or "Failed."))
            end
        end
        box:SetText("")
        box:ClearFocus()
    end)
end

------------------------------------------------------------
-- Refresh / Update
------------------------------------------------------------
function IT:RefreshUI()
    if not self.frame or not self.rows then return end

    local totalItems = #self.sortedItems
    local catName = self:GetActiveCategoryName()
    self.countLabel:SetText(catName .. ": " .. totalItems .. " item" .. (totalItems == 1 and "" or "s"))

    -- Compute grand total value across all items in this category
    local grandTotal = 0
    for _, id in ipairs(self.sortedItems) do
        local itemPrice = self:GetItemPrice(id)
        if itemPrice then
            local _, total = self:GetOwnedCount(id)
            grandTotal = grandTotal + (itemPrice * total)
        end
    end
    if grandTotal > 0 then
        self.totalLabel:SetText("Total: " .. self:FormatMoney(grandTotal))
    else
        self.totalLabel:SetText("")
    end

    FauxScrollFrame_Update(self.scrollFrame, totalItems, VISIBLE_ROWS, ROW_HEIGHT)

    local offset = FauxScrollFrame_GetOffset(self.scrollFrame)

    for i = 1, VISIBLE_ROWS do
        local idx = offset + i
        local row = self.rows[i]

        if idx <= totalItems then
            local itemID = self.sortedItems[idx]
            local data = self.itemCache[itemID]

            row.itemID = itemID

            if data then
                row.icon:SetTexture(data.icon)
                local c = self:GetQualityColor(data.quality)
                row.name:SetText(data.name)
                row.name:SetTextColor(c[1], c[2], c[3])

                local bags, total = self:GetOwnedCount(itemID)
                if total > bags then
                    row.count:SetText(bags .. "/" .. total)
                else
                    row.count:SetText(tostring(bags))
                end
                row.count:SetTextColor(bags > 0 and 1 or 0.5, bags > 0 and 1 or 0.5, bags > 0 and 1 or 0.5)

                local itemPrice = self:GetItemPrice(itemID)
                if itemPrice then
                    row.priceUnit:SetText("|cff999999" .. (self:FormatMoney(itemPrice) or "") .. "|r")
                    local totalValue = itemPrice * total
                    row.price:SetText(self:FormatMoney(totalValue) or "")
                elseif data.quality ~= 0 and self:HasAuctionator() then
                    row.priceUnit:SetText("")
                    row.price:SetText("|cff666666-|r")
                else
                    row.priceUnit:SetText("")
                    row.price:SetText("")
                end
            else
                row.icon:SetTexture(134400)
                row.name:SetText("Loading... (ID: " .. itemID .. ")")
                row.name:SetTextColor(0.5, 0.5, 0.5)
                row.count:SetText("")
                row.priceUnit:SetText("")
                row.price:SetText("")
            end

            row:Show()
        else
            row:Hide()
        end
    end
end
