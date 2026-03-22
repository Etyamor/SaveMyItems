-- SaveMyItems Slash Commands
local _, IT = ...

function IT:RegisterSlashCommands()
    SLASH_SAVEMYITEMS1 = "/savemyitems"
    SLASH_SAVEMYITEMS2 = "/smi"

    SlashCmdList["SAVEMYITEMS"] = function(msg)
        local cmd, arg = msg:match("^(%S+)%s*(.*)")
        cmd = cmd and cmd:lower() or msg:lower()

        if cmd == "add" and arg ~= "" then
            local id = arg:match("item:(%d+)") or tonumber(arg)
            if id then
                local ok, err = IT:AddItem(id)
                if ok then
                    print("|cff00ccffSave My Items|r: Added item " .. id .. " to " .. IT:GetActiveCategoryName() .. ".")
                else
                    print("|cff00ccffSave My Items|r: " .. err)
                end
            else
                print("|cff00ccffSave My Items|r: Usage: /smi add <itemID>")
            end

        elseif cmd == "remove" or cmd == "rm" or cmd == "delete" then
            local id = arg:match("item:(%d+)") or tonumber(arg)
            if id then
                local ok, err = IT:RemoveItem(id)
                if ok then
                    print("|cff00ccffSave My Items|r: Removed item " .. id .. " from " .. IT:GetActiveCategoryName() .. ".")
                else
                    print("|cff00ccffSave My Items|r: " .. err)
                end
            else
                print("|cff00ccffSave My Items|r: Usage: /smi remove <itemID>")
            end

        elseif cmd == "clear" then
            local items = IT:GetActiveItems()
            wipe(items)
            wipe(IT.sortedItems)
            IT:RebuildSortedList()
            IT:RefreshUI()
            print("|cff00ccffSave My Items|r: Cleared all items from \"" .. IT:GetActiveCategoryName() .. "\".")

        elseif cmd == "show" or cmd == "" then
            IT.frame:Show()

        elseif cmd == "hide" or cmd == "close" then
            IT.frame:Hide()

        elseif cmd == "toggle" then
            if IT.frame:IsShown() then
                IT.frame:Hide()
            else
                IT.frame:Show()
            end

        elseif cmd == "list" then
            local catName = IT:GetActiveCategoryName()
            if #IT.sortedItems == 0 then
                print("|cff00ccffSave My Items|r: No items in \"" .. catName .. "\".")
            else
                print("|cff00ccffSave My Items|r: Items in \"" .. catName .. "\":")
                for _, id in ipairs(IT.sortedItems) do
                    local data = IT.itemCache[id]
                    if data then
                        print("  " .. data.link .. " (ID: " .. id .. ")")
                    else
                        print("  ID: " .. id .. " (loading...)")
                    end
                end
            end

        elseif cmd == "cat" or cmd == "category" then
            local subCmd, subArg = arg:match("^(%S+)%s*(.*)")
            subCmd = subCmd and subCmd:lower() or ""

            if subCmd == "add" or subCmd == "new" then
                if subArg == "" then
                    print("|cff00ccffSave My Items|r: Usage: /smi cat add <name>")
                else
                    local ok, result = IT:AddCategory(subArg)
                    if ok then
                        IT:SetActiveCategory(result)
                        print("|cff00ccffSave My Items|r: Created category \"" .. subArg .. "\".")
                    else
                        print("|cff00ccffSave My Items|r: " .. result)
                    end
                end

            elseif subCmd == "remove" or subCmd == "delete" or subCmd == "rm" then
                if subArg == "" then
                    print("|cff00ccffSave My Items|r: Usage: /smi cat remove <name>")
                else
                    local found = IT:FindCategoryByName(subArg)
                    if found then
                        local name = IT.db.categories[found].name
                        local ok, err = IT:RemoveCategory(found)
                        if ok then
                            print("|cff00ccffSave My Items|r: Deleted category \"" .. name .. "\".")
                        else
                            print("|cff00ccffSave My Items|r: " .. err)
                        end
                    else
                        print("|cff00ccffSave My Items|r: Category \"" .. subArg .. "\" not found.")
                    end
                end

            elseif subCmd == "rename" then
                local oldName, newName = subArg:match("^(.-)%s*|%s*(.+)$")
                if oldName and newName then
                    local found = IT:FindCategoryByName(oldName)
                    if found then
                        local ok, err = IT:RenameCategory(found, newName)
                        if ok then
                            print("|cff00ccffSave My Items|r: Renamed to \"" .. newName .. "\".")
                        else
                            print("|cff00ccffSave My Items|r: " .. err)
                        end
                    else
                        print("|cff00ccffSave My Items|r: Category \"" .. oldName .. "\" not found.")
                    end
                else
                    print("|cff00ccffSave My Items|r: Usage: /smi cat rename OldName | NewName")
                end

            elseif subCmd == "list" or subCmd == "" then
                print("|cff00ccffSave My Items|r: Categories:")
                for _, key in ipairs(IT.db.categoryOrder) do
                    local cat = IT.db.categories[key]
                    local count = 0
                    for _ in pairs(cat.items) do count = count + 1 end
                    local marker = (key == IT.activeCategory) and " |cff00ff00<active>|r" or ""
                    print("  " .. cat.name .. " (" .. count .. " items)" .. marker)
                end

            else
                -- Treat entire arg as a category name to switch to
                local found = IT:FindCategoryByName(arg)
                if found then
                    IT:SetActiveCategory(found)
                    print("|cff00ccffSave My Items|r: Switched to \"" .. IT.db.categories[found].name .. "\".")
                else
                    print("|cff00ccffSave My Items|r: Category \"" .. arg .. "\" not found. Use /smi cat list.")
                end
            end

        elseif cmd == "help" then
            print("|cff00ccffSave My Items|r commands:")
            print("  |cff00ff00/smi|r or |cff00ff00/smi show|r - Open the tracker window")
            print("  |cff00ff00/smi hide|r - Close the tracker window")
            print("  |cff00ff00/smi toggle|r - Toggle the tracker window")
            print("  |cff00ff00/smi add <itemID>|r - Add an item to the active category")
            print("  |cff00ff00/smi remove <itemID>|r - Remove an item")
            print("  |cff00ff00/smi list|r - List items in the active category")
            print("  |cff00ff00/smi clear|r - Clear items in the active category")
            print("  |cff00ff00--- Categories ---|r")
            print("  |cff00ff00/smi cat|r or |cff00ff00/smi cat list|r - List all categories")
            print("  |cff00ff00/smi cat add <name>|r - Create a new category")
            print("  |cff00ff00/smi cat remove <name>|r - Delete a category")
            print("  |cff00ff00/smi cat rename Old | New|r - Rename a category")
            print("  |cff00ff00/smi cat <name>|r - Switch to a category")
            print("  |cff00ff00/smi help|r - Show this help")
        else
            print("|cff00ccffSave My Items|r: Unknown command. Type |cff00ff00/smi help|r for usage.")
        end
    end
end
