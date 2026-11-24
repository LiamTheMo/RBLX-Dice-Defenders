local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Chrome = require(script.Parent.Bag.Chrome)
local Display = require(ReplicatedStorage.Shared.Display)
local NetClient = require(script.Parent.NetClient)
local Parts = require(script.Parent.Bag.Parts)
local UiKit = require(script.Parent.UiKit)

local TutorialView = {}

function TutorialView.new(parent, openMenu, toast)
	local panel = Chrome.panel(parent, {
		Name = "Tutorial",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -90),
		Size = UDim2.new(1, -24, 0, 116),
		Visible = false,
		ZIndex = 65,
	})
	UiKit.make("UISizeConstraint", { MaxSize = Vector2.new(490, 116) }, panel)
	local text = Parts.text(panel, {
		Name = "Instruction",
		Position = UDim2.fromOffset(12, 8),
		Size = UDim2.new(1, -24, 0, 48),
		TextSize = 19,
		TextWrapped = true,
		ZIndex = 66,
	})
	local action, alternate
	local busy = false

	local function request(name)
		if busy then
			return
		end
		busy = true
		task.spawn(function()
			local ok, code = NetClient.Request("TutorialAction", name, "")
			busy = false
			if not ok then
				toast(
					if code == "ContinueCoop"
						then "Your shared co-op run can keep going."
						elseif code == "Overflow" then "Make room in your inventory to claim the gift."
						else "That tutorial action is unavailable right now."
				)
			elseif name == "Claim" then
				local info = code and Display.Dice[code]
				toast(`Tutorial gift claimed: {if info then info.Name else "Epic die"}, 500 Gems and 5 Dice Shards.`)
			end
		end)
	end

	local first = UiKit.button(
		{ Name = "Primary", Size = UDim2.new(0.48, 0, 0, 44), ZIndex = 66 },
		panel,
		UiKit.GREEN,
		function()
			if action then
				action()
			end
		end
	)
	local second = UiKit.button(
		{ Name = "Secondary", Position = UDim2.new(0.51, 0, 0, 62), Size = UDim2.new(0.48, 0, 0, 44), ZIndex = 66 },
		panel,
		Color3.fromRGB(195, 220, 246),
		function()
			if alternate then
				alternate()
			end
		end
	)
	return function(menuOpen)
		local meta, snap = NetClient.LastMeta, NetClient.Last
		local tutorial = meta and meta.Tutorial
		local phase = snap and snap.Phase
		local playing = phase == "Playing"
		local lobby = phase == "Lobby" or phase == "Ended"
		action, alternate = nil, nil
		panel.Visible = false
		if not tutorial or (not lobby and not playing) or (menuOpen and not playing) then
			return
		end
		local title, subtitle
		if tutorial.Stage == "Roll" and lobby then
			text.Text =
				`Roll your first five dice. You have {tutorial.Gems} starter Gems and {tutorial.Rolls}/{tutorial.RollCount} dice.`
			title, action = "OPEN ROLL", function()
				openMenu("Roll")
			end
		elseif tutorial.Stage == "Play" and lobby then
			text.Text = "Your new dice are equipped. Open Play and clear wave 10."
			title, action = "OPEN PLAY", function()
				openMenu("Play")
			end
		elseif tutorial.Stage == "Play" and playing then
			text.Text =
				`Tutorial: clear wave {tutorial.TargetWave}   ·   {snap.WavesCompleted or 0}/{tutorial.TargetWave}`
		elseif tutorial.Stage == "Choose" and playing then
			text.Text =
				"Wave 10 cleared. End the run to claim your tutorial gift, or keep playing for more wave rewards."
			if snap.PlayerCount == 2 then
				text.Text = "Wave 10 cleared. Keep playing for more rewards and claim your gift when the team run ends."
				title, action = "KEEP GOING", function()
					request("Continue")
				end
			else
				title, action = "END RUN", function()
					request("End")
				end
				subtitle, alternate = "KEEP GOING", function()
					request("Continue")
				end
			end
		elseif tutorial.Stage == "Gift" and lobby then
			text.Text =
				`Tutorial gift: a random Epic die, {tutorial.GiftGems} Gems and {tutorial.GiftShards} Dice Shards.`
			title, action = "CLAIM GIFT", function()
				request("Claim")
			end
		else
			return
		end
		panel.Visible = true
		panel.Size = UDim2.new(1, -24, 0, if title then 116 else 60)
		first.Visible, second.Visible = title ~= nil, subtitle ~= nil
		first.Position = UDim2.new(if subtitle then 0.01 else 0.26, 0, 0, 62)
		first.Text, second.Text = title or "", subtitle or ""
	end
end

return TutorialView
