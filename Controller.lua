-- strict!

local public = {}
local private = {}
local network = require(game.ServerScriptService.Roboot.NetworkManagement.Object.Controller)
local maid = require(game.ReplicatedStorage.SharedAssets.maid)
local httpService: HttpService = game:GetService("HttpService")
local runer : RunService = game:GetService("RunService")

export type Effigy = {
	model : Model,
	colour : Color3,
	transparency : number,
	decay : number?,
	player : Player?,
	
	new : (self : Effigy, model : Model, player : Player?, colour : Color3, transparency : number) -> Effigy,
	simulate : (self : Effigy) -> boolean,
	terminate : (self : Effigy) -> nil
	
	
} -- CREATE A EXACT COPY OF A MODEL, THE MODELS TRANSPARENCY, COLOUR AND MATERIAL IS CONFIGURED IN THE OBJECT WHEN CALLED

private.nextVSID = 0
function private:getNextVSID()
	private.nextVSID += 1
	return private.nextVSID
end

private.nextEffigyId = 0
function private:getnextEffigyId()
	private.nextEffigyId += 1
	return private.nextEffigyId
end



public.Effigy = {}
local effigy : Effigy = public.Effigy
effigy.__index = effigy


function effigy:new(model : Model,player : Player? , colour : Color3, transparency : number) : Effigy
	local new : Effigy = setmetatable({},self)
	
	new.id = private:getnextEffigyId()
	new.model = model
	new.colour = colour
	new.transparency = transparency
	new.player = player
	new.decay = 4
	
	return new
end

function effigy:simulate()
	network:fireEvent("Effigy_VFX",self.player,
		{
			colour = self.colour,
			transparency = self.transparency,
			decay = self.decay,
			model = self.model
		}
	)
end


function effigy:terminate()
	local obj : Effigy = self
	task.spawn(function()
		table.clear(obj)
		table.freeze(obj)
	end)
end


export type VisualSequence = {
	cameraData : {Folder?},
	animations : {Animation},
	players : {Player?},
	model : Model,
	id : number,


	new : (self : VisualSequence, model : Model, ...Animation|Player) -> VisualSequence,
	Play : (self : VisualSequence, speed : number?, fade : number?) -> boolean,
	Stop : (self : VisualSequence) -> boolean,
	AdjustSpeed : (self : VisualSequence, speed : number) -> boolean,
	Length : number,

	terminate : (self : VisualSequence) -> nil,

} -- LINK EVENTS TO ANIMATION, ALLOW FOR MULTIPLE ANIMATIONS TO BE RUN AT ONCE, CAMERA MUST WORK WITH VISUAL SEQUENCE IF CAMERA DATA IS GIVEN.



public.VisualSequence = {}
local vs = public.VisualSequence
vs.__index = vs


function vs:new(model : Model, ... : Animation|Player|Folder)
	local new : VisualSequence = setmetatable({},self)
	new.players = {}
	new.cameraDatas = {}
	new.animations = {}
	new.model = model
	new.id = private:getNextVSID()
	local lencon
	lencon = network:addEndpoint("VS_GET_LENGTH_ID"..tostring(new.id),function(player : Player,length : number)
		if length ~= nil and typeof(length) == "number" then
			new.Length = length
			lencon:Disconnect()
			
		end
	end)
	
	
	for index : number, asset : Animation|Player|Folder in {...} do 
		if asset:IsA("Player") then
			table.insert(new.players,asset)
		elseif asset:IsA("Animation") then
			table.insert(new.animations,asset)
		elseif asset:IsA("Folder") then
			table.insert(new.cameraDatas,asset)
		end
	end
	
	
	if #new.players == 0 then
		network:fireEvent("VS_ADD_ENTRY",nil,
			{
				animations = new.animations,
				cameraDatas = new.cameraDatas,
				["model"] = new.model,
				id = new.id
				
			})	
		
	elseif #new.players > 0 then
		for index : number , player : Player in new.players do 
			network:fireEvent("VS_ADD_ENTRY",player,
				{
					animations = new.animations,
					cameraDatas = new.cameraDatas,
					id = new.id,
					["model"] = new.model
						
				})
		end
		
	end
	
	return new
end


function vs:Play(speed : number? , fade : number?)
	if #self.players == 0 then
		network:fireEvent("VS_PLAY_SEQ",nil,{id = self.id,["speed"] = speed,["fade"] = fade})
	elseif #self.players > 0 then
		for index : number , player : Player in self.players do 
			network:fireEvent("VS_PLAY_SEQ",player,{id = self.id,["speed"] = speed,["fade"] = fade})
		end
	end
	
end


function vs:AdjustSpeed(speed : number)
	if #self.players == 0 then
		network:fireEvent("VS_AS_SEQ",nil,{id = self.id,["speed"] = speed})
	elseif #self.players > 0 then
		for index : number , player : Player in self.players do 
			network:fireEvent("VS_PLAY_SEQ",player,{id = self.id,["speed"] = speed})
		end
	end
	
end

function vs:Stop()
	if #self.players == 0 then
		network:fireEvent("VS_STOP_SEQ",nil,self.id)
	elseif #self.players > 0 then
		for index : number , player : Player in self.players do 
			network:fireEvent("VS_STOP_SEQ",player, self.id)
		end
	end

end


export type TrackHandler = {
	tracks : {AnimationTrack},
	trackMaid : maid.maid,
	
	Play : (self : TrackHandler, speed : number?,fadeTime : number?) -> nil,
	Stop : (self : TrackHandler) -> nil,
	AdjustSpeed : (self : TrackHandler, speed : number) -> nil,
	new : (self : TrackHandler, model : Model, ...Animation) -> TrackHandler,
	Length : number
	
}

function private:getAnimator(model : Model)
	local result : Animator?
	for index : number , animator : Animator in model:GetDescendants() do 
		if animator:IsA("Animator") then
			result = animator
			break
		end
	end
	return result
end

public.TrackHandler = {}
local trackHandler  = public.TrackHandler
trackHandler.__index = trackHandler

function private:isTrackLoaded(id: string, animator: Animator): AnimationTrack?
	local tracks: {AnimationTrack} = animator:GetPlayingAnimationTracks()
	local result: AnimationTrack?
	for index: number, track: AnimationTrack in tracks do
		if track.Animation.AnimationId == id then
			result = track
			break
		end
	end

	return result
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


function trackHandler:new(model : Model, ... : Animation)
	local new : TrackHandler = setmetatable({},self)
	new.trackMaid = maid:new()
	new.tracks = {}
	local animator : Animator = private:getAnimator(model)
	for index : number , animation : Animation in {...} do 
		local track : AnimationTrack = private:isTrackLoaded(animation.AnimationId,animator)
		
		if track == nil then
			track = animator:LoadAnimation(animation)
			for index : number , part : Instance in model:GetDescendants() do 
				track:GetMarkerReachedSignal(part.Name):Connect(function(json : string)
					applyPropertiesToPart(part,json)
				end)
			end	
		end
		
		table.insert(new.tracks,track)
	end
	
	model.Destroying:Once(function()
		self.trackMaid:clean()
	end)
	
	task.spawn(function()
		local length : number = 0
		for index : number , track : AnimationTrack in new.tracks do 
			repeat 
				task.wait()
			until track.Length ~= 0
			length += track.Length
		end
		new.Length = length
	end)
	
	return new
end

function trackHandler:Play(speed : number?,fadeTime : number?)
	self.trackMaid:clean()
	
	for index : number , track : AnimationTrack in self.tracks do 
		track:AdjustSpeed(speed or 1)

	end
	
	
	self.trackMaid:handle(task.spawn(function()
		for index : number , track : AnimationTrack in self.tracks do 
			track:Play(fadeTime or nil,nil,speed)
			track.Stopped:Wait()
		end
		
	end))
	
	
	
end

function trackHandler:AdjustSpeed(speed : number)
	for index : number , track : AnimationTrack in self.tracks do 
		track:AdjustSpeed(speed or 1)

	end
end

function trackHandler:Stop()
	self.trackMaid:clean()
	for index : number , track : AnimationTrack in self.tracks do 
		track:Stop()
		
	end

end

export type Omitter = { -- VFX AND SOUND ARE PLAYED ON CLIENT SIDE
	player : Player,
	Particles : {ParticleEmitter|Sound},
	isAttachment : boolean,
	Prop : Model,
	amount : number,
	decay : number,
	rate : number,
	location : CFrame,
	direction : Vector3,
	acceleration : Vector3,
	primarypart : BasePart?,

	new : (self : Omitter, ...Sound|ParticleEmitter) -> Omitter,
	Play : (self : Omitter) -> boolean,

	terminate : (self : Omitter) -> nil


} -- CONTAIN A PARTICLE AND SOUNDS, OMIT IN AN AREA OR A POINT, BE SET TO MOVE WITH VECTOR GIVEN


public.Omitter = {}
local omitter = public.Omitter
omitter.__index = omitter


function omitter:new(... : Sound|ParticleEmitter)
	local new : Omitter = setmetatable({},self)
	new.Particles = {...}
	new.isAttachment = false
	new.amount = 1
	new.decay = 1
	new.rate = 1
	new.location = CFrame.new()
	new.direction = Vector3.new(0,0,0)
	new.acceleration = Vector3.zero
	
	return new
end


function omitter:Play()
	local sendData = {
		particles = self.Particles,
		isAttachment = self.isAttachment,
		amount = self.amount,
		decay = self.decay,
		rate = self.rate,
		location = self.location,
		direction = self.direction,
		acceleration = self.acceleration,
		prop = self.Prop,
		primarypart = self.primarypart
	}
	
	if self.player then
		network:fireEvent("OMITTER_PLAY",self.player,sendData)
	else
		network:fireEvent("OMITTER_PLAY",nil,sendData)
	end
	
end

function omitter:terminate()
	task.spawn(function()
		table.clear(self)
		table.freeze(self)
	end)
end


export type ShadowPuppet = {
	model : Model,
	player : Player?,
	animations : {Animation},
	colour : Color3,
	transparency : number,
	direction : Vector3,
	acceleration : Vector3,
	speed : number,


	new : (self : ShadowPuppet, model : Model, colour : Color3, transparency : number) -> ShadowPuppet,
	spawn : (self : ShadowPuppet) -> Model,
	terminate : (self : ShadowPuppet) -> nil

} -- A COPY OF A MODEL, THE COPY IS INVISIBLE AND IS USED TO PLAY ANIMATIONS. BEST USED WHEN PAIRED WITH EFFIGY

public.ShadowPuppet = {}
public.ShadowPuppet.__index = public.ShadowPuppet
local shadowPuppet : ShadowPuppet = public.ShadowPuppet

function shadowPuppet:new(model : Model, ... : Animation)
	local new : ShadowPuppet = setmetatable({},self)
	
	new.model = model
	new.trackHandler = trackHandler
	new.direction = Vector3.zero
	new.acceleration = Vector3.zero
	new.colour = Color3.new(1, 1, 1)
	new.transparency = 1
	new.animations = {...}
	new.speed = 1

	return new
end

	
function shadowPuppet:spawn()
	local puppet : Model
	puppet = self.model:Clone()
	puppet.PrimaryPart.Anchored = true
	
	
	task.spawn(function()
		for index : number , part : BasePart in puppet:GetDescendants() do 
			if part:IsA("BasePart") then
				part.Transparency = self.transparency
				part.Color = self.colour
			elseif not part:IsA("Humanoid")	and not part:IsA("Animator") and not part:IsA("Motor6D") and not part:IsA("Attachment") and not part:IsA("AnimationController")	then
				part:Destroy()
			end
		end
	end)
	
	puppet.Parent = workspace
	puppet:PivotTo(self.model:GetPivot())
	
	local trackHandler : TrackHandler = trackHandler:new(puppet,table.unpack(self.animations))
	trackHandler:Play(self.speed)
	
	
	task.delay(trackHandler.Length,function()
		puppet:Destroy()
	end)
	
	task.spawn(function()
		local count : number = 0
		local run : RBXScriptConnection = runer.Heartbeat:Connect(function(dt : number)
			puppet:PivotTo(puppet:GetPivot() + (self.direction * dt) + (self.acceleration * count * dt) )
			count += 1
		end)
		
	end)
	
	
	
	return puppet
end

function shadowPuppet:terminate()
	task.spawn(function()
		table.clear(self)
		table.freeze(self)
	end)
end





return public
