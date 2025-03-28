local folderName = ...


local string_byte = string.byte
local string_find = string.find
local string_format = string.format
local string_match = string.match
local string_sub = string.sub

local tonumber = tonumber

local _G = _G
local CreateFrame = _G.CreateFrame
local GameTooltip = _G.GameTooltip
local GetItemInfo = _G.C_Item.GetItemInfo
local GetTime     = _G.GetTime

local LE_ITEM_RECIPE_BOOK = _G.LE_ITEM_RECIPE_BOOK
local LE_ITEM_CLASS_RECIPE = _G.LE_ITEM_CLASS_RECIPE

local ITEM_SPELL_TRIGGER_ONUSE = _G.ITEM_SPELL_TRIGGER_ONUSE
local TOOLTIP_SUPERCEDING_SPELL_NOT_KNOWN = _G.TOOLTIP_SUPERCEDING_SPELL_NOT_KNOWN
local MINIMAP_TRACKING_VENDOR_REAGENT = _G.MINIMAP_TRACKING_VENDOR_REAGENT





-- -- For debugging.
-- local function PrintTable(t, indent)
  -- assert(type(t) == "table", "PrintTable() called for non-table!")

  -- local indentString = ""
  -- for i = 1, indent do
    -- indentString = indentString .. "  "
  -- end

  -- for k, v in pairs(t) do
    -- if type(v) ~= "table" then

      -- -- if type(v) == "string" and string_find(v, "Steak") then
      -- if type(v) == "string" then
        -- print(indentString, k, "=", v)
      -- end
    -- else
      -- print(indentString, k, "=")
      -- print(indentString, "  {")
      -- PrintTable(v, indent + 2)
      -- print(indentString, "  }")
    -- end
  -- end
-- end





-- Have to override GameTooltip.GetItem() after calling ClearLines().
-- This will restore the original after the tooltip is closed.
local originalGetItem = GameTooltip.GetItem
GameTooltip:HookScript("OnHide", function(self)
  self.GetItem = originalGetItem
end)



-- To scan the tooltip for the "Use: Teaches you..." line.
-- There is the global string ITEM_SPELL_TRIGGER_ONUSE for "Use:"
-- but there is none for "Teaches you...".
-- Just scanning for "Use:" is not enough, as recipe products have a "Use:" too.
-- Thus, we have to store these strings for all locales:
local teachesYouString = {
  ["deDE"] = "Lehrt Euch",
  ["enUS"] = "Teaches you",
  ["enGB"] = "Teaches you",
  ["esES"] = "Te enseña",
  ["esMX"] = "Te enseña",
  ["frFR"] = "Vous apprend",
  ["itIT"] = "Ti insegna",
  ["koKR"] = "배웁니다",
  ["ptBR"] = "Ensina",
  ["ruRU"] = "Обучает",
  ["zhCN"] = "教你",
  ["zhTW"] = "教你"
}


local locale = GetLocale()

if not teachesYouString[locale] then
  print("TidyRecipeTooltip: Locale", locale, "not supported. Please contact the developer!")
  return
end





-- Searches the tooltip for "Use: Teaches you..." and returns the line number.
local function GetUseTeachesYouLineNumber(tooltip, itemId)

  -- This works also for koKR, which is right to left.
  local searchPattern = "^" .. ITEM_SPELL_TRIGGER_ONUSE .. ".-" .. teachesYouString[locale]

  -- Buggy tooltips:
  -- https://us.forums.blizzard.com/en/wow/t/faults-in-tooltips/825379
  if itemId == 142331 or itemId == 142333 then
    searchPattern = "^" .. ITEM_SPELL_TRIGGER_ONUSE
  end


  -- Search from bottom to top, because the searched line is most likely down.
  -- Furthermore, if it is an item with two "Use: Teaches you..."
  -- like "Recipe: Vial of the Sands" (67538) or "Recipe: Elderhorn Riding Harness" (141850),
  -- we are only interested in the bottommost one.
  -- Only search up to line 2, because the searched line is definitely not topmost.
  for i = tooltip:NumLines(), 2, -1 do
    local line = _G[tooltip:GetName().."TextLeft"..i]:GetText()
    if string_find(line, searchPattern) then
      return i
    end
  end

  return nil

end


local function AddLineOrDoubleLine(tooltip, leftText, rightText, leftTextR, leftTextG, leftTextB, rightTextR, rightTextG, rightTextB, indentedWordWrap)
  if rightText then
    tooltip:AddDoubleLine(leftText, rightText, leftTextR, leftTextG, leftTextB, rightTextR, rightTextG, rightTextB)
  else
    tooltip:AddLine(leftText, leftTextR, leftTextG, leftTextB, indentedWordWrap)
  end
end


local function RearrangeTooltip(self)

  -- -- For debugging if Blizzard changes something, use this to investigate.
  -- PrintTable(self, 1)
  -- if true then return end


  -- TooltipUtil.GetDisplayedItem(self) is the same as self:GetItem()
  local name, unreliableLink, recipeItemId = TooltipUtil.GetDisplayedItem(self)
  if not name or not unreliableLink or not recipeItemId then return end

  -- Get sell price and types of (potential) recipe. Name for debugging.
  local recipeItemName, _, _, _, _, _, _, _, _, _, recipeItemSellPrice, recipeItemTypeId, recipeItemSubTypeId = GetItemInfo(recipeItemId)
  -- print(recipeItemTypeId, Enum.ItemClass.Recipe, recipeItemSubTypeId, Enum.ItemRecipeSubclass.Book)

  -- Only looking at recipes, but not touching those books...
  if recipeItemTypeId ~= Enum.ItemClass.Recipe or recipeItemSubTypeId == Enum.ItemRecipeSubclass.Book then return end



  ------------------------------------------------
  --- Now we know we are dealing with a recipe!
  ------------------------------------------------
  -- print("#########################################################")
  -- print("recipeItemId", recipeItemId)


  -- This always gives us the recipe product.
  local recipeProductItemLink = self.processingInfo.tooltipData.hyperlink
  if not recipeProductItemLink then return end
  local recipeProductItemId = tonumber(string_match(recipeProductItemLink, "^.-:(%d+):"))
  -- print("recipeProductItemId", recipeProductItemId)


  -- This is how we recognise "false" recipes like Prospecting, Milling, Unravelling, etc...
  if recipeItemId == recipeProductItemId then return end


  -- Get sell price (and types, not needed) of recipe product.
  local _, _, _, _, _, _, _, _, _, _, recipeProductItemSellPrice, recipeProductItemTypeId, recipeProductItemSubTypeId = GetItemInfo(recipeProductItemId)


  -- -- The "unreliable link" is sometimes the recipe product (e.g. "Formula: Enchanted Lantern"),
  -- -- and sometimes the recipe itself (e.g. "Recipe: Crocolisk Steak").
  -- -- It seems that the former is the case when the recipe product is itself a teaching item.
  -- local unreliableItemId = tonumber(string_match(unreliableLink, "^.-:(%d+):"))
  -- print("unreliableItemId", unreliableItemId)
  -- if unreliableItemId ~= recipeItemId then
    -- print("This recipe generates another teaching item. Do we need this info?")
  -- end




  -- -- For debugging.
  -- local recipeTooltipLines = C_TooltipInfo.GetItemByID(recipeItemId).lines
  -- print("\n")
  -- print("Tooltip of recipe (only left text):")
  -- local numLines = 1
  -- while recipeTooltipLines[numLines] do
    -- print(numLines, recipeTooltipLines[numLines].leftText)
    -- numLines = numLines + 1
  -- end
  -- print("Sell price of recipe:", recipeItemSellPrice)



  local recipeProductTooltipLines = C_TooltipInfo.GetItemByID(recipeProductItemId).lines


  -- -- For debugging.
  -- print("\n")
  -- print("Tooltip of recipe product (only left text):")
  -- local numLines = 1
  -- while recipeProductTooltipLines[numLines] do
    -- print(numLines, recipeProductTooltipLines[numLines].leftText)
    -- numLines = numLines + 1
  -- end
  -- print("Sell price of recipe product:", recipeProductItemSellPrice)



  -- To store the line of the money frame.
  local moneyFrameLineNumber = nil
  local moneyAmount = nil

  -- Check if there is a moneyFrameLineNumber.
  if recipeItemSellPrice > 0 then
    if self.shownMoneyFrames then
      -- If there are money frames, we check if "SELL_PRICE: ..." is among them.
      for i = 1, self.shownMoneyFrames, 1 do

        local moneyFrameName = self:GetName().."MoneyFrame"..i
        if _G[moneyFrameName.."PrefixText"]:GetText() == string_format("%s:", SELL_PRICE) then

          local _, moneyFrameAnchor = _G[moneyFrameName]:GetPoint(1)
          moneyFrameLineNumber = tonumber(string_match(moneyFrameAnchor:GetName(), self:GetName().."TextLeft(%d+)"))
          -- Should always be the same as recipeItemSellPrice, as recipes never stack.
          moneyAmount = _G[moneyFrameName].staticMoney
          break
        end
      end
    end
  end


  -- If the recipe does not have a sell price (e.g. "Recipe: Haunted Herring"),
  -- we take the last line of the original recipe tooltip. Should also work...
  if moneyFrameLineNumber == nil then

    local recipeTooltipLines = C_TooltipInfo.GetItemByID(recipeItemId).lines
    local numLines = 1
    while recipeTooltipLines[numLines] do
      numLines = numLines + 1
    end
    moneyFrameLineNumber = numLines - 1

  end



  -- To store the start line of recipeProductItem tooltip in recipe tooltip.
  local productStartLine = nil

  -- To store the line of recipe reagents.
  local reagentsLineNumber = nil

  -- Needed to identify end of product tooltip and reagent line number.
  local useTeachesYouLineNumber = GetUseTeachesYouLineNumber(self, recipeItemId)
  if not useTeachesYouLineNumber then
    print("TidyRecipeTooltip: Could not find \"Use: Teaches you...\" line. If this behaviour is reproducible, please report item id", recipeItemId, "to the developer!")
    return
  end



  -- To store all text and text colours of the original tooltip lines.
  local leftText = {}
  local leftTextR = {}
  local leftTextG = {}
  local leftTextB = {}

  local rightText = {}
  local rightTextR = {}
  local rightTextG = {}
  local rightTextB = {}


  local numLinesRecipe = self:NumLines()

  for i = 1, numLinesRecipe, 1 do

    leftText[i] = _G[self:GetName().."TextLeft"..i]:GetText()
    leftTextR[i], leftTextG[i], leftTextB[i] = _G[self:GetName().."TextLeft"..i]:GetTextColor()

    rightText[i] = _G[self:GetName().."TextRight"..i]:GetText()
    rightTextR[i], rightTextG[i], rightTextB[i] = _G[self:GetName().."TextRight"..i]:GetTextColor()

    -- print(i, leftText[i])


    -- For comparison, ignore the initial linebreak character in the recipe tooltip.
    if not productStartLine and strsub(leftText[i], 2) == recipeProductTooltipLines[1].leftText then
      productStartLine = i
    end

    -- The reagents are directly after useTeachesYouLineNumber unless TOOLTIP_SUPERCEDING_SPELL_NOT_KNOWN is in between.
    if not reagentsLineNumber and i > useTeachesYouLineNumber and leftText[i] ~= TOOLTIP_SUPERCEDING_SPELL_NOT_KNOWN then
      reagentsLineNumber = i
    end

  end


  -- If we did not find the product tooltip in the recipe tooltip, we quit.
  -- This should also take care of formulas not teaching an item, where product tooltip and recipe tooltip are the same,
  -- because when we look for the first line we cut off the first character.
  if not productStartLine then
    return
  end

  if not reagentsLineNumber then
    return
  end




  -- print("moneyFrameLineNumber", moneyFrameLineNumber, " (moneyAmount", moneyAmount)
  -- print("productStartLine", productStartLine)
  -- print("reagentsLineNumber", reagentsLineNumber)
  -- print("useTeachesYouLineNumber", useTeachesYouLineNumber)



  -- -- For debugging.
  -- if true then return end



  -- #########################################################
  -- Rebuild the tooltip!
  self:ClearLines()

  -- Overriding GameTooltip.GetItem(), such that other addons can still use it
  -- to learn which item is displayed. Will be restored after GameTooltip:OnHide() (see above).
  -- (Should not be necessary, when we make sure we are the last addon to hook.)
  self.GetItem = function(self) return name, unreliableLink, recipeItemId end


  -- Never word wrap the title line!
  AddLineOrDoubleLine(self, leftText[1], rightText[1], leftTextR[1], leftTextG[1], leftTextB[1], rightTextR[1], rightTextG[1], rightTextB[1], false)


  -- Print the header lines of the recipe.
  for i = 2, productStartLine-1, 1 do
    AddLineOrDoubleLine(self, leftText[i], rightText[i], leftTextR[i], leftTextG[i], leftTextB[i], rightTextR[i], rightTextG[i], rightTextB[i], true)
  end



  -- Print "Use: Teaches you" always in green!
  self:AddLine(leftText[useTeachesYouLineNumber], 0, 1, 0, true)



  -- Print everything after useTeachesYouLineNumber until the money line except for reagentsLineNumber.
  -- Never word wrap here!
  for i = useTeachesYouLineNumber+1, moneyFrameLineNumber-1, 1 do
    if i~= reagentsLineNumber then
      AddLineOrDoubleLine(self, leftText[i], rightText[i], leftTextR[i], leftTextG[i], leftTextB[i], rightTextR[i], rightTextG[i], rightTextB[i], false)
    end
  end

  -- Print money line if applicable.
  if moneyAmount or recipeItemSellPrice > 0 then
    SetTooltipMoney(self, moneyAmount or recipeItemSellPrice, nil, string_format("%s:", SELL_PRICE))
  else
    self:AddLine(ITEM_UNSELLABLE, 1, 1, 1, false)
  end


  -- Print the recipe product info.
  for i = productStartLine, useTeachesYouLineNumber-1, 1 do
    AddLineOrDoubleLine(self, leftText[i], rightText[i], leftTextR[i], leftTextG[i], leftTextB[i], rightTextR[i], rightTextG[i], rightTextB[i], true)
  end

  -- Print the reagents.
  self:AddLine(" ")
  self:AddLine(MINIMAP_TRACKING_VENDOR_REAGENT .. ": " .. leftText[reagentsLineNumber], leftTextR[reagentsLineNumber], leftTextG[reagentsLineNumber], leftTextB[reagentsLineNumber], true)

  -- Print everything after the original money line.
  for i = moneyFrameLineNumber+1, numLinesRecipe, 1 do
    AddLineOrDoubleLine(self, leftText[i], rightText[i], leftTextR[i], leftTextG[i], leftTextB[i], rightTextR[i], rightTextG[i], rightTextB[i], false)
  end

end



local function InitCode()
  TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, RearrangeTooltip)
end


-- Increase chance that we are the last addon to hook,
-- avoiding interference with other addons.
local startupFrame = CreateFrame("Frame")
startupFrame:RegisterEvent("PLAYER_LOGIN")
startupFrame:SetScript("OnEvent", function(self, event, ...)
  C_Timer.After(3, InitCode)
end)





-- -- To test recipe tooltips by item id:
-- local testframe1 = CreateFrame("Frame", _, UIParent, BackdropTemplateMixin and "BackdropTemplate")
-- testframe1:SetBackdrop({ bgFile = "Interface/Tooltips/UI-Tooltip-Background",
                      -- edgeFile = "Interface/DialogFrame/UI-DialogBox-Border",
                      -- tile = true, tileSize = 16, edgeSize = 16,
                      -- insets = { left = 4, right = 4, top = 4, bottom = 4 }})
-- testframe1:SetBackdropColor(0.0, 0.0, 0.0, 1.0)
-- testframe1:SetPoint("CENTER", UIParent, "CENTER", 0, 0)

-- testframe1:SetWidth(300)
-- testframe1:SetHeight(100)

-- testframe1:SetMovable(true)
-- testframe1:EnableMouse(true)
-- testframe1:RegisterForDrag("LeftButton")
-- testframe1:SetScript("OnDragStart", testframe1.StartMoving)
-- testframe1:SetScript("OnDragStop", testframe1.StopMovingOrSizing)
-- testframe1:SetClampedToScreen(true)


-- testframe1:SetScript("OnEnter", function()
  -- GameTooltip:SetOwner(testframe1, "ANCHOR_TOPLEFT")

  -- -- Recipes creating a usable item.
  -- -- These are itemTypeId 15 (Miscellaneous)
  -- -- GameTooltip:SetHyperlink("item:67308:0:0:0:0:0:0:0")    -- itemSubTypeId 2 (Companion Pets)
  -- -- GameTooltip:SetHyperlink("item:67538:0:0:0:0:0:0:0")    -- itemSubTypeId 5 (Mounts)
  -- -- GameTooltip:SetHyperlink("item:141850:0:0:0:0:0:0:0")   -- itemSubTypeId 5 (Mounts)

  -- -- Grey recipe not teaching anything.
  -- -- GameTooltip:SetHyperlink("item:104230:0:0:0:0:0:0:0")

  -- -- Formula that only teaches a spell but no item.
  -- -- GameTooltip:SetHyperlink("item:16252:0:0:0:0:0:0:0")

  -- -- Recipes with buggy tooltips.
  -- -- https://us.forums.blizzard.com/en/wow/t/faults-in-tooltips/825379
  -- -- GameTooltip:SetHyperlink("item:142331:0:0:0:0:0:0:0")
  -- -- GameTooltip:SetHyperlink("item:142333:0:0:0:0:0:0:0")

  -- -- GameTooltip:SetHyperlink("item:198132:0:0:0:0:0:0:0")

  -- -- Pattern: Boots of Natural Grace
  -- -- GameTooltip:SetHyperlink("item:30305:0:0:0:0:0:0:0")

  -- -- Schematic: Unstable Temporal Time Shifter
  -- -- GameTooltip:SetHyperlink("item:166736:0:0:0:0:0:0:0")

  -- -- "Recipes" where the recipeItemId == recipeProductItemId.
  -- GameTooltip:SetHyperlink("item:16083:0:0:0:0:0:0:0")    -- Expert Fishing - The Bass and You
  -- -- GameTooltip:SetHyperlink("item:219191:0:0:0:0:0:0:0")   -- Hastily Scrawled Notes
  -- -- GameTooltip:SetHyperlink("item:221968:0:0:0:0:0:0:0")   -- Legibly Scribbled Notes
  -- -- GameTooltip:SetHyperlink("item:194709:0:0:0:0:0:0:0")   -- Prospecting
  


  -- GameTooltip:Show()
-- end )

