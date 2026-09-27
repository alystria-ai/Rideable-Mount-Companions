-- Mounted ground steering only. The shared companion service owns ordinary
-- following/combat before and after a control lease. No flight or teleporting.
local M={}
local function valid(o)return o and o:IsValid()and not o:HasAnyFlags(EObjectFlags.RF_BeginDestroyed|EObjectFlags.RF_FinishDestroyed)end
local function identity(o)return o:GetFullName()..'#'..tostring(o:GetAddress())end
local function key(pc,name)return pc:IsInputKeyDown({KeyName=FName(name)})end
local function clamp(v,a,b)return math.max(a,math.min(b,v))end
local function number(value,label)
 local n=tonumber(value);assert(n and n==n and math.abs(n)<math.huge,label..' is unavailable');return n
end
local function yaw(rotation)return tonumber(rotation.Yaw or rotation.yaw)or 0 end
local function bearPace(profile,value)
 -- The authored Bear selector uses 0.5 for walk and 1 for run. Its open-world
 -- profile has an inline pace curve; use a private two-key curve for each gait.
 local source=StaticFindObject('/Game/_Dawnwalker/Player/MovementProfiles/CF_InputSizeToInputValue_Walk.CF_InputSizeToInputValue_Walk')
 assert(valid(source),'Native pace curve unavailable')
 local curve=StaticConstructObject(source:GetClass(),profile,0,0,0,false,false,source)
 assert(valid(curve)and curve:GetAddress()~=source:GetAddress(),'Private bear pace curve unavailable')
 assert(#curve.FloatCurve.Keys>0 and #curve.FloatCurve.Keys<=16,'Unexpected bear pace curve')
 for i=1,#curve.FloatCurve.Keys do
  local k=curve.FloatCurve.Keys[i];k.Value=value;k.ArriveTangent=0;k.LeaveTangent=0
 end
 profile.MovementConfig.InputSizeToInputValue.ExternalCurve=curve
 profile.MovementConfig.bCycleStateVelocitySyncEnabled=false
 profile.MovementConfig.LookAtMode=0
end
local function wolfTravelPace(profile)
 -- The native Wolf selector distinguishes combat run (pace 1) from the
 -- travelling gallop (pace 3). Raise the requested gait, not animation speed.
 local source=profile.MovementConfig.InputSizeToInputValue.ExternalCurve
 assert(valid(source),'Wolf pace curve unavailable')
 local curve=StaticConstructObject(source:GetClass(),profile,0,0,0,false,false,source)
 assert(valid(curve)and curve:GetAddress()~=source:GetAddress(),'Private Wolf pace curve unavailable')
 assert(#curve.FloatCurve.Keys>0 and #curve.FloatCurve.Keys<=16,'Unexpected Wolf pace curve')
 for i=1,#curve.FloatCurve.Keys do
  local key=curve.FloatCurve.Keys[i];key.Value=3;key.ArriveTangent=0;key.LeaveTangent=0
 end
 profile.MovementConfig.InputSizeToInputValue.ExternalCurve=curve
end
local function ownsGaitLayer(entry)
 return valid(entry.layer)and identity(entry.layer)==entry.layerId
end
local function selectGait(entry,running)
 if not ownsGaitLayer(entry)or not valid(entry.original)then return end
 local current=entry.layer.CycleBlendSpaceSet
 local ownsCopy=valid(entry.copy)and identity(entry.copy)==entry.copyId
 if not valid(current)or(current:GetAddress()~=entry.original:GetAddress()and(not ownsCopy or current:GetAddress()~=entry.copy:GetAddress()))then return end
 if not running then entry.layer.CycleBlendSpaceSet=entry.original;return end
 if not ownsCopy then
  local source=entry.original
  assert(valid(source),'Native animal cycle selector retired')
  local copy=StaticConstructObject(source:GetClass(),entry.layer,0,0,0,false,false,source)
  assert(valid(copy)and copy:GetAddress()~=source:GetAddress(),'Private animal selector unavailable')
  for j=1,#source.Assets do
   local bs=source.Assets[j].BlendSpace;local run=entry.runSource or bs
   assert(valid(bs)and valid(run)and #bs.SampleData>0 and #bs.SampleData<=64 and #run.SampleData<=64,'Native animal cycle samples unavailable')
   if entry.authoredRun then
    -- Wolves and bears have authored selectors containing their running gait.
    -- Keep native sampling data intact instead of rewriting SampleData.
    -- Only this private set borrows it; the shared asset is never modified.
    copy.Assets[j].BlendSpace=run
   else
    local private=StaticConstructObject(bs:GetClass(),copy,0,0,0,false,false,bs)
    assert(valid(private)and private:GetAddress()~=bs:GetAddress(),'Private animal cycle unavailable')
    copy.Assets[j].BlendSpace=private
    for k=1,#bs.SampleData do
     local sample=bs.SampleData[k];local best,gap
     for n=1,#run.SampleData do
      local candidate=run.SampleData[n]
      if math.abs(candidate.SampleValue.Y-entry.runPace)<.01 and valid(candidate.Animation)then
       local d=math.abs((candidate.SampleValue.X-sample.SampleValue.X+180)%360-180)
       if not gap or d<gap then best=candidate.Animation;gap=d end
      end
     end
     assert(valid(best),'Native animal running animation unavailable')
     private.SampleData[k].Animation=best
    end
   end
  end
  -- Fill samples before exposing the asset. Swapping the blend-space pointer
  -- invalidates the animation player's cache; editing active SampleData does not.
  entry.copy=copy;entry.copyId=identity(copy)
 end
 entry.layer.CycleBlendSpaceSet=entry.copy
end
local function nativeGaitCycles(self,family,runSource,runPace)
 self.gaitLeases=self.gaitLeases or{}
 local found=0
 for i=1,math.min(#self.actor.Mesh.LinkedInstances,12)do
  local layer=self.actor.Mesh.LinkedInstances[i]
  local class=valid(layer)and layer:GetClass():GetFullName()or''
  local matches=class:find('ABP_'..family..'LocomotionLayers_C',1,true)
   or family=='Dog'and class:find('ABP_WolfLocomotionLayers_C',1,true)
  if matches then
   found=found+1;local id=identity(layer);local existing
   for _,entry in ipairs(self.gaitLeases)do if entry.layerId==id then existing=entry;break end end
   if not existing then
    local source=layer.CycleBlendSpaceSet
    assert(valid(source)and #source.Assets>0 and #source.Assets<=16,'Native animal cycle selector unavailable')
    local entry={layer=layer,layerId=id,original=source,runSource=runSource,runPace=runPace or 1,authoredRun=(family=='Wolf'or family=='Bear')and runSource~=nil}
    self.gaitLeases[#self.gaitLeases+1]=entry
    if self.running then selectGait(entry,true)end
   end
  end
 end
 return found
end

function M.new(actor,species)
 assert(valid(actor)and valid(actor.CharacterMovement),'A live native creature is required')
 local self={actor=actor,actorId=identity(actor),world=identity(actor:GetWorld()),movement=actor.CharacterMovement,speed=100}
 function self:current(pc)
  return valid(self.actor)and not self.actor:IsActorBeingDestroyed()and identity(self.actor)==self.actorId
   and valid(self.movement)and valid(pc)and valid(pc.Pawn)and valid(pc.Pawn:GetWorld())and identity(pc.Pawn:GetWorld())==self.world
 end
 function self:acquire(pc)
  if not self:current(pc)then return false,'Creature changed or world retired'end
  if self.active then return true end
  if self.handle~=nil or self.walkHandle~=nil or self.rotationHandle~=nil or self.idleRotationHandle~=nil or self.releaseSteps then
   local released,reason=self:release(pc);if not released then return false,reason end
  end
  local m=self.movement;self.base=m:GetCurrentMovementProfile()
  if not valid(self.base)then return false,'Native locomotion profile is unavailable'end
  -- Capture before pushing either handle. Failed acquisition still has a
  -- complete rollback, even if PushRotationMode or a later field write fails.
  self.oldMaxWalkSpeed=number(m.MaxWalkSpeed,'Native walk speed')
  self.oldAcceleration=number(m.MaxAcceleration,'Native acceleration')
  self.controller=self.actor.Controller
  self.oldFocus=valid(self.controller)and self.controller:GetFocusActor()or nil
  self.releaseSteps={};self.releaseError=nil
  local ok,err=xpcall(function()
  -- A resting follower deliberately uses the 140 cm/s walker profile. Borrow
  -- the wolf's authored running profile when already loaded; other species
  -- derive a bounded riding pace from a private copy of their own profile.
  self.paceMultiplier=1
  local skeleton=self.actor.Mesh:GetSkinnedAsset().Skeleton
  -- Gargoyles only supply directional start/cycle selectors. A follower's
  -- input-driven, velocity-facing profile never enters their locomotion cycle.
  -- Start from the authored ground profile, not the boosted follower clone.
  if species=='gargoyle'then
   local authored=StaticFindObject('/Game/_Dawnwalker/Combat/Enemies/Bosses/Gargoyle/DA_NPC_Walker_MovementProfile_Gargogyle.DA_NPC_Walker_MovementProfile_Gargogyle')
   assert(valid(authored),'Native Gargoyle ground profile unavailable')
   self.base=authored;self.gargoyle=true;self.rotationMode=2 -- FaceDirection.
  end
  if species=='mare'then
   -- Both live Mare variants expose directional strafe cycles. Use their own
   -- authored combat locomotion profile without enabling combat or attacks.
   local authored=StaticFindObject('/Game/_Dawnwalker/Combat/Enemies/Mare/DA_Combat_Mare_MovementProfile.DA_Combat_Mare_MovementProfile')
   assert(valid(authored),'Native Mare movement profile unavailable')
   self.base=authored;self.mare=true;self.rotationMode=2
   local walk=self.actor.DefaultMovementProfile
   assert(valid(walk),'Native Mare walking profile unavailable')
   self.walkProfile=StaticConstructObject(walk:GetClass(),m,0,0,0,false,false,walk)
   assert(valid(self.walkProfile)and self.walkProfile:GetAddress()~=walk:GetAddress(),'Private Mare walking profile unavailable')
   self.walkBaseSpeed=number(walk.MovementConfig.MaxSpeed,'Mare walking speed')
   self.walkBaseRootScale=number(walk.MovementConfig.RootSpeedScale,'Mare walking root speed')
   self.walkProfile.Priority=201;self.walkProfile.MovementConfig.RotationMode=2
   self.walkProfile.MovementConfig.LookAtMode=0
  end
  -- Following can leave a private catch-up profile active. Never multiply
  -- that boosted root motion again for a ridden bear.
  if self.actor:GetClass():GetFullName():find('BP_BearCharacter_C',1,true)then
   local authored=StaticFindObject('/Game/_Dawnwalker/NPC/Animals/MovementProfiles/DA_Bear_Walk_OpenWorld_MovementProfile.DA_Bear_Walk_OpenWorld_MovementProfile')
   assert(valid(authored),'Native bear locomotion profile unavailable')
   self.base=authored;self.bear=true
   self.walkProfile=StaticConstructObject(authored:GetClass(),m,0,0,0,false,false,authored)
   assert(valid(self.walkProfile)and self.walkProfile:GetAddress()~=authored:GetAddress(),'Private bear walking profile unavailable')
   self.walkBaseSpeed=number(authored.MovementConfig.MaxSpeed,'Bear walking speed')
   self.walkBaseRootScale=number(authored.MovementConfig.RootSpeedScale,'Bear walking root speed')
   self.walkProfile.Priority=201;bearPace(self.walkProfile,.5)
  end
  -- Dogs and the Beast of Balaur inherit the Wolf pawn and its default mesh.
  -- A skeleton match alone must never replace a dog's own locomotion selector.
  local wolfLayer=false
  for i=1,math.min(#self.actor.Mesh.LinkedInstances,12)do
   local layer=self.actor.Mesh.LinkedInstances[i]
   if valid(layer)and layer:GetClass():GetFullName():find('ABP_WolfLocomotionLayers_C',1,true)then
    wolfLayer=true
   end
  end
  if wolfLayer and species~='dog'and valid(skeleton)and skeleton:GetFullName():find('WLF_Common_Body_A_Skeleton',1,true)then
   self.wolf=true
   local runPath='/Game/_Dawnwalker/NPC/NonHuman/Wolf/DA_Wolf_FaceVelocity_Run_MovementProfile.DA_Wolf_FaceVelocity_Run_MovementProfile'
   local run=StaticFindObject(runPath)
   if valid(run)and run:GetFullName():match('^%S+ (.+)$')==runPath then self.base=run end
   local walkPath='/Game/_Dawnwalker/NPC/NonHuman/Wolf/DA_Wolf_FaceVelocity_Walk_MovementProfile.DA_Wolf_FaceVelocity_Walk_MovementProfile'
   local walk=StaticFindObject(walkPath)
   if valid(walk)and walk:GetFullName():match('^%S+ (.+)$')==walkPath then
    self.walkProfile=StaticConstructObject(walk:GetClass(),m,0,0,0,false,false,walk)
    assert(valid(self.walkProfile)and self.walkProfile:GetAddress()~=walk:GetAddress(),'Private walking profile unavailable')
    self.walkBaseSpeed=number(walk.MovementConfig.MaxSpeed,'Walking profile speed')
    self.walkBaseRootScale=number(walk.MovementConfig.RootSpeedScale,'Walking root speed')
    self.walkProfile.Priority=201;self.walkProfile.MovementConfig.bCycleStateVelocitySyncEnabled=false
    self.walkProfile.MovementConfig.LookAtMode=0
   end
  end
  if species=='dog'or species=='boar'then
   self.boar=species=='boar'
   self.dog=species=='dog'
   -- Inspected native selectors use pace 0.5 for walk and 1 for run. Keep
   -- those selectors; only wolves have the separate pace-3 travelling gallop.
   local family=species=='boar'and'Boar'or'Wolf'
   local prefix='/Game/_Dawnwalker/NPC/NonHuman/'..family..'/DA_'..family..'_FaceVelocity_'
   local run=StaticFindObject(prefix..'Run_MovementProfile.DA_'..family..'_FaceVelocity_Run_MovementProfile')
   local walk=StaticFindObject(prefix..'Walk_MovementProfile.DA_'..family..'_FaceVelocity_Walk_MovementProfile')
   if valid(run)and valid(walk)then
    self.base=run
    self.walkProfile=StaticConstructObject(walk:GetClass(),m,0,0,0,false,false,walk)
    assert(valid(self.walkProfile)and self.walkProfile:GetAddress()~=walk:GetAddress(),'Private creature walking profile unavailable')
    self.walkBaseSpeed=number(walk.MovementConfig.MaxSpeed,'Walking profile speed')
    self.walkBaseRootScale=number(walk.MovementConfig.RootSpeedScale,'Walking root speed')
    self.walkProfile.Priority=201;self.walkProfile.MovementConfig.bCycleStateVelocitySyncEnabled=false
    self.walkProfile.MovementConfig.LookAtMode=0
   end
  end
  self.baseSpeed=number(self.base.MovementConfig.MaxSpeed,'Profile speed')
  self.baseRootScale=number(self.base.MovementConfig.RootSpeedScale,'Profile root speed')
  assert(self.baseSpeed>0,'The native locomotion profile has no usable ground speed')
  if self.gargoyle then
   self.baseSpeed=400;self.baseRootScale=1.5
  elseif self.baseSpeed<300 then self.paceMultiplier=math.min(3.5,490/math.max(1,self.baseSpeed))end
  self.profile=StaticConstructObject(self.base:GetClass(),m,0,0,0,false,false,self.base)
  assert(valid(self.profile)and self.profile:GetAddress()~=self.base:GetAddress(),'A private movement profile could not be created')
  -- Speed scaling otherwise feeds back into gait selection, leaving boosted
  -- mounts stuck in a hurried walk/trot even at full rider input. Keep gait
  -- driven by input and scale only this private profile's physical pace.
  if not self.bear and not self.gargoyle then self.profile.MovementConfig.bCycleStateVelocitySyncEnabled=false end
  self.profile.MovementConfig.LookAtMode=0 -- Do not aim the creature's head up at its rider.
  if self.rotationMode then self.profile.MovementConfig.RotationMode=self.rotationMode end
  if self.bear then
   -- Input pace 1 retains the bear's brisk combat gait. Travelling pace 3
   -- reaches its native run without multiplying the physical speed again.
   bearPace(self.profile,3)
   -- Separate walking and running caps, with unchanged root-motion rate.
   self.baseSpeed=self.walkBaseSpeed*2
   self.gaitSource=StaticFindObject('/Game/_Dawnwalker/Animation/Animals/Bear/Animation/Locomotion/Locomotion_Combat/BS_Bear_Combat_CycleFaceVelocity.BS_Bear_Combat_CycleFaceVelocity')
   assert(valid(self.gaitSource)and valid(skeleton)and valid(self.gaitSource.Skeleton)and self.gaitSource.Skeleton:GetAddress()==skeleton:GetAddress(),'Native Bear running gait is unavailable')
   assert(nativeGaitCycles(self,'Bear',self.gaitSource,1)>0,'Bear locomotion layer unavailable')
  end
  if self.boar then assert(nativeGaitCycles(self,'Boar')>0,'Boar locomotion layer unavailable')end
  if self.dog then
   self.dogRun=StaticFindObject('/Game/_Dawnwalker/Animation/Animals/Wolf/Animation/Locomotion_Combat/BS_Wolf_COEN_CycleFaceVelocity.BS_Wolf_COEN_CycleFaceVelocity')
   assert(valid(self.dogRun)and valid(skeleton)and valid(self.dogRun.Skeleton)and self.dogRun.Skeleton:GetAddress()==skeleton:GetAddress(),'Compatible canine travelling run unavailable')
   assert(nativeGaitCycles(self,'Dog',self.dogRun,3)>0,'Dog locomotion layer unavailable')
  end
  if self.wolf then
   wolfTravelPace(self.profile)
   self.gaitSource=StaticFindObject('/Game/_Dawnwalker/Animation/Animals/Wolf/Animation/Locomotion_Combat/BS_Wolf_COEN_CycleFaceVelocity.BS_Wolf_COEN_CycleFaceVelocity')
   assert(valid(self.gaitSource)and valid(skeleton)and valid(self.gaitSource.Skeleton)and self.gaitSource.Skeleton:GetAddress()==skeleton:GetAddress(),'Native Wolf travelling gait is unavailable')
   assert(nativeGaitCycles(self,'Wolf',self.gaitSource,3)>0,'Wolf locomotion layer unavailable')
  end
  if self.wolf or self.bear then
   -- AnimDriven can keep the previous cycle's physical velocity after a gait
   -- switch. SpeedAnimDriven follows the selected private profile's pace,
   -- allowing the native travelling stride and a slower walk on Shift release.
   self.profile.MovementConfig.VelocitySyncMode=1
   if valid(self.walkProfile)then self.walkProfile.MovementConfig.VelocitySyncMode=1 end
  end
  self.gaitFamily=self.dog and'Dog'or self.wolf and'Wolf'or self.boar and'Boar'or self.bear and'Bear'or nil
  self.gaitSource=self.dogRun or self.gaitSource
  self.gaitPace=(self.dog or self.wolf)and 3 or 1
  self.profile.Priority=200
  -- The movement component caches values when a profile is pushed.
  local ratio=(self.paceMultiplier or 1)*self.speed/100
  self.profile.MovementConfig.MaxSpeed=self.baseSpeed*ratio
  self.profile.MovementConfig.RootSpeedScale=self.baseRootScale*ratio
  if valid(self.walkProfile)then
   self.walkProfile.MovementConfig.MaxSpeed=self.walkBaseSpeed*self.speed/100
   self.walkProfile.MovementConfig.RootSpeedScale=self.walkBaseRootScale*self.speed/100
  end
  self.handle=m:PushMovementProfile(self.profile)
  if type(self.handle)~='number'or self.handle<0 then self.handle=nil;error('Native movement profile lease was rejected')end
  -- Most creatures use FaceVelocity. Gargoyles require FaceDirection and
  -- follow the heading supplied below. Clear rider focus in both cases; idle
  -- rotation is separately suspended so the mount cannot chase its own rider.
  self.rotationHandle=m:PushRotationMode(self.rotationMode or 1,200)
  if type(self.rotationHandle)~='number'or self.rotationHandle<0 then self.rotationHandle=nil;error('Native rotation lease was rejected')end
  if valid(self.controller)then self.focusCleared=true;self.controller:K2_ClearFocus()end
  self.active=true;self.lastSpeed=nil;self:setSpeed(self.speed);self:setRunning(false);self:setMoving(false)
  end,debug.traceback)
  if not ok then
   local restored,reason=self:release(pc)
   return false,tostring(err)..(restored and ''or '\nMovement recovery pending: '..tostring(reason))
  end
  return true
 end
 function self:setSpeed(percent)
  self.speed=clamp(tonumber(percent)or 100,50,250)
  if not self.active or not valid(self.profile)then return end
  local ratio=(self.paceMultiplier or 1)*self.speed/100;local requested=self.baseSpeed*ratio
  self.profile.MovementConfig.MaxSpeed=requested
  self.profile.MovementConfig.RootSpeedScale=self.baseRootScale*ratio
  if valid(self.walkProfile)then
   self.walkProfile.MovementConfig.MaxSpeed=self.walkBaseSpeed*self.speed/100
   self.walkProfile.MovementConfig.RootSpeedScale=self.walkBaseRootScale*self.speed/100
  end
  self.movement.MaxWalkSpeed=requested;self.movement.MaxAcceleration=math.max(self.oldAcceleration,requested*2)
  if self.lastSpeed and math.abs(requested-self.lastSpeed)>.01 then
   -- MovementConfig is cached by the native component. Refresh only our own
   -- handles when the slider actually changes, preserving the selected gait.
   local running=self.running==true
   if self.walkHandle~=nil then self.movement:PopMovementProfile(self.walkHandle);self.walkHandle=nil end
   if self.handle~=nil then self.movement:PopMovementProfile(self.handle);self.handle=nil end
   local handle=self.movement:PushMovementProfile(self.profile)
   assert(type(handle)=='number'and handle>=0,'Updated riding profile was rejected')
   self.handle=handle
   self:setRunning(running)
  end
  self.lastSpeed=requested
 end
 function self:setRunning(on)
  if self.running~=on then
   for _,entry in ipairs(self.gaitLeases or{})do selectGait(entry,on)end
   self.running=on
  end
  if not valid(self.walkProfile)then return end
  -- Keep both private profiles referenced by the native stack for the ride.
  -- An unpushed walking profile can be collected during a long sprint, leaving
  -- release-Shift stuck on the running profile. Priority selects the winner.
  local priority=on and 199 or 201
  if self.walkHandle~=nil and self.walkProfile.Priority==priority then return end
  if self.walkHandle~=nil then self.movement:PopMovementProfile(self.walkHandle);self.walkHandle=nil end
  self.walkProfile.Priority=priority
  local handle=self.movement:PushMovementProfile(self.walkProfile)
  assert(type(handle)=='number'and handle>=0,'Walking profile lease was rejected')
  self.walkHandle=handle
 end
 function self:setMoving(on)
  if on then
   if self.idleRotationHandle~=nil then self.movement:PopRotationMode(self.idleRotationHandle);self.idleRotationHandle=nil end
  elseif self.idleRotationHandle==nil then
   -- Native pawn focus can return after ClearFocus. None prevents idle facing
   -- without fighting the actor transform every frame. Restore velocity-facing
   -- only when the rider supplies movement input.
   local handle=self.movement:PushRotationMode(0,201)
   assert(type(handle)=='number'and handle>=0,'Idle rotation lease was rejected')
   self.idleRotationHandle=handle
  end
 end
 function self:update(pc,dt)
  if not self.active or not self:current(pc)then return false end
  if self.gaitFamily then
   self.gaitCheck=(self.gaitCheck or 0)-(tonumber(dt)or 0)
   if self.gaitCheck<=0 then
    self.gaitCheck=.5
    -- Variant attachments can replace their inherited animation layer after
    -- spawn. Refresh only the mounted mesh, never scan the world's animals.
    nativeGaitCycles(self,self.gaitFamily,self.gaitSource,self.gaitPace)
   end
  end
  local forward=(key(pc,'W')and 1 or 0)-(key(pc,'S')and 1 or 0)
  local side=(key(pc,'D')and 1 or 0)-(key(pc,'A')and 1 or 0)
  local magnitude=math.sqrt(forward*forward+side*side)
  self:setMoving(magnitude>0)
  if magnitude>0 then
   local running=key(pc,'LeftShift')or key(pc,'RightShift');self:setRunning(running)
   local heading=math.rad(yaw(pc:GetControlRotation()));local x=(math.cos(heading)*forward-math.sin(heading)*side)/magnitude
   local y=(math.sin(heading)*forward+math.cos(heading)*side)/magnitude
   local c=self.actor.Controller
   if valid(c)then
    local desired=math.deg(math.atan(y,x));local angle=yaw(c:GetControlRotation());local delta=(desired-angle+180)%360-180
    c:SetControlRotation({pitch=0,Pitch=0,Yaw=angle+delta*math.min(1,math.max(0,tonumber(dt)or 0)*5),Roll=0})
   end
   self.actor:AddMovementInput({X=x,Y=y,Z=0},(valid(self.walkProfile)or running)and 1 or 0.375,true)
  end
  return true
 end
 function self:brake(pc)
  if self.active and self:current(pc)then self.movement:StopMovementImmediately();self:setMoving(false)end
 end
 function self:release(pc)
  -- Drop only retired Lua bookkeeping; never restore onto another pawn/world.
  if not self:current(pc)then
   self.active=false;self.handle=nil;self.walkHandle=nil;self.rotationHandle=nil;self.idleRotationHandle=nil;self.profile=nil;self.walkProfile=nil;self.cycleLeases=nil;self.gaitLeases=nil;self.running=nil;self.releaseSteps=nil;return true
  end
  if not self.active and self.handle==nil and self.walkHandle==nil and self.rotationHandle==nil and self.idleRotationHandle==nil and not self.releaseSteps then return true end
  self.active=false;self.releaseSteps=self.releaseSteps or{}
  local failures={};local function restore(label,fn)
   if self.releaseSteps[label]then return end
   local ok,err=pcall(fn);if ok then self.releaseSteps[label]=true else failures[#failures+1]=label..': '..tostring(err)end
  end
  restore('walking profile',function()if self.walkHandle~=nil then self.movement:PopMovementProfile(self.walkHandle);self.walkHandle=nil end end)
  restore('movement profile',function()if self.handle~=nil then self.movement:PopMovementProfile(self.handle);self.handle=nil end end)
  restore('creature cycle selector',function()
   for _,entry in ipairs(self.gaitLeases or{})do selectGait(entry,false)end
   for _,entry in ipairs(self.cycleLeases or{})do
    if valid(entry.layer)and valid(entry.original)and valid(entry.layer.CycleBlendSpaceSet)
     and entry.layer.CycleBlendSpaceSet:GetAddress()==entry.copy:GetAddress()then entry.layer.CycleBlendSpaceSet=entry.original end
   end
   self.cycleLeases=nil;self.gaitLeases=nil;self.running=nil
  end)
  restore('idle rotation mode',function()if self.idleRotationHandle~=nil then self.movement:PopRotationMode(self.idleRotationHandle);self.idleRotationHandle=nil end end)
  restore('rotation mode',function()if self.rotationHandle~=nil then self.movement:PopRotationMode(self.rotationHandle);self.rotationHandle=nil end end)
  restore('focus',function()
   if self.focusCleared and valid(self.controller)and valid(self.actor.Controller)
    and self.actor.Controller:GetAddress()==self.controller:GetAddress()and not valid(self.controller:GetFocusActor())and valid(self.oldFocus)then self.controller:K2_SetFocus(self.oldFocus)end
   self.focusCleared=nil;self.oldFocus=nil
  end)
  restore('walk speed',function()if self.oldMaxWalkSpeed~=nil then self.movement.MaxWalkSpeed=self.oldMaxWalkSpeed end end)
  restore('acceleration',function()if self.oldAcceleration~=nil then self.movement.MaxAcceleration=self.oldAcceleration end end)
  restore('stop',function()self.movement:StopMovementImmediately()end)
  if #failures>0 then self.releaseError=table.concat(failures,'; ');return false,self.releaseError end
  self.profile=nil;self.walkProfile=nil;self.releaseSteps=nil;self.releaseError=nil;return true
 end
 return self
end
return M
