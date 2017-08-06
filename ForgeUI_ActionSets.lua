----------------------------------------------------------------------------------------------
-- Client Lua Script for ForgeUI addon
--
-- name: 		ForgeUI_ActionSets.lua
-- author:		Veex
-- about:		Abilities manager addon for ForgeUI
-----------------------------------------------------------------------------------------------

require "Window"
require "AbilityBook"
require "ActionSetLib"
require "Spell"
require "Tooltip"

local F = _G["ForgeLibs"]["ForgeUI"] -- ForgeUI API
local G = _G["ForgeLibs"]["ForgeGUI"] -- ForgeGUI

-----------------------------------------------------------------------------------------------
-- ForgeUI Addon Definition
-----------------------------------------------------------------------------------------------
local ForgeUI_ActionSets = {
	_NAME = "ForgeUI_ActionSets",
	_API_VERSION = 3,
	_VERSION = "1.0",
	DISPLAY_NAME = "Action sets",

	tQueuedAbilities = {},

	tSettings = {
		profile = {
			strMenuSprite = "Lights",
			bIsLayoutScanned = false,
			bEnableMenuButtons = true,
			bInvisibleMenuButtons = false,
			bEnableAbilityMenuButtons = true,
			bEnableAbilityHistory = true,
			bLockAbilityHistory = false,
			bShowTooltips = true,
			bPlaySound = false,
			bCombatMenu = true,
			nMenuButtonWidth = 50,
			nMenuButtonHeight = 20,
			nMenuButtonOffsetY = 20,
			nAbilityButtonSize = 50,
			nHistoryMax = 3,
			tHistory = {},
		}
	}
}

-----------------------------------------------------------------------------------------------
-- Constants
-----------------------------------------------------------------------------------------------
local strSpriteAbilityMenu = "CRB_TooltipSprites:sprTT_MainFill"

local tMenuSprites = {
	["Lights"] = "charactercreate:sprCharC_HeaderStepHighlight",
	["Arrow"] = "CRB_QuestTrackerSprites:btnQT_TrackerMinimizePressedFlyby",
	["Glow"] = "CRB_DatachronSprites:sprDCPP_ExCompleteBucket3"
}

-----------------------------------------------------------------------------------------------
-- Local
-----------------------------------------------------------------------------------------------
local debug = function(msg, value)
	if ForgeUI_ActionSets.Rover ~= nil then
		ForgeUI_ActionSets.Rover:AddWatch(msg, value, 0)
	end
end

-----------------------------------------------------------------------------------------------
-- ForgeAPI
-----------------------------------------------------------------------------------------------
function ForgeUI_ActionSets:ForgeAPI_PreInit()
--	Apollo.RegisterEventHandler("ShowActionBarShortcut", "ShowShortcutBar", self)
end

function ForgeUI_ActionSets:ForgeAPI_Init()
	self.xmlDoc = XmlDoc.CreateFromFile("..//ForgeUI_ActionSets//ForgeUI_ActionSets.xml")
	self.xmlDoc:RegisterCallback("OnDocLoaded", self)

	Apollo.RegisterEventHandler("UnitEnteredCombat",	"OnEnteredCombat", self)
	Apollo.RegisterEventHandler("CombatLogResurrect", "OnResurrected", self)
	Apollo.RegisterEventHandler("PlayerLevelChange",	"InitAddon", self)
	Apollo.RegisterEventHandler("PlayerEnteredWorld",	"OnEnterWorld", self)

	-- self.Rover = Apollo.GetAddon("Rover")

	local wndMenuItem = F:API_AddMenuItem(self, self.DISPLAY_NAME, "General")
end

function ForgeUI_ActionSets:OnDocLoaded()
	if self.xmlDoc == nil or not self.xmlDoc:IsLoaded() then return end

	self.wndMenuOverlay = Apollo.LoadForm(self.xmlDoc, "ForgeUI_MenuOverlay", nil, self)
	self.wndAbilityMenuOverlay = Apollo.LoadForm(self.xmlDoc, "ForgeUI_AbilityMenuOverlay", nil, self)

	self:InitAddon()
end

-----------------------------------------------------------------------------------------------
-- Events
-----------------------------------------------------------------------------------------------
function ForgeUI_ActionSets:OnEnteredCombat(unit, bInCombat)
	local unitPlayer = GameLib.GetPlayerUnit()

	if unitPlayer and unitPlayer:IsValid() then
		if unit == unitPlayer and self.tMenuButtons then
			local bDead = unitPlayer:IsDead()
			if not self._DB.profile.bCombatMenu and bInCombat then
				self:MenuButtonsShow(false)
			else
				self:MenuButtonsShow(true)
			end
			self.bInCombat = bInCombat
			if not bInCombat and not bDead then self:ApplyQueue() end
		end
	end
end

function ForgeUI_ActionSets:OnEnterWorld()
	local unitPlayer = GameLib.GetPlayerUnit()

	if unitPlayer and unitPlayer:IsValid() then
		local bInCombat = unitPlayer:IsInCombat()
		local bDead = unitPlayer:IsDead()

		if not self._DB.profile.bCombatMenu and bInCombat then
			self:MenuButtonsShow(false)
		else
			self:MenuButtonsShow(true)
		end
		self.bInCombat = bInCombat
		if not bInCombat and not bDead then self:ApplyQueue() end
	end
end

function ForgeUI_ActionSets:OnResurrected(param)
	local unitPlayer = GameLib.GetPlayerUnit()
	if unitPlayer and unitPlayer:IsValid() then
		if param.unitCaster == unitPlayer and self.tMenuButtons then
			self:ApplyQueue()
		end
	end
end

-----------------------------------------------------------------------------------------------
-- Addon functions
-----------------------------------------------------------------------------------------------
function ForgeUI_ActionSets:InitAddon()
	self:ValidateHistory()
	self:BuildMenuButtons()
end

function ForgeUI_ActionSets:GetActionBarButtons()
	local tAddon = Apollo.GetAddon("ForgeUI_ActionBars")
	if not tAddon then
		debug("ForgeUI_ActionBars addon found", false)
		return nil
	else
		debug("ForgeUI_ActionBars addon found", true)
	end

	if not tAddon._DB.profile.tFrames[1].bShow then
		debug("ForgeUI_ActionBars bShow is", tAddon._DB.profile.tFrames[1].bShow)
		return nil
	else
		debug("ForgeUI_ActionBars bShow is", tAddon._DB.profile.tFrames[1].bShow)
	end

	local tActionBar = tAddon:API_GetTBars()["ForgeUI_ActionBar"]
	if not tActionBar then
		debug("ForgeUI:API_GetTBars", false)
		return nil
	else
		debug("ForgeUI:API_GetTBars", true)
	end

	local tActionButtons = tActionBar:GetChildren()
	if not tActionButtons or not tActionButtons[1] or not tActionButtons[8] then
		debug("ForgeUI_ActionBar is valid host", false)
		return nil
	else
		debug("ForgeUI_ActionBar is valid host", true)
	end

	return tActionButtons
end

function ForgeUI_ActionSets:BuildMenuButtons()
	debug("-> BuildMenuButtons")
	if self.tMenuButtons then
		debug("Destroying menu buttons", true)
		for nLasIndex, wndButton in ipairs(self.tMenuButtons) do
			wndButton:Destroy()
		end
	end
	self.tMenuButtons = {}

	local tActionButtons = self:GetActionBarButtons()
	if not tActionButtons then return end

	if not self._DB.profile.bEnableMenuButtons then
		return
	end

	self:ScanLayout(tActionButtons)

	for nLasIndex, tActionButton in ipairs(tActionButtons) do
		debug("Trying to build menu button at index "..nLasIndex, tActionButton)
		if ActionSetLib.IsSlotUnlocked(nLasIndex - 1) == ActionSetLib.CodeEnumLimitedActionSetResult.Ok then
			debug("LAS slot unlocked at index "..nLasIndex..", building...", true)
			local wndMenuButton = Apollo.LoadForm(self.xmlDoc, "ForgeUI_MenuButton", nil, self)
			local wndQueueButton = Apollo.LoadForm(self.xmlDoc, "ForgeUI_AbilityOverlayQueue", tActionButton, self)

			if not self._DB.profile.bInvisibleMenuButtons then
				wndMenuButton:SetSprite(tMenuSprites[self._DB.profile.strMenuSprite])
			end

			local tMenuButtonData = {
				strType = "MenuButton",
				nLasIndex = nLasIndex,
				tActionButton = tActionButton,
				wndQueueButton = wndQueueButton,
			}

			wndMenuButton:SetData(tMenuButtonData)
			wndQueueButton:SetData(tMenuButtonData)

			self.tMenuButtons[#self.tMenuButtons + 1] = wndMenuButton
			self:PositionMenuButton(tActionButton, wndMenuButton)

			wndMenuButton:Show(true, true)
		end
	end
	debug("Menu buttons has been successfuly created", self.tMenuButtons)
end

function ForgeUI_ActionSets:ScanLayout(tActionButtons)
	if not self._DB.profile.bIsLayoutScanned then
		local tActionButton = tActionButtons[1]
		self._DB.profile.nMenuButtonWidth = tActionButton:GetClientRect().nWidth
		self._DB.profile.nMenuButtonHeight = 20
		self._DB.profile.nMenuButtonOffsetY = 20
		self._DB.profile.nAbilityButtonSize = tActionButton:GetClientRect().nWidth

		self._DB.profile.bIsLayoutScanned = true
		self:RefreshConfig()
	end
end

------------------------------------------------------------------------------------------------------------------------
-- Menu buttons
------------------------------------------------------------------------------------------------------------------------
function ForgeUI_ActionSets:MenuButtonsShow(bShow)
	for _, wndMenuButton in ipairs(self.tMenuButtons) do
		if wndMenuButton:IsShown() ~= bShow then
			wndMenuButton:Show(bShow, true)
		end
	end
end

function ForgeUI_ActionSets:PositionMenuButton(tActionButton, wndMenuButton)
	local tClientRect = tActionButton:GetClientRect()
	local wndX = select(1, tActionButton:GetPos()) + select(1, tActionButton:GetParent():GetPos())
	local wndY = select(2, tActionButton:GetPos()) + select(2, tActionButton:GetParent():GetPos())

	local xOffset = (tClientRect.nWidth - self._DB.profile.nMenuButtonWidth) / 2
	local x = wndX + xOffset
	local y = wndY + (- self._DB.profile.nMenuButtonOffsetY)
	local w = x + self._DB.profile.nMenuButtonWidth
	local h = y + self._DB.profile.nMenuButtonHeight

	if self._DB.profile.bMenuButtonDetectWidth then
		x = wndX
		w = x + tClientRect.nWidth
	end

	wndMenuButton:SetAnchorOffsets(x, y, w, h)

	debug(("Position menu button at : %s, %s, %s, %s"):format(x, y, w, h), nil)
end

function ForgeUI_ActionSets:RepositionMenuButtons()
	for _, wndMenuButton in pairs(self.tMenuButtons) do
		local tActionButton = wndMenuButton:GetData().tActionButton
		self:PositionMenuButton(tActionButton, wndMenuButton)
	end
end

function ForgeUI_ActionSets:OnMenuButtonEnter(wndHandler, wndControl, posX, posY)
	if wndHandler ~= wndControl then return end

	if not self.wndCurrentMenu or self.wndCurrentMenu ~= wndControl then
		self:OnCloseMenu()
		self:PopulateAndOpenMenu(wndControl)
	end
end

function ForgeUI_ActionSets:OnMenuButtonExit(wndHandler, wndControl, posX, posY)
	if wndHandler ~= wndControl then return end

	local timerCloseMenuDelay = ApolloTimer.Create(0.1, false, "OnCloseMenuDelay", self)
end

function ForgeUI_ActionSets:OnCloseMenuDelay()
	local wnd = Apollo.GetMouseTargetWindow()

	if wnd and (wnd:GetName() == "ForgeUI_AbilityButton" or wnd:GetName() == "ForgeUI_MenuButton") then
		return
	end

	self:OnCloseMenu()
end

function ForgeUI_ActionSets:OnCloseMenu()
	if self.wndMenuOverlay and self.wndMenuOverlay:IsShown() then
		self.wndMenuOverlay:Show(false)
	end
	self.wndCurrentMenu = nil
end

function ForgeUI_ActionSets:PopulateAndOpenMenu(wndMenuButton)
	local wndMenuOverlay = self.wndMenuOverlay
	local tButtonData = wndMenuButton:GetData()
	local nLasIndex = tButtonData.nLasIndex

	for _, wndMenuButton in ipairs(wndMenuOverlay:GetChildren()) do
		wndMenuButton:Destroy()
	end

	local nAbilityCurrentId = ActionSetLib.GetCurrentActionSet()[nLasIndex]

	local nTargetTier = 1
	if nAbilityCurrentId and nAbilityCurrentId ~= 0 then
		nTargetTier = self:Ability_GetTier(nAbilityCurrentId)
	end

	if self._DB.profile.bEnableAbilityMenuButtons then
		debug("Building Ability Menu buttons at index "..nLasIndex.."...")
		self:CreateAbilityMenuButton("Assault", Spell.CodeEnumSpellTag.Assault, nLasIndex, 100, nTargetTier)
		self:CreateAbilityMenuButton("Support", Spell.CodeEnumSpellTag.Support, nLasIndex, 99, nTargetTier)
		self:CreateAbilityMenuButton("Utility", Spell.CodeEnumSpellTag.Utility, nLasIndex, 98, nTargetTier)
	end

	if self._DB.profile.bEnableAbilityHistory then
		for idx, nAbilityId in ipairs(self:GetHistoryByIndex(nLasIndex, nAbilityCurrentId)) do
			debug("Adding ability "..nAbilityId.." from history ")
			local tAbility = self:GetAvailableAssaultSkills()[nAbilityId] or self:GetAvailableSupportSkills()[nAbilityId] or self:GetAvailableUtilitySkills()[nAbilityId]
			if tAbility then
				self:CreateHistoryButton(tAbility, nLasIndex, idx, nTargetTier)
			end
		end
	end

	-- positioning and showing
	wndMenuOverlay:ArrangeChildrenVert(Window.CodeEnumArrangeOrigin.LeftOrTop, function(a,b) return a:GetData().nPriority >= b:GetData().nPriority end)

	local x, y = wndMenuButton:GetPos()

	local xDiff = (wndMenuButton:GetClientRect().nWidth - self._DB.profile.nAbilityButtonSize) / 2.0
	local yDiff = (#wndMenuOverlay:GetChildren() or 0) * self._DB.profile.nAbilityButtonSize

	x = x + xDiff
	-- y = y - 2

	wndMenuOverlay:SetAnchorPoints(0, 0, 0, 0)
	wndMenuOverlay:SetAnchorOffsets(x, y - yDiff, x + self._DB.profile.nAbilityButtonSize, y)
	wndMenuOverlay:ToFront()
	wndMenuOverlay:Show(true)

	self.wndCurrentMenu = wndMenuButton
end

function ForgeUI_ActionSets:CreateAbilityMenuButton(strCaption, strAbilityCategory, nLasIndex, nPriority, nTargetTier)
	if next(self:GetAbilityMenuSkills(nLasIndex, strAbilityCategory)) ~= nil then
		local wndAbilityMenuButton = Apollo.LoadForm(self.xmlDoc, "ForgeUI_AbilityButton", self.wndMenuOverlay, self)
		wndAbilityMenuButton:SetSprite(strSpriteAbilityMenu)
		wndAbilityMenuButton:SetBGColor("UI_WindowBGDefault")
		wndAbilityMenuButton:SetText(strCaption)
		wndAbilityMenuButton:SetAnchorPoints(0, 0, 0, 0)
		wndAbilityMenuButton:SetAnchorOffsets(0, 0, self._DB.profile.nAbilityButtonSize, self._DB.profile.nAbilityButtonSize)

		tAbilityMenuButtonData = {
			strType = "AbilityButton_Menu",
			strAbilityCategory = strAbilityCategory,
			nLasIndex = nLasIndex,
			nPriority = nPriority,
			nTargetTier = nTargetTier,
		}

		wndAbilityMenuButton:SetData(tAbilityMenuButtonData)
	end
end

function ForgeUI_ActionSets:GetHistoryByIndex(nLasIndex, nAbilityCurrentId)
	debug("-> GetHistoryByIndex  nAbilityCurrentId " .. nAbilityCurrentId.. " nLasIndex "..nLasIndex)

	local tAbilityList = nil
	local nSpecId = AbilityBook.GetCurrentSpec()
	local tSpecHistory = self._DB.profile.tHistory[nSpecId]

	if tSpecHistory then
		tAbilityList = tSpecHistory[nLasIndex]
	end

	local tResult = {}
	if tAbilityList then
		for _, nAbilityNewId in pairs(tAbilityList) do
			if nAbilityCurrentId and nAbilityNewId ~= nAbilityCurrentId then
				tResult[#tResult + 1] = nAbilityNewId
			end
			if #tResult >= self._DB.profile.nHistoryMax then
				break
			end
		end
	end

	return tResult
end

function ForgeUI_ActionSets:CreateHistoryButton(tAbility, nLasIndex, nPriority, nTargetTier)
	local bIsValid = true
	for _, nId in pairs(self:GetActionSetAfterQueue()) do
		if nId == tAbility.nId then
			debug("History ability "..tAbility.nId.." already in LAS. Disabling...")
			bIsValid = false
		end
	end

	local wndAbilityButton = Apollo.LoadForm(self.xmlDoc, "ForgeUI_AbilityButton", self.wndMenuOverlay, self)
	wndAbilityButton:FindChild("Icon"):SetSprite(tAbility.strIcon)
	wndAbilityButton:FindChild("Icon"):SetBGColor(bIsValid and "UI_WindowBGDefault" or "UI_BtnTextGrayDisabled")
	wndAbilityButton:SetAnchorPoints(0, 0, 0, 0)
	wndAbilityButton:SetAnchorOffsets(0, 0, self._DB.profile.nAbilityButtonSize, self._DB.profile.nAbilityButtonSize)

	local tAbilityButtonData = {
		strType = "AbilityButton_History",
		nLasIndex = nLasIndex,
		nAbilityId = tAbility.nId,
		nPriority = nPriority,
		nLevel = tAbility.nLevel,
		bDisabled = not bIsValid,
	}

	if nTargetTier then
		local tAbilityTiered = tAbility.tTiers[nTargetTier]
		if tAbilityTiered then
			tAbilityButtonData.tAbilityTiered = tAbilityTiered.splObject
		end
	end

	wndAbilityButton:SetData(tAbilityButtonData)

	return wndAbilityButton
end

------------------------------------------------------------------------------------------------------------------------
-- Ability / AbilityMenu buttons
------------------------------------------------------------------------------------------------------------------------
function ForgeUI_ActionSets:OnAbilityButtonEnter( wndHandler, wndControl, posX, posY )
	if wndHandler ~= wndControl then return end

	local tButtonData = wndControl:GetData()
	local strButtonType = tButtonData.strType

	if strButtonType == "AbilityButton_Menu" and self.wndCurrentAbilityMenu ~= wndControl then
		self:PopulateAndOpenAbilityMenu(wndControl)
	end
end

function ForgeUI_ActionSets:OnAbilityButtonExit( wndHandler, wndControl, posX, posY )
	if wndHandler ~= wndControl then return end

	local timerCloseMenuDelay = ApolloTimer.Create(0.1, false, "OnCloseMenuDelay", self)
	local timerCloseAbilityMenuDelay = ApolloTimer.Create(0.1, false, "OnCloseAbilityMenuDelay", self)
end

function ForgeUI_ActionSets:OnCloseAbilityMenuDelay()
	local wnd = Apollo.GetMouseTargetWindow()
	if (wnd and wnd:GetName() == "ForgeUI_AbilityButton" and wnd:GetData().strType ~= "AbilityButton_History") then
		return
	end

	self:OnCloseAbilityMenu()
end

function ForgeUI_ActionSets:OnCloseAbilityMenu()
	if self.wndAbilityMenuOverlay and self.wndAbilityMenuOverlay:IsShown() then
		self.wndAbilityMenuOverlay:Show(false)
	end
	self.wndCurrentAbilityMenu = nil
end

function ForgeUI_ActionSets:PopulateAndOpenAbilityMenu(wndAbilityMenuButton)
	local wndAbilityMenuOverlay = self.wndAbilityMenuOverlay
	local tButtonData = wndAbilityMenuButton:GetData()
	local strAbilityCategory = tButtonData.strAbilityCategory
	local nLasIndex = tButtonData.nLasIndex
	local nTargetTier = tButtonData.nTargetTier

	for _, wndAbilityButton in pairs(wndAbilityMenuOverlay:GetChildren()) do
		wndAbilityButton:Destroy()
	end

	for nAbilityId, tAbility in pairs(self:GetAbilityMenuSkills(nLasIndex, strAbilityCategory)) do

		local wndAbilityButton = Apollo.LoadForm(self.xmlDoc, "ForgeUI_AbilityButton", wndAbilityMenuOverlay, self)
		wndAbilityButton:FindChild("Icon"):SetSprite(tAbility.strIcon)
		wndAbilityButton:SetAnchorPoints(0, 0, 0, 0)
		wndAbilityButton:SetAnchorOffsets(0, 0, self._DB.profile.nAbilityButtonSize, self._DB.profile.nAbilityButtonSize)

		local tAbilityButtonData = {
			strType = "AbilityButton",
			nAbilityId = nAbilityId,
			nLasIndex = nLasIndex,
			nLevel = tAbility.nLevel,
		}

		if nTargetTier and tAbility.tTiers then
			local tAbilityTiered = tAbility.tTiers[nTargetTier]
			if tAbilityTiered then
				tAbilityButtonData.tAbilityTiered = tAbilityTiered.splObject
			end
		end
		wndAbilityButton:SetData(tAbilityButtonData)
	end

	-- positioning and showing
	wndAbilityMenuOverlay:ArrangeChildrenHorz(Window.CodeEnumArrangeOrigin.LeftOrTop, function(a,b) return a:GetData().nLevel < b:GetData().nLevel end)

	local x = select(1, wndAbilityMenuButton:GetPos()) + select(1, wndAbilityMenuButton:GetParent():GetPos())
	local y = select(2, wndAbilityMenuButton:GetPos()) + select(2, wndAbilityMenuButton:GetParent():GetPos())
	x = x + wndAbilityMenuButton:GetClientRect().nWidth
	xDiff = (#wndAbilityMenuOverlay:GetChildren() or 0) * self._DB.profile.nAbilityButtonSize

	wndAbilityMenuOverlay:SetAnchorOffsets(x, y, x + xDiff, y + self._DB.profile.nAbilityButtonSize)
	wndAbilityMenuOverlay:ToFront()
	wndAbilityMenuOverlay:Show(true, true)
	self.wndCurrentAbilityMenu = wndAbilityMenuButton
end

function ForgeUI_ActionSets:GetAbilityMenuSkills(nLasIndex, strAbilityCategory)
	local tActionSet = self:GetActionSetAfterQueue()
	local tExcludeId = {}
	for nLasIndex, nId in pairs(tActionSet) do
		tExcludeId[nId] = true
	end

	for _, nId in ipairs(self:GetHistoryByIndex(nLasIndex, tActionSet[nLasIndex])) do
		if not tExcludeId[nId] then
			tExcludeId[nId] = true
		end
	end

	return self:GetAvailableSkills(strAbilityCategory, tExcludeId)
end

function ForgeUI_ActionSets:GetAvailableAssaultSkills()
	return self:GetAvailableSkills(Spell.CodeEnumSpellTag.Assault)
end

function ForgeUI_ActionSets:GetAvailableSupportSkills()
	return self:GetAvailableSkills(Spell.CodeEnumSpellTag.Support)
end

function ForgeUI_ActionSets:GetAvailableUtilitySkills()
	return self:GetAvailableSkills(Spell.CodeEnumSpellTag.Utility)
end

function ForgeUI_ActionSets:GetAvailableSkills(strAbilityCategory, tExcludeId)
	local tResult = {}
	local tSelectedId = {}

	for _, nId in pairs(ActionSetLib.GetCurrentActionSet()) do
		tSelectedId[nId] = true
	end

	for _, tAbility in pairs(AbilityBook.GetAbilitiesList(strAbilityCategory)) do
		if tAbility.bIsActive then
			if tExcludeId == nil or not tExcludeId[tAbility.nId] then
				tResult[tAbility.nId] = {
					nId = tAbility.nId,
					strName = tAbility.strName,
					nTier = tAbility.nCurrentTier,
					nLevel = tAbility.tTiers[1].nLevelReq,
					strIcon = tAbility.tTiers[1].splObject:GetIcon(),
					bActive = (tSelectedId[tAbility.nId] == true),
					tTiers = tAbility.tTiers,
				}
			end
		end
	end

	table.sort(tResult, function(a,b) return a.nLevel < b.nLevel end)
	return tResult
end

function ForgeUI_ActionSets:OnAbilityButtonClick(wndHandler, wndControl, eMouseButton, nLastRelativeMouseX, nLastRelativeMouseY, bDoubleClick, bStopPropagation)
	local tButtonData = wndControl:GetData()
	if tButtonData and (tButtonData.strType == "AbilityButton" or tButtonData.strType == "AbilityButton_History") then
		if eMouseButton == GameLib.CodeEnumInputMouse.Left then
			if tButtonData.bDisabled then return end

			if self:IsInCombat() or self:IsDead() then
				self:QueueForChange(tButtonData.nLasIndex, tButtonData.nAbilityId)
				self:OnCloseAbilityMenu()
				self:OnCloseMenu()
			else
				self:Ability_RequestChange(tButtonData.nLasIndex, tButtonData.nAbilityId)
				self:OnCloseAbilityMenu()
				self:OnCloseMenu()
			end
		elseif eMouseButton == GameLib.CodeEnumInputMouse.Right then
			if not self._DB.profile.bLockAbilityHistory then
				if tButtonData.strType == "AbilityButton_History" then
					self:RemoveHistoryFromList(tButtonData.nLasIndex, tButtonData.nAbilityId)
					self:OnCloseMenu()
				end
			end
		end
	end
end

function ForgeUI_ActionSets:OnAbilityButtonTooltip(wndHandler, wndControl, eToolTipType, posX, posY)
	if self._DB.profile.bShowTooltips then
		local tButtonData = wndControl:GetData()
		if tButtonData and (tButtonData.strType == "AbilityButton" or tButtonData.strType == "AbilityButton_History") and tButtonData.tAbilityTiered then
			Tooltip.GetSpellTooltipForm(self, wndControl, tButtonData.tAbilityTiered)
		end
	end
end

------------------------------------------------------------------------------------------------------------------------
-- Queue functions
------------------------------------------------------------------------------------------------------------------------
function ForgeUI_ActionSets:QueueForChange(nLasIndex, nAbilityNewId)
	debug("Adding to Queue: Swap ability at index " .. nLasIndex .. " to ability " .. nAbilityNewId)
	self.tQueuedAbilities[nLasIndex] = nAbilityNewId

	--[[add to history]]
	local tActionSet = ActionSetLib.GetCurrentActionSet()
	local nAbilityCurrentId = tActionSet[nLasIndex]
	if nAbilityCurrentId ~= 0 then
		self:AddHistory(nLasIndex, nAbilityCurrentId, nAbilityNewId)
	end

	--[[apply icon]]
	local tButtonData;
	for _, wndButton in ipairs(self.tMenuButtons) do
		local data = wndButton:GetData()
		if data and data.nLasIndex == nLasIndex then
			tButtonData = data
			break;
		end
	end

	if not tButtonData or not tButtonData.wndQueueButton then return debug("Failed to find Button for index "..nLasIndex) end

	tButtonData.wndQueueButton:Show(true, true)
	tButtonData.wndQueueButton:FindChild("Icon"):SetSprite(self:GetIconForAbilityId(nAbilityNewId))
end

function ForgeUI_ActionSets:RemoveQueuedAbility(nLasIndex)
	local nOldAbilityId = self.tQueuedAbilities[nLasIndex]
	debug("Removing from Queue: Swap ability at index " .. nLasIndex .. " to ability " .. nOldAbilityId)
	self.tQueuedAbilities[nLasIndex] = nil

	--[[remove icon]]
	local tButtonData;
	for _, wndButton in ipairs(self.tMenuButtons) do
		local data = wndButton:GetData()
		if data and data.nLasIndex == nLasIndex then
			tButtonData = data
			break;
		end
	end

	if not tButtonData or not tButtonData.wndQueueButton then return debug("Failed to find Button for index "..nLasIndex) end

	tButtonData.wndQueueButton:Show(false, true)
end

function ForgeUI_ActionSets:ApplyQueue()
	if not self:IsInCombat() and not self:IsDead() and next(self.tQueuedAbilities) then --is not empty
		self:Ability_RequestMultiChange(self.tQueuedAbilities)
		self.tQueuedAbilities = {}

		--remove icons
		for _, wndButton in ipairs(self.tMenuButtons) do
			local tData = wndButton:GetData()
			if tData and tData.wndQueueButton then
				tData.wndQueueButton:Show(false, true)
			end
		end
	end
end

function ForgeUI_ActionSets:OnQueueOverlayClick(wndHandler, wndControl, eMouseButton, ...)
	if wndHandler ~= wndControl then return end
	if eMouseButton == GameLib.CodeEnumInputMouse.Right then
		local tData = wndHandler:GetData()
		if not tData or not tData.nLasIndex then return end
		self:RemoveQueuedAbility(tData.nLasIndex)
	end
end
------------------------------------------------------------------------------------------------------------------------
-- LAS functions
------------------------------------------------------------------------------------------------------------------------
function ForgeUI_ActionSets:Ability_RequestChange(nLasIndex, nAbilityNewId)
	debug("Attempting to swap ability at index " .. nLasIndex .. " to ability " .. nAbilityNewId)
	local tActionSet = ActionSetLib.GetCurrentActionSet()
	local tLasLookup = {} -- TODO: not used
	for idx, nAbilityId in pairs(tActionSet) do
		tLasLookup[nAbilityId] = idx
	end

	local nAbilityCurrentId = tActionSet[nLasIndex]
	debug("nAbilityCurrentId = " .. tostring(nAbilityCurrentId))
	if nAbilityCurrentId then
		debug("Found ability " .. nAbilityCurrentId .. " on index " .. nLasIndex .. " in current las")
		tActionSet[nLasIndex] = nAbilityNewId
		if nAbilityCurrentId ~= 0 then
			debug("Copying tier level...")
			local nCurrentTier = self:Ability_GetTier(nAbilityCurrentId)
			self:Ability_SetTier(nAbilityCurrentId, 1)
			self:Ability_SetTier(nAbilityNewId, nCurrentTier)
		end

		local tResult = ActionSetLib.RequestActionSetChanges(tActionSet)
		if tResult.eResult ~= ActionSetLib.CodeEnumLimitedActionSetResult.Ok then
			debug("Failed to save new las, result:", tResult.eResult)
		else
			if self._DB.profile.bPlaySound then
				Sound.Play(186)
			end
		end

		if not self._DB.profile.bLockAbilityHistory then
			if nAbilityCurrentId ~= 0 then
				self:AddHistory(nLasIndex, nAbilityCurrentId, nAbilityNewId)
			end
		end
	else
		debug("The ability " .. nAbilityCurrentId .. " is not on the las")
	end
end

function ForgeUI_ActionSets:Ability_RequestMultiChange(tChanges) --[nLasIndex, nAbilityNewId]
	debug("Attempting a bulk switch", tChanges)
	local tActionSet = ActionSetLib.GetCurrentActionSet()

	--split these, because we need to do downgrades first (all of them)
	local tAbilityDowngrade = {} --[nAbilityId] = nTier
	local tAbilityUpgrade = {} --[nAbilityId] = nTier

	for nLasIndex, nAbilityNewId in pairs(tChanges) do --fill up/down-grades and apply changes to tActionSet
		local nAbilityCurrentId = tActionSet[nLasIndex]
		if nAbilityCurrentId then
			tActionSet[nLasIndex] = nAbilityNewId
			if nAbilityCurrentId ~= 0 then
				local nCurrentTier = self:Ability_GetTier(nAbilityCurrentId)
				tAbilityDowngrade[nAbilityCurrentId] = 1
				tAbilityUpgrade[nAbilityNewId] = nCurrentTier
			end
		end
	end

	--apply downgrades
	debug("Bulk Downgrading:", tAbilityDowngrade)
	for nAbilityId, nTier in pairs(tAbilityDowngrade) do
		self:Ability_SetTier(nAbilityId, nTier)
	end

	--apply upgrades
	debug("Bulk Upgrading:", tAbilityUpgrade)
	for nAbilityId, nTier in pairs(tAbilityUpgrade) do
		self:Ability_SetTier(nAbilityId, nTier)
	end

	--switching skills
	local tResult = ActionSetLib.RequestActionSetChanges(tActionSet)
	if tResult.eResult ~= ActionSetLib.CodeEnumLimitedActionSetResult.Ok then
		debug("Failed to save new las, result:", tResult.eResult)
	else
		if self._DB.profile.bPlaySound then
			Sound.Play(186)
		end
	end
end

function ForgeUI_ActionSets:Ability_GetTier(nAbilityId)
	for _, tAbility in pairs(AbilityBook.GetAbilitiesList()) do
		if (tAbility.nId == nAbilityId) then
			return tAbility.nCurrentTier
		end
	end
	return nil
end

function ForgeUI_ActionSets:Ability_SetTier(nAbilityId, nTier)
	debug("Setting tier " .. nTier .. " for ability " .. nAbilityId)
	AbilityBook.UpdateSpellTier(nAbilityId, nTier)
end

------------------------------------------------------------------------------------------------------------------------
-- History functions
------------------------------------------------------------------------------------------------------------------------
function ForgeUI_ActionSets:ValidateHistory()
	debug("-> ValidateHistory")
	local tAbilityCategories = {
		[1] = Spell.CodeEnumSpellTag.Assault,
		[2] = Spell.CodeEnumSpellTag.Support,
		[3] = Spell.CodeEnumSpellTag.Utility,
	}

	local tAbilityList = {}
	for _, eAbilityCategory in ipairs(tAbilityCategories) do
		for _, tAbility in ipairs(AbilityBook.GetAbilitiesList(eAbilityCategory)) do
			if tAbility.bIsActive then
				tAbilityList[tAbility.nId] = true
			end
		end
	end
	debug("Valid abilties ID table", tAbilityList)

	local tHistory = self._DB.profile.tHistory
	for nActionSet, tSetHistory in pairs(tHistory) do
		debug("Validating abilities for LAS "..nActionSet, tSetHistory)
		for nLasIndex, tIndexHistory in pairs(tSetHistory) do
			debug(("Validating abilities for nLasIndex %s in LAS %s"):format(nLasIndex, nActionSet), tIndexHistory)
			for idx, nAbilityId in pairs(tIndexHistory) do
				if not tAbilityList[nAbilityId] then
					debug(("Ability %s for nLasIndex %s in LAS %s is not valid. Removing..."):format(nAbilityId, nLasIndex, nActionSet), true)
					tIndexHistory[idx] = nil
				else
					debug(("Ability %s for nLasIndex %s in LAS %s is valid"):format(nAbilityId, nLasIndex, nActionSet), true)
				end
			end
		end
	end
end

function ForgeUI_ActionSets:AddHistory(nLasIndex, nAbilityCurrentId, nAbilityNewId)
	debug("Adding swap history from index " .. nLasIndex .. " nAbilityCurrentId = " .. nAbilityCurrentId .. " nAbilityNewId = " .. nAbilityNewId)

	local nSpecId = AbilityBook.GetCurrentSpec()
	local tHistory = self._DB.profile.tHistory

	if not tHistory[nSpecId] then
		tHistory[nSpecId] = {}
	end

	local tSpecHistory = tHistory[nSpecId]
	tSpecHistory[nLasIndex] = self:AddHistoryToList(tSpecHistory[nLasIndex], nAbilityCurrentId, nAbilityNewId)
end

function ForgeUI_ActionSets:AddHistoryToList(tSpecHistory, nAbilityCurrentId, nAbilityNewId)
	if tSpecHistory == nil then
		tSpecHistory = {}
	end

	tSpecHistory = self:TableInsertEx(tSpecHistory, nAbilityNewId, self._DB.profile.nHistoryMax + 1)
	tSpecHistory = self:TableInsertEx(tSpecHistory, nAbilityCurrentId, self._DB.profile.nHistoryMax + 1)

	return tSpecHistory
end

function ForgeUI_ActionSets:RemoveHistoryFromList(nLasIndex, nAbilityId)
	debug("-> RemoveHistoryFromList nLasIndex = " .. nLasIndex .. " nAbilityId = " .. nAbilityId)

	local nSpecId = AbilityBook.GetCurrentSpec()
	local tHistory = self._DB.profile.tHistory

	if tHistory[nSpecId] then
		tHistory[nSpecId][nLasIndex] = self:TableRemoveEx(tHistory[nSpecId][nLasIndex], nAbilityId)
	end
end

------------------------------------------------------------------------------------------------------------------------
-- Helpers
------------------------------------------------------------------------------------------------------------------------
function ForgeUI_ActionSets:IsInCombat()
	local player = GameLib.GetPlayerUnit()
	return player and player:IsValid() and player:IsInCombat() or self.bInCombat or false
end

function ForgeUI_ActionSets:IsDead()
	local player = GameLib.GetPlayerUnit()
	return player and player:IsValid() and player:IsDead() or false --assume not dead, if not existing.
end

function ForgeUI_ActionSets:GetIconForAbilityId(nAbilityId)
	for _, tAbility in ipairs(AbilityBook.GetAbilitiesList()) do
		if tAbility.nId == nAbilityId then
			local _, tTier = next(tAbility.tTiers)
			return tTier and tTier.splObject:GetIcon() or nil
		end
	end
end

function ForgeUI_ActionSets:GetActionSetAfterQueue()
	local tActionSet = ActionSetLib.GetCurrentActionSet()
	for nLasIndex, nId in pairs(self.tQueuedAbilities) do
		tActionSet[nLasIndex] = nId
	end
	return tActionSet
end

function ForgeUI_ActionSets:TableInsertEx(tHistory, nAbilityNewId, nHistoryMax)
	debug("-> TableInsertEx newId = ".. nAbilityNewId .. " max = " .. nHistoryMax)
	tHistory = tHistory or {}

	for _, nId in pairs(tHistory) do
		if nId == nAbilityNewId then
			return tHistory
		end
	end

	local tResult = { [1] = nAbilityNewId }

	for _, nId in pairs(tHistory) do
		if #tResult >= nHistoryMax then
			break
		end

		if nId ~= nAbilityNewId and not tResult[nId] then
			tResult[#tResult + 1] = nId
		end
	end

	return tResult
end

function ForgeUI_ActionSets:TableRemoveEx(tHistory, nAbilityId)
	local tHistoryNew = {}
	if tHistory ~= nil then
		for _, v in pairs(tHistory) do
			if v ~= nAbilityId then
				tHistoryNew[#tHistoryNew + 1] = v
			end
		end
	end

	return tHistoryNew
end

------------------------------------------------------------------------------------------------------------------------
-- Profile
------------------------------------------------------------------------------------------------------------------------
function ForgeUI_ActionSets:ForgeAPI_LoadSettings()
	--
end

function ForgeUI_ActionSets:ForgeAPI_ProfileChanged()
	debug("-> ForgeAPI_ProfileChanged ... InitAddon")
	self:InitAddon()
end

function ForgeUI_ActionSets:ForgeAPI_PopulateOptions()
	local wndGeneral = self.tOptionHolders["General"]

	G:API_AddCheckBox(self, wndGeneral, "Enable menu buttons", self._DB.profile, "bEnableMenuButtons", { tMove = {0, 0}, fnCallback = self.BuildMenuButtons })
	G:API_AddCheckBox(self, wndGeneral, "Invisible menu buttons", self._DB.profile, "bInvisibleMenuButtons", { tMove = {0, 30}, fnCallback = self.BuildMenuButtons })
	G:API_AddCheckBox(self, wndGeneral, "Enable in-combat menu", self._DB.profile, "bCombatMenu", { tMove = {0, 60}})
	G:API_AddCheckBox(self, wndGeneral, "Show tooltips", self._DB.profile, "bShowTooltips", { tMove = {0, 90} })
	G:API_AddCheckBox(self, wndGeneral, "Play sound", self._DB.profile, "bPlaySound", { tMove = {0, 120} })
	G:API_AddNumberBox(self, wndGeneral, "Menu button width", self._DB.profile, "nMenuButtonWidth", { tMove = {300, 0}, fnCallback = self.RepositionMenuButtons })
	G:API_AddNumberBox(self, wndGeneral, "Menu button height", self._DB.profile, "nMenuButtonHeight", { tMove = {300, 30}, fnCallback = self.RepositionMenuButtons })
	G:API_AddNumberBox(self, wndGeneral, "Menu button vertical offset", self._DB.profile, "nMenuButtonOffsetY", { tOffsets = { 305, 65, 600, 90 }, fnCallback = self.RepositionMenuButtons })

	G:API_AddCheckBox(self, wndGeneral, "Show ability menu buttons", self._DB.profile, "bEnableAbilityMenuButtons", { tMove = {0, 150} })
	G:API_AddNumberBox(self, wndGeneral, "Ability buttons size", self._DB.profile, "nAbilityButtonSize", { tMove = {300, 150}, fnCallback = self.RepositionMenuButtons })

	G:API_AddCheckBox(self, wndGeneral, "Show ability history", self._DB.profile, "bEnableAbilityHistory", { tMove = {0, 210} })
	G:API_AddNumberBox(self, wndGeneral, "Number of shortcuts per ability", self._DB.profile, "nHistoryMax", { tOffsets = { 305, 215, 600, 210 } })
	G:API_AddCheckBox(self, wndGeneral, "Lock ability history", self._DB.profile, "bLockAbilityHistory", { tMove = {0, 240} })

	local wndSkinBox = G:API_AddComboBox(self, wndGeneral, "Menu button skin", self._DB.profile, "strMenuSprite", { tMove = {0, 270}, tWidths = {100, 150}, fnCallback = self.BuildMenuButtons })
	G:API_AddOptionToComboBox(self, wndSkinBox , "Lights", "Lights", {})
	G:API_AddOptionToComboBox(self, wndSkinBox , "Arrow", "Arrow", {})
	G:API_AddOptionToComboBox(self, wndSkinBox , "Glow", "Glow", {})

	G:API_AddButton(self, wndGeneral, "Rescan layout", { tOffsets = {305, 275, 455, 300}, fnCallback = function() self._DB.profile.bIsLayoutScanned = false self:BuildMenuButtons() end })
end

-----------------------------------------------------------------------------------------------
-- ForgeUI addon registration
-----------------------------------------------------------------------------------------------
F:API_NewAddon(ForgeUI_ActionSets, { arDependencies = { "ForgeUI_ActionBars" } })
