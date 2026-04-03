--[[
	WeaponsService

	Server-side weapon management system built with Knit.
	Handles weapon creation, equipping, firing validation,
	reloading, state tracking, and cleanup in a scalable architecture.
]]

--// Dependencies
local Knit = require(game:GetService('ReplicatedStorage').Packages.Knit)
local Signal = require(game.ReplicatedStorage.Packages.Signal)

--// Constants
local WeaponPath = script.Weapon

--// Service
local WeaponsService = Knit.CreateService{
	Name = 'WeaponsService',
	
	Client = {
		EquipSignal = Knit.CreateSignal(),
		UnEquipSignal = Knit.CreateSignal(),
		FireSignal = Knit.CreateSignal(),
		ReloadSignal = Knit.CreateSignal(),
		RecoilSignal = Knit.CreateSignal(),
	},
	WeaponClasses = {},
	EquippedWeapons = {},
	PlayerWeapons = {},
	LastShotTimes = {},
	NextShotModifications = {},
	RestrictedPlayers = {}
}

--// Methods

function WeaponsService:Create(player, tool)
	if not player or not tool then return end

	-- Code safety checks.
	local class = tool:GetAttribute('Class')
	if not class then
		warn(`[WeaponsService]: Tool:{tool.Name}, does not have a class.`)
		return
	end
	if not WeaponPath[class] then
		warn(`[WeaponsService]: Class:{class}, does not exist.`)
		return
	end
	if not WeaponPath[class][tool.Name] then
		warn(`[WeaponsService]: Weapon:{tool.Name}, does not exist.`)
		return
	end

	-- Check if player already has this weapon
	if not self.PlayerWeapons[player.Name] then
		self.PlayerWeapons[player.Name] = {}
	end

	if not self.PlayerWeapons[player.Name][tool.Name] then
		-- Get the weapon class (e.g., Revolver) and initialize it
		local weaponClass = self.WeaponClasses[class][tool.Name]
		local weapon = weaponClass.new(player, tool)  -- Create an instance of the weapon
		
		self.PlayerWeapons[player.Name][tool.Name] = weapon  -- Store the weapon instance
		self.HolsterService:Holster(player, tool) -- Holster the weapon
		
		tool.Destroying:Once(function()
			self.PlayerWeapons[player.Name][tool.Name] = nil
			local equippedWeapon = self.EquippedWeapons[player.Name] 
			if equippedWeapon and equippedWeapon.Tool == tool then
				self.EquippedWeapons[player.Name] = nil
			end
		end)
	end
end

function WeaponsService:Equip(player, tool)
	if not player or not tool then return end

	local weapon = self.PlayerWeapons[player.Name][tool.Name]
	if weapon then
		self.HolsterService:Unholster(player)
		weapon:Equip()
	else
		warn(`[WeaponsService]: Player does not have Weapon:{tool.Name}`)
		return
	end

	self.EquippedWeapons[player.Name] = weapon
end

function WeaponsService:UnEquip(player)
	if not player then return end

	-- Get the current equipped weapon and unequip it.
	local weapon = self.EquippedWeapons[player.Name]
	if not weapon then
		warn(`[WeaponsService]: {player.Name} has no weapon equipped.`)
		return
	end

	self.HolsterService:Holster(player, weapon.Tool) -- Holster the weapon
	weapon:UnEquip()

	self.EquippedWeapons[player.Name] = nil
end

function WeaponsService:Fire(player, mousePos, isAiming)
	if not player then return end
	if self:IsRestricted(player) then return end

	local weapon = self.EquippedWeapons[player.Name]
	if not weapon then
		warn(`[WeaponsService]: {player.Name} has no weapon equipped.`)
		return
	end

	local roundsPerSecond = weapon.RoundsPerSecond
	if not roundsPerSecond or roundsPerSecond <= 0 then
		warn(`[WeaponsService]: Invalid RoundsPerSecond value for {weapon.Name}.`)
		return
	end

	-- Track the time of the last shot for this player
	local lastShotTime = self.LastShotTimes[player.Name]
	local currentTime = tick()

	-- enough time hasn't passed since the last shot
	local shotCooldown = 1 / roundsPerSecond
	local marginOfError = 0.015
	if lastShotTime and (currentTime - lastShotTime) < (shotCooldown - marginOfError) then 
		return
	end

	-- Apply modifications if they exist
	local modification = self.NextShotModifications[player.Name]
	if modification then
		weapon:ApplyModification(modification)
		self.NextShotModifications[player.Name] = nil -- Clear after use
	end
	
	-- Update the last shot time
	self.LastShotTimes[player.Name] = currentTime

	weapon:Fire(player, mousePos, isAiming, self.Client.RecoilSignal)
end

function WeaponsService:ModifyNextShot(player, modification)
	if not player or not modification then return end
	self.NextShotModifications[player.Name] = modification
end

function WeaponsService:Reload(player)
	if not player then return end
	if self:IsRestricted(player) then return end

	local weapon = self.EquippedWeapons[player.Name]
	if not weapon then
		warn(`[WeaponsService]: {player.Name} has no weapon equipped.`)
		return
	end
	
	weapon:Reload()
end

function WeaponsService:SetRestricted(player, isRestricted)
	if not player then return end
	self.RestrictedPlayers[player.Name] = isRestricted and true or nil
end

function WeaponsService:IsRestricted(player)
	return self.RestrictedPlayers[player.Name] ~= nil
end


function WeaponsService:GetEquippedWeapon(player)
	if not player then return end

	local weapon = self.EquippedWeapons[player.Name]
	if not weapon then
		warn(`[WeaponsService]: {player.Name} has no weapon equipped.`)
		return nil
	end
	
	return weapon
end

function WeaponsService:DestroyWeapons(player)
	if not player then return end
	
	--[[for _, weapon in pairs(player.Backpack:GetChildren()) do
		if weapon:IsA('Tool') and weapon:GetAttribute('Weapon')then
			weapon:Destroy()
		end
	end
	for _, weapon in pairs(player.Character:GetChildren()) do
		if weapon:IsA('Tool') and weapon:GetAttribute('Weapon')then
			weapon:Destroy()
		end
	end]]
	
	local weapon = self.EquippedWeapons[player.Name]
	if weapon then
		if self.PlayerWeapons[player.Name][weapon.Tool.Name] then
			self.PlayerWeapons[player.Name][weapon.Tool.Name] = nil
		end
		
		weapon:Destroy()
		weapon = nil
		self.EquippedWeapons[player.Name] = nil
	end
	
	for index, weapon in pairs(self.PlayerWeapons[player.Name]) do
		weapon:Destroy()
		weapon = nil
		index = nil
	end
	
	self.PlayerWeapons[player.Name] = {}
end


--// Client Methods

function WeaponsService.Client:DestroyWeapons(player)
	self.Server:DestroyWeapons(player)
end

function WeaponsService.Client:GetWeaponSettings(player, class, weaponName, setting)
	-- Code safety checks
	if not self.Server.WeaponClasses[class] then
		warn(`[WeaponsService]: Class:{class}, does not exist.`)
	end
	if not self.Server.WeaponClasses[class][weaponName] then
		warn(`[WeaponsService]: Weapon:{weaponName}, does not exist.`)
	end
	if not self.Server.WeaponClasses[class][weaponName].Settings[setting] then
		warn(`[WeaponsService]: Setting:{setting}, does not exist.`)
	end

	-- Return the setting.
	return self.Server.WeaponClasses[class][weaponName].Settings[setting]
end

--// Handling
function WeaponsService:KnitStart()	
	self.HolsterService = Knit.GetService('HolsterService')

	-- Set up the weapon classes.
	for _, class in pairs(WeaponPath:GetChildren()) do
		if not self.WeaponClasses[class.Name] then
			self.WeaponClasses[class.Name] = {}
		end

		-- Set up the weapons
		for _, weapon in pairs(class:GetChildren()) do
			if not self.WeaponClasses[class.Name][weapon.Name] then
				self.WeaponClasses[class.Name][weapon.Name] = require(weapon)  -- Require the weapon class (Rifle, etc.)
			end
		end
	end

	-- Set up the PlayerWeapons table
	for _, player in pairs(game.Players:GetPlayers()) do
		self.PlayerWeapons[player.Name] = {}
	end

	--> Create the player weapons.
	game.Players.PlayerAdded:Connect(function(player)
		self.PlayerWeapons[player.Name] = {}
		
		player.CharacterAdded:Connect(function(character)
			for _, weapon in pairs(player.Backpack:GetChildren()) do
				if weapon:IsA('Tool') and weapon:GetAttribute('Weapon') then
					self:Create(player, weapon)
				end
			end
		end)

		player.Backpack.ChildAdded:Connect(function(weapon)
			if weapon:IsA('Tool') and weapon:GetAttribute('Weapon') then
				self:Create(player, weapon)
			end
		end)
	end)

	-- Player removing connection for clean up logic.
	game.Players.PlayerRemoving:Connect(function(player)
		local weapon = self.EquippedWeapons[player.Name]
		if weapon then
			weapon:Destroy()
		end
		self.EquippedWeapons[player.Name] = nil
	end)

	-- Signal connections.
	self.Client.EquipSignal:Connect(function(player, weaponName)
		local weapon = player.Character:FindFirstChild(weaponName)
		if weapon then
			self:Equip(player, weapon)
		end
	end)

	self.Client.UnEquipSignal:Connect(function(player)
		self:UnEquip(player)
	end)

	self.Client.FireSignal:Connect(function(player, mousePos, isAiming)
		self:Fire(player, mousePos, isAiming)
	end)

	self.Client.ReloadSignal:Connect(function(player)
		self:Reload(player)
	end)
end

return WeaponsService
