--[[
	CarrySystem (Server Script)
	Place in: ServerScriptService

	Handles:
	- CatPolice touching Criminals = auto-catch
	- Criminal positioned lying on police officer's head (CFrame weld)
	- Police plays carry animation
	- Criminal can't move while carried
	- ThrowPart interaction = criminal gets launched into jail

	REQUIRES: GameManager script to be running (for team assignments and events)

	SETUP:
	- Set CARRY_ANIMATION_ID below to your CatPolice carry animation asset ID
	- "ThrowPart" Part must exist inside GameMap
]]

local Players = game:GetService("Players")
local Teams = game:GetService("Teams")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")

-- ============================================================
-- CONFIG - SET YOUR ANIMATION ID HERE
-- ============================================================
local CARRY_ANIMATION_ID = "rbxassetid://0" -- << REPLACE 0 WITH YOUR ANIMATION ID
-- ============================================================

local THROW_FORCE = 80 -- how hard criminals get thrown
local THROW_UPWARD = 40 -- upward force when thrown
local THROW_DURATION = 0.5 -- how long the throw force lasts
local CATCH_COOLDOWN = 2 -- seconds between catches (prevents spam)
local CARRY_SPEED_MULTIPLIER = 0.85 -- police walk a bit slower while carrying

-- References
local GameMap = workspace:WaitForChild("GameMap")
local ThrowPart = GameMap:WaitForChild("ThrowPart")

-- Wait for events folder from GameManager
local EventsFolder = ReplicatedStorage:WaitForChild("GameEvents")
local DisableControlsEvent = EventsFolder:WaitForChild("DisableControls")
local RoundStatusEvent = EventsFolder:WaitForChild("RoundStatus")

-- Create carry-specific events
local CarryStatusEvent = Instance.new("RemoteEvent")
CarryStatusEvent.Name = "CarryStatus"
CarryStatusEvent.Parent = EventsFolder

-- State tracking
local carryData = {} -- [policePlayer] = {criminal = Player, weld = WeldConstraint, animTrack = AnimationTrack}
local carriedPlayers = {} -- [criminalPlayer] = policePlayer (reverse lookup)
local catchCooldowns = {} -- [policePlayer] = tick()
local touchConnections = {} -- [player] = {connections}
local throwPartConnection = nil

-- Helper: Check if player is on CatPolice team
local function isPolice(player)
	return player.Team and player.Team.Name == "CatPolice"
end

-- Helper: Check if player is on Criminals team
local function isCriminal(player)
	return player.Team and player.Team.Name == "Criminals"
end

-- Helper: Set criminal into lying position on police head using CFrame
local function positionCriminalOnHead(policeCharacter, criminalCharacter)
	local policeHead = policeCharacter:FindFirstChild("Head")
	local criminalRoot = criminalCharacter:FindFirstChild("HumanoidRootPart")

	if not policeHead or not criminalRoot then return nil end

	-- Anchor the criminal's root part temporarily to prevent physics issues
	-- We'll use a WeldConstraint instead

	-- Position criminal lying flat on top of police head
	-- Rotate 90 degrees on the X axis so they're lying down
	-- Offset upward so they sit on top of the head
	local offsetCFrame = CFrame.new(0, 1.5, 0) * CFrame.Angles(0, 0, math.rad(90))

	-- Set initial position
	criminalRoot.CFrame = policeHead.CFrame * offsetCFrame

	-- Create WeldConstraint to keep criminal attached
	local weld = Instance.new("WeldConstraint")
	weld.Name = "CarryWeld"
	weld.Part0 = policeHead
	weld.Part1 = criminalRoot
	weld.Parent = criminalRoot

	-- Store the offset for reference
	local offsetValue = Instance.new("CFrameValue")
	offsetValue.Name = "CarryOffset"
	offsetValue.Value = offsetCFrame
	offsetValue.Parent = criminalRoot

	return weld
end

-- Helper: Make criminal "ragdoll-like" lying pose
local function setCriminalLyingPose(criminalCharacter, enabled)
	local humanoid = criminalCharacter:FindFirstChild("Humanoid")
	if not humanoid then return end

	if enabled then
		-- Disable all movement states
		humanoid:SetStateEnabled(Enum.HumanoidStateType.Running, false)
		humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)
		humanoid:SetStateEnabled(Enum.HumanoidStateType.Climbing, false)
		humanoid:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)
		humanoid:SetStateEnabled(Enum.HumanoidStateType.Freefall, false)
		humanoid.WalkSpeed = 0
		humanoid.JumpPower = 0
		humanoid.JumpHeight = 0
		humanoid.AutoRotate = false

		-- Set platform stand state (limp body)
		humanoid.PlatformStand = true
	else
		-- Re-enable everything
		humanoid:SetStateEnabled(Enum.HumanoidStateType.Running, true)
		humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, true)
		humanoid:SetStateEnabled(Enum.HumanoidStateType.Climbing, true)
		humanoid:SetStateEnabled(Enum.HumanoidStateType.FallingDown, true)
		humanoid:SetStateEnabled(Enum.HumanoidStateType.Freefall, true)
		humanoid.WalkSpeed = 16
		humanoid.JumpPower = 50
		humanoid.JumpHeight = 7.2
		humanoid.AutoRotate = true
		humanoid.PlatformStand = false
	end
end

-- Play carry animation on police
local function playCarryAnimation(policeCharacter)
	local humanoid = policeCharacter:FindFirstChild("Humanoid")
	if not humanoid then return nil end

	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = humanoid
	end

	local animation = Instance.new("Animation")
	animation.AnimationId = CARRY_ANIMATION_ID
	animation.Parent = policeCharacter

	local animTrack = animator:LoadAnimation(animation)
	animTrack.Priority = Enum.AnimationPriority.Action
	animTrack.Looped = true
	animTrack:Play()

	return animTrack
end

-- Start carrying a criminal
local function startCarry(policePlayer, criminalPlayer)
	local policeChar = policePlayer.Character
	local criminalChar = criminalPlayer.Character

	if not policeChar or not criminalChar then return end

	-- Check cooldown
	if catchCooldowns[policePlayer] and (tick() - catchCooldowns[policePlayer]) < CATCH_COOLDOWN then
		return
	end

	-- Don't carry if already carrying someone
	if carryData[policePlayer] then return end

	-- Don't carry if this criminal is already being carried
	if carriedPlayers[criminalPlayer] then return end

	print("[CarrySystem] " .. policePlayer.Name .. " caught " .. criminalPlayer.Name)

	-- 1. Disable criminal movement (server-side)
	setCriminalLyingPose(criminalChar, true)

	-- 2. Disable criminal controls (client-side)
	DisableControlsEvent:FireClient(criminalPlayer, true)

	-- 3. Position criminal on police head
	local weld = positionCriminalOnHead(policeChar, criminalChar)
	if not weld then
		-- Failed, revert
		setCriminalLyingPose(criminalChar, false)
		DisableControlsEvent:FireClient(criminalPlayer, false)
		return
	end

	-- 4. Play carry animation on police
	local animTrack = playCarryAnimation(policeChar)

	-- 5. Slow down police a little
	local policeHumanoid = policeChar:FindFirstChild("Humanoid")
	if policeHumanoid then
		policeHumanoid.WalkSpeed = 16 * CARRY_SPEED_MULTIPLIER
	end

	-- 6. Store state
	carryData[policePlayer] = {
		criminal = criminalPlayer,
		weld = weld,
		animTrack = animTrack,
	}
	carriedPlayers[criminalPlayer] = policePlayer
	catchCooldowns[policePlayer] = tick()

	-- Notify clients
	CarryStatusEvent:FireAllClients("Caught", policePlayer.Name, criminalPlayer.Name)
end

-- Stop carrying (release without throw)
local function stopCarry(policePlayer, dontResetControls)
	local data = carryData[policePlayer]
	if not data then return end

	local criminalPlayer = data.criminal
	local criminalChar = criminalPlayer and criminalPlayer.Character

	-- Remove weld
	if data.weld and data.weld.Parent then
		data.weld:Destroy()
	end

	-- Remove offset value
	if criminalChar then
		local offsetVal = criminalChar:FindFirstChild("HumanoidRootPart")
		if offsetVal then
			local cv = offsetVal:FindFirstChild("CarryOffset")
			if cv then cv:Destroy() end
			local cw = offsetVal:FindFirstChild("CarryWeld")
			if cw then cw:Destroy() end
		end
	end

	-- Stop animation
	if data.animTrack then
		data.animTrack:Stop()
		data.animTrack:Destroy()
	end

	-- Reset police speed
	local policeChar = policePlayer.Character
	if policeChar then
		local policeHumanoid = policeChar:FindFirstChild("Humanoid")
		if policeHumanoid then
			policeHumanoid.WalkSpeed = 16
		end
	end

	-- Re-enable criminal
	if criminalChar and not dontResetControls then
		setCriminalLyingPose(criminalChar, false)
		DisableControlsEvent:FireClient(criminalPlayer, false)
	end

	-- Clean state
	carriedPlayers[criminalPlayer] = nil
	carryData[policePlayer] = nil
end

-- Throw criminal when police touches ThrowPart
local function throwCriminal(policePlayer)
	local data = carryData[policePlayer]
	if not data then return end

	local criminalPlayer = data.criminal
	local criminalChar = criminalPlayer and criminalPlayer.Character
	local policeChar = policePlayer.Character

	if not criminalChar or not policeChar then
		stopCarry(policePlayer)
		return
	end

	local criminalRoot = criminalChar:FindFirstChild("HumanoidRootPart")
	local policeRoot = policeChar:FindFirstChild("HumanoidRootPart")

	if not criminalRoot or not policeRoot then
		stopCarry(policePlayer)
		return
	end

	-- Stop the carry (but don't reset controls yet — we want the criminal to fly first)
	stopCarry(policePlayer, true) -- dontResetControls = true

	-- Calculate throw direction: forward from police + upward
	local lookVector = policeRoot.CFrame.LookVector
	local throwDirection = (lookVector * THROW_FORCE) + Vector3.new(0, THROW_UPWARD, 0)

	-- Re-enable physics on criminal temporarily for the throw
	local criminalHumanoid = criminalChar:FindFirstChild("Humanoid")
	if criminalHumanoid then
		criminalHumanoid.PlatformStand = false
	end

	-- Apply throw force using LinearVelocity
	local attachment = criminalRoot:FindFirstChildOfClass("Attachment")
	if not attachment then
		attachment = Instance.new("Attachment")
		attachment.Parent = criminalRoot
	end

	local linearVelocity = Instance.new("LinearVelocity")
	linearVelocity.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
	linearVelocity.Velocity = throwDirection
	linearVelocity.MaxForce = math.huge
	linearVelocity.Attachment0 = attachment
	linearVelocity.Parent = criminalRoot

	Debris:AddItem(linearVelocity, THROW_DURATION)

	-- Notify
	CarryStatusEvent:FireAllClients("Thrown", policePlayer.Name, criminalPlayer.Name)

	print("[CarrySystem] " .. policePlayer.Name .. " threw " .. criminalPlayer.Name .. " into jail!")

	-- After throw, re-enable criminal controls after a delay
	task.delay(1.5, function()
		if criminalChar and criminalChar.Parent then
			setCriminalLyingPose(criminalChar, false)
			-- But keep them in jail — they stay there
			-- You could teleport them to a jail spawn or just leave them
		end
		if criminalPlayer and criminalPlayer.Parent then
			DisableControlsEvent:FireClient(criminalPlayer, false)
		end
	end)
end

-- Set up touch detection for a police character
local function setupPoliceTouchDetection(policePlayer)
	local char = policePlayer.Character
	if not char then return end

	local connections = {}

	-- Listen for touching criminals
	for _, part in ipairs(char:GetDescendants()) do
		if part:IsA("BasePart") then
			local conn = part.Touched:Connect(function(otherPart)
				if not isPolice(policePlayer) then return end

				-- Check if touched part belongs to a criminal
				local otherChar = otherPart.Parent
				if not otherChar then return end

				local otherHumanoid = otherChar:FindFirstChild("Humanoid")
				if not otherHumanoid then return end

				local otherPlayer = Players:GetPlayerFromCharacter(otherChar)
				if not otherPlayer then return end

				if isCriminal(otherPlayer) and not carriedPlayers[otherPlayer] then
					startCarry(policePlayer, otherPlayer)
				end
			end)
			table.insert(connections, conn)
		end
	end

	touchConnections[policePlayer] = connections
end

-- Set up ThrowPart detection
local function setupThrowPart()
	if throwPartConnection then
		throwPartConnection:Disconnect()
	end

	throwPartConnection = ThrowPart.Touched:Connect(function(otherPart)
		local char = otherPart.Parent
		if not char then return end

		local player = Players:GetPlayerFromCharacter(char)
		if not player then return end

		if isPolice(player) and carryData[player] then
			throwCriminal(player)
		end
	end)
end

-- Clean up when player leaves or dies
local function cleanupPlayer(player)
	-- If police was carrying someone
	if carryData[player] then
		stopCarry(player)
	end

	-- If criminal was being carried
	if carriedPlayers[player] then
		local policePlayer = carriedPlayers[player]
		stopCarry(policePlayer)
	end

	-- Disconnect touch events
	if touchConnections[player] then
		for _, conn in ipairs(touchConnections[player]) do
			conn:Disconnect()
		end
		touchConnections[player] = nil
	end
end

-- Player setup
Players.PlayerAdded:Connect(function(player)
	player.CharacterAdded:Connect(function(character)
		-- Wait for character to fully load
		character:WaitForChild("HumanoidRootPart")
		character:WaitForChild("Humanoid")
		task.wait(0.5)

		-- Set up touch detection if they're police
		if isPolice(player) then
			setupPoliceTouchDetection(player)
		end

		-- Re-setup if team changes
		player:GetPropertyChangedSignal("Team"):Connect(function()
			-- Clean up old connections
			if touchConnections[player] then
				for _, conn in ipairs(touchConnections[player]) do
					conn:Disconnect()
				end
				touchConnections[player] = nil
			end

			-- Set up new connections if now police
			task.wait(0.5) -- Wait for character to exist after team change
			if isPolice(player) and player.Character then
				setupPoliceTouchDetection(player)
			end
		end)

		-- Handle death
		local humanoid = character:FindFirstChild("Humanoid")
		if humanoid then
			humanoid.Died:Connect(function()
				cleanupPlayer(player)
			end)
		end
	end)
end)

-- Handle player leaving
Players.PlayerRemoving:Connect(function(player)
	cleanupPlayer(player)
end)

-- Listen for round end to clean up all carries
RoundStatusEvent.OnServerEvent:Connect(function(player, status)
	-- This won't fire from clients normally, but we can listen to our own
end)

-- Clean up all carries (called between rounds from GameManager)
-- We expose this via a BindableEvent
local CleanupCarries = Instance.new("BindableEvent")
CleanupCarries.Name = "CleanupCarries"
CleanupCarries.Parent = EventsFolder

CleanupCarries.Event:Connect(function()
	for policePlayer, _ in pairs(carryData) do
		stopCarry(policePlayer)
	end
end)

-- Initialize ThrowPart
setupThrowPart()

print("[CarrySystem] Loaded successfully!")
