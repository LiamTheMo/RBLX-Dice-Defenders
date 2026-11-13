--!strict
-- Shop menu logic: pure, no Instances. Display only; nothing here sells or grants anything.

local ShopLogic = {}

export type Section = { Kind: string, Heading: string, Items: { any }? }

-- Tab order and labels; icons are the View's job.
ShopLogic.TABS = {
	{ Id = "FEATURED", Label = "FEATURED" },
	{ Id = "GAMEPASSES", Label = "GAMEPASSES" },
	{ Id = "GEMS", Label = "GEMS" },
	{ Id = "SHARDS", Label = "SHARDS" },
}

local function cards(heading: string, items: { any }): Section
	return { Kind = "Cards", Heading = heading, Items = items }
end

function ShopLogic.sectionsFor(tabId: string, data: any): { Section }
	if tabId == "FEATURED" then
		return {
			{ Kind = "Hero", Heading = "STARTER PACK", Items = { data.Starter } },
			cards("GAMEPASSES", data.Gamepasses),
			cards("GEMS", data.Gems),
		}
	elseif tabId == "GAMEPASSES" then
		return { cards("GAMEPASSES", data.Gamepasses) }
	elseif tabId == "GEMS" then
		return { cards("GEMS", data.Gems) }
	end
	local heading = "COMING SOON"
	for _, tab in ShopLogic.TABS do
		if tab.Id == tabId then
			heading = tab.Label
		end
	end
	return { { Kind = "Soon", Heading = heading } }
end

-- Whole number with thousands commas: 1200 -> "1,200". Floors; never negative.
function ShopLogic.priceText(n: number): string
	local s = tostring(math.max(0, math.floor(n)))
	while true do
		local r, count = string.gsub(s, "^(%d+)(%d%d%d)", "%1,%2")
		s = r
		if count == 0 then
			return s
		end
	end
end

-- One flight at a time: begin() is true once until finish().
function ShopLogic.guard(): { begin: () -> boolean, finish: () -> () }
	local busy = false
	return {
		begin = function()
			if busy then
				return false
			end
			busy = true
			return true
		end,
		finish = function()
			busy = false
		end,
	}
end

return ShopLogic
