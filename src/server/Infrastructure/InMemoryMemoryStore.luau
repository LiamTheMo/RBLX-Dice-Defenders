-- In-memory stand-in for a MemoryStore sorted map (same API as MemoryStoreGateway). TTL runs on an
-- injectable clock (`now() -> seconds`). Used by specs and by Studio sessions without API access.
-- `failNext` makes the next N calls return (false, reason), to exercise degrade paths. `failClaimRemove` makes the
-- next N Claims lose their final remove (the claimer still gets the value; the key stays hidden like a marker).

local ProfileSchema = require(script.Parent.Parent.Rules.ProfileSchema)

local InMemoryMemoryStore = {}
InMemoryMemoryStore.__index = InMemoryMemoryStore

local copy = ProfileSchema.DeepCopy

function InMemoryMemoryStore.new(now: (() -> number)?)
	return setmetatable(
		{ _now = now or os.time, _items = {}, _seq = 0, failNext = 0, failClaimRemove = 0 },
		InMemoryMemoryStore
	)
end

function InMemoryMemoryStore:Available(): boolean
	return true
end

function InMemoryMemoryStore:_check(): boolean
	if self.failNext > 0 then
		self.failNext -= 1
		return false
	end
	return true
end

function InMemoryMemoryStore:_live(key: string)
	local item = self._items[key]
	if item and item.expires <= self._now() then
		self._items[key] = nil
		return nil
	end
	if item and item.claimed then
		return nil -- a claim marker: hidden from every reader
	end
	return item
end

-- Returns true, or (false, reason).
function InMemoryMemoryStore:Set(key: string, value: any, ttlSeconds: number)
	if not self:_check() then
		return false, "simulated failure"
	end
	self._seq += 1
	self._items[key] = { value = copy(value), expires = self._now() + ttlSeconds, seq = self._seq }
	return true
end

-- Returns (true, value|nil) or (false, reason).
function InMemoryMemoryStore:Get(key: string)
	if not self:_check() then
		return false, "simulated failure"
	end
	local item = self:_live(key)
	return true, item and copy(item.value)
end

function InMemoryMemoryStore:Remove(key: string)
	if not self:_check() then
		return false, "simulated failure"
	end
	self._items[key] = nil
	return true
end

-- Live entries in key order (like the real sorted map, not age order): (true, { {Key, Value} ... }) or (false, reason).
function InMemoryMemoryStore:List(limit: number)
	if not self:_check() then
		return false, "simulated failure"
	end
	local rows = {}
	for key in self._items do
		local item = self:_live(key)
		if item then
			table.insert(rows, { Key = key, Value = copy(item.value), seq = item.seq })
		end
	end
	table.sort(rows, function(a, b)
		return a.Key < b.Key
	end)
	local out = {}
	for i = 1, math.min(limit, #rows) do
		out[i] = { Key = rows[i].Key, Value = rows[i].Value }
	end
	return true, out
end

-- Removes and returns the entry only once: (true, value|nil) or (false, reason).
function InMemoryMemoryStore:Claim(key: string)
	if not self:_check() then
		return false, "simulated failure"
	end
	local item = self:_live(key)
	if item and self.failClaimRemove > 0 then
		self.failClaimRemove -= 1
		item.claimed = true -- the remove failed: only the marker is left
	else
		self._items[key] = nil
	end
	return true, item and copy(item.value)
end

return InMemoryMemoryStore
