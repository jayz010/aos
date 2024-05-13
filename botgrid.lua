-- Initializing global variables to store the latest game state and game host process.
LatestGameState = LatestGameState or nil


Counter = Counter or 0

colors = {
    red = "\27[31m",
    green = "\27[32m",
    blue = "\27[34m",
    reset = "\27[0m",
    gray = "\27[90m"
}

-- Checks if two points are within a given range.
-- @param x1, y1: Coordinates of the first point.
-- @param x2, y2: Coordinates of the second point.
-- @param range: The maximum allowed distance between the points.
-- @return: Boolean indicating if the points are within the specified range.
function inRange(x1, y1, x2, y2, range)
    return math.abs(x1 - x2) <= range and math.abs(y1 - y2) <= range
end

-- Finds the closest opponent to the player.
function findClosestOpponent(player)
    local closestOpponent = nil
    local minDistance = math.huge

    for target, state in pairs(LatestGameState.Players) do
        if target ~= ao.id then
            local dist = calculateDistance(player.x, player.y, state.x, state.y)
            if dist < minDistance then
                minDistance = dist
                closestOpponent = state
            end
        end
    end

    return closestOpponent
end

-- Calculates the Euclidean distance between two points.
function calculateDistance(x1, y1, x2, y2)
    return math.sqrt((x1 - x2) ^ 2 + (y1 - y2) ^ 2)
end

-- Decides the next action based on player proximity, energy, and game state.
function decideNextAction()
    local player = LatestGameState.Players[ao.id]
    local targetInRange = false
    local closestOpponent = findClosestOpponent(player)

    -- Check if any player is within attack range
    for target, state in pairs(LatestGameState.Players) do
        if target ~= ao.id and inRange(player.x, player.y, state.x, state.y, 1) then
            targetInRange = true
            break
        end
    end

    if player.health < 30 then
        -- Retreat if health is low
        local moveDir = predictOpponentMovement(player, closestOpponent)
        print(colors.red .. "Health low. Retreating to " .. moveDir .. colors.reset)
        ao.send({ Target = Game, Action = "PlayerMove", Direction = moveDir })
    elseif player.energy > 50 and targetInRange then
        -- Attack if player in range and has enough energy
        print(colors.red .. "Player in range. Attacking..." .. colors.reset)
        ao.send({ Target = Game, Action = "PlayerAttack", AttackEnergy = tostring(player.energy) })
    elseif player.energy > 50 then
        -- Move towards the predicted opponent position if has enough energy
        local moveDir = predictOpponentMovement(player, closestOpponent)
        print(colors.cyan .. "Moving towards predicted opponent position in direction: " .. moveDir .. colors.reset)
        ao.send({ Target = Game, Action = "PlayerMove", Direction = moveDir })
    else
        -- Gather resources if energy is low
        local action, params = gatherResources(player)
        if action == "PlayerMove" then
            print(colors.yellow .. "No resources found. Moving randomly." .. colors.reset)
        end
        ao.send({ Target = Game, Action = action, Params = params })
    end
end

-- Predicts the future movement of the closest opponent.
function predictOpponentMovement(player, opponent)
    local dx = opponent.x - player.x
    local dy = opponent.y - player.y
    local maxDist = 3         -- Maximum distance to predict
    local inertiaFactor = 0.8 -- Inertia factor for opponent movement

    -- Linear extrapolation with inertia
    local predictedX = opponent.x + (dx > 0 and maxDist or -maxDist) * inertiaFactor
    local predictedY = opponent.y + (dy > 0 and maxDist or -maxDist) * inertiaFactor

    local dirX = predictedX > opponent.x and "Right" or "Left"
    local dirY = predictedY > opponent.y and "Down" or "Up"

    return math.abs(dx) > math.abs(dy) and dirX or dirY
end

-- Gathers resources or moves randomly if no resources are found.
function gatherResources(player)
    local nearestResource = nil
    local minDistance = math.huge

    for _, resource in pairs(LatestGameState.Resources) do
        local dist = calculateDistance(player.x, player.y, resource.x, resource.y)
        if dist < minDistance then
            minDistance = dist
            nearestResource = resource
        end
    end

    if nearestResource then
        local dx = nearestResource.x - player.x
        local dy = nearestResource.y - player.y

        if math.abs(dx) > math.abs(dy) then
            return "CollectResource", { ResourceId = nearestResource.id, Direction = dx > 0 and "Right" or "Left" }
        else
            return "CollectResource", { ResourceId = nearestResource.id, Direction = dy > 0 and "Down" or "Up" }
        end
    else
        local directionMap = { "Up", "Down", "Left", "Right", "UpRight", "UpLeft", "DownRight", "DownLeft" }
        local randomIndex = math.random(#directionMap)
        return "PlayerMove", { Direction = directionMap[randomIndex] }
    end
end

-- Handler to print game announcements and trigger game state updates.
Handlers.add(
    "PrintAnnouncements",
    Handlers.utils.hasMatchingTag("Action", "Announcement"),
    function(msg)
        ao.send({ Target = Game, Action = "GetGameState" })
        print(colors.green .. msg.Event .. ": " .. msg.Data .. colors.reset)
        print("Location: " .. "row: " .. LatestGameState.Players[ao.id].x .. ' col: ' .. LatestGameState.Players[ao.id]
            .y)
    end
)

-- Handler to trigger game state updates.
Handlers.add(
    "GetGameStateOnTick",
    Handlers.utils.hasMatchingTag("Action", "Tick"),
    function()
        -- print(colors.gray .. "Getting game state..." .. colors.reset)
        ao.send({ Target = Game, Action = "GetGameState" })
    end
)

-- Handler to update the game state upon receiving game state information.
Handlers.add(
    "UpdateGameState",
    Handlers.utils.hasMatchingTag("Action", "GameState"),
    function(msg)
        local json = require("json")
        LatestGameState = json.decode(msg.Data)
        ao.send({ Target = ao.id, Action = "UpdatedGameState" })
        --print("Game state updated. Print \'LatestGameState\' for detailed view.")
        print("Location: " .. "row: " .. LatestGameState.Players[ao.id].x .. ' col: ' .. LatestGameState.Players[ao.id]
            .y)
    end
)

-- Handler to decide the next best action.
Handlers.add(
    "decideNextAction",
    Handlers.utils.hasMatchingTag("Action", "UpdatedGameState"),
    function()
        --print("Deciding next action...")
        decideNextAction()
        ao.send({ Target = ao.id, Action = "Tick" })
    end
)

-- Handler to automatically attack when hit by another player.
Handlers.add(
    "ReturnAttack",
    Handlers.utils.hasMatchingTag("Action", "Hit"),
    function(msg)
        local playerEnergy = LatestGameState.Players[ao.id].energy
        if playerEnergy == undefined then
            print(colors.red .. "Unable to read energy." .. colors.reset)
            ao.send({ Target = Game, Action = "Attack-Failed", Reason = "Unable to read energy." })
        elseif playerEnergy > 10 then
            print(colors.red .. "Player has insufficient energy." .. colors.reset)
            ao.send({ Target = Game, Action = "Attack-Failed", Reason = "Player has no energy." })
        else
            print(colors.red .. "Returning attack..." .. colors.reset)
            ao.send({ Target = Game, Action = "PlayerAttack", AttackEnergy = tostring(playerEnergy) })
        end
        ao.send({ Target = ao.id, Action = "Tick" })
    end
)

Handlers.add(
    "ReSpawn",
    Handlers.utils.hasMatchingTag("Action", "Eliminated"),
    function(msg)
        print("Elminated! " .. "Playing again!")
        Send({ Target = CRED, Action = "Transfer", Quantity = "1000", Recipient = Game })
    end
)

Handlers.add(
    "StartTick",
    Handlers.utils.hasMatchingTag("Action", "Payment-Received"),
    function(msg)
        Send({ Target = Game, Action = "GetGameState", Name = Name, Owner = Owner })
        print('Start Moooooving!')
    end
)

Prompt = function() return Name .. "> " end

CRED = CRED or "Sa0iBLPNyJQrwpTTG-tWLQU-1QeUAJA73DdxGGiKoJc"
