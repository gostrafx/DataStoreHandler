--!strict
--[[
	Author: [FlowGostavo]
	Last Updated: April 2026
]]

export type DataStoreHandler = {
	New: (profileData: any, player: Player, copy: boolean?, maxDepth: number?) -> (DataStoreHandler, boolean),
	Get: (self: DataStoreHandler, path: string) -> any,
	Set: (self: DataStoreHandler, path: string, value: any) -> boolean,
	Patch: (self: DataStoreHandler, path: string, partialData: { [any]: any }) -> boolean,
	Increment: (self: DataStoreHandler, path: string, amount: number) -> boolean,
	OperateOnValue: (self: DataStoreHandler, path: string, operation: string, operand: number) -> boolean,
	Has: (self: DataStoreHandler, path: string) -> boolean,
	AddToList: (self: DataStoreHandler, path: string, value: any) -> boolean,
	UpdateList: (self: DataStoreHandler, path: string, value: any) -> boolean,
	RemoveByKey: (self: DataStoreHandler, path: string) -> boolean,
	RemoveByKeyList: (self: DataStoreHandler, path: string, list: { [any]: any }) -> boolean,
	AddPropertyToListItem: (self: DataStoreHandler, path: string, value: any) -> boolean,
	UpdateListItemProperty: (self: DataStoreHandler, path: string, value: any) -> boolean,
	RemovePropertyFromListItem: (self: DataStoreHandler, path: string) -> boolean,
	ClearList: (self: DataStoreHandler, path: string) -> boolean,
	PopFromList: (self: DataStoreHandler, path: string, index: number?) -> any,
	MapList: (self: DataStoreHandler, path: string, transform: (value: any) -> any) -> boolean,
	GetRaw: (self: DataStoreHandler) -> any,
	GetPlayer: (self: DataStoreHandler) -> Player,
	Reset: (self: DataStoreHandler, path: string, defaultValue: any) -> boolean,
	Toggle: (self: DataStoreHandler, path: string) -> boolean,
	FindInList: (self: DataStoreHandler, path: string, predicate: (value: any) -> boolean) -> (number?, any),
	Diff: (self: DataStoreHandler, otherData: any) -> { [string]: { old: any, new: any } },
	Swap: (self: DataStoreHandler, pathA: string, pathB: string) -> boolean,
	MoveInList: (self: DataStoreHandler, path: string, fromIndex: number, toIndex: number) -> boolean,
	CountList: (self: DataStoreHandler, path: string) -> number?,
	BatchSet: (self: DataStoreHandler, changes: { [string]: any }) -> boolean,
	BatchSetCompiled: (self: DataStoreHandler, changes: { [{ any }]: any }) -> boolean,
	Snapshot: (self: DataStoreHandler) -> any,
	SnapshotPath: (self: DataStoreHandler, path: string) -> any,
	Restore: (self: DataStoreHandler, snapshot: any) -> boolean,
	Destroy: (self: DataStoreHandler) -> (),
}

------------------------------------------------------------------------
-- CONSTANTS
------------------------------------------------------------------------
local type = type
local tonumber = tonumber
local tostring = tostring
local next = next
local insert = table.insert
local remove = table.remove
local unpack = table.unpack
local sort = table.sort
local clear = table.clear
local create = table.create
local stringSplit = string.split

local MAX_DEPTH = 64
-- Module-level path cache so we don't re-parse the same dot-separated
-- string on every single call. Keys are weakly held so unused paths
-- don't accumulate in memory.
local _pathCache = setmetatable({} :: { [string]: { any } }, { __mode = "v" })

------------------------------------------------------------------------
-- INTERNAL HELPERS
------------------------------------------------------------------------

-- Recursively copies a table. A `seen` set tracks references we've
-- already visited, so circular structures don't cause infinite loops.
-- If the tree is deeper than MAX_DEPTH we bail early and warn rather
-- than blowing the stack.
local function deepCopy(original: any, seen: { [any]: any }?, depth: number?, maxDepth: number?): any
	depth = depth or 0
	maxDepth = maxDepth or MAX_DEPTH
	if depth > maxDepth then
		warn("deepCopy: maximum depth reached (" .. maxDepth .. "), copy interrupted")
		return nil
	end
	if type(original) ~= "table" then
		return original
	end
	seen = seen or {}
	if seen[original] then
		warn("deepCopy: cycle detected, reference ignored")
		return nil
	end
	seen[original] = true
	local copy = {}
	for k, v in original do
		copy[deepCopy(k, seen, depth + 1, maxDepth)] = deepCopy(v, seen, depth + 1, maxDepth)
	end
	-- We deliberately leave seen[original] set. If the same table
	-- appears in multiple branches of the tree, we need to know we've
	-- been here so we don't loop forever.
	return copy
end

-- Compares two tables and records every path where they differ.
-- Written iteratively (explicit stack) so deeply nested data can't
-- overflow the call stack. Path segments are built up as strings and
-- only concatenated once per node, keeping allocations low.
--
-- Convention: `old` = value in `current`, `new` = value in `reference`.
local function deepDiff(current: any, reference: any, result: { [string]: { old: any, new: any } }, maxDepth: number?)
	maxDepth = maxDepth or MAX_DEPTH

	local stack = { { cur = current, ref = reference, prefix = "", depth = 0 } }

	while #stack > 0 do
		local n = #stack
		local frame = stack[n]
		stack[n] = nil

		local cur = frame.cur
		local ref = frame.ref
		local prefix = frame.prefix
		local depth = frame.depth

		if depth > maxDepth then
			warn("deepDiff: maximum depth reached (" .. maxDepth .. "), branch ignored")
			continue
		end

		if type(cur) == "table" and type(ref) == "table" then
			local visited = {}
			for k in cur do
				visited[k] = true
				local childPrefix = prefix == "" and tostring(k) or (prefix .. "." .. tostring(k))
				insert(stack, { cur = cur[k], ref = ref[k], prefix = childPrefix, depth = depth + 1 })
			end
			for k in ref do
				if not visited[k] then
					local childPrefix = prefix == "" and tostring(k) or (prefix .. "." .. tostring(k))
					insert(stack, { cur = nil, ref = ref[k], prefix = childPrefix, depth = depth + 1 })
				end
			end
		else
			if cur ~= ref then
				local key = prefix ~= "" and prefix or "(root)"
				result[key] = { old = cur, new = ref }
			end
		end
	end
end

-- Splits a dot-separated path string into a list of keys, converting
-- any numeric segments to actual numbers so they work as array indices.
-- Results are cached at the module level.
local function parsePath(path: string): { any }
	local cached = _pathCache[path]
	if cached then
		return cached
	end
	local segments: { any } = stringSplit(path, ".")
	for i, key in segments do
		local numKey = tonumber(key)
		if numKey ~= nil then
			segments[i] = numKey
		end
	end
	_pathCache[path] = segments
	return segments
end

-- Walks a table by the given list of keys and returns whatever is at
-- the end, or nil if any intermediate node is missing or not a table.
local function deepGet(t: any, path: { any }): any
	for _, key in path do
		if type(t) ~= "table" then
			return nil
		end
		t = t[key]
	end
	return t
end

-- Walks a table by the given list of keys and writes `value` at the
-- last key. Intermediate tables that don't exist yet are created
-- automatically. Errors if an intermediate node exists but isn't
-- a table (e.g. trying to write under a number).
local function deepSet(t: any, path: { any }, value: any)
	for i = 1, #path - 1 do
		local key = path[i]
		local node = t[key]
		if node == nil then
			t[key] = {}
			t = t[key]
		elseif type(node) ~= "table" then
			error(
				string.format(
					"deepSet: node '%s' is of type '%s' (expected: table). Cannot write under it.",
					tostring(key),
					type(node)
				),
				2
			)
		else
			t = node
		end
	end
	t[path[#path]] = value
end

-- Recursively merges the contents of `t2` into `t1`.
--
-- For each key-value pair in `t2`:
--   - If both `t1[key]` and `t2[key]` are tables, they are merged
--     recursively.
--   - Otherwise, the value from `t2` overwrites the value in `t1`.
--
-- The merge is destructive; `t1` is modified in-place.
local function deepMerge(t1: { [any]: any }, t2: { [any]: any })
	for k, v in t2 do
		if type(v) == "table" and type(t1[k]) == "table" then
			deepMerge(t1[k], v)
		else
			t1[k] = v
		end
	end
end

local function shallowCopy(t: { [any]: any }): { [any]: any }
	local new = create(#t)
	for k, v in t do
		new[k] = v
	end
	return new
end

-- Shallow-copies only the nodes along `path`, leaving the rest shared.
-- Returns the new root and the parent table of the final key.
local function cowBatch(root: { [any]: any }, changes: { [{ any }]: any }): { [any]: any }
	local newRoot = shallowCopy(root)
	local cloned = {}

	for keys, value in changes do
		local node = newRoot

		for i = 1, #keys - 1 do
			local key = keys[i]
			local child = node[key]

			if type(child) == "table" then
				local cached = cloned[child]
				if cached then
					node[key] = cached
					node = cached
				else
					local newChild = shallowCopy(child)
					cloned[child] = newChild
					node[key] = newChild
					node = newChild
				end
			else
				break
			end
		end

		node[keys[#keys]] = value
	end

	return newRoot
end

------------------------------------------------------------------------
-- DataStoreHandler
------------------------------------------------------------------------

local DataStoreHandler = {}
DataStoreHandler.__index = DataStoreHandler

-- Creates a new handler wrapping `profileData` for the given `player`.
--
-- When `copy` is false (the default) the handler works directly on the
-- table you pass in, which is what you want when using ProfileService —
-- GetRaw() will return the exact same reference ProfileService owns.
-- Pass `copy = true` when you want an isolated copy, e.g. in tests or
-- when the source data is external and shouldn't be mutated directly.
function DataStoreHandler.New(
	profileData: any,
	player: Player,
	copy: boolean?,
	maxDepth: number?
): (DataStoreHandler, boolean)
	if type(profileData) ~= "table" then
		warn("DataStoreHandler.New() — profileData must be a table")
		return nil :: any, false
	end
	local self = setmetatable({}, DataStoreHandler)
	self._data = copy and deepCopy(profileData, nil, nil, maxDepth) or profileData
	self._player = player
	self._maxDepth = maxDepth or MAX_DEPTH
	return self :: any, true
end

function DataStoreHandler:GetPlayer(): Player
	if self._player ~= nil then
		return self._player
	end
	warn("DataStoreHandler:GetPlayer() — player not found")
	return nil :: any
end

-- Returns the value stored at the dot-separated `path`.
function DataStoreHandler:Get(path: string): any
	local keys = parsePath(path)
	return deepGet(self._data, keys)
end

-- Writes `value` at the dot-separated `path`. Missing intermediate
-- tables are created automatically.
function DataStoreHandler:Set(path: string, value: any): boolean
	local keys = parsePath(path)
	local ok, err = pcall(deepSet, self._data, keys, value)
	if not ok then
		warn("DataStoreHandler:Set() — " .. tostring(err))
		return false
	end
	return true
end

-- Adds `amount` to the number stored at `path`. If nothing is stored
-- there yet, starts from 0. Returns false if the existing value is a
-- non-number type.
function DataStoreHandler:Increment(path: string, amount: number): boolean
	local keys = parsePath(path)
	local current = deepGet(self._data, keys)
	if current ~= nil and type(current) ~= "number" then
		warn("DataStoreHandler:Increment() — non-numeric value at '" .. keys[#keys] .. "'")
		return false
	end
	local newValue = (current or 0) + amount
	local ok, err = pcall(deepSet, self._data, keys, newValue)
	if not ok then
		warn("DataStoreHandler:Increment() — " .. tostring(err))
		return false
	end
	return true
end

-- Returns true if a non-nil value exists at `path`.
function DataStoreHandler:Has(path: string): boolean
	local keys = parsePath(path)
	return deepGet(self._data, keys) ~= nil
end

-- Inserts `value` into the table at `path`.
--
-- Whether to treat the table as an array or a dictionary is determined
-- by the type of the first existing key:
--   • number key  → array  (table.insert)
--   • string key  → dict   (merge `value`'s key-value pairs in)
--   • empty table → falls back to inspecting `value` itself
function DataStoreHandler:AddToList(path: string, value: any): boolean
	local keys = parsePath(path)
	local list = deepGet(self._data, keys)
	if type(list) ~= "table" then
		return false
	end

	local firstKey = next(list)
	local isArray

	if firstKey == nil then
		if type(value) == "table" then
			local vKey = next(value)
			isArray = (vKey == nil or type(vKey) == "number")
		else
			isArray = true
		end
	else
		isArray = (type(firstKey) == "number")
	end

	if isArray then
		insert(list, value)
	else
		if type(value) ~= "table" then
			warn("DataStoreHandler:AddToList() — dict expects a table of key-value pairs")
			return false
		end
		for k, v in value do
			list[k] = v
		end
	end

	return true
end

-- Removes the element at the last segment of `path`.
-- For numeric keys, uses table.remove so the array stays contiguous.
-- For string keys, sets the entry to nil.
function DataStoreHandler:RemoveByKey(path: string): boolean
	local keys = parsePath(path)
	if #keys == 0 then
		return false
	end
	local keysCopy = table.move(keys, 1, #keys, 1, {})
	local keyToRemove = remove(keysCopy)

	local list = deepGet(self._data, keysCopy)
	if type(list) ~= "table" then
		return false
	end

	if type(keyToRemove) == "number" then
		if list[keyToRemove] ~= nil then
			remove(list, keyToRemove)
			return true
		end
	elseif type(keyToRemove) == "string" then
		if list[keyToRemove] ~= nil then
			list[keyToRemove] = nil
			return true
		end
	end

	return false
end

-- Removes multiple entries from the table at `path` in one call.
-- Numeric indices are sorted descending before removal so earlier
-- removals don't shift the indices of later ones.
--
-- `keyList` can be in two shapes:
--   • Array-style  { "Sword", "Shield" }  — removes those string/number keys
--   • Map-style    { ["Sword"] = { Equipped = false } }  — removes a dict
--     entry only if all listed sub-fields match
function DataStoreHandler:RemoveByKeyList(path: string, keyList: { [any]: any }): boolean
	local keys = parsePath(path)
	if #keys == 0 then
		return false
	end

	local keysCopy = table.move(keys, 1, #keys, 1, {})
	local container = deepGet(self._data, keysCopy)
	if type(container) ~= "table" then
		return false
	end

	local removed = false
	local numericIndicesToRemove = {}

	for key, value in keyList do
		if type(key) == "number" then
			local entryKey = value
			if type(entryKey) == "number" then
				if container[entryKey] ~= nil then
					insert(numericIndicesToRemove, entryKey)
					removed = true
				end
			else
				if container[entryKey] ~= nil then
					container[entryKey] = nil
					removed = true
				end
			end
		else
			local entry = container[key]
			if type(entry) == "table" then
				local match = true
				for subKey, subVal in value do
					if entry[subKey] ~= subVal then
						match = false
						break
					end
				end
				if match then
					container[key] = nil
					removed = true
				end
			end
		end
	end

	if #numericIndicesToRemove > 0 then
		sort(numericIndicesToRemove, function(a: number, b: number)
			return a > b
		end)
		for _, idx in numericIndicesToRemove do
			remove(container, idx)
		end
	end

	return removed
end

-- Replaces the value at the last segment of `path` with `value`.
-- Returns false if the parent doesn't exist or the key has no value yet.
function DataStoreHandler:UpdateList(path: string, value: any): boolean
	local keys = parsePath(path)
	local parentKeys = { unpack(keys) }
	local finalKey = remove(parentKeys)
	local parent = deepGet(self._data, parentKeys)
	if type(parent) ~= "table" or parent[finalKey] == nil then
		return false
	end
	parent[finalKey] = value
	return true
end

-- Writes `value` at the full `path`. Unlike UpdateList, the target
-- doesn't need to exist beforehand — intermediate tables are created
-- as needed. Returns false if the existing value is a non-table type
-- that would block the write.
function DataStoreHandler:UpdateListItemProperty(path: string, value: any): boolean
	local keys = parsePath(path)
	local current = deepGet(self._data, keys)
	if current ~= nil and type(current) ~= "table" then
		return false
	end
	local ok, err = pcall(deepSet, self._data, keys, value)
	if not ok then
		warn("DataStoreHandler:UpdateListItemProperty() — " .. tostring(err))
	end
	return ok
end

-- Sets the property at the last segment of `path` to nil on the parent
-- item. Returns false if the parent isn't a table or the property
-- doesn't exist.
function DataStoreHandler:RemovePropertyFromListItem(path: string): boolean
	local keys = parsePath(path)
	if #keys == 0 then
		return false
	end
	local keysCopy = { unpack(keys) }
	local property = remove(keysCopy)
	local item = deepGet(self._data, keysCopy)
	if type(item) ~= "table" or item[property] == nil then
		return false
	end
	item[property] = nil
	return true
end

-- Adds a new property to the item found one level above the last path
-- segment. For example, "Inventory.1.Enchanted" would find the table
-- at "Inventory.1" and set its "Enchanted" key to `value`.
function DataStoreHandler:AddPropertyToListItem(path: string, value: any): boolean
	local keys = parsePath(path)
	local parentKeys = { unpack(keys) }
	local property = remove(parentKeys)
	local item = deepGet(self._data, parentKeys)
	if type(item) ~= "table" then
		return false
	end
	item[property] = value
	return true
end

-- Applies a math operation to the number at `path`.
-- Supported operations: "+", "-", "*", "/", "%".
-- Division and modulo by zero are rejected and return false.
function DataStoreHandler:OperateOnValue(path: string, operation: string, operand: number): boolean
	local keys = parsePath(path)
	local current = deepGet(self._data, keys)
	if type(current) ~= "number" then
		return false
	end

	local result
	if operation == "+" then
		result = current + operand
	elseif operation == "-" then
		result = current - operand
	elseif operation == "*" then
		result = current * operand
	elseif operation == "/" then
		if operand == 0 then
			return false
		end
		result = current / operand
	elseif operation == "%" then
		if operand == 0 then
			return false
		end
		result = current % operand
	else
		return false
	end

	deepSet(self._data, keys, result)
	return true
end

-- Returns the raw internal data table. When the handler was created
-- without `copy = true`, this is the exact table you passed to New().
function DataStoreHandler:GetRaw(): any
	return self._data
end

-- Resets the value at `path` to `defaultValue`. This is just a
-- named wrapper around Set() to make intent clearer at the call site.
function DataStoreHandler:Reset(path: string, defaultValue: any): boolean
	return self:Set(path, defaultValue)
end

-- Flips the boolean stored at `path`. Returns false if the value
-- isn't a boolean.
function DataStoreHandler:Toggle(path: string): boolean
	local keys = parsePath(path)
	local current = deepGet(self._data, keys)
	if type(current) ~= "boolean" then
		warn("DataStoreHandler:Toggle() — non-boolean value at '" .. path .. "'")
		return false
	end
	deepSet(self._data, keys, not current)
	return true
end

-- Iterates the array at `path` and returns the index and value of the
-- first element for which `predicate` returns true.
-- Returns (nil, nil) if nothing matches.
--
-- Example:
--   local idx, item = handler:FindInList("Inventory", function(item)
--       return item.Name == "Sword"
--   end)
function DataStoreHandler:FindInList(path: string, predicate: (value: any) -> boolean): (number?, any)
	local keys = parsePath(path)
	local list = deepGet(self._data, keys)
	if type(list) ~= "table" then
		return nil, nil
	end
	for i, value in ipairs(list) do
		local ok, result = pcall(predicate, value)
		if ok and result then
			return i, value
		end
	end
	return nil, nil
end

-- Compares the current data against a `snapshot` and returns a
-- dictionary of every path that differs:
--   { ["Stats.Health"] = { old = 50, new = 100 } }
-- where `old` is the current value and `new` is what was in the snapshot.
--
-- Don't hold onto the result indefinitely — the `old` values hold
-- references into the live data and can delay garbage collection.
function DataStoreHandler:Diff(snapshot: any): { [string]: { old: any, new: any } }
	local result = {}
	deepDiff(self._data, snapshot, result, self._maxDepth)
	return result
end

-- Swaps the values at `pathA` and `pathB`. If writing to pathB fails,
-- pathA is rolled back before returning.
function DataStoreHandler:Swap(pathA: string, pathB: string): boolean
	local keysA = parsePath(pathA)
	local keysB = parsePath(pathB)
	local valA = deepGet(self._data, keysA)
	local valB = deepGet(self._data, keysB)

	local okA, errA = pcall(deepSet, self._data, keysA, valB)
	if not okA then
		warn("DataStoreHandler:Swap() — pathA: " .. tostring(errA))
		return false
	end
	local okB, errB = pcall(deepSet, self._data, keysB, valA)
	if not okB then
		pcall(deepSet, self._data, keysA, valA) -- roll back
		warn("DataStoreHandler:Swap() — pathB: " .. tostring(errB))
		return false
	end
	return true
end

-- Moves the element at `fromIndex` to `toIndex` inside the array at
-- `path`. The surrounding elements shift automatically.
function DataStoreHandler:MoveInList(path: string, fromIndex: number, toIndex: number): boolean
	local keys = parsePath(path)
	local list = deepGet(self._data, keys)
	if type(list) ~= "table" then
		return false
	end
	if list[fromIndex] == nil then
		return false
	end
	local item = remove(list, fromIndex)
	insert(list, toIndex, item)
	return true
end

-- Returns the number of elements in the table at `path`, whether it's
-- an array or a dictionary. Returns nil if `path` doesn't point to a
-- table.
-- Uses the length operator for pure arrays (O(1)); falls back to
-- counting pairs for dictionaries or mixed tables (O(n)).
function DataStoreHandler:CountList(path: string): number?
	local keys = parsePath(path)
	local list = deepGet(self._data, keys)
	if type(list) ~= "table" then
		return nil
	end
	if #list > 0 then
		return #list
	end
	local count = 0
	for _ in list do
		count += 1
	end
	return count
end

-- Applies multiple Set operations as a single atomic unit. All changes
-- are first applied to a deep copy of the data. If any one of them
-- fails, the original data is left completely untouched. Only on full
-- success is the internal data swapped out for the modified copy.
--
-- Example:
--   handler:BatchSet({
--       ["Stats.Health"] = 100,
--       ["Stats.Speed"]  = 16,
--       ["Coins"]        = 500,
--   })
function DataStoreHandler:BatchSet(changes: { [string]: any }): boolean
	local compiled = {}
	for path, value in changes do
		compiled[parsePath(path)] = value
	end
	local ok, result = pcall(cowBatch, self._data, compiled)
	if not ok then
		warn("DataStoreHandler:BatchSet() — " .. tostring(result))
		return false
	end
	self._data = result
	return true
end

-- Applies multiple pre-compiled path updates in a single atomic operation.
--
-- This version expects "compiled paths" instead of strings, meaning each key
-- is already a table of path segments (e.g. { "Stats", "Coins" }).
--
-- Benefits:
--   • No string parsing (string.split avoided)
--   • Lower GC pressure
--   • Faster batch writes for ProfileService-style saves
--   • Atomic update (all changes applied together via COW)
--
-- Example:
--   local changes = {
--       [{ "Coins" }] = 1000,
--       [{ "Stats", "Level" }] = 10,
--       [{ "Inventory", 1, "Name" }] = "Sword"
--   }
--
--   handler:BatchSetCompiled(changes)
--
-- 	local PATH_COINS = { "Coins" }
-- 	local PATH_LEVEL = { "Stats", "Level" }
-- 	local PATH_XP = { "Stats", "XP" }
--
-- 	handler:BatchSetCompiled({
--	 [PATH_COINS] = 1500,
--	 [PATH_LEVEL] = 12,
--	 [PATH_XP] = 3400
-- 	})
function DataStoreHandler:BatchSetCompiled(changes: { [{ any }]: any }): boolean
	local ok, result = pcall(cowBatch, self._data, changes)
	if not ok then
		warn("DataStoreHandler:BatchSetCompiled() — " .. tostring(result))
		return false
	end
	self._data = result
	return true
end

-- Deep-merges `partialData` into the table at `path`, leaving any keys
-- not mentioned in `partialData` untouched. Nested tables are merged
-- recursively.
--
-- Example:
--   handler:Patch("Settings", { Audio = { Volume = 0.5 } })
--   -- Settings.Video is left as-is
function DataStoreHandler:Patch(path: string, partialData: { [any]: any }): boolean
	local keys = parsePath(path)
	local target = deepGet(self._data, keys)

	if type(target) ~= "table" then
		warn("DataStoreHandler:Patch() — target at '" .. path .. "' is not a table")
		return false
	end
	deepMerge(target, partialData)
	return true
end

-- Empties the table at `path` without destroying the table itself, so
-- any existing references to it remain valid.
function DataStoreHandler:ClearList(path: string): boolean
	local keys = parsePath(path)
	local target = deepGet(self._data, keys)

	if type(target) ~= "table" then
		return false
	end

	clear(target)
	return true
end

-- Removes and returns one element from the array at `path`. If `index`
-- is omitted, the last element is popped. Returns nil if the array is
-- empty or the path doesn't point to a table.
function DataStoreHandler:PopFromList(path: string, index: number?): any
	local keys = parsePath(path)
	local target = deepGet(self._data, keys)

	if type(target) ~= "table" or #target == 0 then
		return nil
	end

	return remove(target, index)
end

-- Runs `transform` on every element in the table at `path` and writes
-- the returned value back in place. Works on both arrays and
-- dictionaries. If the transform errors or returns nil for a given
-- element, that element is left unchanged.
--
-- Example:
--   handler:MapList("Stats.Multipliers", function(val) return val * 2 end)
function DataStoreHandler:MapList(path: string, transform: (value: any) -> any): boolean
	local keys = parsePath(path)
	local target = deepGet(self._data, keys)

	if type(target) ~= "table" then
		return false
	end

	for k, v in target do
		local ok, result = pcall(transform, v)
		if ok and result ~= nil then
			target[k] = result
		elseif not ok then
			warn("DataStoreHandler:MapList() — transform failed at key " .. tostring(k) .. ": " .. tostring(result))
		end
	end

	return true
end

-- Returns a deep copy of the entire current data. Safe to pass to
-- Restore() or Diff() later without worrying about the original
-- being modified in the meantime.
function DataStoreHandler:Snapshot(): any
	return deepCopy(self._data, nil, nil, self._maxDepth)
end

-- Same as Snapshot(), but only copies the sub-tree at `path` instead
-- of the whole data. Much cheaper on large datasets when you only care
-- about one section. Returns nil if `path` doesn't exist.
--
-- Note: passing the result of SnapshotPath() to Restore() will replace
-- ALL of _data with just that sub-tree. If you only want to restore the
-- section, use Set() instead:
--   handler:Set("Stats", handler:SnapshotPath("Stats"))
function DataStoreHandler:SnapshotPath(path: string): any
	local keys = parsePath(path)
	local node = deepGet(self._data, keys)
	if node == nil then
		return nil
	end
	return deepCopy(node, nil, nil, self._maxDepth)
end

-- Replaces the current data with a deep copy of `snapshot`. The copy
-- ensures that subsequent changes to the handler can't corrupt the
-- snapshot you're holding.
function DataStoreHandler:Restore(snapshot: any): boolean
	if type(snapshot) ~= "table" then
		warn("DataStoreHandler:Restore() — invalid snapshot")
		return false
	end
	-- Snapshot is already an isolated copy, so we can assign it directly.
	self._data = snapshot
	return true
end

function DataStoreHandler:Destroy()
	self._data = nil
	self._player = nil
	self._maxDepth = nil
end

return DataStoreHandler
