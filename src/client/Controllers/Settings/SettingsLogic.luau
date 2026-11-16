-- Client settings store: the ordered registry the Settings menu draws (Shared/SettingsDefs, the same
-- one the server cleans saves against), get/set with change listeners, per-tab reset, and display text.
-- Pure Luau, no Roblox services, so it runs headless. Not auto-loaded: require it.

local SettingsDefs = require(game:GetService("ReplicatedStorage").Shared.SettingsDefs)

export type Def = SettingsDefs.Def

local SettingsLogic = {}

SettingsLogic.TABS = { "GAMEPLAY", "GRAPHICS", "AUDIO", "MISC" }
SettingsLogic.DEFS = SettingsDefs.DEFS
SettingsLogic.clean = SettingsDefs.clean -- (def, value) -> cleaned value or nil

local byId = SettingsDefs.ById
SettingsLogic.byId = byId
local values: { [string]: any } = {}
for _, def in SettingsLogic.DEFS do
	values[def.id] = def.default
end

local listeners: { (string, any) -> () } = {}
local report = warn or print -- the headless spec runner has no warn

-- The slider value at fraction f (0..1, clamped) of its range, snapped by the store; nil for a non-slider or a NaN f.
function SettingsLogic.fromFraction(id: string, f: number): any
	local def = byId[id]
	if not def or def.kind ~= "slider" or type(f) ~= "number" or f ~= f then
		return nil
	end
	local min = def.min :: number
	return SettingsLogic.clean(def, min + ((def.max :: number) - min) * math.clamp(f, 0, 1))
end

function SettingsLogic.get(id: string): any
	return values[id]
end

function SettingsLogic.set(id: string, value: any): boolean
	local def = byId[id]
	local cleaned = if def then SettingsLogic.clean(def, value) else nil
	if cleaned == nil then
		return false
	end
	if values[id] ~= cleaned then
		values[id] = cleaned
		for _, cb in table.clone(listeners) do
			local ok, err = pcall(cb, id, cleaned)
			if not ok then
				report(`[Settings] {id} listener failed: {err}`)
			end
		end
	end
	return true
end

local function resetWhere(tab: string?)
	for _, def in SettingsLogic.DEFS do
		if tab == nil or def.tab == tab then
			SettingsLogic.set(def.id, def.default)
		end
	end
end

function SettingsLogic.resetTab(tab: string)
	resetWhere(tab)
end

function SettingsLogic.resetAll()
	resetWhere(nil)
end

-- Returns a function that removes the listener.
function SettingsLogic.onChanged(cb: (string, any) -> ()): () -> ()
	table.insert(listeners, cb)
	return function()
		local i = table.find(listeners, cb)
		if i then
			table.remove(listeners, i)
		end
	end
end

-- Steps a select's value by dir (+1 / -1), wrapping. False when nothing can change.
function SettingsLogic.cycle(id: string, dir: number): boolean
	local def = byId[id]
	if not def or def.kind ~= "select" then
		return false
	end
	local options = def.options :: { string }
	if #options < 2 then
		return false
	end
	local i = table.find(options, values[id]) :: number
	return SettingsLogic.set(id, options[(i - 1 + (if dir < 0 then -1 else 1)) % #options + 1])
end

function SettingsLogic.format(id: string, value: any?): string
	local def = byId[id]
	local v = if value == nil then values[id] else value
	if def.kind == "toggle" then
		return if v then "ON" else "OFF"
	elseif def.kind == "slider" then
		return string.format("%d%%", math.round(v))
	end
	return string.upper(v)
end

return SettingsLogic
