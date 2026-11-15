-- Catalog.Build: the client-visible projection of the server catalogues. Arrays
-- only, sorted by Id, equal to config, never a redeem code.

local Server = game:GetService("ServerScriptService").Server
local Catalog = require(Server.Rules.Catalog)
local Dice = require(Server.Config.Dice)
local Inventory = require(Server.Config.Inventory)
local Codes = require(Server.Config.Codes)

-- Deterministic text form; errors on a sparse or mixed table (it would not survive a remote).
local function dump(v)
	if type(v) ~= "table" then
		return tostring(v)
	end
	local keys, n = {}, 0
	for k in v do
		n += 1
		table.insert(keys, k)
	end
	if #v > 0 then
		assert(#v == n, "sparse or mixed table")
	end
	table.sort(keys, function(a, b)
		return tostring(a) < tostring(b)
	end)
	local parts = {}
	for _, k in keys do
		table.insert(parts, tostring(k) .. "=" .. dump(v[k]))
	end
	return "{" .. table.concat(parts, ",") .. "}"
end

local function sortedIds(list)
	for i = 2, #list do
		if not (list[i - 1].Id < list[i].Id) then
			return false
		end
	end
	return true
end

local function count(map)
	local n = 0
	for _ in map do
		n += 1
	end
	return n
end

test("every die appears once with config Name, Rarity, Damage and Rate; sorted by Id", function()
	local c = Catalog.Build()
	expectEq(#c.Dice, count(Dice.Types), "one row per die type")
	expect(sortedIds(c.Dice), "sorted, so ids are unique")
	for _, row in c.Dice do
		local t = Dice.Types[row.Id]
		expect(t ~= nil, "known die " .. tostring(row.Id))
		expect(row.Name == t.name and row.Rarity == t.rarity, row.Id .. " name and rarity")
		expect(row.Damage == t.base and row.Rate == t.rate, row.Id .. " damage and rate")
	end
end)

test("StarterDeck equals Config/Dice.Deck", function()
	local deck = Catalog.Build().StarterDeck
	expectEq(#deck, #Dice.Deck, "length")
	for i, id in Dice.Deck do
		expectEq(deck[i], id, "slot " .. i)
	end
end)

test("every Inventory entry appears once with equal display fields", function()
	local c = Catalog.Build()
	for _, kind in { "Materials", "Items", "Cosmetics" } do
		local rows = c[kind]
		expectEq(#rows, count(Inventory[kind]), kind .. " count")
		expect(sortedIds(rows), kind .. " sorted by Id")
		for _, row in rows do
			local entry = Inventory[kind][row.Id]
			expect(entry ~= nil, kind .. " known id " .. tostring(row.Id))
			for _, field in { "Name", "Rarity", "Description", "Sell", "Icon", "Type", "Slot" } do
				expectEq(row[field], entry[field], kind .. " " .. row.Id .. " " .. field)
			end
		end
	end
	local use = {}
	for _, row in c.Items do
		use[row.Id] = row.Use
	end
	expectEq(use.XpTome, "+100 XP", "XpTome use text")
	expectEq(use.GoldPouch, "+200 Gold", "GoldPouch use text")
end)

test("arrays only, no sparse keys, no functions, nothing shared with config", function()
	local c = Catalog.Build()
	local text = dump(c) -- asserts every table is a plain array or a plain record
	expect(not string.find(text, "function", 1, true), "no functions")
	for _, row in c.Items do
		expect(row.Use == nil or type(row.Use) == "string", "Use is display text")
	end
	expect(c.StarterDeck ~= Dice.Deck, "own copy of the deck")
	expectEq(dump(Catalog.Build()), text, "deterministic")
end)

test("no redeem code or code id appears anywhere in the Catalog", function()
	local text = dump(Catalog.Build())
	for _, entry in Codes.List do
		expect(not string.find(text, entry.Code, 1, true), "code text leaked: " .. entry.Code)
		expect(not string.find(text, entry.Id, 1, true), "code id leaked: " .. entry.Id)
	end
	local source = __sources["ServerScriptService/Server/Rules/Catalog"]
	expect(source ~= nil and not string.find(source, "Codes", 1, true), "Catalog never requires Config/Codes")
end)
