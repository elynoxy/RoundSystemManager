--!strict

--//Version 2.0

--//VARIABLES\\
local ROUND_TIME = 60 --//Time in seconds for each round
local PLAYERS_NEEDED_TO_START = 2 --//Players needed to start the round

--//CONSTRUCTOR\\
local RoundSystemManager = {}
RoundSystemManager.__index = RoundSystemManager

--//STATES\\
RoundSystemManager.States = {
	Waiting = "Waiting",
	Running = "Running",
	Finished = "Finished",
	Error = "Error"
}

--//TYPES\\
type RoundManager = {
	State: string,
	RoundPlayers: {Player},
	ActiveTimer: boolean,
	_callbacks: RoundManagerCallbacks,
}

type RoundManagerCallbacks = {
	OnRoundStart: {(Players: {Player}) -> ()},
	OnRoundEnd: {(Players: {Player}) -> ()},
	OnStateChanged: {(oldState: string, newState: string) -> ()},
	OnTimerEnd: { () -> () },
}

--//CLASSES\\
function RoundSystemManager.new()
	local self = setmetatable({} :: RoundManager, RoundSystemManager)
	
	self.State = RoundSystemManager.States.Waiting
	self.RoundPlayers = {}
	
	self._callbacks = {
		OnRoundStart = {},
		OnRoundEnd = {},
		OnStateChanged = {},
		OnTimerEnd = {},
	} :: RoundManagerCallbacks
	
	self.ActiveTimer = false
	
	return self
end

--//STATE MACHINE\\
local AllowedTransitions = {

	[RoundSystemManager.States.Waiting] = {
		[RoundSystemManager.States.Running] = true,
		[RoundSystemManager.States.Error] = true
	},
	
	[RoundSystemManager.States.Running] = {
		[RoundSystemManager.States.Finished] = true,
		[RoundSystemManager.States.Error] = true
	},
	
	[RoundSystemManager.States.Finished] = {
		[RoundSystemManager.States.Waiting] = true,
		[RoundSystemManager.States.Error] = true
	},
	
	[RoundSystemManager.States.Error] = {
		[RoundSystemManager.States.Waiting] = true,
		[RoundSystemManager.States.Running] = true,
		[RoundSystemManager.States.Finished] = true
	}
}

--//ROUND PRIVATE FUNCTIONS\\
local function _CheckTransition(currentState: string, newState: string): (boolean, string)
	local Transition = AllowedTransitions[currentState]
	
	if not Transition then
		return false, "Current state is not valid"
	end
	
	local IsAllowed = Transition[newState]
	
	if not IsAllowed then
		return false, "Transition is not allowed"
	end
	
	return true, ""
end

local function _CheckPlayers(players: {Player}): (boolean, string)
	if #players < PLAYERS_NEEDED_TO_START then
		return false, "Not enough players"
	end
	
	return true, ""
end

function RoundSystemManager:_CleanRound(): (boolean, string)
	if self.State ~= RoundSystemManager.States.Finished then
		return false, "Round is not finished"
	end
	
	table.clear(self.RoundPlayers)
	
	local succes, err = self:Transition(RoundSystemManager.States.Waiting)
	if not succes then
		return false, err
	end
	
	return true, ""
end

--//TIMER PRIVATE FUNCTIONS\\

function RoundSystemManager:_StartTimer()
	if self.State ~= RoundSystemManager.States.Running then
		return
	end
	
	local time = os.clock()
	
	while self.State == RoundSystemManager.States.Running do
		local deltaTime = os.clock() - time
		
		if deltaTime >= ROUND_TIME then
			break
		end
		
		task.wait(0.5)
	end
	
	if self.State == RoundSystemManager.States.Running then
		for _, cb in ipairs(self._callbacks.OnTimerEnd) do
			cb()
		end
		
		self:End()
	end
end

--//ROUND PUBLIC FUNCTIONS\\
function RoundSystemManager:Transition(newState: string): (boolean, string)
	local IsAllowed, ErrorMessage = _CheckTransition(self.State, newState)

	if not IsAllowed then
		self.State = RoundSystemManager.States.Error
		return false, ErrorMessage
	end

	local oldState = self.State
	self.State = newState
	
	for _, cb in ipairs(self._callbacks.OnStateChanged) do
		cb(oldState, newState)
	end
	
	return true, ""
end

function RoundSystemManager:Start(players: {Player}): (boolean, string)
	if self.State ~= RoundSystemManager.States.Waiting then
		return false, "Round is not waiting"
	end
	
	if self.ActiveTimer  then
		return false, "Timer is already active"
	end
	
	local IsAllowed, ErrorMessage = _CheckPlayers(players)
	if not IsAllowed then
		return false, ErrorMessage
	end
	
	table.clear(self.RoundPlayers)
	
	for _, player in (players) do
		table.insert(self.RoundPlayers, player)
	end
	
	local succes, err = self:Transition(RoundSystemManager.States.Running)
	if not succes then
		return false, err
	end
	
	for _, cb in ipairs(self._callbacks.OnRoundStart) do
		cb(self.RoundPlayers)
	end
	
	self.ActiveTimer = true
	
	task.spawn(function()		
		self:_StartTimer()
		self.ActiveTimer = false
	end)
	
	return true, ""
end

function RoundSystemManager:End(): (boolean, string)
	if self.State ~= RoundSystemManager.States.Running then
		return false, "Round is not running"
	end
	
	local succes, err = self:Transition(RoundSystemManager.States.Finished)	
	if not succes then
		return false, err
	end
	
	for _, cb in ipairs(self._callbacks.OnRoundEnd) do
		cb(self.RoundPlayers)
	end
	
	local succes, err = self:_CleanRound()
	if not succes then
		return false, err
	end
	
	return true, ""
end

--//GETTERS\\
function RoundSystemManager:GetState():string
	if not self then return RoundSystemManager.States.Error end
	
	return self.State
end

function RoundSystemManager:GetPlayers(): {Player}
	if not self then return {} end
	
	return table.clone(self.RoundPlayers)
end

--//PLAYER PUBLIC FUNCTIONS\\
function RoundSystemManager.OnPlayerAdded(self: RoundManager, player: Player)	
	local index = table.find(self.RoundPlayers, player)
	if index then return end
	
	if self.State == RoundSystemManager.States.Waiting then
		table.insert(self.RoundPlayers, player)
	end
end

function RoundSystemManager.OnPlayerRemoving(self: RoundManager, player: Player)	
	local index = table.find(self.RoundPlayers, player)
	if not index then return end
	
	table.remove(self.RoundPlayers, index)
end

--//CALLBACKS\\

function RoundSystemManager:OnRoundStart(callback: ({Player}) -> ())
	if typeof(callback) ~= "function" then
		return
	end
	
	table.insert(self._callbacks.OnRoundStart, callback)
end

function RoundSystemManager:OnRoundEnd(callback: ({Player}) -> ())
	if typeof(callback) ~= "function" then
		return
	end
	
	table.insert(self._callbacks.OnRoundEnd, callback)
end

function RoundSystemManager:OnStateChanged(callback: (oldState: string, newState: string) -> ())
	if typeof(callback) ~= "function" then
		return
	end
	
	table.insert(self._callbacks.OnStateChanged, callback)
end

function RoundSystemManager:OnTimerEnd(callback: () -> ())
	if typeof(callback) ~= "function" then
		return
	end
	
	table.insert(self._callbacks.OnTimerEnd, callback)
end

--//RETURN\\

return RoundSystemManager