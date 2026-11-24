-- The three boss variants (Enemy Kind stays "Boss"; the S record's Variant picks the look). Pure data and one pure roll,
-- shared by the server (which variant comes next), the HUD (name, colour, portrait) and the specs.

local Bosses = {}

Bosses.List = table.freeze({ "GoblinKing", "CursedKing", "CourtJester" })

-- Portrait is the key into Sprites.Boss; Abilities lists the ability ids (tuning is in Bosses.Ability below).
Bosses.Info = table.freeze({
	GoblinKing = table.freeze({
		Name = "Goblin King",
		Color = Color3.fromHex("#4E6B2A"),
		Portrait = "GoblinKing",
		Abilities = table.freeze({ "PortalSummon" }),
	}),
	CursedKing = table.freeze({
		Name = "Cursed King",
		Color = Color3.fromHex("#6B1E5A"),
		Portrait = "CursedKing",
		Abilities = table.freeze({ "HammerLock" }),
	}),
	CourtJester = table.freeze({
		Name = "Court Jester",
		Color = Color3.fromHex("#E8451E"),
		Portrait = "CourtJester",
		Abilities = table.freeze({ "DiceShuffle" }),
	}),
})

-- Boss abilities (server rules in Rules/BossAbilities, playback in the client BossAbilityPlayer). All times are seconds
-- of the match clock. First/Interval: the first cast after the boss spawns, then cast to cast. A cast is a ClipSeconds
-- animation whose cast frame lies CastAt into it; the boss stands still for the whole clip (the windup starts CastAt
-- before the cast and the clip ends ClipSeconds after it started).
Bosses.Ability = table.freeze({
	GoblinKing = table.freeze({
		Id = "PortalSummon",
		First = 8,
		Interval = 14,
		CastAt = 1.0,
		ClipSeconds = 1.8,
		SummonGrunts = 3,
		SummonFast = 1, -- the fast one comes out in the middle; spawns are spaced like a regular wave (Formulas.SpawnInterval)
		PortalAhead = 4.5, -- studs ahead of the boss along the route where the portal opens, so it is seen and not hidden under him
		PortalSeconds = 1.5, -- minimum time the portal stays open (VFX); it stays open until the last summon is out
		MaxRouteFraction = 0.95, -- a boss past this fraction of its route summons nothing
	}),
	CursedKing = table.freeze({
		Id = "HammerLock",
		First = 9,
		Interval = 16,
		CastAt = 1.0,
		ClipSeconds = 1.8,
		LockCount = 3, -- unlocked dice locked per cast
		MaxLocked = 6, -- most dice one boss keeps locked at once
		LockOnSeconds = 0.8, -- the lock-on marker on the chosen dice (VFX)
	}),
	CourtJester = table.freeze({
		Id = "DiceShuffle",
		First = 7,
		Interval = 12,
		CastAt = 1.0,
		ClipSeconds = 1.8,
		Dice = 5, -- dice whose pips are re-rolled per cast (1 to 7, may equal the old value)
	}),
})

-- Variant of the n-th boss of a run: a pure function of (runId, n, previous), never equal to `previous`.
function Bosses.Roll(runId: number, n: number, previous: string?): string
	local pool = {}
	for _, id in Bosses.List do
		if id ~= previous then
			table.insert(pool, id)
		end
	end
	return pool[Random.new(runId * 131 + n):NextInteger(1, #pool)]
end

function Bosses.IsVariant(value: any): boolean
	return type(value) == "string" and Bosses.Info[value] ~= nil
end

return table.freeze(Bosses)
