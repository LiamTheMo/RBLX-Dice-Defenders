--!strict
-- Persistent Hammer Lock overlays (Cursed King): one small group per locked die, driven by the board snapshot (the die's
-- L flag), so it appears with the lock, survives a late join and disappears with the unlock or the match. A group is a
-- translucent violet cage ring, two crossed chain bars and a padlock plate (4 parts, 2 on the Low tier); at most 6 dice
-- per boss, so <= 24 parts per lane (BossFxData.Budget.CursedKing.Locks). One shared loop pulses every group; an unlock
-- releases the group with a small shard burst. Clear() leaves nothing behind (match end, arena rebuild).

local BossFxData = require(script.Parent.BossFxData)
local Fx = require(script.Parent.FxLib)
local SettingsLogic = require(script.Parent.Parent.Settings.SettingsLogic)

local LockFx = {}

type Group = { owner: string, cell: number, pos: Vector3, ring: MeshPart?, plain: { BasePart }, phase: number }

local VIOLET = BossFxData.Palette.CursedKing.Violet
local STONE = BossFxData.Palette.CursedKing.Stone
local LIGHT = BossFxData.Palette.CursedKing.Light
local CAGE_Y, TOP_Y = 1.3, 2.8 -- ring height and chain / plate height above the pad

local groups: { [string]: Group } = {}
local folder: Folder? = nil
local loop: Fx.Handle? = nil
local clock = 0

local function root(): Folder
	local f = folder
	if f == nil or f.Parent == nil then
		f = Instance.new("Folder")
		f.Name = "LockFx"
		f.Parent = workspace
		folder = f
	end
	return f :: Folder
end

local function reduced(): boolean
	return SettingsLogic.get("reducedMotion") == true
end

local function block(size: Vector3, cf: CFrame, color: Color3, material: Enum.Material): BasePart
	local part = Instance.new("Part")
	part.Anchored, part.CanCollide, part.CanQuery, part.CanTouch, part.CastShadow = true, false, false, false, false
	part.Material, part.Color, part.Size, part.CFrame = material, color, size, cf
	part.Parent = root()
	return part
end

local function build(owner: string, cell: number, pos: Vector3): Group
	local group: Group = { owner = owner, cell = cell, pos = pos, plain = {}, phase = cell * 0.7 }
	group.ring = Fx.Part("Fx_Ring", {
		Parent = root(),
		Color = VIOLET,
		Material = Enum.Material.Neon,
		Size = Vector3.new(4.4, 0.2, 4.4),
		CFrame = CFrame.new(pos + Vector3.new(0, CAGE_Y, 0)),
		Transparency = 0.45,
	})
	if Fx.Tier(reduced()) ~= "Low" then
		for _, turn in { math.rad(45), math.rad(-45) } do
			local cf = CFrame.new(pos + Vector3.new(0, TOP_Y, 0)) * CFrame.Angles(0, turn, 0)
			table.insert(group.plain, block(Vector3.new(0.3, 0.3, 4.6), cf, STONE, Enum.Material.Metal))
		end
	end
	local plate =
		block(Vector3.new(0.9, 0.3, 0.7), CFrame.new(pos + Vector3.new(0, TOP_Y + 0.25, 0)), LIGHT, Enum.Material.Metal)
	table.insert(group.plain, plate)
	return group
end

local function release(group: Group)
	Fx.Release(group.ring)
	group.ring = nil
	for _, part in group.plain do
		part:Destroy()
	end
	table.clear(group.plain)
end

-- Four shards fly off the unlocked die and fade (plain parts, destroyed at the end).
local function shatter(pos: Vector3)
	if reduced() or Fx.Live() >= Fx.GLOBAL_CAP then
		return
	end
	local shards: { BasePart } = {}
	for k = 1, 4 do
		shards[k] =
			block(Vector3.new(0.3, 0.3, 0.9), CFrame.new(pos + Vector3.new(0, TOP_Y, 0)), LIGHT, Enum.Material.Neon)
	end
	local t = 0
	local handle = Fx.Run(function(dt: number)
		t += dt
		local u = math.min(t / 0.35, 1)
		for k, shard in shards do
			local a = (k / 4) * 2 * math.pi
			local out = 3.2 * u
			shard.CFrame = CFrame.new(
				pos + Vector3.new(math.cos(a) * out, TOP_Y + 1.5 * u - 3 * u * u, math.sin(a) * out)
			) * CFrame.Angles(u * 6, a, u * 4)
			shard.Transparency = u
		end
		return u >= 1
	end, function()
		for _, shard in shards do
			shard:Destroy()
		end
	end)
	if handle == nil then
		for _, shard in shards do
			shard:Destroy()
		end
	end
end

local function remove(key: string, burst: boolean)
	local group = groups[key]
	if group == nil then
		return
	end
	groups[key] = nil
	release(group)
	if burst then
		shatter(group.pos)
	end
end

local function ensureLoop()
	if loop and not loop.isDone() then
		return
	end
	loop = Fx.Run(function(dt: number)
		clock += dt
		local still = reduced()
		for _, group in groups do
			local pulse = if still then 0.5 else 0.5 + 0.5 * math.sin(clock * 3 + group.phase)
			if group.ring then
				group.ring.Transparency = 0.7 - 0.35 * pulse
				group.ring.Size = Vector3.new(4.4 + 0.3 * pulse, 0.2, 4.4 + 0.3 * pulse)
			end
		end
		return next(groups) == nil
	end)
end

-- owner: "own" or "ally" board; cells: the locked cells of that board; positionOf: world position of a pad.
function LockFx.Sync(owner: string, cells: { [number]: boolean }, positionOf: (number) -> Vector3)
	for key, group in groups do
		if group.owner == owner and not cells[group.cell] then
			remove(key, true)
		end
	end
	for cell in cells do
		local key = owner .. ":" .. cell
		if groups[key] == nil then
			groups[key] = build(owner, cell, positionOf(cell))
		end
	end
	if next(groups) ~= nil then
		ensureLoop()
	end
end

-- Match end / arena rebuild: every overlay goes, no burst.
function LockFx.Clear()
	for key in groups do
		remove(key, false)
	end
	if loop then
		loop.cancel()
		loop = nil
	end
end

return LockFx
