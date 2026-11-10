--!strict
-- Remote names under ReplicatedStorage.Remotes (docs/MVP.md, "Remotes").
-- Function = RemoteFunction (client -> server intent, returns (ok, code?));
-- Event = RemoteEvent (server -> client). Nothing else is shared with clients
-- except Core/Loader, Core/Signal, Layout and Display.

local Remotes = {}

Remotes.Kinds = table.freeze({
	Start = "Function", -- (seq)
	Summon = "Function", -- (seq)
	Merge = "Function", -- (seq, from, to)
	EquipDeck = "Function", -- (seq, ids): 5 distinct owned die ids
	ClaimQuest = "Function", -- (seq, questId)
	State = "Event", -- S -> C snapshot
	Enemies = "Event", -- S -> C, owner only: {S, H, R, F}
	Meta = "Event", -- S -> C, owner only: {Dice, Deck, Quests, DailyResetAt}
})

return table.freeze(Remotes)
