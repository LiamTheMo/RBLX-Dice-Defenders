-- Results: the unified end-of-match window (Summary / Victory / Defeat). Lobby calls :Render(snap) on every State / Meta tick;
-- ResultsLogic turns the Ended snapshot into a view-model, ResultsView draws it. The server owns every number.
-- CONTINUE only dismisses the window locally in every mode (the duel server returns players to the lobby itself).

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")

local NetClient = require(script.Parent.Parent.NetClient)
local UiSounds = require(script.Parent.Parent.UiSounds)
local ResultsLogic = require(script.Parent.ResultsLogic)
local ResultsView = require(script.Parent.ResultsView)

local Results = {}
Results.__index = Results

function Results.new(parent: GuiObject)
	local self = setmetatable(
		{ _dismissed = false, _sig = nil, _open = false, _hadLevel = false, _pending = nil, _pendingSig = nil },
		Results
	)
	self._view = ResultsView.new(parent, {
		onContinue = function()
			self:_continue()
		end,
		onSkip = function()
			self._view:Skip()
		end,
	})
	self.Root = self._view.Root
	return self
end

function Results:_continue()
	self._dismissed = true
	self._pending = nil -- _pendingSig stays, so a re-read of the same snapshot cannot re-pop it
	self:_hide()
end

function Results:_hide()
	if self._open then
		self._open = false
		UiSounds.MenuClosed()
	end
	self._view:Hide()
end

function Results:IsOpen(): boolean
	return self._open
end

-- snap: NetClient.Last, or any snapshot-like Ended table (a duel result handed over by the lobby server plugs in here: pass it as `snap`).
-- Idempotent: an unchanged view-model does nothing; Meta arriving later only refreshes the level bar.
function Results:Render(snap)
	-- snap.PendingResult (lobby server, sent once, then cleared server-side): keep it here until the player presses CONTINUE.
	local fresh = type(snap) == "table" and snap.PendingResult
	if type(fresh) == "table" then
		local sig = HttpService:JSONEncode(fresh)
		if sig ~= self._pendingSig then
			self._pendingSig, self._pending, self._dismissed, self._sig = sig, fresh, false, nil
		end
	elseif type(snap) == "table" and snap.Phase == "Ended" then
		self._pending = nil -- a new Ended snapshot (solo / co-op) replaces an undismissed duel result
	end
	if type(snap) == "table" and snap.Phase ~= "Ended" and self._pending then
		snap = self._pending -- later Lobby / Idle snapshots do not remove it
	end
	if type(snap) ~= "table" or snap.Phase ~= "Ended" then
		self._dismissed, self._sig, self._v, self._hadLevel = false, nil, nil, false
		if self._open then
			self:_hide()
		end
		return
	end
	if self._dismissed then
		return
	end
	local lp = Players.LocalPlayer
	local v = ResultsLogic.view(snap, NetClient.LastMeta, { Name = lp.DisplayName, UserId = lp.UserId })
	if not v then
		return
	end
	self._v = v
	local sig = HttpService:JSONEncode(v)
	if sig == self._sig then
		return
	end
	self._sig = sig
	local first = not self._open
	local levelAppeared = v.Level ~= nil and not self._hadLevel -- Meta can land after the snapshot: animate the bar then
	self._hadLevel = v.Level ~= nil
	self._view:Render(v, first or levelAppeared)
	if first then
		self._open = true
		self._view:Show()
		UiSounds.MenuOpened()
	end
end

function Results:Destroy()
	self._view:Destroy()
end

return Results
