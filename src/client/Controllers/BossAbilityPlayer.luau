--!strict
-- Client playback of boss ability events (the Enemies batch A records, see Match bossEvent).
-- A "windup" record starts the ability clip (clip start = cast time - Bosses.Ability.CastAt) and the Windup hook, a "cast"
-- record fires Cast + Impact, a "telegraph" record fires Telegraph. The clip is baked data in BossAbilityData/<Variant>
-- (tools/gen_boss_ability.py, same layout as BossWalkData plus Fps); a variant without a data module plays no animation
-- but keeps its VFX hooks. Pose returns an override EnemyRig.Step blends over the walk pose, blending in and out.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Bosses = require(ReplicatedStorage.Shared.Bosses)
local BossWalk = require(script.Parent.BossWalk)
local BossFx = require(script.Parent.Effects.BossFx)

local BossAbilityPlayer = {}

export type Data = { Fps: number?, Frames: number, Joints: { [string]: { number } } }
export type Override = { poses: { [string]: CFrame }, weight: number }

BossAbilityPlayer.BlendIn = 0.12 -- seconds from the walk pose into the clip
BossAbilityPlayer.BlendOut = 0.25 -- seconds from the last clip pose back to the walk

local cache: { [string]: Data | false } = {}

-- The baked clip of a variant, or nil when its module is missing or broken.
function BossAbilityPlayer.Data(variant: string): Data?
	local hit = cache[variant]
	if hit == nil then
		hit = false
		local ok, data = pcall(function()
			local folder = script.Parent:FindFirstChild("BossAbilityData")
			local module = if folder then folder:FindFirstChild(variant) else nil
			return if module and module:IsA("ModuleScript") then require(module) else nil
		end)
		if ok and type(data) == "table" and data.Frames and data.Joints then
			hit = data :: Data
		end
		cache[variant] = hit
	end
	return if hit then hit :: Data else nil
end

-- Blend weight of the clip over the walk pose `t` seconds into the ability: ramps in over BlendIn, holds 1 until the clip
-- ends, ramps out over BlendOut; nil before the start and after the blend-out.
function BossAbilityPlayer.Weight(clipSeconds: number, t: number): number?
	if t < 0 or t > clipSeconds + BossAbilityPlayer.BlendOut then
		return nil
	end
	if t > clipSeconds then
		return 1 - (t - clipSeconds) / BossAbilityPlayer.BlendOut
	end
	return math.min(1, t / BossAbilityPlayer.BlendIn)
end

-- Override for EnemyRig.Step at `t` seconds into the ability, or nil (no data, finished or not started).
function BossAbilityPlayer.Sample(data: Data?, clipSeconds: number, t: number): Override?
	local weight = BossAbilityPlayer.Weight(clipSeconds, t)
	if data == nil or weight == nil then
		return nil
	end
	return { poses = BossWalk.PoseClip(data, t * (data.Fps or 30)), weight = weight }
end

local function infoOf(e, record, variant: string): BossFx.Info
	return {
		Id = record.Id,
		Ability = record.Ability,
		Phase = record.Phase,
		CastAt = record.At,
		Target = record.Target,
		Info = record.Info,
		Config = Bosses.Ability[variant],
		Seat = e.seat,
		Arena = e.playerCount,
		Position = e.part.Position,
	}
end

-- One A record for the enemy entry `e` (EnemyView's table: part, rig, variant, seat, playerCount).
function BossAbilityPlayer.On(e, record)
	local variant = e.variant
	local cfg = if variant then Bosses.Ability[variant] else nil
	if cfg == nil or e.rig == nil or type(record.At) ~= "number" then
		return
	end
	local info = infoOf(e, record, variant)
	local model = e.rig.model
	if record.Phase == "windup" then
		e.ability = { startAt = record.At - cfg.CastAt, data = BossAbilityPlayer.Data(variant), cfg = cfg }
		BossFx.Call(variant, "Windup", model, e.rig, info)
	elseif record.Phase == "cast" then
		BossFx.Call(variant, "Cast", model, e.rig, info)
		BossFx.Call(variant, "Impact", model, e.rig, info)
	end
end

-- Per frame: the pose override of the running ability on `e` (clears it when done), or nil.
function BossAbilityPlayer.Pose(e, serverNow: number): Override?
	local ability = e.ability
	if ability == nil then
		return nil
	end
	local t = serverNow - ability.startAt
	if t > ability.cfg.ClipSeconds + BossAbilityPlayer.BlendOut then
		e.ability = nil
		return nil
	end
	return BossAbilityPlayer.Sample(ability.data, ability.cfg.ClipSeconds, t)
end

return BossAbilityPlayer
