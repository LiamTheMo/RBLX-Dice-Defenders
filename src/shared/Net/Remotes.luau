--!strict
-- Remote names under ReplicatedStorage.Remotes (docs/MVP.md, "Remotes").
-- Function = RemoteFunction (client -> server intent, returns (ok, code?));
-- Event = RemoteEvent (server -> client). Nothing else is shared with clients
-- except Core/Loader, Core/Signal, Layout, Display and SettingsDefs.

local Remotes = {}

Remotes.Kinds = table.freeze({
	Start = "Function", -- (seq)
	Summon = "Function", -- (seq)
	Merge = "Function", -- (seq, from, to)
	EquipDeck = "Function", -- (seq, ids): 5 distinct owned die ids
	ClaimQuest = "Function", -- (seq, questId)
	RedeemCode = "Function", -- (seq, code)
	SaveSettings = "Function", -- (seq, patch): {[settingId] = value}, cleaned against Shared/SettingsDefs
	BagAction = "Function", -- (seq, action, id, qty): Sell/Use/Lock/Unlock/Equip/Unequip (Rules/Bag)
	Roll = "Function", -- (seq, pool, count): paid random dice (Rules/Roll); odds, prices and pity stay on the server
	Buy = "Function", -- (seq, offerId): a Gold or Gems Shop offer (Rules/Shop); price and grant stay on the server
	UpgradeDie = "Function", -- (seq, dieId): spend spare copies of that die for +1 level (Rules/Upgrade); the client never sends a level, copies or cost
	PowerUp = "Function", -- (seq, dieId): in-match Power Up of one die type of the deck (Rules/Match.TryPowerUp); MP, tier and cost stay on the server
	State = "Event", -- S -> C snapshot
	Enemies = "Event", -- S -> C, owner only: {S, H, R, F}
	Meta = "Event", -- S -> C, that player only: lobby payload (docs/MVP.md "Meta")
	Catalog = "Event", -- S -> C, that player only, once on load before Meta: display catalogue
	RollResult = "Event", -- S -> C, that player only, after a successful Roll: {Pool, Results = {{Id, Rarity, New}}, Pity}
})

return table.freeze(Remotes)
