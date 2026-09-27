local M={}
local function valid(o)return o and o:IsValid()and not o:HasAnyFlags(EObjectFlags.RF_BeginDestroyed|EObjectFlags.RF_FinishDestroyed)end
local function identity(o)return o:GetFullName()..'#'..tostring(o:GetAddress())end
local function readProfile(path)
 local f=io.open(path,'r');if not f then return end;local text=f:read(4096)or'';f:close()
 local id=text:match('"characterId"%s*:%s*"([%x%-]+)"');if id and #id==36 then return id end
end
function M.new(modRoot,sharedPayload,log,settings,previous)
 local Service=dofile(sharedPayload..'/sdk/CompanionCreatures.lua');local SDK=dofile(sharedPayload..'/sdk/CompanionAI.lua')
 local Movement=dofile(modRoot..'/Scripts/movement.lua');local Mount=dofile(modRoot..'/Scripts/mount.lua')
 local roster=dofile(modRoot..'/Scripts/roster.lua');local byId={};for _,r in ipairs(roster)do byId[r.id]=r end
 local Settings=dofile(modRoot..'/Scripts/settings.lua')
 local actionProfile=readProfile(modRoot..'/config/action-profile.json');settings=settings or{}
 local loaded,profiles=pcall(dofile,modRoot..'/config/creature-profiles.lua');if not loaded or type(profiles)~='table'then profiles={}end
 local voiceMode=settings.voice or 0;local languageMode=settings.language or 0
 local function profileFor(id)
  local row=profiles[id];if not row then return actionProfile end
  local multilingual=voiceMode==2
  if voiceMode==0 then
   local f=io.open(sharedPayload..'/runtime/ui-language.txt','r');local language=f and f:read(32)or'en';if f then f:close()end
   multilingual=languageMode>1 or languageMode==0 and language:gsub('%s','')~='en'
  end
  return multilingual and row.multilingual or row.english
 end
 local self={roster=roster,selectedId=roster[1].id,status='Choose a creature, then summon it.',size=settings.size or 100,speed=settings.speed or 100,replies=settings.replies~=false,log=log or function()end}
 self.service=previous and previous.service or Service.new(sharedPayload..'/runtime','creature-companion-mounts');self.ai=previous and previous.ai or SDK.new(sharedPayload..'/runtime','creature-companion-mounts')
 self.seats=settings.seats or{}
 function self:applySeat()
  if not self.active or not self.mountState then return end
  local seat=Settings.seat(self,self.active.definition.id);self.mountState:setOffsets(seat.height,seat.forward,seat.side)
 end
 function self:view()
  local a=self.active;local mounted=self.mountState and self.mountState.state=='mounted'
  return {roster=self.roster,selected=byId[self.selectedId],selectedId=self.selectedId,
   active=a and{id=a.definition.id,name=a.definition.name,actor=a.actor,memberId=a.memberId,mounted=mounted,rideable=a.definition.rideable~=false},
   mounted=mounted,mountState=self.mountState and self.mountState.state or'unmounted',loading=self.requestId~=nil or self.dismissId~=nil or self.dismissPending==true or self.recovering==true or(self.mountState and self.mountState.state=='preparing')or false,status=self.status,size=self.size,speed=self.speed}
 end
 function self:select(id)if byId[id]then self.selectedId=id end end
 function self:summon(id)
  local r=byId[id or self.selectedId];if not r then return false,'Choose a creature'end
  if not r.enabled then self.status='This creature is awaiting a compatible seat.';return false,self.status end
  if self.requestId or self.dismissId or self.dismissPending then self.status='Wait for the current creature operation';return false,self.status end
  if self.active then
   self.replacement=r.id;local ok,message=self:dismiss()
   if not ok then self.replacement=nil end
   return ok,message
  end
  self.selectedId=r.id;self.requestDefinition=r;self.requestId=self.service:summon(r.catalogueId);self.status='Loading '..r.name..'...';return true
 end
 function self:dismiss()
  if self.dismissId or self.dismissPending then self.status='Dismissal is already pending';return false,self.status end
  if not self.active then self.status='No creature is present';return false,self.status end
  if self.mountState and self.mountState.state~='unmounted'then
   if self.mountState.state~='restoring'then
    local ok,err=self:dismount()
    if not ok and self.mountState.state~='restoring'then self.status=err or'Could not dismount';return false,self.status end
   end
   if self.mountState.state~='unmounted'then self.dismissPending=true;self.status='Restoring Coen before dismissing the creature...';return true,self.status end
  end
  self.dismissId=self.service:dismiss(self.active.memberId);self.status='Dismissing creature...';return true,self.status
 end
 function self:toggleMount()
  if self.dismissId or self.dismissPending or self.requestId then self.status='Wait for the current creature operation';return false,self.status end
  if self.mountState and self.mountState.state~='unmounted'then return self:dismount()end
  return self:mount()
 end
 function self:mount()
  if self.dismissId or self.dismissPending then self.status='Wait for dismissal to finish';return false,self.status end
  if not self.active or not self.mountState then self.status='Summon a creature first';return false,self.status end
  if self.active.definition.rideable==false then self.status='This creature can fight beside you, but has no native ground-riding gait.';return false,self.status end
  local ok,message=self.mountState:request(self.pc);self.status=message or(ok and'Ready to ride'or'Cannot ride yet')
  self.log((ok and 'Mount requested: 'or 'Mount unavailable: ')..self.status)
  if ok then self:registerAI()end;return ok,self.status
 end
 function self:dismount()
  if not self.mountState then return false,'Not riding'end
  local ok,message=self.mountState:dismount();self.status=message or(ok and'Dismounted. Your creature follows normally.'or'Could not dismount');self:registerAI();return ok,self.status
 end
 function self:applySize()
  local a=self.active;if not a or not valid(a.actor)then return end
  if self.mountState and self.mountState.state~='unmounted'then self.status='Dismount before changing size';return end
  local p=a.actor:K2_GetActorLocation();local oldHalf=a.actor.CapsuleComponent:GetScaledCapsuleHalfHeight()
  local factor=self.size/100;a.actor:SetActorScale3D({X=a.baseScale.X*factor,Y=a.baseScale.Y*factor,Z=a.baseScale.Z*factor})
  local newHalf=a.actor.CapsuleComponent:GetScaledCapsuleHalfHeight()
  a.actor:K2_SetActorLocation({X=p.X,Y=p.Y,Z=p.Z+newHalf-oldHalf},true,{},false)
 end
 function self:setSize(value)
  if self.mountState and self.mountState.state~='unmounted'then return false,'Dismount before changing size'end
  self.size=math.max(50,math.min(250,tonumber(value)or 100));self:applySize();return true
 end
 function self:setSpeed(value)
  self.speed=math.max(50,math.min(250,tonumber(value)or 100));if self.movement then self.movement:setSpeed(self.speed)end;return true
 end
 function self:setSetting(key,value)
  if key=='seats'then self.seats=value or{};self:applySeat();return true end
  if key=='language'then languageMode=Settings.clamp(key,value);self:registerAI();return true end
  if key=='voice'then voiceMode=Settings.clamp(key,value);self:registerAI();return true end
  if key=='size'then return self:setSize(value)end
  if key=='speed'then return self:setSpeed(value)end
  if key=='replies'then self.replies=value==true;self:registerAI();if self.pc then self.ai:update(self.pc)end;return true end
  return false,'Unknown setting'
 end
 function self:registerAI()
  if not self.active then return end
  local r=self.active.definition;local characterId=profileFor(r.id);if not characterId then return false end
  local mount=self.mountState and self.mountState.state or'unmounted'
  local available=mount=='unmounted'
  local actions=available and{'Follow','Stop Walking','Look At Player','Leave','Come Here','Attack Nearby Enemies'}or{}
  local state=available and(self.lastOrder and 'Last requested order: '..self.lastOrder or'Following Coen')or mount=='mounted'and'Coen is currently riding this creature'or'Riding transition in progress'
  self.ai:register('creature',self.active.actor,{characterId=characterId,name=r.name,silentReplies=not self.replies,localActionsOnly=not self.replies,
   actions=actions,
   context='You are Coen\'s allied '..r.species..' companion named '..r.name..'. '..state..'. Use your own stable personality and creature background. Speak ordinary dialogue in the player\'s language. No stage directions, animal noises, sniffs or growls. Briefly acknowledge supported orders and emit the appropriate listed action. You can also converse about the journey. No movement orders are available during riding or a riding transition. Do not invent actions or claim success before the game confirms it. Use the current species and identity, not another creature from earlier history.'})
  self.registeredProfile=characterId
  return true
 end
 function self:attach(status,definition)
  local actor=status.actor;local r=definition or self.requestDefinition;local scale=actor:GetActorScale3D()
  assert(r,'Creature definition is unavailable')
  self.recovering=nil;self.mountState=nil;self.movement=nil
  self.active={actor=actor,identity=identity(actor),memberId=status.memberId,definition=r,baseScale={X=scale.X,Y=scale.Y,Z=scale.Z}}
  self.requestId=nil;self.requestDefinition=nil;self:applySize()
  self.movement=Movement.new(actor,r.species);self.movement:setSpeed(self.speed)
  self:registerAI()
  self.mountState=Mount.new(actor,status.memberId,self.movement,self.ai,self.service,self.log)
  self:applySeat()
  self.status=r.name..' ready.'
 end
 function self:forget()
  if self.mountState then self.mountState:forget()end
  self.ai:unregister('creature');self.active=nil;self.requestId=nil;self.requestDefinition=nil;self.mountState=nil;self.movement=nil;self.lastOrder=nil
  self.dismissId=nil;self.dismissPending=nil;self.orderId=nil;self.replacement=nil;self.hostEpoch=nil;self.recovering=nil
  self.status='Loaded save changed. Summon a creature for this journey.'
 end
 function self:update(pc,dt)
  self.pc=pc
  if not valid(pc)or not valid(pc.Pawn)or not valid(pc.Pawn:GetWorld())then if self.world then self:forget();self.world=nil end;return end
  local world=identity(pc.Pawn:GetWorld())..'/'..identity(pc.Pawn)
  if self.world and world~=self.world then self:forget()end;self.world=world
  self.service:tick(pc)
  if self.hostEpoch and self.service.epoch~=self.hostEpoch then
   if self.mountState and self.mountState:current()then self.mountState:restore(self.mountState:safeExitPoint())end
   self:forget();self.status='The companion service restarted. Summon a creature again.'
  end
  self.hostEpoch=self.service.epoch
  if self.active and self.voicePollAt~=os.time()then
   self.voicePollAt=os.time()
   if profileFor(self.active.definition.id)~=self.registeredProfile then self:registerAI()end
  end
  self.ai:update(pc)
  if self.dismissPending and self.active and(not self.mountState or self.mountState.state=='unmounted')then
   self.dismissPending=nil;self.dismissId=self.service:dismiss(self.active.memberId);self.status='Dismissing creature...'
  end
  if self.dismissId then
   local result=self.service:status(self.dismissId)
   if result and result.phase=='dismissed'then
    local replacement=self.replacement;self.ai:unregister('creature');self.active=nil;self.mountState=nil;self.movement=nil;self.lastOrder=nil
    self.dismissId=nil;self.replacement=nil;self.status='Creature dismissed'
    if replacement then self:summon(replacement)end
   elseif result and(result.phase=='failed'or result.phase=='unavailable')and result.error then
    self.dismissId=nil;self.replacement=nil;self.status='Dismissal failed: '..result.error
   end
  end
  if self.requestId then
   local request=self.service:status(self.requestId)
   if request and request.phase=='ready'and valid(request.actor)then self:attach(request)
   elseif request and(request.phase=='failed'or request.phase=='error'or request.phase=='cancelled'or request.phase=='unavailable'and request.error)then self.status=request.error or'Creature could not be loaded';self.requestId=nil;self.requestDefinition=nil
   elseif request and request.phase=='unavailable'then self.status='Waiting for the companion service to resume...'end
  end
  if self.active then
   if not self.dismissId then
    local member=self.service:status(self.active.memberId)
    if member and member.phase=='loading'then
     if not self.recovering then
      if self.mountState and self.mountState:current()then self.mountState:restore(self.mountState:safeExitPoint())end
      self.ai:unregister('creature');self.recovering=true
     end
     self.status=member.error or'Your creature is recovering...';return
    elseif member and member.phase=='ready'and valid(member.actor)and identity(member.actor)~=self.active.identity then
     local definition=self.active.definition
     if self.mountState and self.mountState:current()then self.mountState:restore(self.mountState:safeExitPoint())end
     self.ai:unregister('creature');self:attach(member,definition)
    elseif member and member.phase=='ready'and self.recovering then
     self.recovering=nil;self:registerAI();self.status=self.active.definition.name..' has recovered.'
    elseif member and member.phase=='unavailable'and member.error then
     self:forget();self.status=member.error;return
    end
   end
   if not valid(self.active.actor)or self.active.actor:IsActorBeingDestroyed()or identity(self.active.actor)~=self.active.identity then
    if self.dismissId then return end
    self:forget();self.status='The creature is no longer present';return
   end
   if self.mountState then
    local before=self.mountState.state;self.mountState:update(pc,dt)
    if before~=self.mountState.state then self.status=self.mountState.error or self.mountState.notice or(self.mountState.state=='mounted'and'Riding. WASD to move, Shift to run. Use Mount / Dismount to get off.'or'Ready to travel beside you.');self:registerAI()end
    if self.mountState.state=='preparing'and self.mountState.preparingMessage then self.status=self.mountState.preparingMessage end
   end
   local action=self.ai:pollAction()
   if action then
    if self.mountState and self.mountState.state~='unmounted'then self.status='Dismount before giving movement orders.'
    elseif self.service.action and not self.dismissId and not self.dismissPending then self.orderId=self.service:action(self.active.memberId,action.name);self.lastOrder=action.name;self.status='Order: '..action.name;self:registerAI()end
   end
   if self.orderId then local result=self.service:status(self.orderId)
    if result and result.phase=='failed'then self.status=result.error or'The order could not be carried out';self.orderId=nil
    elseif result and result.phase=='completed'then self.orderId=nil end
   end
  end
 end
 function self:shutdown()
  if self.mountState and self.mountState:current()then self.mountState:restore(self.mountState:safeExitPoint())end
  self.ai:close();self.service:close()
 end
 if previous then
  assert(not previous.requestId and not previous.dismissId and not previous.dismissPending and not previous.orderId and not previous.recovering,'Creature operation still active')
  assert(not previous.mountState or previous.mountState.state=='unmounted','Dismount before reloading mount code')
  self.pc=previous.pc;self.world=previous.world;self.hostEpoch=previous.hostEpoch
  self.selectedId=byId[previous.selectedId]and previous.selectedId or self.selectedId
  self.lastOrder=previous.lastOrder;self.status=previous.status
  if previous.active then
   local a=previous.active
   assert(valid(a.actor)and identity(a.actor)==a.identity and byId[a.definition.id],'Creature changed during reload')
   self.active={actor=a.actor,identity=a.identity,memberId=a.memberId,definition=byId[a.definition.id],baseScale=a.baseScale}
   self.movement=Movement.new(a.actor,self.active.definition.species);self.movement:setSpeed(self.speed)
   self.mountState=Mount.new(a.actor,a.memberId,self.movement,self.ai,self.service,self.log)
   self:applySeat()
  end
 end
 return self
end
return M
