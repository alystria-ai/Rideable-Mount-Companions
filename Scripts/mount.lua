-- Coen remains possessed. Only this session owns his seat, camera and input
-- suppression; the parent mod grants separate creature and camera leases.
local M={}
local function valid(o)return o and o:IsValid()and not o:HasAnyFlags(EObjectFlags.RF_BeginDestroyed|EObjectFlags.RF_FinishDestroyed)end
local function id(o)return o:GetFullName()..'#'..tostring(o:GetAddress())end
local function v(x,y,z)return {X=x,Y=y,Z=z}end
local function vec(p)return v(p.X,p.Y,p.Z)end
-- This build exposes CoreUObject.Rotator as pitch / Yaw / Roll. Keep both
-- pitch spellings when constructing a value for UE4SS's native marshaller.
local function norm(p)
 local pitch=tonumber(p.pitch or p.Pitch)or 0
 return {pitch=pitch,Pitch=pitch,Yaw=tonumber(p.Yaw or p.yaw)or 0,Roll=tonumber(p.Roll or p.roll)or 0}
end
local function path(o)return o:GetFullName():match('^%S+ (.+)$')end
local cached={}
local function find(p)
 local o=cached[p];if valid(o)and path(o)==p then return o end
 o=StaticFindObject(p);if valid(o)then cached[p]=o end;return o
end
local posePath='/Game/_Dawnwalker/Animation_MH/Humans/Male_Human/Animation/Community/Male_Human_Community_Background_Sitting_B/Male_Human_Community_Sitting_Reading_Book_Loop_01.Male_Human_Community_Sitting_Reading_Book_Loop_01'
local function blocked(pc)
 return find('/Script/Engine.Default__GameplayStatics'):IsGamePaused(pc)or pc:IsAnyGameInputBlockerActive()
end
local function fighting(actor)
 local lib=find('/Script/RebelAI.Default__RebelAIBlueprintFunctionLibrary')
 if not valid(actor)or actor:IsActorBeingDestroyed()or not valid(lib)then return false end
 local stub=lib:GetAIStub(actor)
 if not valid(stub)or not valid(stub.AIBoard)then return false end
 if not stub:IsInitializedAndHasPawn()or not valid(stub.AIBoard)then return false end
 local attached=stub:GetActor()
 if not valid(attached)or attached:GetAddress()~=actor:GetAddress()then return false end
 return stub:IsInCombat()==true or stub.AIBoard.Combat.bInCombat==true
end
function M.new(actor,memberId,movement,ai,service,log)
 local self={actor=actor,memberId=memberId,movement=movement,ai=ai,service=service,state='unmounted',log=log or function()end}
 function self:setOffsets(height,forward,side)
  self.offsets={height=height,forward=forward,side=side}
  local s=self.session;if self.state=='mounted'and s and s.seatCalibrated and self:current()then self:applyOffsets()end
 end
 function self:applyOffsets()
  local s=self.session;local o=self.offsets or{};local base=s.baseSeatPosition
  if not base then return end
  -- Local seat axes rotate with the mount, and Coen keeps his own scale.
  s.rider:K2_SetActorRelativeLocation(v(base.X+(o.forward or 0),base.Y+(o.side or 0),base.Z+(o.height or 0)),false,{},true)
 end
 function self:current()
  local s=self.session
  return s and valid(s.pc)and valid(s.rider)and id(s.pc)==s.pcId and id(s.rider)==s.riderId
   and valid(self.actor)and not self.actor:IsActorBeingDestroyed()and id(self.actor)==s.actorId
   and valid(s.rider:GetWorld())and id(s.rider:GetWorld())==s.world
   and valid(s.pc.Pawn)and id(s.pc.Pawn)==s.riderId
 end
 function self:request(pc)
  if self.state~='unmounted'then return false,'A riding transition is already active'end
  self.notice=nil;self.error=nil
  if self.releasedAt then
   local acknowledgement=self.service:status(self.memberId)
   if not acknowledgement or not acknowledgement.stamp or acknowledgement.stamp<=self.releasedAt or acknowledgement.controlled then return false,'Waiting for the previous ride to finish restoring'end
   self.releasedAt=nil
  end
  if not valid(pc)or not valid(pc.Pawn)or not valid(self.actor)then return false,'Player or creature unavailable'end
  local rider=pc.Pawn
  if fighting(rider)or fighting(self.actor)then return false,'Finish combat before riding'end
  if valid(rider:GetAttachParentActor())then return false,'Coen is already attached to another object'end
  local p,d=rider:K2_GetActorLocation(),self.actor:K2_GetActorLocation()
  if (p.X-d.X)^2+(p.Y-d.Y)^2+(p.Z-d.Z)^2>700^2 then return false,'Move closer to your creature'end
  local mesh=rider.Mesh;local pose=find(posePath)
  if not valid(mesh)or not valid(mesh:GetSkinnedAsset())or not valid(mesh:GetSkinnedAsset().Skeleton)then return false,'Coen\'s body is not ready'end
  if valid(pose)and(not valid(pose.Skeleton)or path(pose.Skeleton)~=path(mesh:GetSkinnedAsset().Skeleton))then return false,'Seated animation does not match Coen in this build'end
  if rider.CharacterMovement.MovementMode~=1 then return false,'Stand on solid ground before riding'end
  if not valid(self.actor.Mesh)or self.actor.Mesh:GetBoneIndex(FName('spine_02'))<0 then return false,'This creature does not yet have a verified back bone'end
  self.session={pc=pc,rider=rider,pcId=id(pc),riderId=id(rider),actorId=id(self.actor),world=id(rider:GetWorld()),pose=pose,mesh=mesh,start=os.time()}
  self.state='preparing';self.service:setControlLease(self.memberId,true);self.service:tick(pc)
  self.ai:setCameraLease('creature',true);self.ai:update(pc)
  return true,'Preparing to ride. Return to gameplay to mount.'
 end
 function self:activate()
  local s=self.session;local pc,rider=s.pc,s.rider
  assert(self:current()and self.service:controlReady(self.memberId)and self.ai:cameraReady('creature'),'Riding leases are not ready')
  s.pose=find(posePath)
  assert(valid(s.pose)and valid(s.pose.Skeleton)and path(s.pose.Skeleton)==path(s.mesh:GetSkinnedAsset().Skeleton),'Compatible seated animation is not ready')
  -- Capture after the parent camera releases its own first-person body mask.
  s.view=pc:GetViewTarget();s.collision=rider:GetActorEnableCollision()
  s.originalPosition=vec(rider:K2_GetActorLocation());s.originalRotation=norm(rider:K2_GetActorRotation())
  s.movementMode=rider.CharacterMovement.MovementMode;s.customMode=rider.CharacterMovement.CustomMovementMode
  s.ignoreBaseRotation=rider.CharacterMovement.bIgnoreBaseRotation;s.controllerYaw=rider.bUseControllerRotationYaw
  assert(type(s.ignoreBaseRotation)=='boolean'and type(s.controllerYaw)=='boolean','Player rotation settings are not ready')
  s.animMode=s.mesh:GetAnimationMode();local anim=s.mesh:GetAnimInstance()
  assert(valid(anim),'Coen\'s animation instance is not ready');s.animClass=anim:GetClass()
  s.ignoredMovement=pc:IsMoveInputIgnored();s.capsuleHalf=rider.CapsuleComponent:GetScaledCapsuleHalfHeight()
  local acquired,reason=self.movement:acquire(pc);assert(acquired,reason)
  s.camera=rider:GetWorld():SpawnActor(find('/Script/Engine.CameraActor'),self.actor:K2_GetActorLocation(),{Pitch=0,Yaw=0,Roll=0})
  assert(valid(s.camera),'Riding camera could not be created')
  s.camera:SetOwner(self.actor)
  s.camera.CameraComponent.bConstrainAspectRatio=false;s.camera.CameraComponent.FieldOfView=85
  -- Validate the camera before changing Coen's movement, collision or pose.
  self:camera(0)
  s.seat=self.actor:AddComponentByClass(find('/Script/Engine.SceneComponent'),true,{
   Rotation={X=0,Y=0,Z=0,W=1},Translation=v(0,0,0),Scale3D=v(1,1,1)},false)
  assert(valid(s.seat),'Rider seat could not be created')
  local back=self.actor.Mesh:GetSocketLocation(FName('spine_02'));local root=self.actor:K2_GetActorLocation()
  local scale=self.actor:GetActorScale3D();local lift=math.max(8,16*scale.Z)
  s.seatLift=lift;s.poseElapsed=0
  -- A capsule origin is above the visual pelvis. Position the seated pelvis on
  -- the back while keeping Coen's own scale independent of creature size.
  s.seat:K2_SetWorldLocationAndRotation(v(back.X,back.Y,back.Z+s.capsuleHalf+lift),norm(self.actor:K2_GetActorRotation()),false,{},true)
  assert(s.seat:K2_AttachToComponent(self.actor:K2_GetRootComponent(),FName('None'),1,1,1,false),'Seat attachment failed')
  self.movement:brake(pc);s.playerMutated=true;rider.CharacterMovement:StopMovementImmediately()
  rider.CharacterMovement:SetMovementMode(0,0);rider:SetActorEnableCollision(false)
  rider.CharacterMovement.bIgnoreBaseRotation=true;rider.bUseControllerRotationYaw=false
  if not s.ignoredMovement then pc:SetIgnoreMoveInput(true);s.ownsMoveIgnore=true end
  assert(rider:K2_AttachToComponent(s.seat,FName('None'),2,2,1,false),'Rider attachment failed')
  s.attached=true;s.animationChanged=true;s.mesh:PlayAnimation(s.pose,true)
  self:camera(0)
  pc:SetViewTargetWithBlend(s.camera,s.firstPerson and 0 or 0.2,0,0,false);self.state='mounted';self.error=nil
  self.log('Mounted '..self.memberId)
 end
 function self:safeExitPoint()
  if not self:current()then return end
  local s=self.session;local a=self.actor:K2_GetActorLocation();local yaw=math.rad(norm(self.actor:K2_GetActorRotation()).Yaw)
  local capsule=s.rider.CapsuleComponent;local radius=capsule:GetScaledCapsuleRadius();local half=capsule:GetScaledCapsuleHalfHeight()
  local creatureRadius=self.actor.CapsuleComponent:GetScaledCapsuleRadius();local creatureHalf=self.actor.CapsuleComponent:GetScaledCapsuleHalfHeight()
  local lib=find('/Script/Engine.Default__KismetSystemLibrary');local color={R=0,G=0,B=0,A=0}
  local spread=math.max(130,creatureRadius+radius+65)
  for _,ring in ipairs({1,1.6,2.2})do
  for _,offset in ipairs({math.pi/2,-math.pi/2,math.pi,0,math.pi/4,-math.pi/4,3*math.pi/4,-3*math.pi/4})do
   local x,y=a.X+math.cos(yaw+offset)*spread*ring,a.Y+math.sin(yaw+offset)*spread*ring;local hit={}
   if lib:LineTraceSingle(s.pc,v(x,y,a.Z+creatureHalf+100),v(x,y,a.Z-creatureHalf-300),0,false,{self.actor,s.rider},0,hit,true,color,color,0)and hit.ImpactNormal.Z>=0.72 then
    local dest=v(hit.ImpactPoint.X,hit.ImpactPoint.Y,hit.ImpactPoint.Z+half+5);local clear={}
    if not lib:CapsuleTraceSingle(s.pc,dest,v(dest.X,dest.Y,dest.Z+1),radius,half,0,false,{self.actor,s.rider},0,clear,true,color,color,0)then return dest end
   end
  end
  end
 end
 function self:releaseLeases(pc)
  self.releasedAt=os.time()
  self.service:setControlLease(self.memberId,false);self.service:tick(pc)
  if self.ai.actors.creature then self.ai:setCameraLease('creature',false);self.ai:update(pc)end
 end
 function self:restore(dest)
  local s=self.session;if not self:current()then self:forget();return false end
  local now=os.time()
  if s.nextRestoreAt and now<s.nextRestoreAt then return false,self.error end
  s.nextRestoreAt=now+1;self.state='restoring'
  if s.attached then
   local parent=s.rider:GetAttachParentActor()
   if not valid(parent)or parent:GetAddress()~=self.actor:GetAddress()then
    -- The host guard or native scene already detached Coen. Never pop its
    -- input counter or reapply player animation a second time.
    s.externalRestore=true;s.attached=false
   end
  end
  s.restoreDestination=s.restoreDestination or dest or s.originalPosition;s.restored=s.restored or{}
  local failures={};local function restore(label,fn)
   if s.restored[label]then return end
   local ok,err=pcall(fn);if ok then s.restored[label]=true else failures[#failures+1]=label..': '..tostring(err)end
  end
  local function failed()
   self.error=table.concat(failures,'; ')
   if s.lastRestoreError~=self.error then s.lastRestoreError=self.error;self.log('Rider recovery: '..self.error)end
   return false,self.error
  end
  restore('movement',function()local ok,err=self.movement:release(s.pc);assert(ok,err)end)
  if s.attached then restore('detach',function()s.rider:K2_DetachFromActor(1,1,1);s.attached=false end)end
  if s.attached then return failed()end
  if s.playerMutated and not s.externalRestore then
   restore('position',function()s.rider:K2_SetActorLocation(s.restoreDestination,false,{},true)end)
   restore('collision',function()s.rider:SetActorEnableCollision(s.collision)end)
   restore('player movement',function()s.rider.CharacterMovement:SetMovementMode(s.movementMode,s.customMode)end)
   restore('player rotation',function()s.rider.CharacterMovement.bIgnoreBaseRotation=s.ignoreBaseRotation;s.rider.bUseControllerRotationYaw=s.controllerYaw end)
  end
  if s.animationChanged and not s.externalRestore then
   -- SetAnimInstanceClass can recreate the native instance. Complete it once,
   -- independently of SetAnimationMode, so a later retry cannot restart it.
   restore('animation class',function()s.mesh:SetAnimInstanceClass(s.animClass)end)
   if s.restored['animation class']then restore('animation mode',function()s.mesh:SetAnimationMode(s.animMode,false)end)end
  end
  if s.ownsMoveIgnore and not s.externalRestore then restore('input',function()s.pc:SetIgnoreMoveInput(false);s.ownsMoveIgnore=false end)end
  if valid(s.camera)then
   restore('camera',function()local view=s.pc:GetViewTarget();if valid(view)and view:GetAddress()==s.camera:GetAddress()then s.pc:SetViewTargetWithBlend(valid(s.view)and s.view or s.rider,0,0,0,false)end;s.camera:K2_DestroyActor()end)
  end
  if valid(s.seat)then restore('seat',function()s.seat:K2_DestroyComponent(self.actor)end)end
  if #failures>0 then return failed()end
  restore('leases',function()self:releaseLeases(s.pc)end)
  if #failures>0 then return failed()end
  self.session=nil;self.state='unmounted';self.error=s.activationError
  return true
 end
 function self:forget()
  -- World/save replacement owns destruction of retired actors. No stale native
  -- restoration is attempted against a new Coen or world.
  self.service:setControlLease(self.memberId,false)
  if self.ai.actors.creature then self.ai:setCameraLease('creature',false)end
  self.session=nil;self.state='unmounted';self.movement.active=false
 end
 function self:dismount()
  if self.state=='preparing'then return self:cancel()end
  if self.state~='mounted'or not self:current()then return false,'Not riding'end
  local dest=self:safeExitPoint();if not dest then self.movement:brake(self.session.pc);return false,'Move beside clear, level ground to dismount'end
  return self:restore(dest)
 end
 function self:cancel()
  if self.state=='preparing'and self:current()then self:releaseLeases(self.session.pc)end
  self.session=nil;self.state='unmounted';return true
 end
 function self:camera(dt)
  local s=self.session;local p=self.actor:K2_GetActorLocation();local r=norm(s.pc:GetControlRotation())
  local preferences=self.ai:cameraPreferences()
  if s.firstPerson~=preferences.firstPerson then
   s.firstPerson=preferences.firstPerson
   s.camera.Tags=s.firstPerson and {FName('CreatureMountFirstPerson')}or{}
  end
  local fov=s.firstPerson and preferences.fov or 85
  if s.cameraFov~=fov then s.camera.CameraComponent:SetFieldOfView(fov);s.cameraFov=fov end
  if s.firstPerson then
   -- Use a stable seated eye height rather than the bobbing animation socket.
   -- The rider's root includes the live seat offsets selected on Summon.
   local rider=s.rider:K2_GetActorLocation();local yaw=math.rad(r.Yaw)
   local pitch=math.max(-75,math.min(75,(r.pitch+180)%360-180))
   local dest=v(rider.X+preferences.forward*math.cos(yaw),rider.Y+preferences.forward*math.sin(yaw),rider.Z+(s.seatedEyeHeight or 65)+preferences.height)
   s.camera:K2_SetActorLocationAndRotation(dest,norm({pitch=pitch,Yaw=r.Yaw,Roll=0}),false,{},true)
   return
  end
  local yaw=math.rad(r.Yaw);local pitch=math.rad(math.max(-45,math.min(30,(r.pitch+180)%360-180)))
  local size=self.actor:GetActorScale3D().Z;local distance=math.max(340,420*math.sqrt(size))
  local target=v(p.X,p.Y,p.Z+self.actor.CapsuleComponent:GetScaledCapsuleHalfHeight()+65)
  local dest=v(target.X-distance*math.cos(yaw)*math.cos(pitch),target.Y-distance*math.sin(yaw)*math.cos(pitch),target.Z-distance*math.sin(pitch))
  local hit={};local color={R=0,G=0,B=0,A=0};local lib=find('/Script/Engine.Default__KismetSystemLibrary')
  if lib:LineTraceSingle(s.pc,target,dest,0,false,{self.actor,s.rider},0,hit,true,color,color,0)then dest=v(hit.ImpactPoint.X+hit.ImpactNormal.X*15,hit.ImpactPoint.Y+hit.ImpactNormal.Y*15,hit.ImpactPoint.Z+hit.ImpactNormal.Z*15)end
  s.camera:K2_SetActorLocation(dest,false,{},true);s.camera:K2_SetActorRotation(norm({pitch=math.deg(pitch),Yaw=r.Yaw,Roll=0}),false)
 end
 function self:update(pc,dt)
  if self.state=='unmounted'then return end
  if not self:current()then self:forget();return end
  local s=self.session
  if self.state=='restoring'then if os.time()>=(s.nextRestoreAt or 0)then self:restore()end;return end
  -- Two owned actors only, five checks per second, with no world scans or
  -- dialogue request. Latch combat until the rider has been restored.
  s.combatElapsed=(s.combatElapsed or .2)+dt
  if s.combatElapsed>=.2 then
   s.combatElapsed=0
   if fighting(s.rider)or fighting(self.actor)then s.combatDismount=true end
  end
  if s.combatDismount then
   if self.state=='preparing'then self:cancel();self.error='Finish combat before riding';return end
   self.movement:brake(pc)
   -- Pause preserves the seat; resume exits before accepting further input.
   if not blocked(pc)then
    s.exitElapsed=(s.exitElapsed or .25)+dt
    if s.exitElapsed>=.25 then
     s.exitElapsed=0
     local dest=self:safeExitPoint()
     if dest then self.log('Riding ended: combat started');self.notice='Dismounted for combat. Your creature can fight alongside you.';self:restore(dest);return end
     self.error='Combat started. Looking for clear ground to dismount.'
    end
   end
   -- If the host already revoked control, let the existing recovery below
   -- finish cleaning our camera and private profiles after its safe rollback.
   if self.service:controlReady(self.memberId)and self.ai:cameraReady('creature')then return end
  end
  if self.state=='preparing'then
   if os.time()-s.start>65 then self.error='Riding preparation expired';self.log(self.error);self:cancel();return end
   local member=self.service:status(self.memberId);self.preparingMessage=member and member.error or'Preparing to ride'
   if blocked(pc)then self.preparingMessage='Return to gameplay to mount';return end
   if self.service:controlReady(self.memberId)and self.ai:cameraReady('creature')then
    local ok,err=xpcall(function()self:activate()end,debug.traceback)
    if not ok then s.activationError=tostring(err):match('^[^\n]+');self.error=s.activationError;self.log(tostring(err));self:restore()end
   end
   return
  end
  if not self.service:controlReady(self.memberId)or not self.ai:cameraReady('creature')then
   self.log('Riding ended: creature control or camera lease was withdrawn')
   self.movement:brake(pc);self:restore(self:safeExitPoint()or s.originalPosition);return
  end
  -- An unavailable reflected field can return a truthy TrivialObject wrapper.
  -- Only an actual boolean means the engine has entered cinematic mode.
  local cinematic=pc.bCinematicMode==true or s.rider.IsCinematicFinisher==true
  if os.time()~=(s.lastDialogueCheck or 0)then
   s.lastDialogueCheck=os.time();s.nativeDialogue=false
   local library=find('/Script/Engine.Default__SubsystemBlueprintLibrary');local class=find('/Script/DialogueSystem.CinematicSubsystem')
   if valid(library)and valid(class)then local subsystem=library:GetWorldSubsystem(pc,class);s.nativeDialogue=valid(subsystem)and valid(subsystem:GetActiveDialogue())end
  end
  if cinematic or s.nativeDialogue then
   self.log(s.nativeDialogue and 'Riding ended: native dialogue started'or 'Riding ended: native cinematic or finisher started')
   self:restore(self:safeExitPoint()or s.originalPosition);return
  end
  if blocked(pc)then s.cameraNeedsResume=true;self.movement:brake(pc);return end
  if s.cameraNeedsResume then
   s.cameraNeedsResume=nil
   local view=pc:GetViewTarget()
   if valid(view)and view:GetAddress()==s.rider:GetAddress()then pc:SetViewTargetWithBlend(s.camera,0,0,0,false)end
  end
  if not s.seatCalibrated then
   s.poseElapsed=(s.poseElapsed or 0)+dt
   if s.poseElapsed>=.15 then
    -- The seated pelvis has a different height from standing Coen. Wait for
    -- animation evaluation, then align it to the creature's back once.
    local pelvis=s.mesh:GetSocketLocation(FName('pelvis'));local back=self.actor.Mesh:GetSocketLocation(FName('spine_02'))
    local p=s.rider:K2_GetActorLocation();local dx,dy,dz=back.X-pelvis.X,back.Y-pelvis.Y,back.Z+s.seatLift-pelvis.Z
    if dx*dx+dy*dy+dz*dz<300^2 then s.rider:K2_SetActorLocation(v(p.X+dx,p.Y+dy,p.Z+dz),false,{},true)end
    local base=s.rider:K2_GetRootComponent().RelativeLocation;s.baseSeatPosition=vec(base)
    local head=s.mesh:GetSocketLocation(FName('head'));local origin=s.rider:K2_GetActorLocation()
    s.seatedEyeHeight=head.Z-origin.Z
    s.seatCalibrated=true;self:applyOffsets()
   end
  end
  self.movement:update(pc,dt);self:camera(dt)
 end
 return self
end
return M
