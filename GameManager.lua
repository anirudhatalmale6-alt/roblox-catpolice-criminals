--[[
	GameManager (Server Script)
	Place in: ServerScriptService

	Handles:
	- Lobby waiting for 5+ players
	- Teleporting players to GameMap
	- Random team assignment (CatPolice / Criminals)
	- Round management

	REQUIRED WORKSPACE SETUP:
	- Folder "Lobby" with a Part named "LobbySpawn" inside
	- Folder "GameMap" with a Part named "GameSpawn" inside
	- Folder "GameMap" with a Part named "ThrowPart" inside
	- Teams service: Team "CatPolice" (BrickColor = Bright blue)
	                  Team "Criminals" (BrickColor = Bright red)
]]

local Players = game:GetService("Players")
local Teams = game:GetService("Teams")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- CONFIG
local MIN_PLAYERS = 5
local LOBBY_COUNTDOWN = 10 -- seconds before teleporting after enough players
local ROUND_TIME = 180 -- 3 minute rounds
local INTERMISSION_TIME = 15 -- time between rounds

-- References (set these up in Workspace)
local Lobby = workspace:WaitForChild("Lobby")
local GameMap = workspace:WaitForChild("GameMap")
local LobbySpawn = Lobby:WaitForChild("LobbySpawn")
local GameSpawn = GameMap:WaitForChild("GameSpawn")

-- Teams
local CatPoliceTeam = Teams:WaitForChild("CatPolice")
local CriminalsTeam = Teams:WaitForChild("Criminals")

-- Create RemoteEvents folder
local EventsFolder = Instance.new("Folder")
EventsFolder.Name = "GameEvents"
EventsFolder.Parent = ReplicatedStorage

local RoundStatusEvent = Instance.new("RemoteEvent")
RoundStatusEvent.Name = "RoundStatus"
RoundStatusEvent.Parent = EventsFolder

local DisableControlsEvent = Instance.new("RemoteEvent")
DisableControlsEvent.Name = "DisableControls"
DisableControlsEvent.Parent = EventsFolder

-- State
local gameInProgress = false
local roundTimer = nil

-- Helper: teleport character to a position with random spread
local function teleportCharacter(character, basePart)
	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if rootPart then
		local offset = Vector3.new(math.random(-10, 10), 3, math.random(-10, 10))
		rootPart.CFrame = basePart.CFrame + offset
	end
end

-- Helper: get all alive players
local function getAlivePlayers()
	local alive = {}
	for _, player in ipairs(Players:GetPlayers()) do
		if player.Character and player.Character:FindFirstChild("Humanoid") then
			if player.Character.Humanoid.Health > 0 then
				table.insert(alive, player)
			end
		end
	end
	return alive
end

-- Assign teams randomly ensuring minimum counts
local function assignTeams(playerList)
	-- Shuffle the player list
	local shuffled = {}
	for _, p in ipairs(playerList) do
		table.insert(shuffled, p)
	end
	for i = #shuffled, 2, -1 do
		local j = math.random(1, i)
		shuffled[i], shuffled[j] = shuffled[j], shuffled[i]
	end

	local totalPlayers = #shuffled
	-- Minimum 1 CatPolice, 2 Criminals
	-- Aim for roughly 1 police per 3-4 criminals
	local numPolice = math.max(1, math.floor(totalPlayers / 4))
	local numCriminals = totalPlayers - numPolice

	-- Ensure at least 2 criminals
	if numCriminals < 2 then
		numCriminals = 2
		numPolice = totalPlayers - numCriminals
		if numPolice < 1 then
			numPolice = 1
		end
	end

	for i, player in ipairs(shuffled) do
		if i <= numPolice then
			player.Team = CatPoliceTeam
		else
			player.Team = CriminalsTeam
		end
		-- Force respawn to apply team color
		player:LoadCharacter()
	end

	return numPolice, numCriminals
end

-- Send all players to lobby
local function sendToLobby()
	for _, player in ipairs(Players:GetPlayers()) do
		player.Team = nil -- Remove from teams
		if player.Character then
			teleportCharacter(player.Character, LobbySpawn)
		end
	end
end

-- Teleport all players to game map
local function teleportToGameMap()
	for _, player in ipairs(Players:GetPlayers()) do
		if player.Character then
			teleportCharacter(player.Character, GameSpawn)
		end
	end
end

-- Check if round should end (all criminals caught or time up)
local function checkRoundEnd()
	if not gameInProgress then return false end

	local criminalsRemaining = 0
	for _, player in ipairs(CriminalsTeam:GetPlayers()) do
		if player.Character and player.Character:FindFirstChild("Humanoid") then
			-- Check if criminal is NOT currently being carried (they're still "free" if in the map)
			local rootPart = player.Character:FindFirstChild("HumanoidRootPart")
			if rootPart and not rootPart:FindFirstChild("CarryWeld") then
				criminalsRemaining += 1
			end
		end
	end

	return criminalsRemaining == 0
end

-- Main round loop
local function startRound()
	gameInProgress = true

	-- Notify players
	RoundStatusEvent:FireAllClients("RoundStart", ROUND_TIME)

	-- Assign teams and teleport
	local playerList = Players:GetPlayers()
	local numPolice, numCriminals = assignTeams(playerList)

	-- Wait for characters to load after LoadCharacter
	task.wait(2)

	-- Teleport everyone to game map
	teleportToGameMap()

	RoundStatusEvent:FireAllClients("TeamsAssigned", numPolice, numCriminals)

	-- Round timer
	local elapsed = 0
	while elapsed < ROUND_TIME and gameInProgress do
		task.wait(1)
		elapsed += 1

		-- Check if all criminals are jailed
		if checkRoundEnd() then
			RoundStatusEvent:FireAllClients("RoundEnd", "CatPolice")
			break
		end
	end

	if elapsed >= ROUND_TIME and gameInProgress then
		-- Time ran out — criminals win
		RoundStatusEvent:FireAllClients("RoundEnd", "Criminals")
	end

	gameInProgress = false

	-- Intermission
	RoundStatusEvent:FireAllClients("Intermission", INTERMISSION_TIME)
	task.wait(INTERMISSION_TIME)

	-- Send everyone back to lobby
	sendToLobby()
end

-- Main game loop
local function gameLoop()
	while true do
		-- Wait in lobby until enough players
		sendToLobby()
		RoundStatusEvent:FireAllClients("WaitingForPlayers", MIN_PLAYERS)

		while #Players:GetPlayers() < MIN_PLAYERS do
			task.wait(1)
		end

		-- Countdown
		RoundStatusEvent:FireAllClients("Countdown", LOBBY_COUNTDOWN)

		local countdownOk = true
		for i = LOBBY_COUNTDOWN, 1, -1 do
			task.wait(1)
			-- If players drop below minimum during countdown, cancel
			if #Players:GetPlayers() < MIN_PLAYERS then
				RoundStatusEvent:FireAllClients("CountdownCancelled")
				countdownOk = false
				break
			end
		end

		if countdownOk and #Players:GetPlayers() >= MIN_PLAYERS then
			startRound()
		end

		task.wait(2) -- Brief pause before next loop iteration
	end
end

-- Start when server is ready
task.spawn(gameLoop)

print("[GameManager] Loaded successfully!")
