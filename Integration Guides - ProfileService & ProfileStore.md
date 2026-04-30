# Integration Guides - ProfileService & ProfileStore

1. [ProfileService Integration](#profileservice-integration)
2. [ProfileStore Integration](#profilestore-integration)
3. [Comparison: ProfileService vs ProfileStore](#comparison-profileservice-vs-profilestore)
4. [Migration Guide](#migration-guide)
5. [Advanced Patterns](#advanced-patterns)

---

## ProfileService Integration

### Overview

**ProfileService** is a stand-alone module for loading and auto-saving DataStore profiles. It provides:
- Session-locking to prevent data conflicts
- Auto-saving at configurable intervals
- Profile versioning and reconciliation
- Global updates and meta-tags

**Key concept:** A Profile is loaded once on the server and cached locally. No DataStore delays on every read/write.

### Installation

```lua
-- ProfileService is available on the Roblox library
-- Place it in ServerScriptService or ReplicatedStorage
```

### Basic Setup with DataStoreHandler

```lua
local Players = game:GetService("Players")
local DataStoreHandler = require(game.ServerScriptService.DataStoreHandler)
local ProfileService = require(game.ServerScriptService.ProfileService)

-- Configuration
local PROFILE_STORE_NAME = "PlayerProfiles"
local PROFILE_TEMPLATE = {
    Version = 1,
    Stats = {
        Level = 1,
        Health = 100,
        MaxHealth = 100,
        Experience = 0,
    },
    Inventory = {},
    Currency = {
        Coins = 0,
        Gems = 0,
    },
    Settings = {
        Volume = 1.0,
        Brightness = 1.0,
    },
    Achievements = {},
}

-- Store references
local ProfileStore = ProfileService.GetProfileStore(PROFILE_STORE_NAME, PROFILE_TEMPLATE)
local PlayerHandlers = {}

-- Player joins
Players.PlayerAdded:Connect(function(player)
    -- Load profile from ProfileService
    local profile = ProfileStore:LoadProfileAsync("Player_" .. player.UserId)
    
    -- Handle load failure
    if not profile then
        player:Kick("Failed to load profile - try rejoining")
        return
    end
    
    -- Reconcile to fill missing keys with defaults
    profile:Reconcile()
    
    -- Bind release event (player kicked or server shutting down)
    profile:ListenToRelease(function()
        PlayerHandlers[player] = nil
        if player.Parent then
            player:Kick("Profile released (server shutting down?)")
        end
    end)
    
    -- Create DataStoreHandler (reference mode = direct sync with ProfileService)
    local handler, success = DataStoreHandler.New(profile.Data, player, false)
    
    if not success then
        profile:Release()
        player:Kick("Failed to create data handler")
        return
    end
    
    -- Store reference
    PlayerHandlers[player] = {
        Handler = handler,
        Profile = profile,
    }
    
    print("✓ Profile loaded for " .. player.Name)
    
    -- Fire custom event or event signal
    game:GetService("RunService").Heartbeat:Wait()
    print("Handler ready for " .. player.Name)
end)

-- Player leaves
Players.PlayerRemoving:Connect(function(player)
    local session = PlayerHandlers[player]
    if session then
        -- Handler will auto-save through ProfileService
        session.Handler:Destroy()
        session.Profile:Release()
        PlayerHandlers[player] = nil
        print("✓ Profile saved and released for " .. player.Name)
    end
end)

-- Helper function to get handler
local function GetHandler(player)
    local session = PlayerHandlers[player]
    return session and session.Handler or nil
end

-- Helper function to get profile
local function GetProfile(player)
    local session = PlayerHandlers[player]
    return session and session.Profile or nil
end
```

### Complete Example: Player Joining with Stats Display

```lua
-- In a separate script or continued from above

local Players = game:GetService("Players")

Players.CharacterAdded:Connect(function(character)
    local player = Players:GetPlayerFromCharacter(character)
    local handler = GetHandler(player)
    
    if not handler then return end
    
    -- Load player stats from handler
    local level = handler:Get("Stats.Level") or 1
    local health = handler:Get("Stats.Health") or 100
    local maxHealth = handler:Get("Stats.MaxHealth") or 100
    
    -- Apply to character
    local humanoid = character:WaitForChild("Humanoid")
    humanoid.MaxHealth = maxHealth
    humanoid.Health = health
    
    print(player.Name .. " spawned at Level " .. level)
    
    -- Damage tracking
    local lastHealth = health
    humanoid.HealthChanged:Connect(function(newHealth)
        local damage = lastHealth - newHealth
        if damage > 0 then
            handler:Set("Stats.Health", newHealth)
            lastHealth = newHealth
        end
    end)
end)
```

### Adding Coins System

```lua
local function AddCoins(player, amount)
    local handler = GetHandler(player)
    if not handler then return false end
    
    local currentCoins = handler:Get("Currency.Coins") or 0
    return handler:Set("Currency.Coins", currentCoins + amount)
end

local function GetCoins(player)
    local handler = GetHandler(player)
    if not handler then return 0 end
    
    return handler:Get("Currency.Coins") or 0
end

local function RemoveCoins(player, amount)
    local handler = GetHandler(player)
    if not handler then return false end
    
    local currentCoins = handler:Get("Currency.Coins") or 0
    if currentCoins < amount then
        return false  -- Not enough coins
    end
    
    return handler:Set("Currency.Coins", currentCoins - amount)
end

-- Usage
AddCoins(game.Players.Player1, 100)
print("Coins: " .. GetCoins(game.Players.Player1))
RemoveCoins(game.Players.Player1, 50)
```

### Level Up System with ProfileService

```lua
local function LevelUpPlayer(player)
    local handler = GetHandler(player)
    if not handler then return false end
    
    local currentLevel = handler:Get("Stats.Level") or 1
    local newLevel = currentLevel + 1
    
    -- Atomic update
    local success = handler:BatchSet({
        ["Stats.Level"] = newLevel,
        ["Stats.Experience"] = 0,
        ["Stats.MaxHealth"] = 100 + (newLevel * 10),
        ["Stats.Health"] = 100 + (newLevel * 10),
        ["Achievements.ReachedLevel" .. newLevel] = os.time(),
    })
    
    if success then
        print(player.Name .. " reached Level " .. newLevel)
        
        -- Update character if spawned
        if player.Character then
            local humanoid = player.Character:FindFirstChild("Humanoid")
            if humanoid then
                humanoid.MaxHealth = 100 + (newLevel * 10)
                humanoid.Health = humanoid.MaxHealth
            end
        end
    end
    
    return success
end

-- Usage
LevelUpPlayer(game.Players.Player1)
```

### Inventory Management with ProfileService

```lua
local function AddInventoryItem(player, itemName, itemData)
    local handler = GetHandler(player)
    if not handler then return false end
    
    local item = {
        Name = itemName,
        Data = itemData,
        AddedTime = os.time(),
    }
    
    return handler:AddToList("Inventory", item)
end

local function GetInventoryCount(player)
    local handler = GetHandler(player)
    if not handler then return 0 end
    
    return handler:CountList("Inventory") or 0
end

local function RemoveInventoryItemByName(player, itemName)
    local handler = GetHandler(player)
    if not handler then return false end
    
    local index, item = handler:FindInList("Inventory", function(i)
        return i.Name == itemName
    end)
    
    if index then
        return handler:RemoveByKey("Inventory." .. index)
    end
    
    return false
end

local function GetInventory(player)
    local handler = GetHandler(player)
    if not handler then return {} end
    
    return handler:Get("Inventory") or {}
end

-- Usage
AddInventoryItem(game.Players.Player1, "Sword", { Damage = 25, Rarity = "Common" })
AddInventoryItem(game.Players.Player1, "Shield", { Defense = 15, Rarity = "Uncommon" })

print("Inventory items: " .. GetInventoryCount(game.Players.Player1))
RemoveInventoryItemByName(game.Players.Player1, "Sword")
```

### Handling Profile Release

```lua
-- ProfileService will automatically release profiles when:
-- 1. Server shuts down
-- 2. Player leaves
-- 3. You manually call profile:Release()

local function ForceReleaseProfile(player)
    local session = PlayerHandlers[player]
    if session then
        session.Handler:Destroy()
        session.Profile:Release()
        PlayerHandlers[player] = nil
        print("✓ Manually released profile for " .. player.Name)
    end
end

-- Example: Release if inactive for 30 minutes
local lastActivity = {}

Players.PlayerAdded:Connect(function(player)
    lastActivity[player] = tick()
end)

game:GetService("RunService").Heartbeat:Connect(function()
    for player, lastTime in pairs(lastActivity) do
        if tick() - lastTime > 1800 then  -- 30 minutes
            print("Releasing inactive player: " .. player.Name)
            ForceReleaseProfile(player)
            lastActivity[player] = nil
        end
    end
end)
```

---

## ProfileStore Integration

### Overview

**ProfileStore** is the newer successor to ProfileService with improvements:
- Cleaner API
- Better performance
- Improved session-locking
- Automatic profile versioning
- Built for scalability

**Key features:**
- `:StartSessionAsync()` for session control
- Automatic periodic saving
- Meta-tags and global updates support

### Installation

```lua
-- Get ProfileStore from Roblox library or GitHub
-- Place in ServerScriptService or ReplicatedStorage
```

### Basic Setup with DataStoreHandler

```lua
local Players = game:GetService("Players")
local DataStoreHandler = require(game.ServerScriptService.DataStoreHandler)
local ProfileStore = require(game.ServerScriptService.ProfileStore)

-- Configuration
local PROFILE_STORE = ProfileStore.new("PlayerData", {
    Version = 1,
    Stats = {
        Level = 1,
        Health = 100,
        MaxHealth = 100,
        Experience = 0,
    },
    Inventory = {},
    Currency = {
        Coins = 0,
        Gems = 0,
    },
    Quests = {
        Active = {},
        Completed = {},
    },
    Achievements = {},
})

local PlayerHandlers = {}

Players.PlayerAdded:Connect(function(player)
    local userId = tostring(player.UserId)
    
    -- Start session
    PROFILE_STORE:StartSessionAsync(userId, function(loadedData)
        -- loadedData is the saved profile data
        -- If nil, ProfileStore will use the template
        
        if loadedData then
            print("✓ Loaded existing profile for " .. player.Name)
        else
            print("✓ Created new profile for " .. player.Name)
        end
        
        return true  -- Accept the loaded data
    end, function(playerLeft)
        -- Called when player leaves or session ends
        print("Session ended for " .. player.Name)
    end)
    
    -- Wait a frame for session to start
    task.wait()
    
    -- Get the profile data
    local profileData = PROFILE_STORE:GetAsync(userId)
    
    if not profileData then
        player:Kick("Failed to load profile")
        return
    end
    
    -- Create DataStoreHandler
    local handler, success = DataStoreHandler.New(profileData, player, false)
    
    if not success then
        player:Kick("Failed to create handler")
        return
    end
    
    PlayerHandlers[player] = {
        Handler = handler,
        UserId = userId,
    }
    
    print("✓ DataStoreHandler ready for " .. player.Name)
end)

Players.PlayerRemoving:Connect(function(player)
    local session = PlayerHandlers[player]
    if session then
        local userId = session.UserId
        
        -- Save the data
        local data = session.Handler:GetRaw()
        PROFILE_STORE:SaveAsync(userId, data)
        
        -- Cleanup
        session.Handler:Destroy()
        PROFILE_STORE:EndSessionAsync(userId)
        PlayerHandlers[player] = nil
        
        print("✓ Profile saved for " .. player.Name)
    end
end)

local function GetHandler(player)
    local session = PlayerHandlers[player]
    return session and session.Handler or nil
end
```

### Complete Example: ProfileStore with Auto-Save

```lua
local AUTO_SAVE_INTERVAL = 300  -- Save every 5 minutes

local function StartAutoSave()
    while true do
        task.wait(AUTO_SAVE_INTERVAL)
        
        for player, session in pairs(PlayerHandlers) do
            if player.Parent then  -- Player still in game
                local data = session.Handler:GetRaw()
                PROFILE_STORE:SaveAsync(session.UserId, data)
                print("✓ Auto-saved for " .. player.Name)
            end
        end
    end
end

-- Start auto-save in background
task.spawn(StartAutoSave)
```

### Quest System with ProfileStore

```lua
local function StartQuest(player, questId, questData)
    local handler = GetHandler(player)
    if not handler then return false end
    
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
    
    return handler:Set("Quests.Active." .. questId, questInfo)
end

local function UpdateQuestProgress(player, questId, progress)
    local handler = GetHandler(player)
    if not handler then return false end
    
    local questPath = "Quests.Active." .. questId
    local quest = handler:Get(questPath)
    
    if not quest then return false end
    
    -- Update progress
    local success = handler:Set(questPath .. ".Progress", progress)
    
    -- Check if complete
    if progress >= quest.MaxProgress then
        CompleteQuest(player, questId)
    end
    
    return success
end

local function CompleteQuest(player, questId)
    local handler = GetHandler(player)
    if not handler then return false end
    
    local questPath = "Quests.Active." .. questId
    local quest = handler:Get(questPath)
    
    if not quest then return false end
    
    -- Move to completed
    handler:Set("Quests.Completed." .. questId, quest)
    handler:RemoveByKey(questPath)
    
    -- Grant rewards
    if quest.Rewards then
        if quest.Rewards.Coins then
            handler:Increment("Currency.Coins", quest.Rewards.Coins)
        end
        if quest.Rewards.Experience then
            handler:Increment("Stats.Experience", quest.Rewards.Experience)
        end
    end
    
    print("✓ Quest completed: " .. quest.Name)
    return true
end

-- Usage
StartQuest(game.Players.Player1, "kill_goblins", {
    Name = "Kill Goblins",
    Description = "Defeat 10 goblins",
    MaxProgress = 10,
    Rewards = { Coins = 100, Experience = 500 },
})

UpdateQuestProgress(game.Players.Player1, "kill_goblins", 5)
UpdateQuestProgress(game.Players.Player1, "kill_goblins", 10)  -- Auto-completes
```

### Trading System with ProfileStore

```lua
local function ProposeTrade(player1, player2, items1, items2, coins1, coins2)
    local handler1 = GetHandler(player1)
    local handler2 = GetHandler(player2)
    
    if not handler1 or not handler2 then
        return false, "Handler not found"
    end
    
    -- Validate player1 has items
    local inv1 = handler1:Get("Inventory") or {}
    if #inv1 < #items1 then
        return false, "Not enough items for player1"
    end
    
    -- Validate player2 has coins
    local coins2Actual = handler2:Get("Currency.Coins") or 0
    if coins2Actual < coins2 then
        return false, "Not enough coins for player2"
    end
    
    -- Atomic trade (both or neither)
    -- Note: This uses two separate handlers, so it's not truly atomic
    -- For true atomicity, you'd need custom logic or use OrderedDataStore
    
    local success1 = handler1:BatchSet({
        ["Currency.Coins"] = (handler1:Get("Currency.Coins") or 0) + coins1,
        ["Inventory"] = {},  -- Remove items
    })
    
    local success2 = handler2:BatchSet({
        ["Currency.Coins"] = coins2Actual - coins2,
        ["Inventory"] = items1,  -- Receive items
    })
    
    if success1 and success2 then
        print("✓ Trade completed between " .. player1.Name .. " and " .. player2.Name)
        return true
    else
        print("✗ Trade failed - partial rollback needed")
        return false, "Trade failed - check console"
    end
end

-- Usage
ProposeTrade(player1, player2, item1, item2, 100, 50)
```

---

## Migration Guide

### From ProfileService to ProfileStore

If you're migrating from ProfileService to ProfileStore:

```lua
-- OLD (ProfileService)
local ProfileStore = ProfileService.GetProfileStore(STORE_NAME, TEMPLATE)
local profile = ProfileStore:LoadProfileAsync("Player_" .. player.UserId)
profile:Reconcile()

-- NEW (ProfileStore)
local ProfileStore = require(...).new("PlayerData", TEMPLATE)
ProfileStore:StartSessionAsync(userId, function(loadedData)
    return true
end)

local profileData = ProfileStore:GetAsync(userId)
```

### Update DataStoreHandler Code

No changes needed to DataStoreHandler integration! Just update the profile loading:

```lua
-- Before (ProfileService)
local profile = ProfileStore:LoadProfileAsync("Player_" .. player.UserId)
local handler = DataStoreHandler.New(profile.Data, player, false)

-- After (ProfileStore)
local profileData = ProfileStore:GetAsync(userId)
local handler = DataStoreHandler.New(profileData, player, false)
```

---

## Advanced Patterns

### Pattern 1: Profile Caching

```lua
local ProfileCache = {}

local function GetOrLoadProfile(player)
    local userId = player.UserId
    
    if not ProfileCache[userId] then
        -- Load from ProfileStore
        local profile = PROFILE_STORE:GetAsync(tostring(userId))
        ProfileCache[userId] = DataStoreHandler.New(profile, player, false)
    end
    
    return ProfileCache[userId]
end
```

### Pattern 2: Batch Profile Updates

```lua
local function BulkUpdateProfiles(updateFunction)
    for player, session in pairs(PlayerHandlers) do
        if player.Parent then
            updateFunction(session.Handler)
        end
    end
    
    -- Auto-save all
    for player, session in pairs(PlayerHandlers) do
        if player.Parent then
            local data = session.Handler:GetRaw()
            PROFILE_STORE:SaveAsync(session.UserId, data)
        end
    end
end

-- Usage: Give everyone 100 coins
BulkUpdateProfiles(function(handler)
    handler:Increment("Currency.Coins", 100)
end)
```

### Pattern 3: Profile Snapshots for Backups

```lua
local function BackupProfile(player)
    local handler = GetHandler(player)
    if not handler then return end
    
    local backup = handler:Snapshot()
    local backupStore = game:GetService("DataStoreService"):GetDataStore("ProfileBackups")
    
    local userId = tostring(player.UserId)
    local success, err = pcall(function()
        backupStore:SetAsync(userId .. "_" .. os.time(), backup)
    end)
    
    if success then
        print("✓ Profile backed up for " .. player.Name)
    end
end

-- Backup all profiles on shutdown
game:BindToClose(function()
    for player in pairs(PlayerHandlers) do
        BackupProfile(player)
    end
end)
```

### Pattern 4: Profile Validation

```lua
local function ValidateProfile(handler)
    -- Check required fields
    if not handler:Has("Stats") then
        handler:Set("Stats", { Level = 1 })
    end
    
    if not handler:Has("Inventory") then
        handler:Set("Inventory", {})
    end
    
    -- Validate ranges
    local level = handler:Get("Stats.Level") or 1
    if level < 1 then
        handler:Set("Stats.Level", 1)
    end
    if level > 1000 then
        handler:Set("Stats.Level", 1000)
    end
    
    print("✓ Profile validated")
end

-- Use after loading
local handler, success = DataStoreHandler.New(profileData, player, false)
if success then
    ValidateProfile(handler)
end
```

---
