-- local folderName = ...
-- local L = LibStub("AceAddon-3.0"):NewAddon(folderName, "AceTimer-3.0")
-- local startupFrame = CreateFrame("Frame")
-- startupFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
-- startupFrame:SetScript("OnEvent", function(self, event, ...)
  -- L:ScheduleTimer("initCode", 5.0)
-- end)

-- function L:initCode()

-- end



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

local ITEM_SPELL_TRIGGER_ONUSE = _G.ITEM_SPELL_TRIGGER_ONUSE


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
local searchPattern = nil
if teachesYouString[locale] then


  -- koKR is right to left.
  if locale == "koKR" then
    searchPattern = "^" .. ITEM_SPELL_TRIGGER_ONUSE .. " .+" .. teachesYouString[locale]
  else
    searchPattern = "^" .. ITEM_SPELL_TRIGGER_ONUSE .. " " .. teachesYouString[locale]
  end

else
  print("TidyRecipeTooltip: Locale", locale, "not supported. Contact the developer!")
end


local tooltipNeedsTidying = false


function L:initCode()

  if not searchPattern then return end

  -- Save any previously registered scripts.
  local otherScripts = GameTooltip:GetScript("OnTooltipSetItem")

  -- Futureproofing, support extra args to pass to previous scripts
  GameTooltip:SetScript("OnTooltipSetItem", function(self, ...)

    -- OnTooltipSetItem gets called twice for recipes which contain embedded items. We only want the second one!
    local name, link = self:GetItem()
    local _, _, _, _, _, _, _, _, _, _, itemSellPrice, itemTypeId = GetItemInfo(link)

    if (itemTypeId == LE_ITEM_CLASS_RECIPE) then

      -- Store the MoneyFrame and useTeachesYou line number for later.
      local moneyFrameLineNumber = nil
      local moneyAmount = nil
      local useTeachesYouLineNumber = nil

      -- The easiest way of knowing when it is the first of two calls is
      -- when the moneyFrame is not yet visible. But this only works
      -- for recipes with an itemSellPrice.
      if itemSellPrice > 0 then

        -- If there are no money frames at all, we are done.
        if not self.shownMoneyFrames then tooltipNeedsTidying = true return end

        -- If there are money frames, we check if "SELL_PRICE: ..." is among them,
        -- assuming that no other addon has put it there before the Blizzard UI.
        for i = 1, self.shownMoneyFrames, 1 do

          local moneyFrameName = self:GetName().."MoneyFrame"..i

          if _G[moneyFrameName.."PrefixText"]:GetText() == string_format("%s:", SELL_PRICE) then

            local _, moneyFrameAnchor = _G[moneyFrameName]:GetPoint(1)
            moneyFrameLineNumber = tonumber(string_match(moneyFrameAnchor:GetName(), self:GetName().."TextLeft(%d+)"))

            -- It is OK to use _G[moneyFrameName] here, because recipes never stack.
            -- Otherwise we would have to do it like my SellPricePerUnit addon.
            moneyAmount = _G[moneyFrameName].staticMoney

            break
          end
        end

        if not moneyFrameLineNumber then tooltipNeedsTidying = true return end

      -- For recipes without itemSellPrice (e.g. soulbound) we have to
      -- scan the tooltip for "Use: Teaches you". (See above)
      else

        -- Search from bottom to top, because the searched line is most likely down.
        -- Only search up to line 2, because the searched line is definitely not topmost.
        for i = self:NumLines(), 2, -1 do
          local line = _G[self:GetName().."TextLeft"..i]:GetText()
          if string_find(line, searchPattern) then
            useTeachesYouLineNumber = i
            break
          end
        end

        if not useTeachesYouLineNumber then tooltipNeedsTidying = true return end

      end




      if tooltipNeedsTidying then

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


        -- At recipeProductFirstLineNumber begins the description of the product item.
        local recipeProductFirstLineNumber = nil


        -- Store the number of lines for after ClearLines().
        local numLines = self:NumLines()

        -- Store all lines of the original tooltip.
        for i = 1, numLines, 1 do

          leftText[i] = _G[self:GetName().."TextLeft"..i]:GetText()
          leftTextR[i], leftTextG[i], leftTextB[i] = _G[self:GetName().."TextLeft"..i]:GetTextColor()

          rightText[i] = _G[self:GetName().."TextRight"..i]:GetText()
          rightTextR[i], rightTextG[i], rightTextB[i] = _G[self:GetName().."TextRight"..i]:GetTextColor()

          -- Collect the important line numbers.
          if not recipeProductFirstLineNumber then
            -- The line begins with a line break!
            if string_byte(string_sub(leftText[i], 1, 1)) == 10 then
              recipeProductFirstLineNumber = i
            end
          elseif not useTeachesYouLineNumber then
            if string_find(leftText[i], searchPattern) then
              useTeachesYouLineNumber = i
            end
          end

        end


        -- Sometimes recipeProductFirstLineNumber is not found at the first try...
        if not recipeProductFirstLineNumber then return end


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

        -- Print everything including and after useTeachesYouLineNumber+2.
        local lastLine = numLines
        if moneyFrameLineNumber then
          lastLine = moneyFrameLineNumber - 1
        end

        for i = useTeachesYouLineNumber+2, lastLine, 1 do
          if rightText[i] then
            self:AddDoubleLine(leftText[i], rightText[i], leftTextR[i], leftTextG[i], leftTextB[i], rightTextR[i], rightTextG[i], rightTextB[i])
          else
            self:AddLine(leftText[i], leftTextR[i], leftTextG[i], leftTextB[i], true)
          end
        end

        if moneyFrameLineNumber then
          SetTooltipMoney(self, moneyAmount, nil, string_format("%s:", SELL_PRICE))
          -- Print the rest, if any.
          for i = moneyFrameLineNumber+1, numLines, 1 do
            if rightText[i] then
              self:AddDoubleLine(leftText[i], rightText[i], leftTextR[i], leftTextG[i], leftTextB[i], rightTextR[i], rightTextG[i], rightTextB[i])
            else
              self:AddLine(leftText[i], leftTextR[i], leftTextG[i], leftTextB[i], true)
            end
          end
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
        self:AddLine(MINIMAP_TRACKING_VENDOR_REAGENT .. ": " .. leftText[useTeachesYouLineNumber+1], leftTextR[useTeachesYouLineNumber+1], leftTextG[useTeachesYouLineNumber+1], leftTextB[useTeachesYouLineNumber+1], true)
        
        tooltipNeedsTidying = false
      end
    end

    if otherScripts then return otherScripts(self, ...) end
  end);
end










-- local mainFrame = CreateFrame("Frame", nil, UIParent)

-- mainFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
-- mainFrame:SetFrameStrata("FULLSCREEN")
-- mainFrame:SetBackdrop({ bgFile = "Interface/Tooltips/UI-Tooltip-Background",
                      -- edgeFile = "Interface/DialogFrame/UI-DialogBox-Border",
                      -- tile = true, tileSize = 16, edgeSize = 16,
                      -- insets = { left = 4, right = 4, top = 4, bottom = 4 }})
-- mainFrame:SetBackdropColor(0.0, 0.0, 0.0, 1.0)


-- mainFrame:SetWidth(300)
-- mainFrame:SetHeight(100)

-- local text = mainFrame:CreateFontString(nil, "ARTWORK", "GameFontNormal")
-- text:SetPoint("CENTER", mainFrame, "CENTER", 0, 0)
-- text:SetText("Test")


