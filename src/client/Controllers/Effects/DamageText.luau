-- Floating damage numbers and HP text formatting. Presentation only: nothing here feeds back
-- into damage, rewards or the server. The pure half (Format / newCoalescer) is headless-tested.

local DamageText = {}

DamageText.MAX_LIVE = 40
DamageText.WINDOW = 0.15 -- hits on one enemy inside this are summed into one number
DamageText.LIFE = 0.6
DamageText.STILL_LIFE = 0.4 -- reducedMotion: static fade, no drift or pop
DamageText.DRIFT = 2
DamageText.POP_FROM, DamageText.POP_TIME = 1.35, 0.12
DamageText.NORMAL_COLOR = Color3.fromRGB(255, 70, 70)
DamageText.CRIT_COLOR = Color3.fromRGB(255, 240, 130)
DamageText.CRIT_STROKE = Color3.fromRGB(255, 70, 10)

local NORMAL_SIZE, CRIT_SIZE = 18, 27 -- crit = 1.5x

local UNITS = { { 1e12, "T" }, { 1e9, "B" }, { 1e6, "M" }, { 1e3, "K" } }

-- 950 -> "950", 1234 -> "1.2K", 3400000 -> "3.4M". Truncates, so a shown value never exceeds the real one.
function DamageText.Format(n: number): string
	n = math.max(0, math.floor(n or 0))
	for _, u in UNITS do
		if n >= u[1] then
			local v = math.floor(n / u[1] * 10) / 10
			if v >= 1000 and u[2] ~= "T" then
				v = 999.9
			end
			return (if v % 1 == 0 then string.format("%d", v) else string.format("%.1f", v)) .. u[2]
		end
	end
	return string.format("%d", n)
end

-- Pure coalescer. Add() sums hits per enemy id; Flush(now, room) returns the numbers due:
-- an enemy emits at most once per window. Beyond `room` live numbers, due entries are dropped, never queued.
export type Entry = { id: number, pos: Vector3, damage: number, crit: boolean }

function DamageText.newCoalescer(window: number?)
	local gap = window or DamageText.WINDOW
	local pending = {} -- id -> { pos, damage, crit }
	local lastEmit = {} -- id -> time
	local self = {}

	function self.Add(id: number, pos: Vector3, damage: number, crit: boolean?)
		if type(damage) ~= "number" or damage <= 0 then
			return
		end
		local p = pending[id]
		if p then
			p.damage += damage
			p.crit = p.crit or crit == true
			p.pos = pos
		else
			pending[id] = { pos = pos, damage = damage, crit = crit == true }
		end
	end

	function self.Flush(now: number, room: number): { Entry }
		local out = {}
		for id, p in pending do
			local last = lastEmit[id]
			if last == nil or now - last >= gap then
				pending[id] = nil
				lastEmit[id] = now
				if #out < room then
					table.insert(out, { id = id, pos = p.pos, damage = p.damage, crit = p.crit })
				end
			end
		end
		return out
	end

	function self.Clear()
		table.clear(pending)
		table.clear(lastEmit)
	end

	return self
end

--------------------------------------------------------------------------- rendering (Studio only)

local coalescer = DamageText.newCoalescer()
local folder: Folder?
local pool = {} -- { part, label, stroke, scale, age, life, crit, still, base, live }
local liveCount = 0

local function build()
	local part = Instance.new("Part")
	part.Name = "DamageText"
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Transparency = 1
	part.Size = Vector3.one * 0.2
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(180, 50)
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.Adornee = part
	gui.Parent = part
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Parent = gui
	local scale = Instance.new("UIScale")
	scale.Parent = label
	local stroke = Instance.new("UIStroke")
	stroke.Parent = label
	return { part = part, label = label, stroke = stroke, scale = scale, age = 0, life = 1, live = false }
end

local function acquire()
	for _, n in pool do
		if not n.live then
			return n
		end
	end
	if #pool >= DamageText.MAX_LIVE then
		return nil
	end
	local n = build()
	table.insert(pool, n)
	return n
end

local function release(n)
	n.live = false
	liveCount -= 1
	n.part.Parent = nil
end

local function show(entry: Entry, reducedMotion: boolean)
	local n = acquire()
	if n == nil or folder == nil then
		return
	end
	n.live, n.age, n.crit, n.still = true, 0, entry.crit, reducedMotion
	n.life = if reducedMotion then DamageText.STILL_LIFE else DamageText.LIFE
	liveCount += 1
	local label, stroke = n.label, n.stroke
	label.Text = DamageText.Format(entry.damage) .. (if entry.crit then "!" else "")
	label.Font = if entry.crit then Enum.Font.GothamBlack else Enum.Font.GothamBold
	label.TextSize = if entry.crit then CRIT_SIZE else NORMAL_SIZE
	label.TextColor3 = if entry.crit then DamageText.CRIT_COLOR else DamageText.NORMAL_COLOR
	label.TextTransparency = 0
	stroke.Color = if entry.crit then DamageText.CRIT_STROKE else Color3.fromRGB(25, 0, 0)
	stroke.Thickness = if entry.crit then 3 else 1.5
	stroke.Transparency = 0
	n.scale.Scale = if entry.crit and not reducedMotion then DamageText.POP_FROM else 1
	n.base = entry.pos + Vector3.new((math.random() - 0.5) * 1.2, 0, (math.random() - 0.5) * 1.2)
	n.part.Position = n.base
	n.part.Parent = folder
end

-- worldPos: where the number starts (the enemy's centre). Hits are coalesced, then shown on the next Step.
function DamageText.Add(id: number, worldPos: Vector3, damage: number?, critical: boolean?)
	if damage then
		coalescer.Add(id, worldPos, damage, critical)
	end
end

function DamageText.Step(dt: number, reducedMotion: boolean?)
	local still = reducedMotion == true
	for _, e in coalescer.Flush(os.clock(), DamageText.MAX_LIVE - liveCount) do
		show(e, still)
	end
	for _, n in pool do
		if n.live then
			n.age += dt
			local t = n.age / n.life
			if t >= 1 then
				release(n)
			else
				if not n.still then
					n.part.Position = n.base + Vector3.new(0, DamageText.DRIFT * (1 - (1 - t) ^ 2), 0)
					if n.crit then
						n.scale.Scale = 1 + (DamageText.POP_FROM - 1) * math.max(0, 1 - n.age / DamageText.POP_TIME)
					end
				end
				local fade = if n.still then t else t * t
				n.label.TextTransparency = fade
				n.stroke.Transparency = fade
			end
		end
	end
end

-- Arena torn down or effects reset: drop pending numbers and hide live ones. Pooled instances are kept.
function DamageText.Clear()
	coalescer.Clear()
	for _, n in pool do
		if n.live then
			release(n)
		end
	end
end

function DamageText.Start(parent: Instance)
	if folder then
		return
	end
	folder = Instance.new("Folder")
	folder.Name = "DamageText"
	folder.Parent = parent
end

return DamageText
