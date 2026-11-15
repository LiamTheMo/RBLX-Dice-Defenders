-- The settings registry shared by the client store (Settings/SettingsLogic) and the server
-- (Rules/Settings, RemoteGuard, ProfileSchema): the ordered defs the Settings menu draws, value
-- cleaning, and the SaveSettings patch shape. Pure Luau, no services: runs headless.

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

local SettingsDefs = {}

SettingsDefs.DEFS = table.freeze({
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
}) :: { Def }

local byId: { [string]: Def } = {}
for _, def in SettingsDefs.DEFS do
	if def.options then
		table.freeze(def.options)
	end
	byId[def.id] = table.freeze(def)
end
SettingsDefs.ById = table.freeze(byId)

local MAX_TEXT = 32 -- bytes: the longest key or string value a SaveSettings patch may carry

local function finite(value: any): boolean
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

-- The cleaned value, or nil when `value` is the wrong type or out of range for `def`.
function SettingsDefs.clean(def: Def, value: any): any
	if def.kind == "toggle" then
		return if type(value) == "boolean" then value else nil
	elseif def.kind == "select" then
		return if type(value) == "string" and table.find(def.options :: { string }, value) then value else nil
	end
	if not finite(value) then
		return nil
	end
	local min, step = def.min :: number, def.step or 1
	local snapped = min + math.round((value - min) / step) * step
	-- Drop float noise from the division (0.30000000000000004 -> 0.3).
	return math.clamp(math.round(snapped * 1000) / 1000, min, def.max :: number)
end

-- SaveSettings guard: a plain table of at most #DEFS entries, string keys of 1..32 bytes, values
-- boolean, finite number or a string of at most 32 bytes. Stops reading after #DEFS + 1 entries.
function SettingsDefs.Shape(patch: any): boolean
	if type(patch) ~= "table" or getmetatable(patch) ~= nil then
		return false
	end
	local n = 0
	for key, value in patch do
		n += 1
		if n > #SettingsDefs.DEFS or type(key) ~= "string" or #key < 1 or #key > MAX_TEXT then
			return false
		end
		local kind = type(value)
		if not (kind == "boolean" or finite(value) or (kind == "string" and #value <= MAX_TEXT)) then
			return false
		end
	end
	return true
end

return table.freeze(SettingsDefs)
