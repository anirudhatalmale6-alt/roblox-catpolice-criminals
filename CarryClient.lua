--[[
	CarryClient (LocalScript)
	Place in: StarterPlayer > StarterPlayerScripts

	Handles:
	- Disabling/enabling player controls when carried
	- UI feedback for carry status
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer

-- Wait for events
local EventsFolder = ReplicatedStorage:WaitForChild("GameEvents")
local DisableControlsEvent = EventsFolder:WaitForChild("DisableControls")
local CarryStatusEvent = EventsFolder:WaitForChild("CarryStatus")

-- Get PlayerModule for controls
local PlayerModule = nil
local Controls = nil

local function getControls()
	if Controls then return Controls end
	local success, result = pcall(function()
		PlayerModule = require(player:WaitForChild("PlayerScripts"):WaitForChild("PlayerModule"))
		Controls = PlayerModule:GetControls()
		return Controls
	end)
	if success then
		return result
	end
	return nil
end

-- Handle control disable/enable from server
DisableControlsEvent.OnClientEvent:Connect(function(shouldDisable)
	local controls = getControls()

	if shouldDisable then
		-- Disable all input
		if controls then
			controls:Disable()
		end

		-- Also disable jumping via character
		local character = player.Character
		if character then
			local humanoid = character:FindFirstChild("Humanoid")
			if humanoid then
				humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)
			end
		end
	else
		-- Re-enable all input
		if controls then
			controls:Enable()
		end

		local character = player.Character
		if character then
			local humanoid = character:FindFirstChild("Humanoid")
			if humanoid then
				humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, true)
			end
		end
	end
end)

-- Optional: Show carry status messages
CarryStatusEvent.OnClientEvent:Connect(function(action, name1, name2)
	-- You can add GUI notifications here
	-- For now, just print to output
	if action == "Caught" then
		print(name1 .. " caught " .. name2 .. "!")
	elseif action == "Thrown" then
		print(name1 .. " threw " .. name2 .. " into jail!")
	end
end)

print("[CarryClient] Loaded successfully!")
