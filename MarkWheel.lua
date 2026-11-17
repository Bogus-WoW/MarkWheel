-- MarkWheel 2.0
--
-- Hold your MarkWheel key while hovering a mob: a wheel of raid markers opens
-- around your cursor. Move onto a marker and let go to put it on that mob.
-- Let go anywhere else to cancel. Picking the marker the mob already has
-- removes it.
--
-- The game only lets Blizzard's own (secure) code set raid markers, so the
-- whole wheel is built from secure frames that were set up before combat.
-- That is what lets it work during a fight too. The one side effect: the mob
-- under your cursor becomes your target when you press the key (the secure
-- macro needs a target to mark, because the cursor leaves the mob).
--
--   /mw            help and current key
--   /mw bind       press the key or mouse button to use (Esc cancels)
--   /mw scale <n>  wheel size, e.g. /mw scale 1.2 (not in combat)
--   /mw status     shows what the secure parts are doing, for troubleshooting
--
-- In a party anyone can mark; in a raid you need lead or assist.

local addonName = ...

local CLICKBIND = "CLICK MarkWheelKey:LeftButton"
BINDING_HEADER_MARKWHEEL = "MarkWheel"
_G["BINDING_NAME_" .. CLICKBIND] = "Hold to open the marker wheel"

local TAG = "|cffffd100MarkWheel|r: "
-- Clockwise from the top: Skull, Moon (right of Skull), Triangle, Star,
-- Circle, Cross (left of Skull). Diamond and Square are left out.
local ORDER = { 8, 5, 4, 1, 2, 7 }
local STEP = 360 / #ORDER
local NAMES = { "Star", "Circle", "Diamond", "Triangle", "Moon", "Square", "Cross", "Skull" }
local RADIUS, ICON, ICON_BIG, HIT = 74, 34, 48, 58
local START_MACRO = "/target [@mouseover,exists]"

local function Print(msg) print(TAG .. msg) end
local function Plain(v) if issecretvalue and issecretvalue(v) then return nil end return v end
local function MarkName(i) return _G["RAID_TARGET_" .. i] or NAMES[i] end
local function IconPath(i) return "Interface\\TargetingFrame\\UI-RaidTargetingIcon_" .. i end

local function DB()
	MarkWheelDB = MarkWheelDB or {}
	MarkWheelDB.scale = MarkWheelDB.scale or 1
	return MarkWheelDB
end

--------------------------------------------------------------------------
-- Secure snippets (run by the game in its restricted environment, so they
-- keep working in combat). They only touch frames passed in as references.
--------------------------------------------------------------------------

-- Before the key button handles a press/release: make the button run its macro
-- on this phase, and on a press start from the "target the mob" macro.
local PRE = [[
local button, down = ...
local k = self:GetFrameRef("key")
k:SetAttribute("useOnKeyDown", down and true or false)
if down then
	k:SetAttribute("macrotext", k:GetAttribute("startmacro"))
end
]]

-- After it ran: on press put the wheel under the cursor; on release hide it
-- and get ready for the next press.
local POST = [[
local message, button, down = ...
local k = self:GetFrameRef("key")
local w = self:GetFrameRef("wheel")
if down then
	k:SetAttribute("macrotext", "")
	local ui = self:GetFrameRef("ui")
	local x, y = ui:GetMousePosition()
	if x and y then
		local l, b, uw, uh = ui:GetRect()
		local s = w:GetAttribute("ws") or 1
		w:ClearAllPoints()
		w:SetPoint("CENTER", ui, "BOTTOMLEFT", x * uw / s, y * uh / s)
	end
	w:Show()
else
	w:Hide()
	k:SetAttribute("macrotext", k:GetAttribute("startmacro"))
end
]]

local ON_ENTER = [[
local k = self:GetFrameRef("key")
k:SetAttribute("macrotext", self:GetAttribute("mt"))
]]
local ON_LEAVE = [[
local k = self:GetFrameRef("key")
k:SetAttribute("macrotext", "")
]]

MarkWheelSnippets = { PRE, POST, ON_ENTER, ON_LEAVE } -- exposed only so tests can compile them

--------------------------------------------------------------------------
-- Building the frames (must happen outside combat)
--------------------------------------------------------------------------

local keyBtn, wheel, icons, hits, centerName, centerMark, selected

local function Select(slot)
	if slot == selected then return end
	selected = slot
	for i, t in ipairs(icons) do
		local on = (i == slot)
		t:SetSize(on and ICON_BIG or ICON, on and ICON_BIG or ICON)
		t:SetAlpha((slot and not on) and 0.55 or 1)
	end
	if not slot then
		centerMark:SetText("release here to cancel")
		return
	end
	local mark = ORDER[slot]
	if UnitExists("target") and Plain(GetRaidTargetIndex("target")) == mark then
		centerMark:SetText("|cffff8080Remove " .. MarkName(mark) .. "|r")
	else
		centerMark:SetText(MarkName(mark))
	end
end

local function RefreshLabel()
	if UnitExists("target") then
		local name = Plain(UnitName("target")) or "target"
		local current = Plain(GetRaidTargetIndex("target"))
		if current then name = ("|T%s:0|t %s"):format(IconPath(current), name) end
		centerName:SetText(name)
	else
		centerName:SetText("|cffff8080No mob under the cursor|r")
	end
end

local function OnUpdate()
	local slot
	for i, h in ipairs(hits) do
		if h:IsMouseOver() then slot = i break end
	end
	RefreshLabel()
	selected = false -- force the text to refresh while the target changes
	Select(slot)
end

local function Build()
	if keyBtn then return true end
	if InCombatLockdown() then return false end
	local db = DB()

	keyBtn = CreateFrame("Button", "MarkWheelKey", UIParent, "SecureActionButtonTemplate,SecureHandlerBaseTemplate")
	keyBtn:SetSize(1, 1)
	keyBtn:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -50, 50)
	keyBtn:RegisterForClicks("AnyDown", "AnyUp")
	keyBtn:SetAttribute("type", "macro")
	keyBtn:SetAttribute("startmacro", START_MACRO)
	keyBtn:SetAttribute("macrotext", START_MACRO)

	wheel = CreateFrame("Frame", "MarkWheelFrame", UIParent, "SecureHandlerBaseTemplate")
	wheel:SetSize(RADIUS * 2 + ICON_BIG + 10, RADIUS * 2 + ICON_BIG + 10)
	wheel:SetFrameStrata("FULLSCREEN_DIALOG")
	wheel:SetPoint("CENTER", UIParent, "CENTER")
	wheel:SetScale(db.scale)
	wheel:SetAttribute("ws", db.scale)
	wheel:Hide()

	for _, f in ipairs({ keyBtn, wheel }) do
		f:SetFrameRef("key", keyBtn)
		f:SetFrameRef("wheel", wheel)
		f:SetFrameRef("ui", UIParent)
	end
	SecureHandlerWrapScript(keyBtn, "OnClick", wheel, PRE, POST)

	local bg = wheel:CreateTexture(nil, "BACKGROUND")
	bg:SetTexture("Interface\\CHARACTERFRAME\\TempPortraitAlphaMask")
	bg:SetSize(RADIUS * 2 + ICON + 18, RADIUS * 2 + ICON + 18)
	bg:SetPoint("CENTER")
	bg:SetVertexColor(0, 0, 0, 0.6)

	local hub = wheel:CreateTexture(nil, "BORDER")
	hub:SetTexture("Interface\\CHARACTERFRAME\\TempPortraitAlphaMask")
	hub:SetSize(44, 44)
	hub:SetPoint("CENTER")
	hub:SetVertexColor(0.25, 0.25, 0.25, 0.8)

	icons, hits = {}, {}
	for slot, mark in ipairs(ORDER) do
		local a = math.rad((slot - 1) * STEP)
		local ox, oy = math.sin(a) * RADIUS, math.cos(a) * RADIUS
		local t = wheel:CreateTexture(nil, "ARTWORK")
		t:SetTexture(IconPath(mark))
		t:SetSize(ICON, ICON)
		t:SetPoint("CENTER", ox, oy)
		icons[slot] = t

		-- invisible secure hit area: hovering it arms the key button's macro
		local h = CreateFrame("Frame", nil, wheel, "SecureHandlerEnterLeaveTemplate")
		h:SetSize(HIT, HIT)
		h:SetPoint("CENTER", wheel, "CENTER", ox, oy)
		h:EnableMouse(true)
		h:SetFrameRef("key", keyBtn)
		h:SetAttribute("mt", "/tm [@target] " .. mark)
		h:SetAttribute("_onenter", ON_ENTER)
		h:SetAttribute("_onleave", ON_LEAVE)
		hits[slot] = h
	end

	centerName = wheel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	centerName:SetPoint("BOTTOM", wheel, "CENTER", 0, 24)
	centerName:SetWidth(RADIUS * 2 - ICON)
	centerName:SetWordWrap(false)
	centerMark = wheel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	centerMark:SetPoint("TOP", wheel, "CENTER", 0, -24)
	centerMark:SetWidth(RADIUS * 2 - ICON)

	wheel:SetScript("OnUpdate", OnUpdate)

	-- /mw debug on: print what the secure parts did, step by step (insecure hooks, so safe)
	keyBtn:HookScript("PostClick", function(self, button, down)
		if not DB().debug then return end
		Print(("key %s: macro now %q, useOnKeyDown %s, wheel %s, target %s"):format(down and "DOWN" or "UP",
			tostring(self:GetAttribute("macrotext")), tostring(self:GetAttribute("useOnKeyDown")),
			wheel:IsShown() and "shown" or "hidden", UnitExists("target") and (Plain(UnitName("target")) or "?") or "none"))
	end)
	for slot, h in ipairs(hits) do
		h:HookScript("OnEnter", function()
			if DB().debug then Print(("hover slot %d (%s): macro %q"):format(slot, MarkName(ORDER[slot]), tostring(keyBtn:GetAttribute("macrotext")))) end
		end)
	end
	return true
end

--------------------------------------------------------------------------
-- Bind mode: press the key or mouse button you want
--------------------------------------------------------------------------

local MOUSE = { LeftButton = "BUTTON1", RightButton = "BUTTON2", MiddleButton = "BUTTON3",
	Button4 = "BUTTON4", Button5 = "BUTTON5" }
local IGNORE = { LSHIFT = true, RSHIFT = true, LCTRL = true, RCTRL = true, LALT = true, RALT = true,
	UNKNOWN = true, LeftButton = true, RightButton = true }

local catcher

local function Bind(key)
	catcher:Hide()
	if InCombatLockdown() then Print("can't change bindings in combat.") return end
	local old = GetBindingAction(key)
	for _, k in ipairs({ GetBindingKey(CLICKBIND) }) do SetBinding(k) end
	SetBinding(key, CLICKBIND)
	SaveBindings(GetCurrentBindingSet())
	Print(("bound to %s."):format(GetBindingText and GetBindingText(key) or key)
		.. ((old and old ~= "" and old ~= CLICKBIND) and (" It used to do: " .. (_G["BINDING_NAME_" .. old] or old) .. ".") or ""))
end

local function StartBind()
	if InCombatLockdown() then Print("can't change bindings in combat.") return end
	if not catcher then
		catcher = CreateFrame("Button", "MarkWheelBindCatcher", UIParent, "BackdropTemplate")
		catcher:SetSize(360, 80)
		catcher:SetPoint("CENTER", 0, 120)
		catcher:SetFrameStrata("DIALOG")
		if catcher.SetBackdrop then
			catcher:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
				edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 16,
				insets = { left = 4, right = 4, top = 4, bottom = 4 } })
			catcher:SetBackdropColor(0, 0, 0, 0.9)
		end
		local t = catcher:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		t:SetPoint("CENTER")
		t:SetText("MarkWheel: press the key or mouse button to hold\n(Esc cancels; left and right click can't be used)")
		catcher:EnableKeyboard(true)
		catcher:RegisterForClicks("AnyDown")
		catcher:SetScript("OnKeyDown", function(self, key)
			if key == "ESCAPE" then self:Hide(); Print("binding unchanged.") return end
			if IGNORE[key] then return end
			Bind(key)
		end)
		catcher:SetScript("OnMouseDown", function(self, button)
			if MOUSE[button] and not IGNORE[button] then Bind(MOUSE[button]) end
		end)
	end
	catcher:Show()
end

--------------------------------------------------------------------------
-- Slash command
--------------------------------------------------------------------------

SLASH_MARKWHEEL1 = "/mw"
SLASH_MARKWHEEL2 = "/markwheel"
SlashCmdList.MARKWHEEL = function(msg)
	local cmd, rest = (msg or ""):match("^%s*(%S*)%s*(.-)%s*$")
	cmd = cmd:lower()
	local db = DB()
	if cmd == "bind" then
		StartBind()
	elseif cmd == "scale" then
		local n = tonumber(rest)
		if n and n >= 0.5 and n <= 2.5 then
			if InCombatLockdown() or not Build() then
				Print("the wheel can only be resized outside combat.")
				return
			end
			db.scale = n
			wheel:SetScale(n)
			wheel:SetAttribute("ws", n)
		end
		Print(("wheel scale %.2f."):format(db.scale))
	elseif cmd == "debug" then
		if rest == "on" then db.debug = true elseif rest == "off" then db.debug = false end
		Print("debug trace: " .. (db.debug and "on" or "off") .. ".")
	elseif cmd == "status" then
		local keys = { GetBindingKey(CLICKBIND) }
		Print(("built: %s, key: %s, in combat: %s"):format(tostring(keyBtn ~= nil),
			#keys > 0 and table.concat(keys, ", ") or "not set", tostring(InCombatLockdown() and true or false)))
		if keyBtn then
			print(("  key button macro: %q, useOnKeyDown: %s"):format(tostring(keyBtn:GetAttribute("macrotext")), tostring(keyBtn:GetAttribute("useOnKeyDown"))))
			print(("  wheel shown: %s, target: %s"):format(tostring(wheel:IsShown() and true or false), UnitExists("target") and (Plain(UnitName("target")) or "?") or "none"))
		end
	else
		local keys = { GetBindingKey(CLICKBIND) }
		Print("hold your key while hovering a mob, move onto a marker and let go. Let go anywhere else to cancel. Works in combat.")
		print("  key: " .. (#keys > 0 and table.concat(keys, ", ") or "|cffff8080not set|r - use /mw bind"))
		print("  /mw bind, /mw scale <0.5-2.5>, /mw status")
	end
end

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("PLAYER_REGEN_ENABLED")
f:RegisterEvent("PLAYER_REGEN_DISABLED")
f:SetScript("OnEvent", function(_, event)
	if event == "PLAYER_LOGIN" or event == "PLAYER_REGEN_ENABLED" then
		DB()
		if not Build() then return end
		if event == "PLAYER_LOGIN" then
			-- older versions bound the hold key to a plain function; move it over
			local old = { GetBindingKey("MARKWHEEL_HOLD") }
			if #old > 0 then
				for _, k in ipairs(old) do SetBinding(k, CLICKBIND) end
				SaveBindings(GetCurrentBindingSet())
				Print("moved your old key over to the new secure binding (needed for marking in combat).")
			end
			if not GetBindingKey(CLICKBIND) then
				C_Timer.After(8, function() Print("no key set yet. Type /mw bind and press the button you want to hold.") end)
			end
		end
	elseif catcher and catcher:IsShown() then
		catcher:Hide() -- don't sit in bind mode once combat starts
	end
end)
