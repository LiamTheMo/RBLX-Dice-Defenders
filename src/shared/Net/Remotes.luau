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
	State = "Event", -- S -> C snapshot
	Enemies = "Event", -- S -> C, owner only: {S, H, R, F}
})

return table.freeze(Remotes)
