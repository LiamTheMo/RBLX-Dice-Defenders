--!strict
-- Boss walk cycles baked from Assets/Models/Enemies/Boss/<Boss>/anim/walk.json (see tools/gen_boss_walk.py).
-- Pure lookup: Pose returns Motor6D.Transform per joint for a phase 0..1 (Motor6D C1 = identity, C0 from rig.json),
-- Stride the studs of path per cycle for an arena (natural stride x the layout factor, so the feet never slide).

local Layout = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Layout"))

local BossWalk = {}

export type Data = { Stride: number, Frames: number, Joints: { [string]: { number } } }

BossWalk.Data = {
	GoblinKing = require(script.Parent.BossWalkData.GoblinKing) :: Data,
	CursedKing = require(script.Parent.BossWalkData.CursedKing) :: Data,
	CourtJester = require(script.Parent.BossWalkData.CourtJester) :: Data,
}

-- Balance studs per animation-stud on each layout (boss speed x cycle seconds of the path, from each anim spec).
BossWalk.Factor = table.freeze({ Solo = 1.4994, Coop = 2.259, Duel = 1.708 })

function BossWalk.Has(variant: string?): boolean
	return variant ~= nil and BossWalk.Data[variant] ~= nil
end

function BossWalk.Stride(variant: string, arena: (number | string)?): number
	return BossWalk.Data[variant].Stride * BossWalk.Factor[Layout.ArenaOf(arena)]
end

local function cframeAt(list: { number }, frame: number): CFrame
	local i = frame * 7
	return CFrame.new(list[i + 1], list[i + 2], list[i + 3], list[i + 4], list[i + 5], list[i + 6], list[i + 7])
end

-- { [joint] = CFrame } at a cycle phase (wraps); lerps between the two neighbouring baked frames.
function BossWalk.Pose(variant: string, phase: number): { [string]: CFrame }
	local data = BossWalk.Data[variant]
	local at = (phase % 1) * data.Frames
	local a = math.floor(at)
	local t = at - a
	local b = (a + 1) % data.Frames
	local poses = {}
	for name, list in data.Joints do
		local from = cframeAt(list, a)
		poses[name] = if t < 1e-4 then from else from:Lerp(cframeAt(list, b), t)
	end
	return poses
end

-- Same pose table for a one-shot clip (ability data): `frame` is clamped to the first and last baked frame, no wrap.
function BossWalk.PoseClip(
	data: { Frames: number, Joints: { [string]: { number } } },
	frame: number
): { [string]: CFrame }
	local at = math.clamp(frame, 0, data.Frames - 1)
	local a = math.floor(at)
	local t = at - a
	local b = math.min(a + 1, data.Frames - 1)
	local poses = {}
	for name, list in data.Joints do
		local from = cframeAt(list, a)
		poses[name] = if t < 1e-4 or a == b then from else from:Lerp(cframeAt(list, b), t)
	end
	return poses
end

return BossWalk
