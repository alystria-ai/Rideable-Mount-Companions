-- One game-thread dispatcher, with no independent service process or API key.
local source=debug.getinfo(1,'S').source:gsub('^@',''):gsub('\\','/')
local modRoot=assert(source:match('^(.*)/Scripts/main%.lua$'),'Cannot resolve Rideable Mount Companions directory')
local sharedPayload=modRoot..'/../DawnwalkerConvai/Payload'
local function log(message)
 print('[CreatureCompanionMounts] '..tostring(message)..'\n')
 local f=io.open(modRoot..'/runtime/status.txt','w');if f then f:write(os.date()..' '..tostring(message));f:close()end
end
local ok,err=pcall(function()
 local Menu=dofile(modRoot..'/Scripts/creature_menu.lua')
 local settings=Menu.configure({sharedPayload=sharedPayload,configPath=modRoot..'/config/config.ini'})
 local Controller=dofile(modRoot..'/Scripts/creature_runtime.lua')
 local controller=Controller.new(modRoot,sharedPayload,log,settings)
 local previous=_G.CreatureCompanionMounts
 if previous and previous.stop then previous.stop()end
 local instance={controller=controller,alive=true};_G.CreatureCompanionMounts=instance
 function instance.stop()instance.alive=false;Menu.close();controller:shutdown()end
 local watched={'creature_runtime','creature_menu','settings','keybindings','roster','movement','mount','localization','translations'}
 local function snapshot()
  local parts={}
  for _,name in ipairs(watched)do
   local path=modRoot..'/Scripts/'..name..'.lua';local f=assert(io.open(path,'r'));local text=f:read('*a');f:close()
   parts[#parts+1]=name..'\0'..text
  end
  local path=modRoot..'/config/creature-profiles.lua';local f=io.open(path,'r')
  if f then local text=f:read('*a');f:close();parts[#parts+1]=text end
  return table.concat(parts,'\0')
 end
 local function validateSources()
  for _,name in ipairs(watched)do assert(loadfile(modRoot..'/Scripts/'..name..'.lua','t',_G))end
  local path=modRoot..'/config/creature-profiles.lua';local f=io.open(path,'r')
  if f then f:close();assert(loadfile(path,'t',_G))end
 end
 local lastSnapshot=snapshot();local candidate,rejected,validated,pollAt
 local function reloadIfReady()
  if os.time()==pollAt then return end;pollAt=os.time()
  local ok,observed=pcall(snapshot)
  if not ok then return end -- Mid-copy or invalid Lua leaves the working version running.
  if observed==lastSnapshot then candidate=nil;instance.reloading=false;return end
  if observed==rejected then return end
  if observed~=candidate then candidate=observed;return end
  if validated~=observed then
   local valid,validationError=pcall(validateSources)
   if not valid then rejected=observed;instance.reloading=false;log('Keeping previous mount code: '..tostring(validationError));return end
   validated=observed
  end
  instance.reloading=true
  -- Use normal restoration and dismissal paths, never drop an attached rider.
  if Menu.isOpen()then Menu.close(true)end
  if controller.requestId or controller.dismissId or controller.dismissPending or controller.orderId or controller.recovering then return end
  if controller.mountState and controller.mountState.state~='unmounted'then
   if controller.mountState.state~='restoring'then controller:dismount()end
   return
  end
  if controller.active then controller:dismiss();return end
  local success,why=pcall(function()
   local nextMenu=dofile(modRoot..'/Scripts/creature_menu.lua')
   local nextSettings=nextMenu.configure({sharedPayload=sharedPayload,configPath=modRoot..'/config/config.ini'})
   local nextController=dofile(modRoot..'/Scripts/creature_runtime.lua').new(modRoot,sharedPayload,log,nextSettings,controller)
   -- Keep both SDK sessions alive; closing the old service would dismiss its member.
   Menu=nextMenu;controller=nextController;instance.controller=controller
   controller:registerAI()
  end)
  instance.reloading=false
  if success then lastSnapshot=observed;candidate=nil;rejected=nil;validated=nil;log('Mount code reloaded.')
  else rejected=observed;log('Mount reload deferred: '..tostring(why))end
 end
 local inFlight=false;local lastError=0;local playerController;local nextControllerPoll=0;local elapsed=0;local step=.033
 local function pump()
  if not instance.alive then inFlight=false;return end
  local worked,failure=pcall(function()
   if not playerController or not playerController:IsValid()or os.time()>=nextControllerPoll then
    playerController=FindFirstOf('BP_PlayerController_C');nextControllerPoll=os.time()+1
   end
   local pc=playerController
   if not pc or not pc:IsValid()then return end
   controller:update(pc,step)
   if not instance.reloading then Menu.tick(pc,controller)end
   reloadIfReady()
  end)
  if not worked and os.time()-lastError>=5 then lastError=os.time();log(failure)end
  inFlight=false
 end
 LoopAsync(16,function()
  if not instance.alive then return true end
  elapsed=elapsed+16
  local riding=controller.mountState and controller.mountState.state=='mounted'
  local transition=controller.mountState and controller.mountState.state~='unmounted'
  local interval=riding and 16 or(Menu.isOpen()or transition)and 33 or 100
  if not inFlight and elapsed>=interval then
   step=math.min(.1,elapsed/1000);elapsed=0;inFlight=true
   local queued,why=pcall(ExecuteInGameThread,pump,EGameThreadMethod.EngineTick);if not queued then inFlight=false;log(why)end
  end
  return false
 end)
 log('Loaded. Shift+F5 opens Rideable Mount Companions.')
end)
if not ok then log('Startup unavailable: '..tostring(err))end
