local folderName = ...
local L = LibStub("AceAddon-3.0"):NewAddon(folderName, "AceTimer-3.0")


local string_find = string.find
local string_format = string.format
local string_match = string.match
local string_byte = string.byte
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

-- Have to set my prehook after all other tooltip addons have loaded.
-- Therefore take this timer!
local startupFrame = CreateFrame("Frame")
startupFrame:RegisterEvent("PLAYER_LOGIN")
startupFrame:SetScript("OnEvent", function(self, event, ...)
  L:ScheduleTimer("initCode", 3.0)
end)



-- Have to override GameTooltip.GetItem() after calling ClearLines().
-- This will restore the original after the tooltip is closed.
local originalGetItem = GameTooltip.GetItem
GameTooltip:HookScript("OnHide", function(self)
  GameTooltip.GetItem = originalGetItem
end)



-- To know if we are in the first or second call of OnTooltipSetItem()
-- for recipes without a sell price, we to scan the tooltip for "Use: Teaches you...".
-- There is the global string ITEM_SPELL_TRIGGER_ONUSE for "Use:"
-- but there is none for "Teaches you...".
-- Just scanning for "Use:" is not enough, as consumable recipe products have a "Use:" too.
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

local locale = GetLocale()
local localeFound = true
if not teachesYouString[locale] then
  localeFound = false
  print("TidyRecipeTooltip: Locale", locale, "not supported. Contact the developer!")
end



function L:initCode()

  if not localeFound then return end

  -- Save any previously registered scripts.
  local otherScripts = GameTooltip:GetScript("OnTooltipSetItem")

  -- Futureproofing, support extra args to pass to previous scripts
  GameTooltip:SetScript("OnTooltipSetItem", function(self, ...)

    -- OnTooltipSetItem gets called twice for recipes which contain embedded items. We only want the second one!
    local name, link = self:GetItem()

    -- Just to be on the safe side...
    if not name or not link then return otherScripts(self, ...) end

    local _, _, _, _, _, _, _, _, _, _, itemSellPrice, itemTypeId, itemSubTypeID = GetItemInfo(link)

    -- Only looking at recipes, but not touching those books...
    if itemTypeId == LE_ITEM_CLASS_RECIPE and itemSubTypeID ~= LE_ITEM_RECIPE_BOOK then


      -- Some recipes may even have two "Use: Teaches you" lines
      -- (e.g. https://www.wowhead.com/item=67538/recipe-vial-of-the-sands)
      -- which is why we have to check that it is the correct one.

      local productName = nil
      -- zhCN and zhTW have a special colon.
      if locale == "zhCN" or locale == "zhTW" then
        productName = string_match(name, ".-：(.+)")
      else
        productName = string_match(name, ".-: (.+)")
      end

      -- If something goes wrong, do nothing.
      if not productName then return otherScripts(self, ...) end


      local searchPattern = nil
      -- koKR is right to left.
      if locale == "koKR" then
        searchPattern = "^" .. ITEM_SPELL_TRIGGER_ONUSE .. ".-" .. productName .. ".-" .. teachesYouString[locale]
      else
        searchPattern = "^" .. ITEM_SPELL_TRIGGER_ONUSE .. ".-" .. teachesYouString[locale] .. ".-" .. productName
      end


      -- Scan the tooltip for "Use: Teaches you".
      -- Search from bottom to top, because the searched line is most likely down.
      -- Only search up to line 2, because the searched line is definitely not topmost.
      local tooltipNeedsTidying = false
      for i = self:NumLines(), 2, -1 do
        local line = _G[self:GetName().."TextLeft"..i]:GetText()
        if string_find(line, searchPattern) then
          tooltipNeedsTidying = true
          break
        end
      end

      if not tooltipNeedsTidying then return otherScripts(self, ...) end


      -- Collect the important line numbers.
      local recipeProductFirstLineNumber = nil
      local useTeachesYouLineNumber = nil
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
      --       Therefore, we have to put wrap=true for all lines in the new tooltip.
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
        elseif not useTeachesYouLineNumber then
          if string_find(leftText[i], searchPattern) then
            useTeachesYouLineNumber = i
          end
        elseif not reagentsLineNumber then
          -- The reagents are directly after useTeachesYouLineNumber
          -- unless TOOLTIP_SUPERCEDING_SPELL_NOT_KNOWN is in between.
          if leftText[i] ~= TOOLTIP_SUPERCEDING_SPELL_NOT_KNOWN then
            reagentsLineNumber = i
          end
        end

      end


      -- Sometimes recipeProductFirstLineNumber is not found at the first try...
      if not recipeProductFirstLineNumber then return otherScripts(self, ...) end


      self:ClearLines()
      -- Got to override GameTooltip.GetItem(), such that other addons can still use it
      -- to learn which item is displayed. Will be restored after GameTooltip:OnHide() (see above).
      self.GetItem = function(self) return name, link end


      -- Print the header lines.
      for i = 1, recipeProductFirstLineNumber-1, 1 do
        if rightText[i] then
          self:AddDoubleLine(leftText[i], rightText[i], leftTextR[i], leftTextG[i], leftTextB[i], rightTextR[i], rightTextG[i], rightTextB[i])
        else
          self:AddLine(leftText[i], leftTextR[i], leftTextG[i], leftTextB[i], true)
        end
      end

      -- Print "Use: Teaches you" in green!
      self:AddLine(leftText[useTeachesYouLineNumber], 0, 1, 0, true)

      -- Print everything after useTeachesYouLineNumber except for reagentsLineNumber and moneyFrameLineNumber.
      for i = useTeachesYouLineNumber+1, numLines, 1 do
        if i ~= reagentsLineNumber and i~= moneyFrameLineNumber then
          if rightText[i] then
            self:AddDoubleLine(leftText[i], rightText[i], leftTextR[i], leftTextG[i], leftTextB[i], rightTextR[i], rightTextG[i], rightTextB[i])
          else
            self:AddLine(leftText[i], leftTextR[i], leftTextG[i], leftTextB[i], true)
          end
        end
      end

      -- Print a money line if applicable.
      if moneyAmount or itemSellPrice > 0 then
        SetTooltipMoney(self, moneyAmount or itemSellPrice, nil, string_format("%s:", SELL_PRICE))
      end

      -- Print the recipe product info.
      for i = recipeProductFirstLineNumber, useTeachesYouLineNumber-1, 1 do
        if rightText[i] then
          self:AddDoubleLine(leftText[i], rightText[i], leftTextR[i], leftTextG[i], leftTextB[i], rightTextR[i], rightTextG[i], rightTextB[i])
        else
          self:AddLine(leftText[i], leftTextR[i], leftTextG[i], leftTextB[i], true)
        end
      end

      -- Print the reagents.
      self:AddLine(" ")
      self:AddLine(MINIMAP_TRACKING_VENDOR_REAGENT .. ": " .. leftText[reagentsLineNumber], leftTextR[reagentsLineNumber], leftTextG[reagentsLineNumber], leftTextB[reagentsLineNumber], true)

    end

    if otherScripts then return otherScripts(self, ...) end
  end);
end

