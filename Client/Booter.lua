local network = require(game.ReplicatedStorage.Network.Controller)

local players: Players = game:GetService("Players")
local player: Player = players.LocalPlayer

local tweener: TweenService = game:GetService("TweenService")
local debris: Debris = game:GetService("Debris")
local runer: RunService = game:GetService("RunService")
local httpService: HttpService = game:GetService("HttpService")

local maid = require(game.ReplicatedStorage.SharedAssets.maid)

local private = {}

private.VSDataStore = {}

local function tableMx(tab: {})
	local count: number = 0

	for _, _ in tab do
		count += 1
	end

	return count
end

type cameraTrack = {
	Frames: {[string]: CFrame},
	FOVS: {[string]: number},
	isLooped: boolean?,
	camera: Camera,
	FramePosition: number,
	length: number,
	maid: maid.maid,
	speed: number,
	reference: BasePart?,
	IsCameraTrack: boolean,
	_stopped: boolean?,

	Stopped: {
		Connect: (Stopped: {}, method: () -> any?) -> {Disconnect: () -> nil},
		listeners: {() -> any?}
	},

	Play: (self: cameraTrack, speed: number?) -> nil,
	Stop: (self: cameraTrack) -> nil,
	AdjustSpeed: (self: cameraTrack, speed: number) -> nil,
}

private.CameraTrack = {}
local ct: cameraTrack = private.CameraTrack
ct.__index = private.CameraTrack

function ct:Play(speed: number?)
	if speed then
		self:AdjustSpeed(speed)
	end

	local camera = self.camera
	local lastFrame: number = math.max(tableMx(self.Frames), tableMx(self.FOVS))

	if lastFrame <= 0 then
		self:Stop()
		return
	end

	self._stopped = false

	local oldCameraType = camera.CameraType
	local oldFOV = camera.FieldOfView

	camera.CameraType = Enum.CameraType.Scriptable

	self.maid:handle(function()
		camera.CameraType = oldCameraType
		camera.FieldOfView = oldFOV
	end)

	if self.speed < 0 then
		self.FramePosition = lastFrame
	else
		self.FramePosition = 1
	end

	local accumulator = 0
	local frameTime = 1 / 60

	local runner: RBXScriptConnection
	runner = runer.Heartbeat:Connect(function(dt: number)
		if self._stopped then
			return
		end

		if self.speed == 0 then
			return
		end

		accumulator += dt * math.abs(self.speed)

		while accumulator >= frameTime do
			accumulator -= frameTime

			local frameKey = tostring(self.FramePosition)
			local frame: CFrame? = self.Frames[frameKey]
			local fov: number? = self.FOVS[frameKey]

			if frame then
				if self.reference ~= nil then
					camera.CFrame = self.reference:GetPivot() * frame
				elseif player.Character then
					camera.CFrame = player.Character:GetPivot() * frame
				else
					camera.CFrame = frame
				end
			end

			if fov then
				camera.FieldOfView = fov
			end

			if self.speed > 0 then
				if self.FramePosition >= lastFrame then
					self:Stop()
					return
				end

				self.FramePosition += 1
			else
				if self.FramePosition <= 1 then
					self:Stop()
					return
				end

				self.FramePosition -= 1
			end
		end
	end)

	self.maid:handle(runner)
end

function ct:Stop()
	if self._stopped then
		return
	end

	self._stopped = true

	for _, method in self.Stopped.listeners do
		task.spawn(method)
	end

	self.maid:clean()
end

function ct:AdjustSpeed(speed: number)
	self.speed = speed
end

function private:createCameraTrack(cameraData: Folder, reference: BasePart?): cameraTrack
	local new: cameraTrack = setmetatable({}, ct)

	new.IsCameraTrack = true
	new.camera = workspace.CurrentCamera
	new.FramePosition = 1
	new.Frames = {}
	new.FOVS = {}
	new.speed = 1
	new.maid = maid:new()
	new._stopped = true

	local frameFolder = cameraData:FindFirstChild("Frames")
	local fovFolder = cameraData:FindFirstChild("FOV")

	local frameCount = 0

	if frameFolder then
		frameCount = #frameFolder:GetChildren()
	end

	new.length = frameCount / 60

	local settings = cameraData:FindFirstChild("Settings")
	local referenceValue = settings and settings:FindFirstChild("Reference")

	if reference then
		new.reference = reference
	elseif referenceValue and referenceValue:IsA("ObjectValue") then
		new.reference = referenceValue.Value
	else
		new.reference = nil
	end

	new.Stopped = {}
	new.Stopped.listeners = {}

	function new.Stopped:Connect(method: () -> any?)
		local option = {}

		table.insert(new.Stopped.listeners, method)

		function option:Disconnect()
			local pos: number? = table.find(new.Stopped.listeners, method)

			if pos then
				table.remove(new.Stopped.listeners, pos)
			end
		end

		return option
	end

	if frameFolder then
		for _, cframeValue in frameFolder:GetChildren() do
			if cframeValue:IsA("CFrameValue") then
				new.Frames[cframeValue.Name] = cframeValue.Value
			end
		end
	end

	if fovFolder then
		for _, fov in fovFolder:GetChildren() do
			if fov:IsA("NumberValue") then
				new.FOVS[fov.Name] = fov.Value
			end
		end
	end

	return new
end

type VSEntry = {
	tracks: {cameraTrack | AnimationTrack},
	loadedTracks: {[string]: AnimationTrack},
	connectedMarkers: {[string]: boolean},
	currentStep: number,
	speed: number,
	maid: maid.maid,
	Reference: BasePart?,
}

function private:getAnimator(model: Model): Animator?
	for _, animator in model:GetDescendants() do
		if animator:IsA("Animator") then
			return animator
		end
	end

	return nil
end

function private:isTrackLoaded(id: string, entry: VSEntry): AnimationTrack?
	return entry.loadedTracks[id]
end

function private:getOrLoadTrack(entry: VSEntry, animator: Animator, animation: Animation): AnimationTrack
	local id: string = animation.AnimationId

	local loadedTrack: AnimationTrack? = private:isTrackLoaded(id, entry)

	if loadedTrack then
		return loadedTrack
	end

	local track: AnimationTrack = animator:LoadAnimation(animation)
	entry.loadedTracks[id] = track

	return track
end

local function applyPropertiesToPart(part: Instance, json: string)
	local success, properties = pcall(function()
		return httpService:JSONDecode(json)
	end)

	if not success or typeof(properties) ~= "table" then
		warn("Invalid marker JSON:", json)
		return
	end

	for property: string, value: any in properties do
		property = string.split(property, " ")[1]

		local readSuccess, member = pcall(function()
			return part[property]
		end)

		if readSuccess then
			if typeof(member) == "function" then
				pcall(function()
					member(part, value)
				end)
			else
				pcall(function()
					part[property] = value
				end)
			end
		end
	end
end

function private:connectMarkersOnce(entry: VSEntry, track: AnimationTrack, model: Model)
	local id: string = track.Animation.AnimationId

	if entry.connectedMarkers[id] then
		return
	end

	entry.connectedMarkers[id] = true

	for _, part: Instance in model:GetDescendants() do
		local connection = track:GetMarkerReachedSignal(part.Name):Connect(function(json: string)
			applyPropertiesToPart(part, json)
		end)

		entry.maid:handle(connection)
	end
end

local function splitTracks(entry: VSEntry): ({AnimationTrack}, {cameraTrack})
	local modelTracks: {AnimationTrack} = {}
	local cameraTracks: {cameraTrack} = {}

	for _, track: AnimationTrack | cameraTrack in entry.tracks do
		if typeof(track) == "table" and track.IsCameraTrack then
			table.insert(cameraTracks, track)
		else
			table.insert(modelTracks, track :: AnimationTrack)
		end
	end

	return modelTracks, cameraTracks
end

local function stopTrack(track: AnimationTrack | cameraTrack)
	if typeof(track) == "table" and track.IsCameraTrack then
		track:Stop()
	else
		local animationTrack = track :: AnimationTrack

		pcall(function()
			animationTrack:Stop()
		end)
	end
end

local function adjustTrackSpeed(track: AnimationTrack | cameraTrack, speed: number)
	if typeof(track) == "table" and track.IsCameraTrack then
		track:AdjustSpeed(speed)
	else
		local animationTrack = track :: AnimationTrack

		pcall(function()
			animationTrack:AdjustSpeed(speed)
		end)
	end
end

network:listenToServerEvent("VS_ADD_ENTRY", function(data: {
	animations: {Animation},
	cameraDatas: {Folder},
	model: Model,
	id: number
	})
	local animator: Animator? = private:getAnimator(data.model)

	if not animator then
		warn("No Animator found for VS entry:", data.id)
		return
	end

	local entry: VSEntry = {}
	entry.tracks = {}
	entry.loadedTracks = {}
	entry.connectedMarkers = {}
	entry.maid = maid:new()
	entry.currentStep = 1
	entry.speed = 1
	entry.Reference = data.model.PrimaryPart

	for _, animation: Animation in data.animations do
		local track: AnimationTrack = private:getOrLoadTrack(entry, animator, animation)

		private:connectMarkersOnce(entry, track, data.model)

		table.insert(entry.tracks, track)
	end

	for _, cameraData: Folder in data.cameraDatas do
		local cameraTrack = private:createCameraTrack(cameraData, entry.Reference)

		table.insert(entry.tracks, cameraTrack)
	end

	private.VSDataStore[tostring(data.id)] = entry

	task.spawn(function()
		local modelTracks, cameraTracks = splitTracks(entry)

		local animLength: number = 0
		local cameraLength: number = 0

		for _, track: AnimationTrack in modelTracks do
			local start = os.clock()

			while track.Length == 0 and os.clock() - start < 5 do
				task.wait()
			end

			if track.Length ~= 0 then
				animLength += track.Length
			else
				warn("Could not get animation length:", track.Animation.AnimationId)
			end
		end

		for _, track: cameraTrack in cameraTracks do
			cameraLength += track.length
		end

		local length: number = math.max(animLength, cameraLength)

		network:callEndpoint("VS_GET_LENGTH_ID" .. tostring(data.id), length)
	end)
end)

network:listenToServerEvent("VS_PLAY_SEQ", function(data: {
	id: number,
	speed: number?,
	fade: number?
	})
	local entry: VSEntry? = private.VSDataStore[tostring(data.id)]

	if not entry then
		return
	end

	if data.speed then
		entry.speed = data.speed
	end

	local modelTracks, cameraTracks = splitTracks(entry)

	entry.maid:handle(task.spawn(function()
		for _, track: cameraTrack in cameraTracks do
			local complete: boolean = false

			local operator = track.Stopped:Connect(function()
				complete = true
			end)

			entry.maid:handle(function()
				operator:Disconnect()
			end)

			track:Play(entry.speed)

			while complete == false do
				task.wait()
			end
		end
	end))

	entry.maid:handle(task.spawn(function()
		for _, track: AnimationTrack in modelTracks do
			track:Play(data.fade or 0, nil, entry.speed)

			if track.Looped then
				track.Stopped:Wait()
			else
				track.Ended:Wait()
			end
		end
	end))
end)

network:listenToServerEvent("VS_STOP_SEQ", function(id: number)
	local entry: VSEntry? = private.VSDataStore[tostring(id)]

	if entry then
		entry.maid:clean()

		for _, track: AnimationTrack | cameraTrack in entry.tracks do
			stopTrack(track)
		end
	end
end)

network:listenToServerEvent("VS_AS_SEQ", function(data: {
	id: number,
	speed: number
	})
	local entry: VSEntry? = private.VSDataStore[tostring(data.id)]

	if entry then
		entry.speed = data.speed

		for _, track: AnimationTrack | cameraTrack in entry.tracks do
			adjustTrackSpeed(track, data.speed)
		end
	end
end)

network:listenToServerEvent("Effigy_VFX", function(data: {
	colour: Color3,
	transparency: number,
	decay: number,
	model: Model
	})
	local effigy: Model = data.model:Clone()

	for _, int: Instance in effigy:GetDescendants() do
		if int:IsA("BasePart") then
			int.Anchored = true
			int.CanCollide = false
			int.CanQuery = false
			int.CanTouch = false
			int.Transparency = data.transparency
			int.Color = data.colour
			int.Material = Enum.Material.Neon

			task.delay(data.decay, function()
				if int and int.Parent then
					local tweenInfo: TweenInfo = TweenInfo.new(
						data.decay,
						Enum.EasingStyle.Sine,
						Enum.EasingDirection.Out
					)

					local tween: Tween = tweener:Create(int, tweenInfo, {
						Transparency = 1
					})

					tween:Play()
				end
			end)
		elseif not int:IsA("Model") and not int:IsA("Folder") then
			int:Destroy()
		end
	end

	effigy.Parent = workspace
	debris:AddItem(effigy, data.decay * 2.1)
end)

type OmitterData = {
	particles : {ParticleEmitter|Sound},
	isAttachment : boolean,
	amount : number,
	decay : number,
	rate : number,
	location : CFrame,
	direction : Vector3,
	acceleration : Vector3,
	prop : Model?,
	primarypart :BasePart?
}


network:listenToServerEvent("OMITTER_PLAY",function(omitterData : OmitterData)
	task.spawn(function()
		local holder : BasePart|Model = omitterData.prop or  Instance.new("Part",workspace)
		local att : Attachment
		if not holder:IsA("Model") then
			att = Instance.new("Attachment",holder)
			holder.Transparency = 1
			holder.CanCollide = false
			holder.CanQuery = false
			holder.CanTouch = false
			holder.Anchored = true
		else
			att = Instance.new("Attachment",holder.PrimaryPart)
			holder.Parent = workspace
		end
		
		holder:PivotTo(if omitterData.primarypart then omitterData.primarypart:GetPivot() + omitterData.primarypart:GetPivot():VectorToWorldSpace(omitterData.direction ) else omitterData.location)
		if omitterData.primarypart then
			local weld : WeldConstraint = Instance.new("WeldConstraint",holder)
			if holder:IsA("Model") then 
				holder.PrimaryPart.Anchored = false
				holder.PrimaryPart.Massless = true
			else
				holder.Anchored = false
				holder.Massless = true
			end
			weld.Part0 = omitterData.primarypart
			weld.Part1 = if holder:IsA("Model") then holder.PrimaryPart else holder
			
		end
		
		local omitters : {Sound|ParticleEmitter} = {}
		for index : number , omitter : Sound|ParticleEmitter in omitterData.particles do 
			local newOmitter : Sound|ParticleEmitter = omitter:Clone()
			if omitterData.isAttachment == true then
				newOmitter.Parent = att	
			else
				newOmitter.Parent = holder
			end
			table.insert(omitters,newOmitter)
		end
		
		
		local count : number = 0
		
		local move : RBXScriptConnection = runer.Heartbeat:Connect(function(dt : number)
			
			if omitterData.direction.Magnitude > 0 and omitterData.primarypart == nil then
				holder:PivotTo(holder:GetPivot() + (omitterData.direction * dt) + ((omitterData.acceleration * dt) * count) )
				count += 1
			end
		end)

		local emit : thread = task.spawn(function()
			while true do 
				for index : number , omitter : Sound|ParticleEmitter in omitters do 
					if omitter : IsA("ParticleEmitter") then
						omitter:Emit(omitter.Rate)
					elseif omitter:IsA("Sound") then
						omitter:Play()
					end
				end
				
				task.wait(omitterData.rate)
			end
		end)
		
		holder.Destroying:Once(function()
			move:Disconnect()
		end)
		
		debris:AddItem(holder,omitterData.decay)
		
	end)
end)