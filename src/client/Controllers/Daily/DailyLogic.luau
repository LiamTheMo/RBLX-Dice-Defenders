--!strict
-- Daily Rewards menu logic: pure, no Instances. Display only; the server decides the streak, the day and the reward.
-- login = Meta.Login {Streak, ClaimedToday, NextClaimAt, NextDay?}; days = Catalog.Daily.Days {{Day, Chest?, Rewards}}.

local QuestLogic = require(script.Parent.Parent.QuestLog.QuestLogic)

local DailyLogic = {}

DailyLogic.DAYS = 7

-- Catalog reward Kind -> the view's reward kind (its icon). Unlisted kinds (Cosmetic) are not drawn.
DailyLogic.KIND = {
	Gold = "Coins",
	Gems = "Gems",
	Item = "Potion", -- XP Tome, Gold Pouch
	Xp = "Potion",
	Material = "Crystals",
	Die = "Die",
}

local function clampStreak(streak: number): number
	return math.clamp(math.floor(streak), 0, DailyLogic.DAYS)
end

function DailyLogic.cardState(day: number, login: { Streak: number, NextDay: number? }?): string
	if login == nil then
		return "Upcoming"
	elseif day <= clampStreak(login.Streak) then
		return "Claimed"
	elseif day == login.NextDay then
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

-- Catalog days -> view days: {Day, Chest?, Rewards = {{Kind (view), Id?, Amount}}}.
function DailyLogic.days(days: { any }): { any }
	local out = {}
	for _, d in days do
		local rewards = {}
		for _, line in d.Rewards or {} do
			local kind = DailyLogic.KIND[line.Kind]
			if kind then
				table.insert(rewards, { Kind = kind, Id = line.Id, Amount = line.Amount })
			end
		end
		table.insert(out, { Day = d.Day, Chest = d.Chest, Rewards = rewards })
	end
	return out
end

-- "Soon" = no Meta yet (the loading card); "Ready" only while the server offers a day.
function DailyLogic.claimState(login: { NextDay: number? }?): string
	if login == nil then
		return "Soon"
	elseif login.NextDay ~= nil then
		return "Ready"
	end
	return "Claimed"
end

-- Unix time the "Next claim in:" timer counts to, or nil (no timer while a day is claimable or before Meta).
function DailyLogic.timerTarget(login: { NextDay: number?, NextClaimAt: number? }?): number?
	if login == nil or login.NextDay ~= nil or type(login.NextClaimAt) ~= "number" then
		return nil
	end
	return login.NextClaimAt
end

-- Bigger amounts draw a bigger coin.
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
