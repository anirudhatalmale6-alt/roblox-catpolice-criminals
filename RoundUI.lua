--[[
	RoundUI (LocalScript)
	Place in: StarterPlayer > StarterPlayerScripts

	Displays round status, countdown timer, and team info on screen.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- Wait for events
local EventsFolder = ReplicatedStorage:WaitForChild("GameEvents")
local RoundStatusEvent = EventsFolder:WaitForChild("RoundStatus")
local CarryStatusEvent = EventsFolder:WaitForChild("CarryStatus")

-- Create UI
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "RoundUI"
screenGui.ResetOnSpawn = false
screenGui.Parent = playerGui

-- Main status label (top center)
local statusFrame = Instance.new("Frame")
statusFrame.Name = "StatusFrame"
statusFrame.Size = UDim2.new(0, 400, 0, 60)
statusFrame.Position = UDim2.new(0.5, -200, 0, 10)
statusFrame.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
statusFrame.BackgroundTransparency = 0.3
statusFrame.BorderSizePixel = 0
statusFrame.Parent = screenGui

local statusCorner = Instance.new("UICorner")
statusCorner.CornerRadius = UDim.new(0, 12)
statusCorner.Parent = statusFrame

local statusLabel = Instance.new("TextLabel")
statusLabel.Name = "StatusLabel"
statusLabel.Size = UDim2.new(1, -20, 1, 0)
statusLabel.Position = UDim2.new(0, 10, 0, 0)
statusLabel.BackgroundTransparency = 1
statusLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
statusLabel.Font = Enum.Font.GothamBold
statusLabel.TextSize = 22
statusLabel.Text = "Waiting for players..."
statusLabel.TextWrapped = true
statusLabel.Parent = statusFrame

-- Notification label (center, fades out)
local notifyLabel = Instance.new("TextLabel")
notifyLabel.Name = "NotifyLabel"
notifyLabel.Size = UDim2.new(0, 500, 0, 50)
notifyLabel.Position = UDim2.new(0.5, -250, 0.35, 0)
notifyLabel.BackgroundTransparency = 1
notifyLabel.TextColor3 = Color3.fromRGB(255, 220, 100)
notifyLabel.TextStrokeTransparency = 0.5
notifyLabel.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
notifyLabel.Font = Enum.Font.GothamBold
notifyLabel.TextSize = 28
notifyLabel.Text = ""
notifyLabel.TextWrapped = true
notifyLabel.TextTransparency = 1
notifyLabel.Parent = screenGui

-- Team indicator (below status)
local teamLabel = Instance.new("TextLabel")
teamLabel.Name = "TeamLabel"
teamLabel.Size = UDim2.new(0, 300, 0, 35)
teamLabel.Position = UDim2.new(0.5, -150, 0, 75)
teamLabel.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
teamLabel.BackgroundTransparency = 0.4
teamLabel.BorderSizePixel = 0
teamLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
teamLabel.Font = Enum.Font.GothamMedium
teamLabel.TextSize = 16
teamLabel.Text = ""
teamLabel.TextWrapped = true
teamLabel.Visible = false
teamLabel.Parent = screenGui

local teamCorner = Instance.new("UICorner")
teamCorner.CornerRadius = UDim.new(0, 8)
teamCorner.Parent = teamLabel

-- Helper: show notification that fades
local function showNotification(text, duration)
	duration = duration or 3
	notifyLabel.Text = text
	notifyLabel.TextTransparency = 0

	task.delay(duration, function()
		-- Fade out
		for i = 0, 1, 0.05 do
			notifyLabel.TextTransparency = i
			task.wait(0.02)
		end
		notifyLabel.TextTransparency = 1
	end)
end

-- Helper: update team display
local function updateTeamDisplay()
	if player.Team then
		teamLabel.Text = "You are: " .. player.Team.Name
		if player.Team.Name == "CatPolice" then
			teamLabel.TextColor3 = Color3.fromRGB(100, 150, 255)
			teamLabel.Text = "You are: CatPolice (Catch the criminals!)"
		else
			teamLabel.TextColor3 = Color3.fromRGB(255, 100, 100)
			teamLabel.Text = "You are: Criminal (Run and hide!)"
		end
		teamLabel.Visible = true
	else
		teamLabel.Visible = false
	end
end

-- Listen for round status events
RoundStatusEvent.OnClientEvent:Connect(function(status, ...)
	local args = {...}

	if status == "WaitingForPlayers" then
		local minPlayers = args[1] or 5
		local currentCount = #Players:GetPlayers()
		statusLabel.Text = "Waiting for players... (" .. currentCount .. "/" .. minPlayers .. ")"
		teamLabel.Visible = false

	elseif status == "Countdown" then
		local seconds = args[1] or 10
		for i = seconds, 1, -1 do
			statusLabel.Text = "Game starting in " .. i .. "..."
			task.wait(1)
		end

	elseif status == "CountdownCancelled" then
		statusLabel.Text = "Not enough players! Waiting..."
		showNotification("Countdown cancelled - players left")

	elseif status == "RoundStart" then
		local roundTime = args[1] or 180
		showNotification("ROUND STARTED!", 2)

		-- Update team display
		task.delay(2.5, updateTeamDisplay)

		-- Countdown timer
		task.spawn(function()
			for i = roundTime, 0, -1 do
				if statusLabel.Text == "Intermission" then break end
				local mins = math.floor(i / 60)
				local secs = i % 60
				statusLabel.Text = string.format("Round: %d:%02d", mins, secs)
				task.wait(1)
			end
		end)

	elseif status == "TeamsAssigned" then
		local numPolice = args[1] or 0
		local numCriminals = args[2] or 0
		showNotification(numPolice .. " CatPolice vs " .. numCriminals .. " Criminals", 3)
		task.delay(0.5, updateTeamDisplay)

	elseif status == "RoundEnd" then
		local winner = args[1] or "Nobody"
		if winner == "CatPolice" then
			statusLabel.Text = "CatPolice WIN!"
			showNotification("All criminals have been jailed!", 5)
		else
			statusLabel.Text = "Criminals WIN!"
			showNotification("Criminals survived the round!", 5)
		end

	elseif status == "Intermission" then
		local seconds = args[1] or 15
		for i = seconds, 1, -1 do
			statusLabel.Text = "Next round in " .. i .. "..."
			task.wait(1)
		end
		teamLabel.Visible = false
	end
end)

-- Listen for carry events
CarryStatusEvent.OnClientEvent:Connect(function(action, name1, name2)
	if action == "Caught" then
		showNotification(name1 .. " caught " .. name2 .. "!", 2)
	elseif action == "Thrown" then
		showNotification(name1 .. " threw " .. name2 .. " into jail!", 3)
	end
end)

-- Track team changes
player:GetPropertyChangedSignal("Team"):Connect(updateTeamDisplay)

-- Track player count for lobby display
Players.PlayerAdded:Connect(function()
	if not player.Team then
		local count = #Players:GetPlayers()
		statusLabel.Text = "Waiting for players... (" .. count .. "/5)"
	end
end)

Players.PlayerRemoving:Connect(function()
	if not player.Team then
		local count = #Players:GetPlayers() - 1
		statusLabel.Text = "Waiting for players... (" .. count .. "/5)"
	end
end)

print("[RoundUI] Loaded successfully!")
