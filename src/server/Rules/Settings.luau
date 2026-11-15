-- Pure SaveSettings rule: merges a client patch into profile.Settings (v6). Walks the shared
-- registry, so only known keys are read; each value is cleaned (Shared/SettingsDefs) and a
-- wrong-typed or bad one is dropped silently. No yield.

local SettingsDefs = require(game:GetService("ReplicatedStorage").Shared.SettingsDefs)

local Settings = {}

-- `patch` has passed SettingsDefs.Shape (RemoteGuard). Always true: bad entries are not an error.
function Settings.Merge(profile, patch): boolean
	for _, def in SettingsDefs.DEFS do
		local value = SettingsDefs.clean(def, patch[def.id])
		if value ~= nil then
			profile.Settings[def.id] = value
		end
	end
	return true
end

return Settings
