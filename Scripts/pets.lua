-- Passive population animals have no combat board. Keep their lifecycle and
-- navigation separate from the fighter adapter; never give them combat AI.
local Module={}
function Module.new(sharedPayload)
 local modules={runtime_path=sharedPayload..'/runtime'}
 local env=setmetatable({},{__index=_G})
 env.require=function(name)
  if modules[name]~=nil then return modules[name]end
  assert(name=='ai_state' or name=='companion_native','Unsupported pet utility')
  modules[name]=assert(loadfile(sharedPayload..'/mod/Scripts/'..name..'.lua','t',env))()
  return modules[name]
 end
 local M={};local AI=env.require('ai_state');local Native=env.require('companion_native')
local definitions={
 pet_white_cat={name='White House Cat',asset='Cat',white=true},
 pet_rabbit={name='Rabbit',asset='Rabbit'},
 pet_chicken={name='Chicken',asset='Chicken'},
 pet_goat={name='Goat',asset='Goat_F'},
 pet_sheep={name='Sheep',asset='Sheep'},
}
local entries={};local serial=0;local player,world;local nextTick=0
local function valid(o)return AI.valid(o)and not o:HasAnyFlags(EObjectFlags.RF_BeginDestroyed|EObjectFlags.RF_FinishDestroyed)end
local function live(o)return valid(o)and not o:IsActorBeingDestroyed()and AI.sameInstance(o:GetWorld(),world)end
local function point(o)local p=o:K2_GetActorLocation();return {X=p.X,Y=p.Y,Z=p.Z}end
local function distance(a,b)return math.sqrt((a.X-b.X)^2+(a.Y-b.Y)^2+(a.Z-b.Z)^2)end
local function project(p)
 local output={X=0,Y=0,Z=0};local nav=AI.find('/Script/NavigationSystem.Default__NavigationSystemV1')
 if valid(nav)and nav:K2_ProjectPointToNavigation(player,p,output,nil,nil,{X=150,Y=150,Z=250})then return {X=output.X,Y=output.Y,Z=output.Z}end
end
local function pace(e,running)
 local movement=e.actor.CharacterMovement;if not valid(movement)then return end
 if not running then
  if e.runHandle~=nil then movement:PopMovementProfile(e.runHandle);e.runHandle=nil end
  return
 end
 if e.runHandle~=nil then return end
 local source=e.actor.RunAwayMovementProfile
 if not valid(source)then return end
 -- Reuse the animal's authored running gait without its fear logic. Never
 -- edit the shared profile used by wild animals or campaign characters.
 local profile=StaticConstructObject(source:GetClass(),movement,0,0,0,false,false,source)
 assert(valid(profile)and profile:GetAddress()~=source:GetAddress(),'Private pet running profile unavailable')
 profile.Priority=200
 e.runProfile=profile;e.runHandle=movement:PushMovementProfile(profile)
end
function M.supports(id)return definitions[id]~=nil end
function M.isId(id)return type(id)=='string'and id:match('^pet_')~=nil end
function M.info(id)
 local e=entries[id];if not e then return {phase='unavailable',memberId=id,error='Pet no longer present'}end
 if e.error then return {phase='failed',memberId=id,error=e.error}end
 if not e.ready then return {phase='loading',memberId=id,error=e.status or'Loading pet'}end
 if not live(e.actor)then return {phase='unavailable',memberId=id,error='Pet is unavailable'}end
 return {phase='ready',memberId=id,actorPath=e.actor:GetFullName(),actorAddress=tostring(e.actor:GetAddress()),controlled=false,actor=e.actor}
end
function M.dismiss(id,retired)
 local e=entries[id];if not e then return true end
 if not retired and live(e.actor)then
  pace(e,false)
  e.actor:SetActorHiddenInGame(true);e.actor:SetActorEnableCollision(false)
  if valid(e.controller)then e.controller:StopMovement()end
 end
 if e.action then local ok,why=Native.stop(e.action);assert(ok,why)end
 entries[id]=nil;return true
end
function M.reset(retired)
 for id in pairs(entries)do M.dismiss(id,retired)end
 entries={};player=nil;world=nil
end
function M.summon(id)
 local d=assert(definitions[id],'Unknown pet');assert(live(player),'Player unavailable')
 serial=serial+1;local key='pet_'..os.time()..'_'..serial
 entries[key]={definition=d,path='/Game/_Dawnwalker/NPC/Animals/SimpleCharacter/NPCDef_'..d.asset..'.NPCDef_'..d.asset..'_C',age=0,mode='follow'}
 return key
end
function M.action(id,action)
 local e=assert(entries[id],'Pet unavailable');assert(e.ready and live(e.actor),'Pet is still loading')
 assert(action=='follow'or action=='stop'or action=='come'or action=='leave','Pets cannot attack or be ridden')
 if action=='leave'then return M.dismiss(id)end
 e.mode=action=='stop'and'stop'or'follow';e.goal=nil;e.rest=nil
 if e.mode=='stop'and valid(e.controller)then e.controller:StopMovement()end
 if e.mode=='stop'then pace(e,false)end
 return true
end
local function load(e)
 e.age=e.age+1;assert(e.age<=60,'Pet loading timed out')
 if not e.action then
  local cls=Native.loadedClass(e.path)
  if not valid(cls)then if not e.requested then assert(Native.requestClass(player,e.path));e.requested=true end;return end
  if not e.pawnPath then local info=assert(Native.inspect(cls:GetCDO()));e.pawnPath=assert(Native.exportedPath(info.pawnClass))end
  if not valid(Native.loadedClass(e.pawnPath))then if not e.bodyRequested then assert(Native.requestClass(player,e.pawnPath));e.bodyRequested=true end;return end
  local p=point(player);local f=player:GetActorForwardVector();local r=player:GetActorRightVector()
  local pos=assert(project({X=p.X+f.X*180+r.X*110,Y=p.Y+f.Y*180+r.Y*110,Z=p.Z}),'Move to open ground to summon a pet')
  local result,why=Native.spawn(player,cls,nil,pos,player:K2_GetActorRotation().Yaw+180);assert(result,why)
  e.action=assert(Native.exportedPath(result.action));return
 end
 local result,why=Native.poll(e.action);assert(result,why)
 for path in(result.pawns or''):gmatch('(/[^%s"\'(),=]+)')do
  local a=AI.find(path)
  if live(a)and a:IsA(AI.find('/Script/Dawnwalker.SimpleCharacter'))then e.actor=a;break end
 end
 if not e.actor then return end
 local a=e.actor
 a.bCanBeDamaged=false
 local stub=a.StubComponent.Stub
 if not valid(stub)or not valid(a.Mesh)or not valid(a.Mesh:GetSkinnedAsset())then return end
 assert(not stub:IsTargetable(),'This animal does not support passive pet targeting')
 if e.definition.white and not e.whiteMaterial then
  local white=AI.find('/Engine/EngineResources/WhiteSquareTexture.WhiteSquareTexture')
  assert(valid(white),'White coat texture is unavailable')
  local original=a.Mesh:GetMaterial(0)
  if not valid(original)then return end
  assert(original:GetFullName():find('/Animalia/Cat/',1,true),'Unexpected cat material')
  local material=a.Mesh:CreateDynamicMaterialInstance(0,original,FName('CompanionWhiteCoat'))
  assert(valid(material),'White coat material is unavailable')
  -- Only this copy's coat albedo changes. Native fur normal/roughness and
  -- the separate eye material remain intact; shared materials are read-only.
  material:SetTextureParameterValue(FName('01. Albedo'),white);e.whiteMaterial=material
 end
 -- The character's scare/wander tick competes with an owned follow path.
 -- Component animation, collision, gravity and path following keep ticking.
 a:SetActorTickEnabled(false);a.StubToRunAwayFrom=nil
 e.controller=a:GetController();if not valid(e.controller)then a:SpawnDefaultController();e.controller=a:GetController()end
 if not valid(e.controller)then return end
 e.controller:K2_ClearFocus();e.controller:StopMovement()
 if valid(e.controller.BrainComponent)then e.controller.BrainComponent:StopLogic('Passive pet following')end
 e.ready=true;e.rest=point(player)
end
local function follow(e)
 assert(live(e.actor),'Pet is no longer present')
 e.actor.bCanBeDamaged=false
 if e.mode~='follow'or not valid(e.controller)then return end
 local p,a=point(player),point(e.actor);local gap=distance(p,a)
 pace(e,gap>350 or e.runHandle~=nil and gap>220)
 if e.goal and e.controller:GetMoveStatus()==0 then e.goal=nil;e.rest=p end
 if gap<160 then if e.goal then e.controller:StopMovement();e.goal=nil;e.rest=p end;return end
 if not e.goal and e.rest and distance(p,e.rest)<180 and gap<550 then return end
 if e.goal and distance(p,e.goal)<100 then return end
 local f=player:GetActorForwardVector();local r=player:GetActorRightVector()
 local target=project({X=p.X-f.X*90+r.X*115,Y=p.Y-f.Y*90+r.Y*115,Z=p.Z})
 if not target then return end
 local result=e.controller:MoveToLocation(target,65,true,true,true,false,nil,true)
 if result~=0 then e.goal=p;e.rest=nil end
end
function M.tick(pc)
 local pawn,w=AI.playerReady(pc)
 if not pawn then if player then M.reset(true)end;return end
 if player and(not AI.sameInstance(player,pawn)or not AI.sameInstance(world,w))then M.reset(true)end
 player,world=pawn,w
 if AI.find('/Script/Engine.Default__GameplayStatics'):IsGamePaused(pc)then return end
 local now=os.clock();if now<nextTick then return end;nextTick=now+1
 for _,e in pairs(entries)do
  if not e.error then
   local ok,why=pcall(e.ready and follow or load,e)
   if not ok then e.error=tostring(why);print('[CreatureCompanionMounts] Pet: '..e.error..'\n')end
  end
 end
end
return M
end
return Module
