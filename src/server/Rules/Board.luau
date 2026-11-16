-- Pure board rules: 15 cells, each a Die {id, type, pip, cd, hits} or false.
-- Every function validates fully before it mutates; a rejected call leaves the
-- board untouched. Randomness (cell, type) is chosen by the caller.
local Balance = require(script.Parent.Parent.Config.Balance)
local Dice = require(script.Parent.Parent.Config.Dice)
local Validate = require(script.Parent.Validate)

local Board = {}

Board.MAX_PIP = 7 -- shown as 7 star

function Board.New(): { any }
	local board = {}
	for i = 1, Balance.BoardCells do
		board[i] = false
	end
	return board
end

function Board.EmptyCells(board: { any }): { number }
	local cells = {}
	for i = 1, Balance.BoardCells do
		if not board[i] then
			table.insert(cells, i)
		end
	end
	return cells
end

-- Places a pip-1 die. Codes: BadCell, CellTaken, BadType.
function Board.Summon(board: { any }, cell: any, typeId: any, id: number): (boolean, string?)
	if not Validate.IsInt(cell, 1, Balance.BoardCells) then
		return false, "BadCell"
	end
	if board[cell] then
		return false, "CellTaken"
	end
	if type(typeId) ~= "string" or Dice.Types[typeId] == nil then
		return false, "BadType"
	end
	board[cell] = { id = id, type = typeId, pip = 1, cd = 0, hits = 0 }
	return true, nil
end

-- Code IllegalMerge for anything outside: both cells occupied, from ~= to, same
-- type, same pip, pip <= 6.
function Board.CheckMerge(board: { any }, from: any, to: any): (boolean, string?)
	if not (Validate.IsInt(from, 1, Balance.BoardCells) and Validate.IsInt(to, 1, Balance.BoardCells)) then
		return false, "IllegalMerge"
	end
	local a, b = board[from], board[to]
	if from == to or not a or not b or a.type ~= b.type or a.pip ~= b.pip or a.pip >= Board.MAX_PIP then
		return false, "IllegalMerge"
	end
	return true, nil
end

-- `from` is cleared; `to` gains a pip and takes `newType` (re-rolled by the caller).
function Board.Merge(board: { any }, from: any, to: any, newType: any): (boolean, string?)
	local ok, code = Board.CheckMerge(board, from, to)
	if not ok then
		return false, code
	end
	if type(newType) ~= "string" or Dice.Types[newType] == nil then
		return false, "BadType"
	end
	local die = board[to]
	die.pip += 1
	die.type = newType
	die.hits = 0
	board[from] = false
	return true, nil
end

return Board
