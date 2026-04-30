# DataStoreHandler - Complete Documentation

**Author:** FlowGostavo  

## 📋 Table of Contents

1. [Overview](#overview)
2. [Installation & Setup](#installation--setup)
3. [Core Concepts](#core-concepts)
4. [API Reference](#api-reference)
5. [Integration Guides](#integration-guides)
6. [Advanced Examples](#advanced-examples)
7. [Performance Tips](#performance-tips)
8. [Troubleshooting](#troubleshooting)

---

## Overview

**DataStoreHandler** is a powerful, type-safe wrapper for managing player profile data in Roblox games. It provides:
  
- ✅ Dot-notation path access (`"Stats.Health"`, `"Inventory.1.Name"`)
- ✅ Atomic batch operations (all-or-nothing updates)
- ✅ Deep copy/merge/diff operations
- ✅ Safe list manipulation (arrays & dictionaries)
- ✅ Copy-on-write optimization for large datasets
- ✅ ProfileService, ProfileStore, DataStore, and DataStore2 compatibility
- ✅ Zero external dependencies

### Key Features

| Feature | Benefit |
|---------|---------|
| **Path-based access** | No deep table nesting in code |
| **Atomic operations** | Data consistency guaranteed |
| **Copy-on-write** | Memory efficient batch updates |
| **Snapshot/Restore** | Easy undo/redo mechanics |
| **Diff tracking** | Know exactly what changed |

---

## Installation & Setup

Link : https://create.roblox.com/store/asset/119568910221062/DataStoreHandler

### Step 1: Add the Module

Place `DataStoreHandler.lua` in **ServerScriptService** or your modules folder:

```
ServerScriptService/
  └── DataStoreHandler.lua
```

### Step 2: Require It

```lua
local DataStoreHandler = require(game.ServerScriptService.DataStoreHandler)
```

### Step 3: Initialize with Player Data

```lua
local handler, success = DataStoreHandler.New(profileData, player)

if not success then
    warn("Failed to initialize handler")
    return
end

-- Handler is now ready to use
```

---

## Core Concepts

### What is a "Path"?

A path is a dot-separated string representing a location in your data tree:

```lua
-- Given this data structure:
{
    Stats = {
        Health = 100,
        Level = 5
    },
    Inventory = {
        { Name = "Sword", Damage = 25 },
        { Name = "Shield", Defense = 15 }
    }
}

-- These are valid paths:
"Stats"              -- The entire Stats table
"Stats.Health"       -- The Health number
"Stats.Level"        -- The Level number
"Inventory"          -- The entire Inventory array
"Inventory.1"        -- First inventory slot (note: numeric)
"Inventory.1.Name"   -- Name of first item
"Inventory.2.Damage" -- Damage of second item
```

### Copy vs. Reference

```lua
-- Reference mode (default): handler modifies the original table
local handler, ok = DataStoreHandler.New(profileData, player, false)
-- Changing via handler affects profileData directly

-- Copy mode: handler works on an isolated copy
local handler, ok = DataStoreHandler.New(profileData, player, true)
-- Changing via handler does NOT affect profileData
```

Use **copy mode** when:
- Testing with external data
- You want isolation for sandboxing
- The source data shouldn't be modified

### Arrays vs. Dictionaries

DataStoreHandler automatically detects the structure:

```lua
-- Array (numeric keys)
local inventory = { "Sword", "Shield", "Potion" }
handler:AddToList("Inventory", "Dagger")  -- Uses table.insert

-- Dictionary (string keys)
local settings = { Volume = 0.8, Brightness = 1.0 }
handler:AddToList("Settings", { Gamma = 1.2 })  -- Merges key-value pairs
```

---

## API Reference

### Constructor

#### `DataStoreHandler.New(profileData, player, copy?, maxDepth?)`

Creates a new handler instance.

**Parameters:**
- `profileData` (table) - The data structure to manage
- `player` (Player) - The player object
- `copy?` (boolean) - If true, works on a deep copy (default: false)
- `maxDepth?` (number) - Max recursion depth for copy operations (default: 64)

**Returns:** (DataStoreHandler, boolean) - Handler and success flag

**Example:**
```lua
local data = {
    Stats = { Health = 100, Mana = 50 },
    Inventory = { "Sword", "Shield" }
}

local player = game.Players.Player1
local handler, success = DataStoreHandler.New(data, player)

if success then
    print("Handler created successfully")
end
```

---

### Reading Data

#### `Get(path) → any`

Retrieves the value at the given path.

**Parameters:**
- `path` (string) - Dot-separated path

**Returns:** any - Value at path, or nil if not found

**Example:**
```lua
local health = handler:Get("Stats.Health")          -- 100
local itemName = handler:Get("Inventory.1.Name")   -- "Sword"
local coins = handler:Get("Currency.Coins")        -- nil if not set
```

#### `GetRaw() → any`

Returns the entire data table without copying.

**Returns:** The raw internal data table

**Example:**
```lua
local allData = handler:GetRaw()
print(allData.Stats.Health)  -- Direct access
```

#### `GetPlayer() → Player`

Returns the player associated with this handler.

**Returns:** Player object or nil

**Example:**
```lua
local player = handler:GetPlayer()
if player and player.Parent == game.Players then
    print(player.Name .. " is still in game")
end
```

#### `Has(path) → boolean`

Checks if a non-nil value exists at the path.

**Parameters:**
- `path` (string) - Dot-separated path

**Returns:** boolean - true if value exists

**Example:**
```lua
if handler:Has("Quests.MainQuest.Completed") then
    print("Player has completed main quest")
end
```

---

### Writing Data

#### `Set(path, value) → boolean`

Sets a value at the given path, creating intermediate tables as needed.

**Parameters:**
- `path` (string) - Dot-separated path
- `value` (any) - Value to set

**Returns:** boolean - Success flag

**Example:**
```lua
handler:Set("Stats.Health", 50)
handler:Set("Inventory.1.Equipped", true)
handler:Set("Settings.Audio.Volume", 0.75)

-- Creates nested structure automatically
handler:Set("Achievements.Secret.Unlocked", true)  -- OK even if Achievements or Secret don't exist
```

#### `Reset(path, defaultValue) → boolean`

Resets a value to its default (alias for Set with clearer intent).

**Parameters:**
- `path` (string) - Dot-separated path
- `defaultValue` (any) - Value to reset to

**Returns:** boolean - Success flag

**Example:**
```lua
handler:Reset("Stats.Health", 100)     -- Restore full health
handler:Reset("Inventory", {})         -- Clear inventory back to empty
handler:Reset("Buffs.Active", false)   -- Deactivate buffs
```

#### `BatchSet(changes) → boolean`

Applies multiple Set operations atomically (all succeed or all fail).

**Parameters:**
- `changes` (table) - Map of paths to values

**Returns:** boolean - Success flag

**Example:**
```lua
-- Level up the player
local success = handler:BatchSet({
    ["Stats.Level"] = handler:Get("Stats.Level") + 1,
    ["Stats.Experience"] = 0,
    ["Stats.HealthMax"] = handler:Get("Stats.HealthMax") + 10,
    ["Achievements.LevelMilestones." .. tostring(newLevel)] = true,
})

if not success then
    print("Level up failed - no changes applied")
end
```

#### `BatchSetCompiled(changes) → boolean`

Like BatchSet, but with pre-parsed paths (faster, lower GC pressure).

**Parameters:**
- `changes` (table) - Map of pre-parsed path tables to values

**Returns:** boolean - Success flag

**Example:**
```lua
-- Pre-compile paths once
local PATH_COINS = { "Currency", "Coins" }
local PATH_LEVEL = { "Stats", "Level" }
local PATH_XP = { "Stats", "Experience" }

-- Use many times with zero string parsing
local success = handler:BatchSetCompiled({
    [PATH_COINS] = 5000,
    [PATH_LEVEL] = 10,
    [PATH_XP] = 2500,
})
```

#### `Patch(path, partialData) → boolean`

Deep-merges partial data into the table at path (non-destructive).

**Parameters:**
- `path` (string) - Dot-separated path to target table
- `partialData` (table) - Partial updates to merge

**Returns:** boolean - Success flag

**Example:**
```lua
-- Without Patch (overwrites entire Settings)
handler:Set("Settings", { Volume = 0.5, Brightness = 1.0 })

-- With Patch (only updates Volume, keeps other keys)
handler:Patch("Settings", { Volume = 0.5 })  -- Brightness unchanged
```

---

### Numeric Operations

#### `Increment(path, amount) → boolean`

Adds to a number at the given path (defaults to 0 if not set).

**Parameters:**
- `path` (string) - Dot-separated path
- `amount` (number) - Amount to add

**Returns:** boolean - Success flag

**Example:**
```lua
handler:Increment("Currency.Coins", 100)       -- +100 coins
handler:Increment("Stats.Experience", 50)      -- +50 XP
handler:Increment("Counters.DeathCount", 1)    -- Death counter++
```

#### `OperateOnValue(path, operation, operand) → boolean`

Performs mathematical operations: `+`, `-`, `*`, `/`, `%`

**Parameters:**
- `path` (string) - Dot-separated path
- `operation` (string) - One of: `"+"`, `"-"`, `"*"`, `"/"`, `"%"`
- `operand` (number) - Right-hand operand

**Returns:** boolean - Success flag

**Example:**
```lua
handler:OperateOnValue("Stats.Health", "-", 25)        -- Damage
handler:OperateOnValue("Stats.Speed", "*", 1.5)        -- Buff
handler:OperateOnValue("Currency.Coins", "/", 2)       -- Split coins
handler:OperateOnValue("Stats.Mana", "%", 100)         -- Modulo

-- Division by zero returns false
if not handler:OperateOnValue("Value", "/", 0) then
    print("Cannot divide by zero")
end
```

#### `Toggle(path) → boolean`

Flips a boolean value.

**Parameters:**
- `path` (string) - Dot-separated path to boolean

**Returns:** boolean - Success flag

**Example:**
```lua
handler:Toggle("Buffs.SpeedBoost")              -- true → false
handler:Toggle("Settings.Audio.Enabled")        -- false → true
handler:Toggle("Achievements.Hidden")           -- Toggle hidden status
```

---

### List/Array Operations

#### `AddToList(path, value) → boolean`

Adds an element to a list (array or dictionary).

**Parameters:**
- `path` (string) - Dot-separated path to list
- `value` (any) - Value to add

**Returns:** boolean - Success flag

**Example:**
```lua
-- Array mode (numeric keys detected)
handler:AddToList("Inventory", { Name = "Sword", Damage = 25 })
handler:AddToList("Inventory", { Name = "Shield", Defense = 15 })
-- Inventory is now: [{ Name="Sword", Damage=25 }, { Name="Shield", Defense=15 }]

-- Dictionary mode (string keys detected)
handler:AddToList("PlayerStats", { Kills = 5 })
handler:AddToList("PlayerStats", { Deaths = 2 })
-- PlayerStats is now: { Kills = 5, Deaths = 2 }
```

#### `UpdateList(path, value) → boolean`

Replaces an existing element (must already exist).

**Parameters:**
- `path` (string) - Dot-separated path to element
- `value` (any) - New value

**Returns:** boolean - Success flag

**Example:**
```lua
-- Update first inventory slot
handler:UpdateList("Inventory.1", { Name = "Better Sword", Damage = 50 })

-- Update a stat
handler:UpdateList("PlayerStats.Kills", 10)
```

#### `RemoveByKey(path) → boolean`

Removes an element at the last path segment.

**Parameters:**
- `path` (string) - Dot-separated path to element to remove

**Returns:** boolean - Success flag

**Example:**
```lua
-- Remove from numeric array (contiguous, uses table.remove)
handler:RemoveByKey("Inventory.1")  -- Shifts remaining items

-- Remove from dictionary (sets to nil)
handler:RemoveByKey("PlayerStats.Kills")
```

#### `RemoveByKeyList(path, keyList) → boolean`

Removes multiple elements in one call (efficient).

**Parameters:**
- `path` (string) - Dot-separated path to container
- `keyList` (table) - Array or map of keys to remove

**Returns:** boolean - Success flag

**Example:**
```lua
-- Remove array indices (automatically sorted descending to prevent shifts)
handler:RemoveByKeyList("Inventory", { 1, 3, 5 })

-- Remove dict keys
handler:RemoveByKeyList("PlayerStats", { "Deaths", "Losses" })

-- Remove dict entries by matching properties
handler:RemoveByKeyList("Quests", {
    ["MainQuest"] = { Status = "Failed" }  -- Only remove if Status == "Failed"
})
```

#### `ClearList(path) → boolean`

Empties a table without destroying it (references remain valid).

**Parameters:**
- `path` (string) - Dot-separated path to table

**Returns:** boolean - Success flag

**Example:**
```lua
handler:ClearList("Inventory")       -- Remove all items
handler:ClearList("ActiveBuffs")     -- Deactivate all buffs
handler:ClearList("Quests.Completed") -- Clear completed quests
```

#### `PopFromList(path, index?) → any`

Removes and returns one element (from end if no index).

**Parameters:**
- `path` (string) - Dot-separated path to array
- `index?` (number) - Index to pop (default: end of array)

**Returns:** any - Popped element, or nil if empty

**Example:**
```lua
local lastItem = handler:PopFromList("Inventory")      -- Pop last
local firstItem = handler:PopFromList("Inventory", 1)  -- Pop first
```

#### `CountList(path) → number?`

Returns the number of elements (array or dictionary).

**Parameters:**
- `path` (string) - Dot-separated path to table

**Returns:** number? - Element count, or nil if not a table

**Example:**
```lua
local inventorySize = handler:CountList("Inventory")
local statCount = handler:CountList("PlayerStats")

if not inventorySize or inventorySize == 0 then
    print("Inventory is empty")
end
```

#### `FindInList(path, predicate) → (number?, any)`

Searches for the first element matching a predicate.

**Parameters:**
- `path` (string) - Dot-separated path to array
- `predicate` (function) - Test function returning boolean

**Returns:** (number?, any) - Index and value, or (nil, nil) if not found

**Example:**
```lua
-- Find sword in inventory
local idx, item = handler:FindInList("Inventory", function(item)
    return item.Name == "Sword"
end)

if idx then
    print("Sword found at index " .. idx)
else
    print("Sword not found")
end

-- Find first equipped item
local idx, item = handler:FindInList("Inventory", function(item)
    return item.Equipped == true
end)

-- Find first weak enemy
local idx, enemy = handler:FindInList("Enemies", function(enemy)
    return enemy.Health < 30
end)
```

#### `MapList(path, transform) → boolean`

Applies a transformation function to every element.

**Parameters:**
- `path` (string) - Dot-separated path to table
- `transform` (function) - Function taking value, returning new value

**Returns:** boolean - Success flag

**Example:**
```lua
-- Double all stat multipliers
handler:MapList("Stats.Multipliers", function(val)
    return val * 2
end)

-- Add 1 to all item durations
handler:MapList("Buffs.Active", function(buff)
    buff.Duration = buff.Duration + 1
    return buff
end)

-- Increase all inventory item prices by 10%
handler:MapList("Inventory", function(item)
    item.Price = item.Price * 1.1
    return item
end)
```

#### `MoveInList(path, fromIndex, toIndex) → boolean`

Moves an element from one index to another (array only).

**Parameters:**
- `path` (string) - Dot-separated path to array
- `fromIndex` (number) - Current index
- `toIndex` (number) - Target index

**Returns:** boolean - Success flag

**Example:**
```lua
-- Reorder inventory
handler:MoveInList("Inventory", 1, 3)  -- Move first item to third position

-- Rearrange quest order
handler:MoveInList("Quests", 5, 1)     -- Move fifth quest to first
```

#### `AddPropertyToListItem(path, value) → boolean`

Adds a new property to a list item.

**Parameters:**
- `path` (string) - Dot-separated path to property (parent is the item)
- `value` (any) - Value to set

**Returns:** boolean - Success flag

**Example:**
```lua
-- Given path "Inventory.1.Enchanted", sets Inventory.1.Enchanted = value
handler:AddPropertyToListItem("Inventory.1.Enchanted", true)

-- Add equipped status to item
handler:AddPropertyToListItem("Inventory.2.Equipped", false)

-- Add durability tracking
handler:AddPropertyToListItem("Inventory.3.CurrentDurability", 100)
```

#### `UpdateListItemProperty(path, value) → boolean`

Updates a property on a list item (creates intermediate tables).

**Parameters:**
- `path` (string) - Dot-separated path to property
- `value` (any) - Value to set

**Returns:** boolean - Success flag

**Example:**
```lua
handler:UpdateListItemProperty("Inventory.1.Durability", 85)
handler:UpdateListItemProperty("Quests.1.Progress", 50)
```

#### `RemovePropertyFromListItem(path) → boolean`

Removes a property from a list item.

**Parameters:**
- `path` (string) - Dot-separated path to property

**Returns:** boolean - Success flag

**Example:**
```lua
handler:RemovePropertyFromListItem("Inventory.1.Enchanted")
handler:RemovePropertyFromListItem("Quests.2.Reward")
```

---

### Snapshots & Restoration

#### `Snapshot() → any`

Creates a deep copy of the entire current data state.

**Returns:** Isolated copy of all data

**Example:**
```lua
-- Take a backup
local backup = handler:Snapshot()

-- Make changes
handler:Set("Stats.Health", 50)
handler:Increment("Currency.Coins", -100)

-- Restore if needed
handler:Restore(backup)
```

#### `SnapshotPath(path) → any`

Creates a deep copy of just one branch.

**Parameters:**
- `path` (string) - Dot-separated path to section

**Returns:** Isolated copy of that section, or nil if not found

**Example:**
```lua
-- Backup just inventory
local inventoryBackup = handler:SnapshotPath("Inventory")

-- Backup just stats
local statsBackup = handler:SnapshotPath("Stats")

-- Modify
handler:Set("Inventory.1.Name", "Broken Sword")

-- Restore just inventory
handler:Restore(inventoryBackup)
```

#### `Restore(snapshot) → boolean`

Replaces all data with a snapshot.

**Parameters:**
- `snapshot` (table) - A snapshot from Snapshot()

**Returns:** boolean - Success flag

**Example:**
```lua
if handler:Restore(backup) then
    print("Data restored successfully")
end
```

---

### Comparison & Diff

#### `Diff(snapshot) → { [string]: { old: any, new: any } }`

Compares current data against a snapshot and returns all differences.

**Parameters:**
- `snapshot` (table) - Reference snapshot

**Returns:** Table of changes: `{ "Path.To.Value" = { old = oldVal, new = newVal } }`

**Example:**
```lua
local before = handler:Snapshot()

-- Make changes
handler:Set("Stats.Health", 50)
handler:Increment("Currency.Coins", 100)
handler:Set("LastLogin", os.time())

-- See what changed
local changes = handler:Diff(before)

for path, change in changes do
    print(path .. ": " .. tostring(change.old) .. " → " .. tostring(change.new))
end

-- Output:
-- Stats.Health: 100 → 50
-- Currency.Coins: 0 → 100
-- LastLogin: nil → 1714521600
```

---

### Value Swapping

#### `Swap(pathA, pathB) → boolean`

Swaps the values at two paths (with rollback on failure).

**Parameters:**
- `pathA` (string) - First path
- `pathB` (string) - Second path

**Returns:** boolean - Success flag

**Example:**
```lua
-- Swap health and mana (why? just for demo)
handler:Swap("Stats.Health", "Stats.Mana")

-- Swap first and second inventory items
handler:Swap("Inventory.1", "Inventory.2")

-- Swap currencies
handler:Swap("Currency.Gold", "Currency.Silver")
```

---

### Cleanup

#### `Destroy() → void`

Clears all references in the handler.

**Example:**
```lua
handler:Destroy()
handler = nil  -- Allow garbage collection
```

---

## Integration Guides

### ProfileService Integration

[ProfileService](https://github.com/MadStudioRoblox/ProfileService) is a popular profile management library. DataStoreHandler integrates seamlessly:

```lua
local Players = game:GetService("Players")
local DataStoreHandler = require(game.ServerScriptService.DataStoreHandler)
local ProfileService = require(game.ServerScriptService.ProfileService)

local STORE_NAME = "PlayerProfiles"
local PROFILE_TEMPLATE = {
    Stats = { Health = 100, Level = 1, Experience = 0 },
    Inventory = {},
    Currency = { Coins = 0, Gems = 0 },
    Settings = { Volume = 1.0, Brightness = 1.0 },
}

local ProfileStore = ProfileService.GetProfileStore(STORE_NAME, PROFILE_TEMPLATE)
local PlayerHandlers = {}

Players.PlayerAdded:Connect(function(player)
    -- Load profile from ProfileService
    local profile = ProfileStore:LoadProfileAsync("Player_" .. player.UserId)
    
    if not profile then
        player:Kick("Failed to load profile")
        return
    end
    
    -- Bind release function
    profile:Reconcile()  -- Fill missing keys with template
    profile:ListenToRelease(function()
        PlayerHandlers[player] = nil
        player:Kick("Profile released")
    end)
    
    -- Create handler (reference mode to work directly with profile.Data)
    local handler, success = DataStoreHandler.New(profile.Data, player, false)
    if not success then
        profile:Release()
        player:Kick("Failed to create handler")
        return
    end
    
    PlayerHandlers[player] = handler
    player.CharacterAdded:Connect(function()
        -- Restore health on spawn
        local health = handler:Get("Stats.Health")
        player.Character.Humanoid.Health = health
    end)
end)

Players.PlayerRemoving:Connect(function(player)
    local handler = PlayerHandlers[player]
    if handler then
        handler:Destroy()
    end
end)

-- Usage
game.Players.Player1.CharacterAdded:Connect(function(char)
    local handler = PlayerHandlers[game.Players.Player1]
    handler:Increment("Currency.Coins", 50)
    handler:Increment("Stats.Experience", 100)
end)
```

### ProfileStore Integration

```lua
local Players = game:GetService("Players")
local DataStoreHandler = require(game.ServerScriptService.DataStoreHandler)
local ProfileStore = require(game.ServerScriptService.ProfileStore)

local store = ProfileStore.new("PlayerData", {
    Version = 1,
    Data = {
        Stats = { Level = 1, Health = 100 },
        Inventory = {},
    }
})

local playerSessions = {}

Players.PlayerAdded:Connect(function(player)
    -- Load with ProfileStore
    local userId = tostring(player.UserId)
    store:LoadAsync(userId, function(profile)
        if profile then
            -- Create handler
            local handler, ok = DataStoreHandler.New(profile, player, false)
            if ok then
                playerSessions[player] = handler
                print("Handler loaded for " .. player.Name)
            end
        end
    end)
end)

Players.PlayerRemoving:Connect(function(player)
    local handler = playerSessions[player]
    if handler then
        local dataToSave = handler:GetRaw()
        local userId = tostring(player.UserId)
        store:SaveAsync(userId, dataToSave)
        handler:Destroy()
        playerSessions[player] = nil
    end
end)
```

### DataStore2 Integration

[DataStore2](https://github.com/Novaly-Studios/Roblox-DataStore2) provides layered caching:

```lua
local Players = game:GetService("Players")
local DataStoreHandler = require(game.ServerScriptService.DataStoreHandler)
local DataStore2 = require(game.ServerScriptService.DataStore2)

DataStore2.Combine("PRIMARY", "Stats", "Inventory", "Currency")

local handlers = {}

Players.PlayerAdded:Connect(function(player)
    local primaryStore = DataStore2("PRIMARY", player)
    
    -- Get or create default
    local data = primaryStore:Get({
        Stats = { Level = 1, Health = 100 },
        Inventory = {},
        Currency = { Coins = 0 },
    })
    
    -- Create handler
    local handler, ok = DataStoreHandler.New(data, player, false)
    if ok then
        handlers[player] = { handler = handler, store = primaryStore }
        
        -- Listen to changes from DataStore2
        primaryStore:OnUpdate(function(newData)
            handler:Restore(newData)
        end)
    end
end)

Players.PlayerRemoving:Connect(function(player)
    local session = handlers[player]
    if session then
        session.store:Set(session.handler:GetRaw())
        session.handler:Destroy()
        handlers[player] = nil
    end
end)
```

### Plain DataStore Integration

```lua
local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local DataStoreHandler = require(game.ServerScriptService.DataStoreHandler)

local playerStore = DataStoreService:GetDataStore("PlayerProfiles")
local handlers = {}

local DEFAULT_DATA = {
    Stats = { Level = 1, Health = 100 },
    Inventory = {},
    Currency = { Coins = 0 },
}

Players.PlayerAdded:Connect(function(player)
    local userId = player.UserId
    local success, data = pcall(function()
        return playerStore:GetAsync("Player_" .. userId)
    end)
    
    if success and data == nil then
        data = deepCopy(DEFAULT_DATA)
    elseif not success then
        print("Failed to load data: " .. tostring(data))
        player:Kick()
        return
    end
    
    local handler, ok = DataStoreHandler.New(data, player, false)
    if ok then
        handlers[player] = handler
    end
end)

Players.PlayerRemoving:Connect(function(player)
    local handler = handlers[player]
    if handler then
        local data = handler:GetRaw()
        local success, err = pcall(function()
            playerStore:SetAsync("Player_" .. player.UserId, data)
        end)
        
        if not success then
            warn("Failed to save: " .. err)
        end
        
        handler:Destroy()
        handlers[player] = nil
    end
end)

function deepCopy(t)
    local new = {}
    for k, v in t do
        new[k] = type(v) == "table" and deepCopy(v) or v
    end
    return new
end
```

---

## Advanced Examples

### Example 1: RPG Leveling System

```lua
local handler = handlers[player]

-- Level up player
local function levelUpPlayer()
    local currentLevel = handler:Get("Stats.Level") or 1
    local newLevel = currentLevel + 1
    
    local changes = {
        ["Stats.Level"] = newLevel,
        ["Stats.Experience"] = 0,
        ["Stats.HealthMax"] = 100 + (newLevel * 10),
        ["Stats.Health"] = 100 + (newLevel * 10),
        ["Stats.ManaMax"] = 50 + (newLevel * 5),
        ["Stats.Mana"] = 50 + (newLevel * 5),
        ["Achievements.Milestones.Level" .. newLevel] = true,
    }
    
    if handler:BatchSet(changes) then
        print("Level up to " .. newLevel)
    end
end

-- Grant skill
local function learnSkill(skillName, skillData)
    local skillPath = "Skills." .. skillName
    return handler:Set(skillPath, skillData)
end

learnSkill("Fireball", { Cooldown = 5, Damage = 25, ManaCost = 30 })
```

### Example 2: Inventory Management

```lua
local handler = handlers[player]

-- Add item to inventory
local function addItem(itemName, itemStats, quantity)
    quantity = quantity or 1
    
    for i = 1, quantity do
        local item = {
            Name = itemName,
            Stats = itemStats,
            Acquired = os.time(),
            Equipped = false,
            Durability = 100,
        }
        handler:AddToList("Inventory", item)
    end
end

-- Equip item
local function equipItem(index)
    -- Unequip all first
    handler:MapList("Inventory", function(item)
        item.Equipped = false
        return item
    end)
    
    -- Equip selected
    local item = handler:Get("Inventory." .. index)
    if item then
        handler:AddPropertyToListItem("Inventory." .. index .. ".Equipped", true)
        print("Equipped: " .. item.Name)
    end
end

-- Find and remove item
local function removeItemByName(itemName)
    local idx, item = handler:FindInList("Inventory", function(i)
        return i.Name == itemName
    end)
    
    if idx then
        handler:RemoveByKey("Inventory." .. idx)
        return true
    end
    return false
end

-- Get inventory value
local function getTotalInventoryValue()
    local total = 0
    local count = handler:CountList("Inventory") or 0
    
    for i = 1, count do
        local item = handler:Get("Inventory." .. i)
        if item and item.Stats and item.Stats.Value then
            total += item.Stats.Value
        end
    end
    return total
end

-- Usage
addItem("Sword", { Damage = 25, Value = 100 }, 1)
addItem("Health Potion", { Healing = 50, Value = 25 }, 5)
equipItem(1)
print("Inventory worth: " .. getTotalInventoryValue())
```

### Example 3: Save/Restore Mechanics

```lua
local handler = handlers[player]
local saveSlots = {}

-- Create save point
local function createSavePoint(slotName)
    local snapshot = handler:Snapshot()
    saveSlots[slotName] = {
        data = snapshot,
        timestamp = os.time(),
    }
    print("Saved to slot: " .. slotName)
end

-- Load save point
local function loadSavePoint(slotName)
    local slot = saveSlots[slotName]
    if not slot then
        return false
    end
    
    if handler:Restore(slot.data) then
        print("Loaded from slot: " .. slotName)
        return true
    end
    return false
end

-- Compare state
local function compareStates(slotName)
    local slot = saveSlots[slotName]
    if not slot then
        return {}
    end
    
    return handler:Diff(slot.data)
end

-- Usage
createSavePoint("before_boss")
-- Battle and take damage
handler:Set("Stats.Health", 10)
local changes = compareStates("before_boss")

for path, change in changes do
    print(path .. ": " .. change.old .. " → " .. change.new)
end

loadSavePoint("before_boss")  -- Undo changes
```

### Example 4: Trading System

```lua
local handler1 = handlers[player1]
local handler2 = handlers[player2]

-- Propose trade
local function proposeTrade(sourceHandler, targetHandler, sourceItems, targetItems, amount)
    -- Validate
    local sourceInventorySize = sourceHandler:CountList("Inventory") or 0
    if sourceInventorySize < #sourceItems then
        return false, "Not enough inventory space"
    end
    
    -- Execute (atomic)
    local success = sourceHandler:BatchSet({
        ["Inventory"] = {},  -- Clear inventory
    })
    
    if not success then
        return false, "Trade failed"
    end
    
    -- Transfer items
    for _, item in sourceItems do
        targetHandler:AddToList("Inventory", item)
    end
    
    -- Transfer currency
    targetHandler:Increment("Currency.Coins", amount)
    sourceHandler:Increment("Currency.Coins", -amount)
    
    return true
end

-- Usage
local sword = { Name = "Sword", Damage = 25 }
local shield = { Name = "Shield", Defense = 15 }

proposeTrade(handler1, handler2, { sword }, { shield }, 50)
```

### Example 5: Quest System

```lua
local handler = handlers[player]

-- Start quest
local function startQuest(questId, questData)
    local questPath = "Quests.Active." .. questId
    
    local questInfo = {
        Id = questId,
        Name = questData.Name,
        Description = questData.Description,
        Progress = 0,
        MaxProgress = questData.MaxProgress,
        Rewards = questData.Rewards,
        StartTime = os.time(),
        Status = "In Progress",
    }
    
    return handler:Set(questPath, questInfo)
end

-- Update quest progress
local function updateQuestProgress(questId, progress)
    local questPath = "Quests.Active." .. questId
    return handler:Set(questPath .. ".Progress", progress)
end

-- Complete quest
local function completeQuest(questId)
    local questPath = "Quests.Active." .. questId
    local quest = handler:Get(questPath)
    
    if not quest then
        return false
    end
    
    -- Move to completed
    handler:Set("Quests.Completed." .. questId, quest)
    handler:RemoveByKey(questPath)
    
    -- Grant rewards
    if quest.Rewards then
        for rewardType, amount in quest.Rewards do
            handler:Increment("Currency." .. rewardType, amount)
        end
    end
    
    return true
end

-- Get active quests
local function getActiveQuests()
    local quests = {}
    local activeQuestsList = handler:Get("Quests.Active") or {}
    
    for questId, questData in activeQuestsList do
        table.insert(quests, {
            Id = questId,
            Data = questData,
        })
    end
    
    return quests
end

-- Usage
startQuest("kill_goblins", {
    Name = "Kill Goblins",
    Description = "Defeat 10 goblins",
    MaxProgress = 10,
    Rewards = { Coins = 100, Experience = 500 },
})

updateQuestProgress("kill_goblins", 5)
updateQuestProgress("kill_goblins", 10)
completeQuest("kill_goblins")
```

### Example 6: Batch Compiled Paths (Performance)

```lua
-- Pre-compile frequently used paths
local PATH_COINS = { "Currency", "Coins" }
local PATH_LEVEL = { "Stats", "Level" }
local PATH_HEALTH = { "Stats", "Health" }
local PATH_MANA = { "Stats", "Mana" }
local PATH_XP = { "Stats", "Experience" }

-- Daily reward
local function grantDailyReward()
    return handler:BatchSetCompiled({
        [PATH_COINS] = (handler:Get("Currency.Coins") or 0) + 100,
        [{ "Rewards", "LastDaily" }] = os.time(),
    })
end

-- Combat system (called many times)
local function takeDamage(amount)
    local currentHealth = handler:Get("Stats.Health") or 100
    return handler:BatchSetCompiled({
        [PATH_HEALTH] = math.max(0, currentHealth - amount),
    })
end

local function gainExperience(amount)
    local currentXp = handler:Get("Stats.Experience") or 0
    local newXp = currentXp + amount
    local currentLevel = handler:Get("Stats.Level") or 1
    
    if newXp >= 1000 then
        return handler:BatchSetCompiled({
            [PATH_XP] = 0,
            [PATH_LEVEL] = currentLevel + 1,
        })
    else
        return handler:BatchSetCompiled({
            [PATH_XP] = newXp,
        })
    end
end

-- Usage (no string parsing overhead)
for i = 1, 100 do
    gainExperience(50)
end
```

---

## Performance Tips

### 1. Use Compiled Paths for Repeated Operations

```lua
-- ❌ BAD: String parsed every call
for i = 1, 1000 do
    handler:Increment("Currency.Coins", 1)
end

-- ✅ GOOD: Parse once, use many times
local PATH_COINS = { "Currency", "Coins" }
for i = 1, 1000 do
    handler:BatchSetCompiled({ [PATH_COINS] = handler:Get("Currency.Coins") + 1 })
end
```

### 2. Batch Operations Instead of Individual Calls

```lua
-- ❌ BAD: 5 individual operations
handler:Set("Stats.Level", 5)
handler:Set("Stats.Health", 100)
handler:Set("Stats.Mana", 50)
handler:Set("Currency.Coins", 1000)
handler:Set("LastUpdate", os.time())

-- ✅ GOOD: 1 atomic operation
handler:BatchSet({
    ["Stats.Level"] = 5,
    ["Stats.Health"] = 100,
    ["Stats.Mana"] = 50,
    ["Currency.Coins"] = 1000,
    ["LastUpdate"] = os.time(),
})
```

### 3. Snapshot Only What You Need

```lua
-- ❌ BAD: Copy entire data structure
local fullBackup = handler:Snapshot()

-- ✅ GOOD: Copy just the section you need
local inventoryBackup = handler:SnapshotPath("Inventory")
```

### 4. Use Copy Mode for External Data

```lua
-- Reference mode: Fast, but modifies original
local handler = DataStoreHandler.New(data, player, false)

-- Copy mode: Slightly slower, but safe
local handler = DataStoreHandler.New(data, player, true)
```

### 5. Avoid Deep Nesting

```lua
-- ❌ AVOID: Very deep structures
{
    Level1 = {
        Level2 = {
            Level3 = {
                Level4 = {
                    Value = 100
                }
            }
        }
    }
}

-- ✅ PREFER: Flatter structures
{
    Level1Value = 100,
    Level2Value = 200,
}
```

---

## Troubleshooting

### Issue: "deepCopy: maximum depth reached"

**Cause:** Data structure is too deeply nested.

**Solution:**
```lua
-- Increase max depth when creating handler
local handler, ok = DataStoreHandler.New(data, player, true, 128)  -- default is 64
```

### Issue: "deepSet: node is not a table"

**Cause:** Trying to write to a path where an intermediate node is a non-table type.

**Solution:**
```lua
-- Check before writing
if handler:Get("Path.To.Node") == nil or type(handler:Get("Path.To.Node")) == "table" then
    handler:Set("Path.To.Node.SubKey", value)
end
```

### Issue: "Cannot divide by zero"

**Cause:** Trying to divide or modulo by 0.

**Solution:**
```lua
if handler:OperateOnValue("Path", "/", 0) then
    print("Success")
else
    print("Division by zero prevented")
end
```

### Issue: BatchSet fails but some changes applied

**Cause:** This shouldn't happen—BatchSet is atomic. If it fails, no changes apply.

**Debug:**
```lua
local success = handler:BatchSet(changes)
if not success then
    -- Check console for warnings
    -- No changes were applied
end
```

### Issue: Performance is slow

**Causes & Solutions:**
1. String parsing every call → Use compiled paths
2. Individual operations → Use BatchSet
3. Copying huge structures → Use SnapshotPath
4. Deep structures → Flatten or increase maxDepth carefully

---

## Best Practices Checklist

- ✅ Use dot-notation paths for clarity
- ✅ Batch related operations together
- ✅ Pre-compile frequently used paths
- ✅ Check return values (boolean success flags)
- ✅ Use Snapshot before risky operations
- ✅ Call Destroy() when done
- ✅ Use copy mode for external/test data
- ✅ Validate data before writing
- ✅ Handle ProfileService/DataStore2 profile releases
- ✅ Keep data structures relatively flat
- ✅ Use typed paths with compiled constants
- ✅ Monitor for circular references in deep data

---

## Complete Working Example

```lua
local Players = game:GetService("Players")
local DataStoreHandler = require(game.ServerScriptService.DataStoreHandler)

-- Pre-compiled paths for performance
local PATHS = {
    LEVEL = { "Stats", "Level" },
    HEALTH = { "Stats", "Health" },
    COINS = { "Currency", "Coins" },
    INVENTORY = { "Inventory" },
}

local handlers = {}

-- Player joins
Players.PlayerAdded:Connect(function(player)
    local data = {
        Stats = { Level = 1, Health = 100, Experience = 0 },
        Currency = { Coins = 0, Gems = 0 },
        Inventory = {},
        Settings = { Volume = 1.0 },
    }
    
    local handler, ok = DataStoreHandler.New(data, player, false)
    if ok then
        handlers[player] = handler
        print("Handler created for " .. player.Name)
    else
        player:Kick("Failed to create handler")
    end
end)

-- Player leaves
Players.PlayerRemoving:Connect(function(player)
    local handler = handlers[player]
    if handler then
        local data = handler:GetRaw()
        -- Save data here
        handler:Destroy()
        handlers[player] = nil
    end
end)

-- Give reward
local function giveReward(player, coins, xp)
    local handler = handlers[player]
    if not handler then return end
    
    handler:BatchSetCompiled({
        [PATHS.COINS] = (handler:Get("Currency.Coins") or 0) + coins,
        [PATHS.XP] = (handler:Get("Stats.Experience") or 0) + xp,
    })
end

-- Test
giveReward(game.Players.Player1, 100, 50)
```

---
