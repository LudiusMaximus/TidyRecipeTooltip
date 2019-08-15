local folderName = ...
local L = LibStub("AceAddon-3.0"):NewAddon(folderName, "AceTimer-3.0")


local table_insert = table.insert

local string_byte = string.byte
local string_find = string.find
local string_format = string.format
local string_gmatch = string.gmatch
local string_gsub = string.gsub
local string_lower = string.lower
local string_match = string.match
local string_sub = string.sub

local tonumber = tonumber

local _G = _G
local CreateFrame = _G.CreateFrame
local GameTooltip = _G.GameTooltip
local GetItemInfo = _G.GetItemInfo

local LE_ITEM_RECIPE_BOOK = _G.LE_ITEM_RECIPE_BOOK
local LE_ITEM_CLASS_RECIPE = _G.LE_ITEM_CLASS_RECIPE

local ITEM_SPELL_TRIGGER_ONUSE = _G.ITEM_SPELL_TRIGGER_ONUSE
local TOOLTIP_SUPERCEDING_SPELL_NOT_KNOWN = _G.TOOLTIP_SUPERCEDING_SPELL_NOT_KNOWN
local MINIMAP_TRACKING_VENDOR_REAGENT = _G.MINIMAP_TRACKING_VENDOR_REAGENT

-- I have to set my hook after all other tooltip addons.
-- Because I am doing a ClearLines(), which may cause other addons (like BagSync)
-- to clear the attribute they are using to only execute on the first of the
-- two calls of OnTooltipSetItem().
-- Therefore take this timer!
local startupFrame = CreateFrame("Frame")
startupFrame:RegisterEvent("PLAYER_LOGIN")
startupFrame:SetScript("OnEvent", function(self, event, ...)
  L:ScheduleTimer("initCode", 3.0)
end)



-- Have to override GameTooltip.GetItem() after calling ClearLines().
-- This will restore the original after the tooltip is closed.
-- (Actually not needed if we are really the last tooltip hook,
-- but it does not hurt either.)
local originalGetItem = GameTooltip.GetItem
GameTooltip:HookScript("OnHide", function(self)
  GameTooltip.GetItem = originalGetItem
end)

-- These are the lines at which other addons start their content.
-- Depending how clever the other addon is they add their
-- content in the first or second call of OnTooltipSetItem().
local firstCallAddonsStartLine = nil
local secondCallAddonsStartLine = nil


-- To know if we are in the first or second call of OnTooltipSetItem() for recipes
-- we scan the tooltip for the "Use: Teaches you..." line.
-- There is the global string ITEM_SPELL_TRIGGER_ONUSE for "Use:"
-- but there is none for "Teaches you...".
-- Just scanning for "Use:" is not enough, as recipe products have a "Use:" too.
-- Thus, we would have to store these strings for all locales:
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


-- Some recipes have two "Use: Teaches you" lines; one for the recipe
-- and one for the recipe's product.
-- E.g.: https://www.wowhead.com/item=67538/recipe-vial-of-the-sands
-- To recognise the line of the recipe, we check if the recipe's product
-- name occurs in it. This does not necessarily work, because sometimes
-- some recipes are called differently in the "Use: Teaches you" line.
-- E.g.: https://de.wowhead.com/item=21371/muster-kernteufelsstofftasche
-- But as long as it works for all the recipes with two "Use: Teaches you"
-- lines, we are fine!
local recipeIdsWithTwoTeachesYouLines = {
  [67538] = true,      -- Recipe: Vial of the Sands
}


local locale = GetLocale()



-- Searches the tooltip for "Use: Teaches you..." and returns the line number.
local function GetUseTeachesYouLineNumber(tooltip, name, link)

  -- We first search for the "Use: Teaches you" line.
  local searchPattern1 = nil
  -- koKR is right to left.
  if locale == "koKR" then
    searchPattern1 = "^" .. ITEM_SPELL_TRIGGER_ONUSE .. ".-" .. teachesYouString[locale]
  else
    searchPattern1 = "^" .. ITEM_SPELL_TRIGGER_ONUSE .. ".-" .. teachesYouString[locale]
  end

  local itemId = tonumber(string_match(link, "^.-:(%d+):"))


  -- Search from bottom to top, because the searched line is most likely down.
  -- Only search up to line 2, because the searched line is definitely not topmost.
  for i = tooltip:NumLines(), 2, -1 do
    local line = _G[tooltip:GetName().."TextLeft"..i]:GetText()
    if string_find(line, searchPattern1) then

      if not recipeIdsWithTwoTeachesYouLines[itemId] then
        return i
      else
        
        -- For recipes with two "Use: Teaches you" lines we check
        -- if the recipe's product name occurs in it.
        local productName = nil
        -- zhCN and zhTW have a special colon.
        if locale == "zhCN" or locale == "zhTW" then
          productName = string_match(name, ".-：(.+)")
        else
          productName = string_match(name, ".-: (.+)")
        end
        if not productName then return nil end

        -- The complete product name is sometimes not included in the
        -- "Use: Teaches you" line. E.g.:
        -- https://ru.wowhead.com/item=67538

        -- We therefore search for each word separately.
        -- This can go wrong, if e.g. for "Vial of the sands"
        -- "of" or "the" would also occur in the recipe product's 
        -- "Use: Teaches you" line. We have to make sure it works
        -- for every item of recipeIdsWithTwoTeachesYouLines.
        
        local productNameWords = {}
        for word in string_gmatch(productName, "%S+") do
          -- Insert word into the table and espace characters - + % . ( ) [ ].
          local escapedWord = string_gsub(word, "[%-+%%.()%[%]]", "%%%0")
          table_insert(productNameWords, escapedWord)
        end

        -- Search from back to front as the last word is more likely to hit!
        for j = #productNameWords, 1, -1 do

          local searchPattern2 = nil
          -- koKR is right to left.
          if locale == "koKR" then
            searchPattern2 = "^" .. ITEM_SPELL_TRIGGER_ONUSE .. ".-" .. productNameWords[j] .. ".-" .. teachesYouString[locale]
          else
            searchPattern2 = "^" .. ITEM_SPELL_TRIGGER_ONUSE .. ".-" .. teachesYouString[locale] .. ".-" .. productNameWords[j]
          end

          if string_find(string_lower(line), string_lower(searchPattern2)) then
            return i
          end
          
        end
        
      end
    end
  end

  return nil

end


local function AddLineOrDoubleLine(tooltip, leftText, rightText, leftTextR, leftTextG, leftTextB, rightTextR, rightTextG, rightTextB, intendedWordWrap)
  if rightText then
    tooltip:AddDoubleLine(leftText, rightText, leftTextR, leftTextG, leftTextB, rightTextR, rightTextG, rightTextB)
  else
    tooltip:AddLine(leftText, leftTextR, leftTextG, leftTextB, intendedWordWrap)
  end
end




function L:initCode()

  if not teachesYouString[locale] then
    print("TidyRecipeTooltip: Locale", locale, "not supported. Contact the developer!")
    return
  end


  -- We do a prehook to read the tooltip before any other addons
  -- have changed it. This will allow us to move their content
  -- to the bottom regardless of whether they have appended
  -- it in the first or second call of OnTooltipSetItem().

  local otherScripts = GameTooltip:GetScript("OnTooltipSetItem")
  local function RunOtherScripts(self, ...)
    if otherScripts then
      return otherScripts(self, ...)
    else
      return
    end
  end

  GameTooltip:SetScript("OnTooltipSetItem", function(self, ...)

    -- Find out if this is the first or second call of OnTooltipSetItem().
    local name, link = self:GetItem()
    if not name or not link then return RunOtherScripts(self, ...) end

    local _, _, _, _, _, _, _, _, _, _, _, itemTypeId, itemSubTypeId = GetItemInfo(link)
    if itemTypeId ~= LE_ITEM_CLASS_RECIPE or itemSubTypeId == LE_ITEM_RECIPE_BOOK then return RunOtherScripts(self, ...) end

    local useTeachesYouLineNumber = GetUseTeachesYouLineNumber(self, name, link)
    if not useTeachesYouLineNumber then

      -- For debugging:
      -- print("|n|nPREHOOK: This is the first call, STOP!")
      -- for i = 1, self:NumLines(), 1 do
        -- local line = _G[self:GetName().."TextLeft"..i]:GetText()
        -- print (i, line)
      -- end

      firstCallAddonsStartLine = self:NumLines() + 1

      return RunOtherScripts(self, ...)

    end
      
    -- For debugging:
    -- print("|n|nPREHOOK: This is the second call, PROCEED!")
    -- for i = 1, self:NumLines(), 1 do
      -- local line = _G[self:GetName().."TextLeft"..i]:GetText()
      -- print (i, line)
    -- end

    secondCallAddonsStartLine = self:NumLines() + 1

    return RunOtherScripts(self, ...)
    
  end)





  -- This is our posthook in which we are actually doing our changes.
  GameTooltip:HookScript("OnTooltipSetItem", function(self)

    -- Find out if this is the first or second call of OnTooltipSetItem().
    local name, link = self:GetItem()
    if not name or not link then return end

    local _, _, _, _, _, _, _, _, _, _, itemSellPrice, itemTypeId, itemSubTypeId = GetItemInfo(link)
    -- Only looking at recipes, but not touching those books...
    if itemTypeId ~= LE_ITEM_CLASS_RECIPE or itemSubTypeId == LE_ITEM_RECIPE_BOOK then return end

    local useTeachesYouLineNumber = GetUseTeachesYouLineNumber(self, name, link)
    if not useTeachesYouLineNumber then

      -- For debugging:
      -- print("|n|nPOSTHOOK: This is the first call, STOP!")
      -- for i = 1, self:NumLines(), 1 do
        -- local line = _G[self:GetName().."TextLeft"..i]:GetText()
        -- print (i, line)
      -- end

      return
      
    end
    

    -- For debugging:
    -- print("|n|nPOSTHOOK: This is the second call, PROCEED!")
    -- for i = 1, self:NumLines(), 1 do
      -- local line = _G[self:GetName().."TextLeft"..i]:GetText()
      -- print (i, line)
    -- end



    -- Collect the other important line numbers.
    local recipeProductFirstLineNumber = nil
    local reagentsLineNumber = nil
    local moneyFrameLineNumber = nil
    -- Should always be the same as itemSellPrice.
    local moneyAmount = nil


    -- Check if there is a moneyFrameLineNumber.
    if itemSellPrice > 0 then
      if self.shownMoneyFrames then
        -- If there are money frames, we check if "SELL_PRICE: ..." is among them.
        for i = 1, self.shownMoneyFrames, 1 do

          local moneyFrameName = self:GetName().."MoneyFrame"..i
          if _G[moneyFrameName.."PrefixText"]:GetText() == string_format("%s:", SELL_PRICE) then

            local _, moneyFrameAnchor = _G[moneyFrameName]:GetPoint(1)
            moneyFrameLineNumber = tonumber(string_match(moneyFrameAnchor:GetName(), self:GetName().."TextLeft(%d+)"))
            -- Should always be the same as itemSellPrice, as recipes never stack.
            moneyAmount = _G[moneyFrameName].staticMoney
            break
          end
        end
      end
    end


    -- Scan the original tooltip and collect the lines.
    -- Store all text and text colours of the original tooltip lines.
    -- TODO: Unfortunately I do not know how to store the "indented word wrap".
    --       Therefore, we have to put wrap=true for most lines in the new tooltip,
    --       except for those we have obsevered to be never wrapped.
    local leftText = {}
    local leftTextR = {}
    local leftTextG = {}
    local leftTextB = {}

    local rightText = {}
    local rightTextR = {}
    local rightTextG = {}
    local rightTextB = {}


    -- Store the number of lines for after ClearLines().
    local numLines = self:NumLines()


    -- Store all lines of the original tooltip.
    for i = 1, numLines, 1 do

      leftText[i] = _G[self:GetName().."TextLeft"..i]:GetText()
      leftTextR[i], leftTextG[i], leftTextB[i] = _G[self:GetName().."TextLeft"..i]:GetTextColor()

      rightText[i] = _G[self:GetName().."TextRight"..i]:GetText()
      rightTextR[i], rightTextG[i], rightTextB[i] = _G[self:GetName().."TextRight"..i]:GetTextColor()


      -- Collect the important line numbers.

      -- The recipe prodocut line begins with a line break!
      if not recipeProductFirstLineNumber then
        if string_byte(string_sub(leftText[i], 1, 1)) == 10 then
          recipeProductFirstLineNumber = i
        end
      -- Don't need to do anything until after useTeachesYouLineNumber.
      elseif not reagentsLineNumber and i > useTeachesYouLineNumber then
        -- The reagents are directly after useTeachesYouLineNumber
        -- unless TOOLTIP_SUPERCEDING_SPELL_NOT_KNOWN is in between.
        if leftText[i] ~= TOOLTIP_SUPERCEDING_SPELL_NOT_KNOWN then
          reagentsLineNumber = i
        end
      end

    end


    if not recipeProductFirstLineNumber or not reagentsLineNumber then return end


    self:ClearLines()

    -- Overriding GameTooltip.GetItem(), such that other addons can still use it
    -- to learn which item is displayed. Will be restored after GameTooltip:OnHide() (see above).
    -- (Actually not needed if we are really the last tooltip hook, but it does not hurt either.)
    self.GetItem = function(self) return name, link end


    -- Never word wrap the title line!
    AddLineOrDoubleLine(self, leftText[1], rightText[1], leftTextR[1], leftTextG[1], leftTextB[1], rightTextR[1], rightTextG[1], rightTextB[1], false)

    -- Print the header lines.
    for i = 2, recipeProductFirstLineNumber-1, 1 do
      AddLineOrDoubleLine(self, leftText[i], rightText[i], leftTextR[i], leftTextG[i], leftTextB[i], rightTextR[i], rightTextG[i], rightTextB[i], true)
    end

    -- Print "Use: Teaches you" in green!
    self:AddLine(leftText[useTeachesYouLineNumber], 0, 1, 0, true)

    -- Print everything after useTeachesYouLineNumber until secondCallAddonsStartLine - 1
    -- except for reagentsLineNumber and moneyFrameLineNumber.
    -- Also never word wrap here!
    for i = useTeachesYouLineNumber+1, secondCallAddonsStartLine - 1, 1 do
      if i ~= reagentsLineNumber and i~= moneyFrameLineNumber then
        AddLineOrDoubleLine(self, leftText[i], rightText[i], leftTextR[i], leftTextG[i], leftTextB[i], rightTextR[i], rightTextG[i], rightTextB[i], false)
      end
    end

    -- Print a money line if applicable.
    if moneyAmount or itemSellPrice > 0 then
      SetTooltipMoney(self, moneyAmount or itemSellPrice, nil, string_format("%s:", SELL_PRICE))
    end

    -- Print the recipe product info.
    for i = recipeProductFirstLineNumber, firstCallAddonsStartLine-1, 1 do
      AddLineOrDoubleLine(self, leftText[i], rightText[i], leftTextR[i], leftTextG[i], leftTextB[i], rightTextR[i], rightTextG[i], rightTextB[i], true)
    end

    -- Print the reagents.
    self:AddLine(" ")
    self:AddLine(MINIMAP_TRACKING_VENDOR_REAGENT .. ": " .. leftText[reagentsLineNumber], leftTextR[reagentsLineNumber], leftTextG[reagentsLineNumber], leftTextB[reagentsLineNumber], true)

    -- Print first call addons.
    for i = firstCallAddonsStartLine, useTeachesYouLineNumber-1, 1 do
      AddLineOrDoubleLine(self, leftText[i], rightText[i], leftTextR[i], leftTextG[i], leftTextB[i], rightTextR[i], rightTextG[i], rightTextB[i], true)
    end

    -- Print second call addons.
    for i = secondCallAddonsStartLine, numLines, 1 do
      AddLineOrDoubleLine(self, leftText[i], rightText[i], leftTextR[i], leftTextG[i], leftTextB[i], rightTextR[i], rightTextG[i], rightTextB[i], true)
    end

  end);
end

