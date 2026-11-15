--!strict
-- Daily Rewards menu logic: pure, no Instances. Display only; nothing here grants anything.

local QuestLogic = require(script.Parent.Parent.QuestLog.QuestLogic)

local DailyLogic = {}

DailyLogic.DAYS = 7

local function clampStreak(streak: number): number
	return math.clamp(math.floor(streak), 0, DailyLogic.DAYS)
end

function DailyLogic.cardState(day: number, streak: number, claimedToday: boolean): string
	local s = clampStreak(streak)
	if day <= s then
		return "Claimed"
	elseif day == s + 1 and not claimedToday then
		return "Today"
	end
	return "Upcoming"
end

function DailyLogic.progressText(streak: number): string
	return clampStreak(streak) .. " / " .. DailyLogic.DAYS .. " DAYS"
end

-- "+1,000"; dice are counted with a multiplication sign: "×1".
function DailyLogic.amountText(reward: { Kind: string, Amount: number }): string
	if reward.Kind == "Die" then
		return "\u{00D7}" .. QuestLogic.format(reward.Amount)
	end
	return "+" .. QuestLogic.format(reward.Amount)
end

function DailyLogic.claimState(data: { Streak: number, ClaimedToday: boolean }?): string
	if data == nil then
		return "Soon" -- live: no server feature yet
	elseif data.ClaimedToday or data.Streak >= DailyLogic.DAYS then
		return "Claimed"
	end
	return "Ready"
end

-- Bigger amounts draw bigger coin stacks.
function DailyLogic.coinTier(amount: number): number
	if amount < 1000 then
		return 1
	elseif amount < 1500 then
		return 2
	end
	return 3
end

function DailyLogic.timerText(secondsLeft: number): string
	return QuestLogic.resetText(math.max(0, secondsLeft))
end

return DailyLogic
