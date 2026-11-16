-- Argument checks for untrusted values.

local Validate = {}

-- Upper bound for any stored count (well inside DataStore and Luau integer precision).
Validate.MAX_INT = 1_000_000_000

-- True for a finite whole number in [lo, hi] (defaults 0 and MAX_INT).
function Validate.IsInt(v: any, lo: number?, hi: number?): boolean
	if type(v) ~= "number" or v ~= v then
		return false
	end
	if v == math.huge or v == -math.huge or v % 1 ~= 0 then
		return false
	end
	return v >= (lo or 0) and v <= (hi or Validate.MAX_INT)
end

return Validate
