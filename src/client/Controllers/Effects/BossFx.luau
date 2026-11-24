--!strict
-- VFX for the boss abilities. BossAbilityPlayer calls BossFx.Call(variant, hook, model, rig, info) on each A event.
--   Windup     the boss starts the ability animation (the cast frame lands info.CastAt - serverNow seconds from now).
--   Cast       the cast frame: the Goblin King portal (PortalFx, recoloured), the Cursed King slam and bolts, the Court
--              Jester confetti.
--   Impact     the result lands: the Court Jester's re-rolled dice (info.Info.Cells / Pips).
-- info: { Id, Ability, Phase, CastAt (server clock), Target, Info (the A record's Info), Config (Bosses.Ability[variant]),
-- Seat, Arena, Position }. The persistent Cursed King chains are LockFx (driven by the board snapshot, not by A events).
-- Effects are pooled mesh parts (FxLib) plus a few plain parts, each run on the shared FxLib loop with a per-variant
-- limiter; onEnd releases/destroys everything, so a cancelled or over-cap effect leaves nothing behind. Purely visual:
-- the server already decided summon / lock / shuffle. Reduced motion keeps only the ground rings, the Low tier (phones)
-- halves the particles. Budgets and palettes live in BossFxData.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Layout = require(ReplicatedStorage.Shared.Layout)
local BossFxData = require(script.Parent.BossFxData)
local SettingsLogic = require(script.Parent.Parent.Settings.SettingsLogic)

local BossFx = {}

-- FxLib builds CFrames and loads meshes at require time, so the headless specs that load BossAbilityPlayer must not
-- reach it: required on first use instead.
local Fx: any = setmetatable({}, {
	__index = function(self, key)
		local lib = require(script.Parent.FxLib)
		setmetatable(self :: any, { __index = lib })
		return lib[key]
	end,
})
type Handle = { cancel: () -> (), isDone: () -> boolean }

export type Info = {
	Id: number,
	Ability: string,
	Phase: string,
	CastAt: number,
	Target: any?,
	Info: { [string]: any }?,
	Config: { [string]: any },
	Seat: number,
	Arena: any,
	Position: Vector3,
}
type Hook = (model: Model, rig: any, info: Info) -> ()

local P = BossFxData.Palette
local NEON = Enum.Material.Neon
local function quadOut(u: number): number
	return Fx.Easing.quadOut(u)
end

local LIMITS = { GoblinKing = 3, CursedKing = 4, CourtJester = 3 }
local PORTAL_LIFT = 1.25 -- as BoardView: the portal centre above the route point
local limiters: { [string]: any } = {}
local folder: Folder? = nil

local function noop(_model: Model, _rig: any, _info: Info) end

local function root(): Folder
	local f = folder
	if f == nil or f.Parent == nil then
		f = Instance.new("Folder")
		f.Name = "BossFx"
		f.Parent = workspace
		folder = f
	end
	return f :: Folder
end

local function reduced(): boolean
	return SettingsLogic.get("reducedMotion") == true
end

local function low(): boolean
	return Fx.Tier(reduced()) == "Low"
end

-- Particle count for this hook: none in reduced motion, half on phones.
local function count(full: number): number
	return BossFxData.Count(full, low(), reduced())
end

local function ground(pos: Vector3): Vector3
	return Vector3.new(pos.X, Layout.Y + 0.15, pos.Z)
end

local function dieAt(info: Info, target: any): Vector3?
	if type(target) ~= "table" or type(target.C) ~= "number" then
		return nil
	end
	return Layout.CellPosition(target.C, target.S or info.Seat, info.Arena) + Vector3.new(0, 0.2, 0)
end

-- World position of a rig joint's part (the scepter head, the wand hand), else `fallback`.
local function jointPos(rig: any, name: string, fallback: Vector3): Vector3
	local motor = if rig and rig.motors then rig.motors[name] else nil
	local part = if motor then motor.Part1 else nil
	return if part and part:IsA("BasePart") then part.Position else fallback
end

-- Parts an effect owns: mesh parts go back to their pool, plain parts are destroyed.
type Owned = { { inst: BasePart, pooled: boolean } }

local function cleanup(owned: Owned)
	for i = #owned, 1, -1 do
		local o = owned[i]
		if o.pooled then
			Fx.Release(o.inst :: any)
		else
			o.inst:Destroy()
		end
		owned[i] = nil
	end
end

local function mesh(owned: Owned, key: string, color: Color3, size: Vector3, cf: CFrame): BasePart?
	local part =
		Fx.Part(key, { Parent = root(), Color = color, Material = NEON, Size = size, CFrame = cf, Transparency = 1 })
	if part then
		table.insert(owned, { inst = part, pooled = true })
	end
	return part
end

local function plain(owned: Owned, shape: Enum.PartType, color: Color3, size: Vector3, cf: CFrame): BasePart
	local part = Instance.new("Part")
	part.Shape = shape
	part.Anchored, part.CanCollide, part.CanQuery, part.CanTouch, part.CastShadow = true, false, false, false, false
	part.Material, part.Color, part.Size, part.CFrame, part.Transparency = NEON, color, size, cf, 1
	part.Parent = root()
	table.insert(owned, { inst = part, pooled = false })
	return part
end

local function limiterFor(variant: string): any
	local limiter = limiters[variant]
	if limiter == nil then
		limiter = Fx.Limiter(LIMITS[variant])
		limiters[variant] = limiter
	end
	return limiter
end

-- Runs step(t, u) for `duration` seconds on the shared loop; build(owned) creates the parts and returns the step.
-- Returns the handle, or nil when over a cap (nothing stays built then).
local function play(variant: string, duration: number, build: (owned: Owned) -> (number, number) -> ()): Handle?
	if Fx.Live() >= Fx.GLOBAL_CAP then
		return nil
	end
	local limiter = limiterFor(variant)
	local owned: Owned = {}
	local step = build(owned)
	local t = 0
	local handle = Fx.Run(function(dt: number)
		t += dt
		step(t, math.min(t / duration, 1))
		return t >= duration
	end, function()
		cleanup(owned)
	end, limiter)
	if handle == nil then
		cleanup(owned)
	end
	return handle
end

-- alpha 0..1 of the part's own opacity (1 - base is the most visible it gets).
local function fade(part: BasePart?, alpha: number, base: number)
	if part then
		part.Transparency = 1 - (1 - base) * math.clamp(alpha, 0, 1)
	end
end

local function flat(d: number): Vector3
	return Vector3.new(d, 0.2, d)
end

-- GoblinKing: Portal Summon -------------------------------------------------------------------------------------------

local GK = {}

-- A dark blue-gray ring and swirl open at the boss's feet while a few gold coins spiral up.
function GK.Windup(_model: Model, _rig: any, info: Info)
	local dur = BossFxData.WindupSeconds(info.CastAt, workspace:GetServerTimeNow())
	local center = ground(info.Position)
	local coinsN = count(4)
	play("GoblinKing", dur, function(owned)
		local ring = mesh(owned, "Fx_Ring", P.GoblinKing.SlateCore, flat(2), CFrame.new(center))
		local swirl = mesh(owned, "Fx_Ring", P.GoblinKing.SlateGlow, flat(1), CFrame.new(center))
		local coins = {}
		for k = 1, coinsN do
			coins[k] = mesh(owned, "Fx_Orb", P.GoblinKing.Gold, Vector3.new(0.5, 0.14, 0.5), CFrame.new(center))
		end
		return function(t, u)
			if ring then
				ring.Size = flat(2 + 3 * quadOut(u))
				fade(ring, 0.4 + 0.6 * u, 0.25)
			end
			if swirl then
				swirl.Size = flat(1.2 + 2.4 * u)
				swirl.CFrame = CFrame.new(center) * CFrame.Angles(0, t * 5, 0)
				fade(swirl, 0.3 + 0.7 * u, 0.4)
			end
			for k, c in coins do
				if c then
					local x, y, z = BossFxData.Spiral(k, coinsN, u, 2.2, 3, 1.5)
					c.CFrame = CFrame.new(center + Vector3.new(x, y, z)) * CFrame.Angles(0, t * 6, math.rad(70))
					fade(c, math.min(1, 4 * u, 4 * (1 - u) + 0.3), 0.05)
				end
			end
		end
	end)
end

-- The map's portal (PortalFx, recoloured) opens at the boss with the die spawn grow-in, stays open while the 4 enemies
-- come out, shrinks closed and is released. info.Target is the distance along the route (nil: nothing was summoned).
function GK.Cast(_model: Model, _rig: any, info: Info)
	if type(info.Target) ~= "number" or Fx.Live() >= Fx.GLOBAL_CAP then
		return
	end
	local camera = workspace.CurrentCamera
	local cameraPos = if camera then camera.CFrame.Position else info.Position + Vector3.new(0, 30, 30)
	local at = Layout.PositionAt(info.Target, info.Seat, info.Arena) + Vector3.yAxis * PORTAL_LIFT
	local serverSpan = if info.Info and type(info.Info.Seconds) == "number" then info.Info.Seconds else 0
	local open = math.max(info.Config.PortalSeconds or 1.5, serverSpan + 0.6) -- stays open until the last summon is out
	local still = reduced()
	local total = if still then open else open + 2 * BossFxData.PortalGrow.Seconds
	local portal = require(script.Parent.PortalFx).Spawn(root(), at, cameraPos, "summon", reduced)
	local t = 0
	local handle = Fx.Run(function(dt: number)
		t += dt
		portal.setScale(if still then 1 else BossFxData.PortalScale(t, open))
		return t >= total
	end, function()
		portal.destroy()
	end, limiterFor("GoblinKing"))
	if handle == nil then
		portal.destroy()
	end
end

-- CursedKing: Hammer Lock ---------------------------------------------------------------------------------------------

local CK = {}

function CK.Windup(_model: Model, rig: any, info: Info)
	local dur = BossFxData.WindupSeconds(info.CastAt, workspace:GetServerTimeNow())
	local crackN = count(4)
	play("CursedKing", dur, function(owned)
		local core = mesh(owned, "Fx_Orb", P.CursedKing.Violet, Vector3.one * 0.5, CFrame.new(info.Position))
		local cracks = {}
		for k = 1, crackN do
			cracks[k] =
				mesh(owned, "Fx_Spark", P.CursedKing.Light, Vector3.new(0.18, 1.4, 0.18), CFrame.new(info.Position))
		end
		return function(t, u)
			local head = jointPos(rig, "Scepter", info.Position + Vector3.new(0, 7, 0))
			if core then
				core.CFrame = CFrame.new(head)
				core.Size = Vector3.one * (0.5 + 1.2 * u)
				fade(core, 0.4 + 0.6 * u, 0.15)
			end
			for k, c in cracks do
				if c then
					local a = (k / crackN) * 2 * math.pi + t * 3
					local flicker = if math.sin(t * 40 + k * 2) > -0.3 then 1 else 0.2
					local dir = Vector3.new(math.cos(a), 0.6 * math.sin(a * 2), math.sin(a))
					c.CFrame = CFrame.lookAt(head, head + dir)
						* CFrame.Angles(math.rad(90), 0, 0)
						* CFrame.new(0, 0.7 * (0.4 + u), 0)
					fade(c, u * flicker, 0.05)
				end
			end
		end
	end)
end

-- The slam: a stone shockwave ring and dust at the scepter head's floor point, violet bolts to each chosen die and a
-- short lock-on ring on them (info.Info.Cells; the persistent chains come from LockFx once the snapshot marks the dice).
function CK.Cast(_model: Model, rig: any, info: Info)
	local head = jointPos(rig, "Scepter", info.Position + Vector3.new(0, 7, 0))
	local floorPos = Vector3.new(head.X, Layout.Y + 0.15, head.Z)
	local targets = {}
	local cells = if info.Info then info.Info.Cells else nil
	for _, cell in cells or {} do
		local die = dieAt(info, { C = cell, S = info.Seat })
		if die then
			table.insert(targets, die)
		end
	end
	local still = reduced()
	local dustN = count(3)
	local dur = info.Config.LockOnSeconds or 0.8
	play("CursedKing", dur, function(owned)
		local wave = mesh(owned, "Fx_Ring", P.CursedKing.Stone, flat(1), CFrame.new(floorPos))
		local dust = {}
		for k = 1, dustN do
			dust[k] = mesh(owned, "Fx_Orb", P.CursedKing.Dust, Vector3.one * 1.2, CFrame.new(floorPos))
		end
		local flash = mesh(owned, "Fx_Orb", P.CursedKing.Light, Vector3.one * 2, CFrame.new(head))
		local bolts, rings = {}, {}
		for k, die in targets do
			local aim = die + Vector3.new(0, 2.5, 0)
			local length = (aim - head).Magnitude
			if not still then
				bolts[k] = plain(
					owned,
					Enum.PartType.Block,
					P.CursedKing.Violet,
					Vector3.new(0.4, 0.4, length),
					CFrame.lookAt((head + aim) / 2, aim)
				)
			end
			rings[k] = mesh(owned, "Fx_Ring", P.CursedKing.Violet, flat(6), CFrame.new(die))
		end
		return function(t, u)
			local e = quadOut(math.min(t / 0.5, 1))
			if wave then
				wave.Size = flat(2 + 14 * e)
				fade(wave, 1 - e, if still then 0.4 else 0.1)
			end
			for k, d in dust do
				if d then
					local a = (k / dustN) * 2 * math.pi
					d.CFrame =
						CFrame.new(floorPos + Vector3.new(math.cos(a) * 5 * e, 0.8 + 1.5 * e, math.sin(a) * 5 * e))
					fade(d, 1 - e, 0.35)
				end
			end
			fade(flash, 1 - math.min(t / 0.25, 1), 0.1)
			for _, bolt in bolts do
				local w = 0.5 * (1 - math.min(t / 0.3, 1)) + 0.05
				bolt.Size = Vector3.new(w, w, bolt.Size.Z)
				fade(bolt, if t < 0.3 then 1 - t / 0.3 else 0, 0.05)
			end
			for _, ring in rings do
				if ring then
					ring.Size = flat(6 - 2.5 * u)
					fade(ring, 0.5 + 0.5 * math.sin(t * 14), 0.15)
				end
			end
		end
	end)
end

-- CourtJester: Dice Shuffle -----------------------------------------------------------------------------------------

local CJ = {}
local CONFETTI = { P.CourtJester.Pink, P.CourtJester.Purple, P.CourtJester.Gold, P.CourtJester.White }

function CJ.Windup(_model: Model, rig: any, info: Info)
	local dur = BossFxData.WindupSeconds(info.CastAt, workspace:GetServerTimeNow())
	local n = count(12)
	local center = ground(info.Position)
	play("CourtJester", dur, function(owned)
		local wand = mesh(owned, "Fx_Orb", P.CourtJester.Pink, Vector3.one * 0.5, CFrame.new(info.Position))
		local stars = {}
		for k = 1, n do
			stars[k] = mesh(owned, "Fx_Star4", CONFETTI[k % 3 + 1], Vector3.one * 0.7, CFrame.new(center))
		end
		return function(t, u)
			if wand then
				wand.CFrame = CFrame.new(jointPos(rig, "HandR", info.Position))
				wand.Size = Vector3.one * (0.4 + 0.9 * u)
				fade(wand, 0.5 + 0.5 * u, 0.1)
			end
			for k, s in stars do
				if s then
					local x, y, z = BossFxData.Spiral(k, n, u, 4, 7, 2)
					s.CFrame = CFrame.new(center + Vector3.new(x, y, z)) * CFrame.Angles(0, t * 5, 0)
					fade(s, math.min(1, 4 * u, 4 * (1 - u) + 0.3), 0.05)
				end
			end
		end
	end)
end

function CJ.Cast(_model: Model, _rig: any, info: Info)
	local from = ground(info.Position) + Vector3.new(0, 3, 0)
	local n = count(14)
	local rng = Random.new(info.Id)
	play("CourtJester", 0.9, function(owned)
		local puff = mesh(owned, "Fx_Orb", P.CourtJester.Pink, Vector3.one * 2, CFrame.new(from))
		local bits, vel = {}, {}
		for k = 1, n do
			bits[k] = plain(
				owned,
				Enum.PartType.Block,
				CONFETTI[k % #CONFETTI + 1],
				Vector3.new(0.4, 0.05, 0.4),
				CFrame.new(from)
			)
			local a = rng:NextNumber(0, 2 * math.pi)
			local s = rng:NextNumber(4, 9)
			vel[k] = Vector3.new(math.cos(a) * s, rng:NextNumber(7, 12), math.sin(a) * s)
		end
		return function(t, u)
			if puff then
				puff.Size = Vector3.one * (2 + 6 * quadOut(u))
				fade(puff, 1 - 2 * u, 0.2)
			end
			for k, b in bits do
				local v = vel[k]
				local x, y, z = BossFxData.Ballistic(v.X, v.Y, v.Z, t, 22)
				b.CFrame = CFrame.new(from + Vector3.new(x, y, z)) * CFrame.Angles(t * 9 + k, t * 7, 0)
				fade(b, if u < 0.6 then 1 else (1 - u) / 0.4, 0)
			end
		end
	end)
end

-- Dice Shuffle result: info.Info = { Cells, Pips } of the re-rolled dice. Each gets a pink star burst and its new pip
-- count flashes above it (one billboard on a tiny anchor part).
function CJ.Impact(_model: Model, _rig: any, info: Info)
	local data = info.Info
	if data == nil or type(data.Cells) ~= "table" then
		return
	end
	local still = reduced()
	play("CourtJester", 0.9, function(owned)
		local bursts, labels, spots = {}, {}, {}
		for k, cell in data.Cells do
			local die = dieAt(info, { C = cell, S = info.Seat })
			if die then
				spots[k] = die
				if not still then
					bursts[k] = mesh(owned, "Fx_Star8", CONFETTI[k % #CONFETTI + 1], flat(1), CFrame.new(die))
				end
				local anchor =
					plain(owned, Enum.PartType.Block, P.CourtJester.White, Vector3.one * 0.2, CFrame.new(die))
				anchor.Transparency = 1
				local gui = Instance.new("BillboardGui")
				gui.Size = UDim2.fromOffset(64, 44)
				gui.AlwaysOnTop = true
				gui.Adornee = anchor
				gui.Parent = anchor
				local text = Instance.new("TextLabel")
				text.Size = UDim2.fromScale(1, 1)
				text.BackgroundTransparency = 1
				text.Font = Enum.Font.GothamBlack
				text.TextScaled = true
				text.TextColor3 = P.CourtJester.Gold
				text.TextStrokeTransparency = 0
				text.Text = tostring(data.Pips[k])
				text.Parent = gui
				labels[k] = { anchor = anchor, text = text }
			end
		end
		return function(t, u)
			local e = quadOut(u)
			for k, burst in bursts do
				if burst then
					burst.Size = flat(2 + 4 * e)
					burst.CFrame = CFrame.new(spots[k]) * CFrame.Angles(0, u * 6, 0)
					fade(burst, 1 - u, 0.1)
				end
			end
			for k, label in labels do
				local flash = if math.sin(t * 24) > -0.2 then 0 else 0.6 -- quick flicker
				label.anchor.CFrame = CFrame.new(spots[k] + Vector3.new(0, 3 + e, 0))
				label.text.TextTransparency = math.max(flash, if u > 0.6 then (u - 0.6) / 0.4 else 0)
				label.text.TextStrokeTransparency = label.text.TextTransparency
			end
		end
	end)
end

BossFx.GoblinKing = { Windup = GK.Windup, Cast = GK.Cast, Impact = noop } :: { [string]: Hook }
BossFx.CursedKing = { Windup = CK.Windup, Cast = CK.Cast, Impact = noop } :: { [string]: Hook }
BossFx.CourtJester = { Windup = CJ.Windup, Cast = CJ.Cast, Impact = CJ.Impact } :: { [string]: Hook }

-- Runs one hook; a failing effect must never break the animation or the enemy loop.
function BossFx.Call(variant: string, hook: string, model: Model, rig: any, info: Info)
	local set = (BossFx :: any)[variant]
	local fn = if type(set) == "table" then set[hook] else nil
	if type(fn) == "function" then
		local ok, err = pcall(fn, model, rig, info)
		if not ok then
			warn("[BossFx] " .. variant .. "." .. hook .. " failed: " .. tostring(err))
		end
	end
end

return BossFx
