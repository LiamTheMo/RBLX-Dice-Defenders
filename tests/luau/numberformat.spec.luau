-- NumberFormat.Compact: up to 2 decimals with a letter suffix, trailing zeros dropped.

local NumberFormat = require(game:GetService("ReplicatedStorage").Shared.NumberFormat)

test("compact numbers keep up to two decimals and drop trailing zeros", function()
	expectEq(NumberFormat.Compact(0), "0", "zero")
	expectEq(NumberFormat.Compact(300), "300", "below 1000 unchanged")
	expectEq(NumberFormat.Compact(297.5), "297.5", "decimals below 1000")
	expectEq(NumberFormat.Compact(34900), "34.9k", "34.9k")
	expectEq(NumberFormat.Compact(3150), "3.15k", "3.15k")
	expectEq(NumberFormat.Compact(27920), "27.92k", "27.92k")
	expectEq(NumberFormat.Compact(1000), "1k", "whole thousand")
	expectEq(NumberFormat.Compact(2500000), "2.5M", "millions")
	expectEq(NumberFormat.Compact(7.2e9), "7.2B", "billions")
	expectEq(NumberFormat.Compact(999999), "1M", "rounding carries into the next suffix")
	expectEq(NumberFormat.Compact(-1500), "-1.5k", "negative")
end)
