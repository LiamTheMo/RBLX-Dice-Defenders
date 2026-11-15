-- Client settings store (session only): the ordered registry the Settings menu draws,
-- value cleaning, get/set with change listeners, per-tab reset, and display text.
-- Pure Luau, no Roblox services, so it runs headless. Not auto-loaded: require it.

export type Def = {
	id: string,
	tab: string,
	kind: "toggle" | "slider" | "select",
	name: string,
	desc: string,
	default: any,
	min: number?,
	max: number?,
	step: number?,
	options: { string }?,
	noEffectYet: boolean, -- true while nothing in the game reads this setting
}

local SettingsLogic = {}

SettingsLogic.TABS = { "GAMEPLAY", "GRAPHICS", "AUDIO", "MISC" }

SettingsLogic.DEFS = {
	-- GAMEPLAY
	{
		id = "autoSkipWaves",
		tab = "GAMEPLAY",
		kind = "toggle",
		name = "Auto Skip Waves",
		desc = "Automatically start the next wave when it's ready.",
		default = false,
		noEffectYet = true,
	},
	{
		id = "damageNumbers",
		tab = "GAMEPLAY",
		kind = "toggle",
		name = "Damage Numbers",
		desc = "Show damage values above enemies when they take damage.",
		default = true,
		noEffectYet = true,
	},
	{
		id = "rangeRings",
		tab = "GAMEPLAY",
		kind = "toggle",
		name = "Tower Range Rings",
		desc = "Show a visible range ring around towers when selected.",
		default = true,
		noEffectYet = true,
	},
	{
		id = "waveAnnouncements",
		tab = "GAMEPLAY",
		kind = "toggle",
		name = "Wave Announcements",
		desc = "Display an on-screen banner when a new wave begins.",
		default = true,
		noEffectYet = true,
	},
	{
		id = "placementGrid",
		tab = "GAMEPLAY",
		kind = "toggle",
		name = "Placement Grid",
		desc = "Show a placement grid to help align towers.",
		default = true,
		noEffectYet = true,
	},
	{
		id = "autoCloseMenus",
		tab = "GAMEPLAY",
		kind = "toggle",
		name = "Auto Close Menus",
		desc = "Automatically close menus after taking an action (e.g., placing a tower).",
		default = false,
		noEffectYet = true,
	},
	-- GRAPHICS
	{
		id = "effectsQuality",
		tab = "GRAPHICS",
		kind = "select",
		name = "Effects Quality",
		desc = "Overall quality of visual effects.",
		default = "High",
		options = { "Low", "Medium", "High" },
		noEffectYet = true,
	},
	{
		id = "projectileEffects",
		tab = "GRAPHICS",
		kind = "toggle",
		name = "Projectile Effects",
		desc = "Show visual effects for projectiles (e.g., trails, impacts).",
		default = true,
		noEffectYet = true,
	},
	{
		id = "shadows",
		tab = "GRAPHICS",
		kind = "toggle",
		name = "Shadows",
		desc = "Render dynamic shadows for units, enemies, and maps.",
		default = true,
		noEffectYet = false,
	},
	{
		id = "screenShake",
		tab = "GRAPHICS",
		kind = "toggle",
		name = "Screen Shake",
		desc = "Shake the screen during intense events.",
		default = false,
		noEffectYet = true,
	},
	{
		id = "uiScale",
		tab = "GRAPHICS",
		kind = "slider",
		name = "UI Scale",
		desc = "Adjust the size of the game UI.",
		default = 100,
		min = 70,
		max = 100,
		step = 5,
		noEffectYet = false,
	},
	{
		id = "effectScale",
		tab = "GRAPHICS",
		kind = "slider",
		name = "Effect Scale",
		desc = "Adjust the size of visual effects (e.g., explosions, auras).",
		default = 75,
		min = 25,
		max = 100,
		step = 5,
		noEffectYet = true,
	},
	-- AUDIO
	{
		id = "masterVolume",
		tab = "AUDIO",
		kind = "slider",
		name = "Master Volume",
		desc = "Adjust the overall volume of all game audio.",
		default = 100,
		min = 0,
		max = 100,
		step = 5,
		noEffectYet = true,
	},
	{
		id = "musicVolume",
		tab = "AUDIO",
		kind = "slider",
		name = "Music",
		desc = "Adjust the volume of background music.",
		default = 70,
		min = 0,
		max = 100,
		step = 5,
		noEffectYet = true,
	},
	{
		id = "sfxVolume",
		tab = "AUDIO",
		kind = "slider",
		name = "Sound Effects",
		desc = "Adjust the volume of general sound effects.",
		default = 85,
		min = 0,
		max = 100,
		step = 5,
		noEffectYet = true,
	},
	{
		id = "interfaceVolume",
		tab = "AUDIO",
		kind = "slider",
		name = "Interface Sounds",
		desc = "Adjust the volume of UI and menu sounds.",
		default = 75,
		min = 0,
		max = 100,
		step = 5,
		noEffectYet = true,
	},
	{
		id = "ambienceVolume",
		tab = "AUDIO",
		kind = "slider",
		name = "Ambience",
		desc = "Adjust the volume of ambient environmental sounds.",
		default = 65,
		min = 0,
		max = 100,
		step = 5,
		noEffectYet = true,
	},
	-- MISC
	{
		id = "reducedMotion",
		tab = "MISC",
		kind = "toggle",
		name = "Reduced Motion",
		desc = "Minimize non-essential animations and screen motion.",
		default = false,
		noEffectYet = false,
	},
	{
		id = "highContrast",
		tab = "MISC",
		kind = "toggle",
		name = "High Contrast UI",
		desc = "Increase UI contrast for better readability.",
		default = false,
		noEffectYet = true,
	},
	{
		id = "showFps",
		tab = "MISC",
		kind = "toggle",
		name = "Show FPS",
		desc = "Display the current frame rate (FPS) on screen.",
		default = false,
		noEffectYet = false,
	},
	{
		id = "hideOthersEffects",
		tab = "MISC",
		kind = "toggle",
		name = "Hide Other Players' Effects",
		desc = "Don't show visual effects from other players (e.g., trails, auras).",
		default = false,
		noEffectYet = true,
	},
	{
		id = "notifications",
		tab = "MISC",
		kind = "toggle",
		name = "Notifications",
		desc = "Receive in-game notifications (e.g., rewards, invites, events).",
		default = true,
		noEffectYet = true,
	},
	{
		id = "language",
		tab = "MISC",
		kind = "select",
		name = "Language",
		desc = "Change the game's display language.",
		default = "English",
		options = { "English" },
		noEffectYet = true,
	},
} :: { Def }

local byId: { [string]: Def } = {}
local values: { [string]: any } = {}
for _, def in SettingsLogic.DEFS do
	byId[def.id] = def
	values[def.id] = def.default
end
SettingsLogic.byId = byId

local listeners: { (string, any) -> () } = {}
local report = warn or print -- the headless spec runner has no warn

-- The cleaned value, or nil when `value` is the wrong type or out of range for `def`.
function SettingsLogic.clean(def: Def, value: any): any
	if def.kind == "toggle" then
		return if type(value) == "boolean" then value else nil
	elseif def.kind == "select" then
		return if type(value) == "string" and table.find(def.options :: { string }, value) then value else nil
	end
	if type(value) ~= "number" or value ~= value or value == math.huge or value == -math.huge then
		return nil
	end
	local min, step = def.min :: number, def.step or 1
	local snapped = min + math.round((value - min) / step) * step
	-- Drop float noise from the division (0.30000000000000004 -> 0.3).
	return math.clamp(math.round(snapped * 1000) / 1000, min, def.max :: number)
end

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
