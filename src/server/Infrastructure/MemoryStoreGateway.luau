-- The only module that calls MemoryStoreService. Wraps one sorted map with pcall + retry/backoff.
-- Every call returns (ok, valueOrReason); callers treat a failure as "queue unavailable" and degrade
-- (a bot match). Same API as InMemoryMemoryStore. Studio without API access: Available() is false.

local MemoryStoreGateway = {}
MemoryStoreGateway.__index = MemoryStoreGateway

MemoryStoreGateway.MAX_ATTEMPTS = 3
MemoryStoreGateway.BASE_DELAY_SECONDS = 0.5

export type Options = {
	map: any?, -- a MemoryStoreSortedMap, or any object with SetAsync/GetAsync/RemoveAsync/GetRangeAsync/UpdateAsync
	name: string?, -- sorted map name when `map` is not given
	sleep: ((number) -> ())?,
	maxAttempts: number?,
	baseDelay: number?,
}

function MemoryStoreGateway.new(options: Options)
	local map = options.map
	local available = map ~= nil
	if map == nil then
		local ok, result = pcall(function()
			return game:GetService("MemoryStoreService"):GetSortedMap(options.name or "DuelQueue")
		end)
		available = ok
		map = if ok then result else nil
	end
	return setmetatable({
		_map = map,
		_available = available,
		_sleep = options.sleep or task.wait,
		_maxAttempts = options.maxAttempts or MemoryStoreGateway.MAX_ATTEMPTS,
		_baseDelay = options.baseDelay or MemoryStoreGateway.BASE_DELAY_SECONDS,
	}, MemoryStoreGateway)
end

function MemoryStoreGateway:Available(): boolean
	return self._available
end

-- Runs `fn(map)` with retries. Returns (true, result) or (false, reason).
function MemoryStoreGateway:_call(fn: (any) -> any)
	if not self._available then
		return false, "MemoryStore unavailable"
	end
	local lastError
	for attempt = 1, self._maxAttempts do
		local ok, result = pcall(fn, self._map)
		if ok then
			return true, result
		end
		lastError = result
		if attempt < self._maxAttempts then
			self._sleep(self._baseDelay * 2 ^ (attempt - 1))
		end
	end
	return false, tostring(lastError)
end

function MemoryStoreGateway:Set(key: string, value: any, ttlSeconds: number)
	local ok, result = self:_call(function(map)
		map:SetAsync(key, value, ttlSeconds)
	end)
	return ok, if ok then nil else result
end

function MemoryStoreGateway:Get(key: string)
	return self:_call(function(map)
		local value = map:GetAsync(key)
		if type(value) == "table" and value.__claimed then
			return nil
		end
		return value
	end)
end

function MemoryStoreGateway:Remove(key: string)
	local ok, result = self:_call(function(map)
		map:RemoveAsync(key)
	end)
	return ok, if ok then nil else result
end

MemoryStoreGateway.PAGE_SIZE = 200 -- GetRangeAsync returns at most 200 items per call

-- Live entries in key order (NOT age order: callers sort by their own timestamp): (true, { {Key, Value} ... }) or
-- (false, reason). Reads in pages of PAGE_SIZE until `limit` rows or the end of the map; marked (claimed) rows
-- are hidden and do not count toward `limit`. Each page is one MemoryStore read.
function MemoryStoreGateway:List(limit: number)
	return self:_call(function(map)
		local rows = {}
		local lowerBound = nil
		while #rows < limit do
			local items = map:GetRangeAsync(Enum.SortDirection.Ascending, MemoryStoreGateway.PAGE_SIZE, lowerBound)
			for _, item in items do
				if #rows < limit and not (type(item.value) == "table" and item.value.__claimed) then
					table.insert(rows, { Key = item.key, Value = item.value })
				end
			end
			if #items < MemoryStoreGateway.PAGE_SIZE then
				break
			end
			lowerBound = { key = items[#items].key }
		end
		return rows
	end)
end

-- Removes and returns the entry only once across servers: (true, value|nil) or (false, reason).
-- UpdateAsync is atomic per key, but a transform that returns nil CANCELS the update (it does not delete), so the
-- first claimer swaps the entry for a short-lived `__claimed` marker (every later claimer sees the marker and gets
-- nil), then removes the key. List and Get hide marked entries.
-- `taken` lives outside the retried closure: once the transform took a value, a retry returns it instead of seeing
-- its own marker and reporting nil. The final RemoveAsync is separate and best effort (the 30 s marker TTL hides
-- the key anyway), so a failed remove never loses a won claim.
function MemoryStoreGateway:Claim(key: string)
	local taken
	local ok, result = self:_call(function(map)
		if taken == nil then
			map:UpdateAsync(key, function(old)
				taken = nil -- the transform may run again on a write conflict
				if old == nil or (type(old) == "table" and old.__claimed) then
					return nil
				end
				taken = old
				return { __claimed = true }
			end, 30)
		end
		return taken
	end)
	if ok and result ~= nil then
		pcall(function()
			self._map:RemoveAsync(key)
		end)
	end
	return ok, result
end

return MemoryStoreGateway
