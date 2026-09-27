-- Native add-on panel. Shared utilities retain the main mod's input, font and
-- world-identity protections; this module owns only its widgets and settings.
local M={}
local script=debug.getinfo(1,'S').source:gsub('^@',''):gsub('\\','/')
local folder=assert(script:match('^(.*)/Scripts/[^/]+$'),'Cannot locate mount configuration')
local options={sharedPayload=folder..'/../DawnwalkerConvai/Payload',configPath=folder..'/config/config.ini',keybindingsPath=folder..'/config/keybindings.ini'}
local Keys=assert(loadfile(folder..'/Scripts/keybindings.lua'))()
local sharedKeys={SingleText='F6',SingleVoice='F7'};local keysAt,keysWire
local Settings=dofile(folder..'/Scripts/settings.lua')
local Localize=dofile(folder..'/Scripts/localization.lua')
local settings=Settings.load('');local v,pending;local serial=0
local AI,Input,Language,Font,Theme,sharedRuntime
local controller,lastPc,lastHeartbeat,lastRequest,nextPoll
local status='Ready';local constants={owner='creature-companion-mounts',heartbeat='addon-ui-creature-companion-mounts.tsv',request='addon-ui-creature-companion-mounts.request',ack='addon-ui-ready-creature-companion-mounts.tsv'}
local function read(path,limit)
 local f=io.open(path,'r');if not f then return ''end
 local value=f:read(limit or 2048)or '';f:close();return value
end
local function write(name,value)
 local f=io.open(sharedRuntime..'/'..name,'w');if not f then return false end
 f:write(value);f:close();return true
end

function M.loadSettings(path)
 if path then options.configPath=path end
 local source=read(options.configPath,16384)
 settings=Settings.load(source)
 -- Native menu choices need numeric, present keys even after an older install.
 local canonical=Settings.serialize(settings)
 if canonical~=source then local f=io.open(options.configPath,'w');if f then f:write(canonical);f:close()end end
 return M.getSettings()
end
function M.getSettings()local copy={};for k,value in pairs(settings)do copy[k]=value end;return copy end
function M.configure(opts)
 for key,value in pairs(opts or {})do if options[key]~=nil then options[key]=value end end
 sharedRuntime=options.sharedPayload..'/runtime'
 lastRequest=read(sharedRuntime..'/'..constants.request,256)
 Keys.load(options.keybindingsPath)
 return M.loadSettings()
end
local function pollKeys(force)
 local now=os.time();if not force and keysAt==now then return end;keysAt=now
 Keys.load(options.keybindingsPath)
 local wire=Keys.wire();if wire~=keysWire and write('addon-ui-creature-companion-mounts.keys.tsv',wire)then keysWire=wire end
 local source=read(options.sharedPayload..'/../keybindings.ini',4096)
 for _,action in ipairs({'SingleText','SingleVoice'})do sharedKeys[action]=source:match(action..'%s*=%s*([%w]+)')or(action=='SingleText'and'F6'or'F7')end
end
local function dependencies()
 if AI then return end
 sharedRuntime=options.sharedPayload..'/runtime'
 local modules={runtime_path=sharedRuntime}
 local allowed={ai_state=true,ui_input=true,ui_font=true,ui_localization=true,ui_translations=true}
 local env=setmetatable({},{__index=_G})
 env.require=function(name)
  if modules[name]~=nil then return modules[name]end
  assert(allowed[name],'Unsupported shared utility: '..tostring(name))
  local fn=assert(loadfile(options.sharedPayload..'/mod/Scripts/'..name..'.lua','t',env))
  modules[name]=fn();return modules[name]
 end
 AI=env.require('ai_state');Input=env.require('ui_input');Font=env.require('ui_font');Language=env.require('ui_localization')
 Theme=assert(loadfile(options.sharedPayload..'/../../DawnwalkerModMenu/Scripts/theme.lua'))()
end
local function playerIdentity(pc)
 local pawn,world=AI.playerReady(pc);if not pawn then return end
 return pawn,world,world:GetFullName()..'#'..world:GetAddress(),pawn:GetFullName()..'#'..pawn:GetAddress()
end
local function heartbeat(force)
 local now=os.time();if not force and now==lastHeartbeat then return end;lastHeartbeat=now
 local pawn,world,worldId,playerId=playerIdentity(lastPc)
 local current=v or pending
 local open=current and pawn and AI.sameInstance(pawn,current.pawn)and AI.sameInstance(world,current.world)
 write(constants.heartbeat,table.concat({'COMPANION-UI','1',tostring(now),open and '1'or '0',current and current.session or '-',worldId or '',playerId or ''},'\t'))
 if v and open then write('native-menu-open.txt',now..'\t'..v.session)end
end
local function otherMenu()
 local stamp,session=read(sharedRuntime..'/native-menu-open.txt',256):match('^(%d+)\t([^\r\n]+)')
 return stamp and os.time()-tonumber(stamp)>=0 and os.time()-tonumber(stamp)<=3 and (not v or session~=v.session)
end
local function cls(path)return assert(AI.find(path),path)end
local function tr(value)return Localize.text(value,Language)end
local function fmt(value,...)local args={...};return tr(value):gsub('{(%d+)}',function(n)return tr(tostring(args[tonumber(n)+1]or''))end)end
local function updateLanguage()
 local value=settings.language
 if value==0 then local source=read(options.sharedPayload..'/../config.ini',16384);value=tonumber(source:match('UiLanguage%s*=%s*([%d.]+)'))or 0 end
 if value>0 then Language.code=Language.languages[value]or'en'
 else Language.code=read(sharedRuntime..'/ui-language.txt',32):gsub('%s','');if Language.code==''then Language.code='en'end end
 Language.index=1;for i,code in ipairs(Language.languages)do if code==Language.code then Language.index=i;break end end
end
local function live(view)
 local pawn,world=AI.playerReady(view.pc)
 return pawn and AI.sameInstance(pawn,view.pawn)and AI.sameInstance(world,view.world)
end
function M.isOpen()return v~=nil or pending~=nil end
function M.status()return status end
function M.close(returnToGame)
 local old=v or pending;v=nil;pending=nil;if not old then return end
 local stamp,owner=read(sharedRuntime..'/native-menu-open.txt',256):match('^(%d+)\t([^\r\n]+)')
 if owner==old.session then write('native-menu-open.txt','0')end
 heartbeat(true)
 write('ui-control.txt','addon-menu-close:'..constants.owner..':'..old.session)
 if not old.host or not live(old)then return end
 for _,button in ipairs(old.buttons or {})do if AI.valid(button.click)then button.click:ClearSelection();button.click:SetIsInteractionEnabled(false);button.click:SetIsEnabled(false)end end
 pcall(function()old.host:DeactivateWidget();old.host:RemoveFromParent()end)
 Input.release(old.lease)
 if AI.valid(old.parent)then pcall(function()
  old.parent.bIsBackHandler=old.parentBack;old.parent:SetIsEnabled(old.parentEnabled)
  if returnToGame then old.parent:ResumeGame()
  else old.library:SetInputMode_GameAndUIEx(old.pc,old.parent,0,false,true);old.parent:SetUserFocus(old.pc)end
 end)end
 status='Ready'
end
local function new(kind)return StaticConstructObject(cls('/Script/UMG.'..kind),v.tree)end
local function add(parent,child)return parent:AddChild(child)end
local function fill(slot)slot:SetHorizontalAlignment(0);slot:SetVerticalAlignment(0);return slot end
local function size(child,width,height)
 local box=new('SizeBox');if width then box:SetWidthOverride(width)end;if height then box:SetHeightOverride(height)end;box:SetContent(child);return box
end
local function text(widget,value)
 value=tr(tostring(value or ''));if v.textCache[widget]==value then return end
 widget:SetText(cls('/Script/Engine.Default__KismetTextLibrary'):Conv_StringToText(value));v.textCache[widget]=value
end
local function font(widget,points)
 Theme.font(widget,v.theme,points)
 if not v.font then v.font=Font.resolve(Language.code,widget.Font.FontObject)end
 if AI.valid(v.font)then widget.Font.FontObject=v.font end
end
local function caption(value,points)
 local widget=new('TextBlock');text(widget,value);widget:SetAutoWrapText(true);widget:SetVisibility(3)
 font(widget,points or 25);Theme.textColor(widget,'body');return widget
end
local function art(name)return Theme.image(v.tree,v.theme,name,{construct=function(path,tree)return StaticConstructObject(cls(path),tree)end})end
local function button(parent,label,fn,width,prominent)
 local paint=new('Button');paint.IsFocusable=false;local labelWidget=caption(label,26);paint:SetContent(labelWidget)
 Theme.button(paint,labelWidget,v.theme,false);font(labelWidget,26);labelWidget:SetJustification(0)
 paint.WidgetStyle.NormalPadding={Left=0,Top=0,Right=0,Bottom=0};paint.WidgetStyle.PressedPadding={Left=0,Top=0,Right=0,Bottom=0}
 fill(labelWidget.Slot):SetPadding({Left=0,Top=6,Right=12,Bottom=6})
 local overlay=new('Overlay');fill(add(overlay,paint))
 local click=v.library:Create(v.pc,v.clickClass,v.pc)
 click:SetIsFocusable(false);click:SetShouldSelectUponReceivingFocus(false);click:SetIsSelectable(true);click:SetIsToggleable(false)
 click:SetIsInteractableWhenSelected(true);click:ClearSelection();click:SetTriggeringInputAction({RowName=FName('None')});click:SetRenderOpacity(0)
 click:SetIsInteractionEnabled(true);fill(add(overlay,click));paint:SetVisibility(3)
 add(parent,size(overlay,width or 640,56)):SetPadding({Left=0,Top=2,Right=14,Bottom=2})
 local item={widget=paint,label=labelWidget,click=click,action=fn,enabled=true,prominent=prominent}
 v.buttons[#v.buttons+1]=item;return item
end
local function enabled(item,on)
 if not item then return end
 on=on==true;if item.enabled==on then return end;item.enabled=on
 item.widget:SetIsEnabled(on);item.widget:SetRenderOpacity(on and 1 or .35)
 item.click:SetIsInteractionEnabled(on);item.click:SetIsEnabled(on);if not on then item.click:ClearSelection()end
end
local function selection(state)
 local id=type(state.selected)=='table'and state.selected.id or state.selected
 for _,entry in ipairs(state.roster or {})do if entry.id==id then return entry end end
 return v and v.selected
end
local lastSettingsSource,settingsPollAt
local function saveSettings()
 local f,why=io.open(options.configPath,'w')
 if not f then status='Could not save settings: '..tostring(why);return false end
 local source=Settings.serialize(settings);f:write(source);f:close();lastSettingsSource=source;return true
end
local function applySetting(key,value)
 if Settings.isSeat(key)then
  local id=controller:view().selectedId;if not id then return false end
  local old=settings.seats;local current=Settings.seat(settings,id);value=Settings.clamp(key,value)
  if current[key]==value then return true end
  local next={};for k,seat in pairs(old or{})do next[k]=seat end
  next[id]={height=current.height,forward=current.forward,side=current.side};next[id][key]=value
  settings.seats=next;controller:setSetting('seats',next)
  if not saveSettings()then settings.seats=old;controller:setSetting('seats',old);return false end
  return true
 end
 value=key=='replies'and value==true or key~='replies'and Settings.clamp(key,value)or false;if settings[key]==value then return end
 local accepted,message
 accepted,message=controller:setSetting(key,value)
 if accepted==false then status=message or 'This setting is unavailable right now';return false end
 local previous=settings[key];settings[key]=value
 if not saveSettings()then
  settings[key]=previous;controller:setSetting(key,previous)
  return false
 end
 return true
end
local function settingValue(key)
 if Settings.isSeat(key)then return Settings.seat(settings,controller:view().selectedId)[key]end
 return settings[key]
end
local function slider(parent,label,key,compact)
 local d=Settings.fields[key];local range=d.max-d.min
 local row=new('HorizontalBox')
 if not compact then add(parent,caption(label,26)):SetPadding({Left=0,Top=14,Right=0,Bottom=6})end
 add(parent,row):SetPadding({Left=0,Top=compact and 6 or 0,Right=0,Bottom=compact and 6 or 0})
 if compact then local labelWidget=caption(label,25);labelWidget:SetAutoWrapText(true);add(row,size(labelWidget,280,42)):SetVerticalAlignment(2) end
 local surface=new('Overlay');add(row,size(surface,compact and 290 or 530,42))
 local frame,trackFill=Theme.sliderTrack(v.tree,v.theme,{construct=function(path,tree)return StaticConstructObject(cls(path),tree)end,need=function(w,why)return assert(w,why)end})
 local slot=add(surface,size(frame,compact and 270 or 500,6));slot:SetHorizontalAlignment(2);slot:SetVerticalAlignment(2)
 local native=new('Slider');native.IsFocusable=true;native.RequiresControllerLock=false;native.IndentHandle=false
 local current=settingValue(key)
 native:SetMinValue(0);native:SetMaxValue(1);native:SetStepSize(d.step/range);native:SetValue((current-d.min)/range);Theme.slider(native,v.theme)
 native:SetSliderBarColor({R=1,G=1,B=1,A=0});fill(add(surface,native));trackFill:SetPercent((current-d.min)/range)
 local value=caption(current..d.unit,25);add(row,size(value,120,42)):SetPadding({Left=20,Top=0,Right=0,Bottom=0});value.Slot:SetVerticalAlignment(2)
 local control={widget=native,key=key,value=current,label=value,fill=trackFill,slider=true,enabled=true,mountId=Settings.isSeat(key)and controller:view().selectedId or nil}
 control.adjust=function(step)native:SetValue((Settings.clamp(key,d.min+native:GetValue()*range+step*d.step)-d.min)/range)end
 v.sliders[#v.sliders+1]=control;v.buttons[#v.buttons+1]=control
end
local helpTopics={'Getting started','Orders','Riding','Settings','Troubleshooting'}
local function helpDetails(topic)
 local title,body=Localize.help(topic)
 return tr(title),fmt(body,Keys.get('Menu'),Keys.get('Mount'),sharedKeys.SingleText,sharedKeys.SingleVoice)
end
local refresh,renderPage
refresh=function()
 local state=controller:view();local choice=selection(state);v.selected=choice
 local summon=v.autoCloseSummon
 if summon and not state.loading then
  v.autoCloseSummon=nil
  local active=state.active
  if type(active)=='table'and active.id==summon.id and active.memberId
   and active.memberId~=summon.previousMember and choice and choice.id==summon.id
   and AI.valid(active.actor)then M.close(true);return end
 end
 local active=type(state.active)=='table'and state.active or nil
 local mounted=state.mounted==true or active and active.mounted==true
 local restoring=state.mountState=='restoring'
 if v.page=='Summon'then
  text(v.name,choice and(choice.name..(choice.rideable==false and ' (combat only)'or''))or 'Choose a creature')
  enabled(v.summon,choice~=nil and choice.enabled~=false and not state.loading)
  for _,item in ipairs(v.buttons)do if item.creatureId then item.active=choice and item.creatureId==choice.id or false end end
 elseif v.page=='Party'then
  text(v.name,active and active.name or 'No creature summoned')
  text(v.partyName,active and active.name or 'Your party is empty')
  text(v.partyMode,restoring and 'Restoring player control' or state.loading and 'Operation in progress' or mounted and 'Currently riding' or active and 'Travelling companion' or 'Choose a creature on Summon to begin.')
  local key=Keys.get('Mount')
  text(v.description,active and(active.rideable==false and 'Combat companion; no native ground-riding gait.'or key..' · Mount / dismount')or 'Choose a creature on Summon.')
 elseif v.page=='Settings'then
  text(v.name,'Conversation')
  text(v.description,'')
  text(v.replyToggle.label,fmt('Spoken replies: {0}',settings.replies and 'On'or'Off'))
  text(v.voiceToggle.label,fmt('Voices: {0}',({'Auto','English','Multilingual'})[settings.voice+1]))
  text(v.languageToggle.label,fmt('Interface: {0}',settings.language==0 and 'Use main mod language'or Language.names[settings.language]))
 elseif v.page=='Controls'then
  text(v.name,'Add-on shortcuts')
  text(v.description,'Select a control, then press Shift and a new key. Esc cancels.')
  for action,row in pairs(v.bindingRows or {})do text(row,v.capture==action and 'Press new shortcut' or Keys.get(action))end
 elseif v.page=='Help'then
  local title,body=helpDetails(v.helpTopic);text(v.name,title);text(v.description,body)
  for topic,item in pairs(v.helpButtons or {})do item.active=topic==v.helpTopic end
 end
 enabled(v.dismiss,active~=nil and not state.loading and not restoring)
 enabled(v.mount,active~=nil and active.rideable~=false and not state.loading and not mounted and not restoring)
 enabled(v.dismount,mounted==true)
 for _,row in ipairs(v.sliders)do
  if Settings.isSeat(row.key)and choice and row.mountId~=choice.id then
   row.mountId=choice.id;row.value=settingValue(row.key);local d=Settings.fields[row.key];local fraction=(row.value-d.min)/(d.max-d.min)
   row.widget:SetValue(fraction);row.fill:SetPercent(fraction);text(row.label,row.value..d.unit)
  end
  local available=(row.key~='size'or not mounted and not state.loading and not restoring)
  if choice and choice.rideable==false and(row.key=='speed'or Settings.isSeat(row.key))then available=false end
  if row.enabled~=available then row.enabled=available;row.widget:SetIsEnabled(available);row.widget:SetRenderOpacity(available and 1 or .4)end
 end
 if v.status then text(v.status,v.notice~=''and v.notice or(v.page=='Controls'and Keys.error)or state.status or status)end
 if v.active then text(v.active,active and fmt('Your companion: {0}',active.name)or 'No creature summoned')end
 if v.progress and v.progressLoading~=state.loading then
  v.progressLoading=state.loading;v.progress:SetIsMarquee(state.loading==true)
  v.progressBox:SetVisibility(state.loading and 3 or 1)
 end
 if v.footerHint then text(v.footerHint,Keys.get('Menu')..' · Close    '..Keys.get('Mount')..' · Mount / dismount    Enter · Choose')end
end
local function paragraph(parent,value,points,padding)
 local label=caption(value,points or 23);label.WrapTextAt=740
 add(parent,size(label,760)):SetPadding({Left=0,Top=padding or 8,Right=0,Bottom=12});return label
end
local function mountButtons(parent)
 local row=new('HorizontalBox');add(parent,row):SetPadding({Left=0,Top=18,Right=0,Bottom=6})
 v.mount=button(row,'Mount',function()M.close(true);controller:mount()end,340,true)
 v.dismount=button(row,'Dismount',function()M.close(true);controller:dismount()end,340,true)
 v.dismiss=button(parent,'Dismiss',function()v.autoCloseSummon=nil;local ok,why=controller:dismiss();v.notice=ok and ''or why or '';refresh()end,694,false)
end
renderPage=function()
 for _,item in ipairs(v.buttons or {})do if item~=v.footerButton and AI.valid(item.click)then item.click:ClearSelection();item.click:SetIsInteractionEnabled(false);item.click:SetIsEnabled(false)end end
 v.content:ClearChildren();v.buttons={};v.sliders={};v.textCache={};v.focus=1;v.hover=nil
 v.name=nil;v.description=nil;v.summon=nil;v.dismiss=nil;v.mount=nil;v.dismount=nil;v.active=nil;v.status=nil;v.progress=nil;v.progressBox=nil;v.progressLoading=nil;v.bindingRows={};v.helpButtons={}
 add(v.content,caption('Rideable Mount Companions',34))
 local tabs=new('HorizontalBox');add(v.content,tabs):SetPadding({Left=0,Top=12,Right=0,Bottom=12})
 for _,page in ipairs({'Summon','Party','Settings','Controls','Help'})do
  local id=page;local item=button(tabs,page,function()
   if v.page~=id then v.page=id;v.capture=nil;v.notice='';v.autoCloseSummon=nil;renderPage()end
  end,295,false);item.active=v.page==page
 end
 add(v.content,size(art('horizontal'),1580,3)):SetPadding({Left=0,Top=0,Right=0,Bottom=20})
 local columns=new('HorizontalBox');add(v.content,columns)
 local list=new('ScrollBox');v.list=list;Theme.scroll(list,v.theme);add(columns,size(list,680,660))
 add(columns,size(art('vertical'),24,660)):SetPadding({Left=22,Top=0,Right=32,Bottom=0})
 local scroll=new('ScrollBox');Theme.scroll(scroll,v.theme);add(columns,size(scroll,800,660));local detail=new('VerticalBox');add(scroll,detail)
 v.name=caption('',33);add(detail,v.name)
 if v.page~='Summon'then v.description=paragraph(detail,'',23,8)end
 if v.page=='Summon'then
  local state=controller:view();local group,first
  for _,entry in ipairs(state.roster or {})do
   if entry.group~=group then group=entry.group;add(list,caption(group or 'Creatures',28)):SetPadding({Left=0,Top=first and 18 or 0,Right=0,Bottom=7})end
   local choice=entry;if choice.enabled~=false and not first then first=choice end
   local item=button(list,choice.name,function()
    if v.autoCloseSummon and v.autoCloseSummon.id~=choice.id then v.autoCloseSummon=nil end
    controller:select(choice.id);v.selected=choice;v.notice='';refresh()
   end,646,false);item.creatureId=choice.id;enabled(item,choice.enabled~=false)
  end
  if not selection(state)and first then controller:select(first.id);v.selected=first end
  slider(detail,'Creature size','size',true)
  slider(detail,'Riding speed','speed',true)
  add(detail,caption('Rider positioning',26)):SetPadding({Left=0,Top=12,Right=0,Bottom=4})
  slider(detail,'Height','height',true);slider(detail,'Forward / back','forward',true);slider(detail,'Left / right','side',true)
  button(detail,'Reset rider position',function()
   local defaults=Settings.seatDefaults(controller:view().selectedId)
   for _,key in ipairs({'height','forward','side'})do applySetting(key,defaults[key])end
   for _,row in ipairs(v.sliders)do if Settings.isSeat(row.key)then row.mountId=nil end end;refresh()
  end,694,false)
  local actions=new('HorizontalBox');add(detail,actions):SetPadding({Left=0,Top=20,Right=0,Bottom=6})
  v.summon=button(actions,'Summon',function()
   if not v.selected then return end
   local id=v.selected.id;local before=controller:view();local accepted,why=controller:summon(id);v.notice=accepted and ''or why or ''
   if accepted then v.autoCloseSummon={id=id,previousMember=type(before.active)=='table'and before.active.memberId or nil}end
   refresh()
  end,340,true)
  v.dismiss=button(actions,'Dismiss',function()v.autoCloseSummon=nil;local ok,why=controller:dismiss();v.notice=ok and ''or why or '';refresh()end,340,true)
  v.active=paragraph(detail,'',22,16);v.status=paragraph(detail,'',22,6)
  v.progress=new('ProgressBar');v.progress:SetFillColorAndOpacity({R=.7,G=.48,B=.17,A=1})
  v.progress.WidgetStyle.BackgroundImage.DrawAs=3;v.progress.WidgetStyle.BackgroundImage.TintColor.SpecifiedColor={R=.035,G=.028,B=.018,A=1}
  v.progress.WidgetStyle.MarqueeImage.DrawAs=3;v.progress.WidgetStyle.MarqueeImage.TintColor.SpecifiedColor={R=1,G=1,B=1,A=1}
  v.progress.WidgetStyle.MarqueeImage.ImageSize={X=140,Y=8}
  v.progressBox=size(v.progress,694,8);add(detail,v.progressBox):SetPadding({Left=0,Top=0,Right=0,Bottom=12})
 elseif v.page=='Party'then
  add(list,caption('Current companion',29)):SetPadding({Left=0,Top=0,Right=0,Bottom=18})
  v.partyName=caption('',29);add(list,v.partyName)
  v.partyMode=caption('',23);v.partyMode.WrapTextAt=620;add(list,size(v.partyMode,640)):SetPadding({Left=0,Top=8,Right=0,Bottom=20})
  button(list,'Choose another creature',function()v.page='Summon';v.autoCloseSummon=nil;v.notice='';renderPage()end,646,false)
  mountButtons(detail);v.status=paragraph(detail,'',23,20)
 elseif v.page=='Settings'then
  add(list,caption('Conversation',29))
  v.replyToggle=button(list,'',function()applySetting('replies',not settings.replies);refresh()end,646,false)
  v.voiceToggle=button(list,'',function()applySetting('voice',(settings.voice+1)%3);refresh()end,646,false)
  v.languageToggle=button(list,'',function()applySetting('language',(settings.language+1)%11);updateLanguage();v.font=nil;renderPage()end,646,false)
  paragraph(list,'Off: type Follow, Stop, Come here, Look at me, Attack or Leave. Commands stay local; voice input is unavailable.',22,12)
 elseif v.page=='Controls'then
  for _,row in ipairs({{id='Menu',label='Creature menu'},{id='Mount',label='Mount / dismount'}})do
   local action=row.id
   local item=button(list,row.label,function()v.capture=action;v.notice='Hold Shift and press a new key. Esc cancels.';refresh()end,646,false)
   local line=new('HorizontalBox');item.widget:SetContent(line);fill(line.Slot):SetPadding({Left=0,Top=0,Right=12,Bottom=0})
   item.label:SetAutoWrapText(false);add(line,size(item.label,330,50));item.label.Slot:SetVerticalAlignment(2)
   local value=caption(Keys.get(action),23);value:SetAutoWrapText(false);value:SetJustification(2);add(line,size(value,280,50));value.Slot:SetVerticalAlignment(2);v.bindingRows[action]=value
  end
  button(list,'Restore default controls',function()local ok,why=Keys.reset();v.capture=nil;v.notice=ok and 'Default shortcuts restored.'or why or '';pollKeys(true);refresh()end,646,false)
  v.status=paragraph(detail,'',23,18)
 else
  v.helpTopic=v.helpTopic or helpTopics[1]
  for _,topic in ipairs(helpTopics)do local id=topic;v.helpButtons[id]=button(list,id,function()v.helpTopic=id;refresh()end,646,false)end
 end
 if v.footerButton then v.buttons[#v.buttons+1]=v.footerButton end
 refresh()
end
local function build(request)
 v=request;pending=nil;v.buttons={};v.sliders={};v.textCache={};v.focus=1;v.inputOffset=0;v.page='Summon';v.notice=''
 updateLanguage();pollKeys(true)
 v.theme=Theme.resolve(function(event,message)print('[Creature Companion Mounts] '..event..': '..tostring(message)..'\n')end)
 v.library=cls('/Script/UMG.Default__WidgetBlueprintLibrary')
 v.host=v.library:Create(v.pc,cls('/Script/CommonUI.CommonActivatableWidget'),v.pc);assert(AI.valid(v.host),'Native mount menu creation failed');v.tree=v.host.WidgetTree
 v.clickClass=AI.retainUIClass(Theme.asset('/Game/_Dawnwalker/UI/_Unified/BaseWidgets/DWW_Button.DWW_Button_C'))
 v.host.bIsBackHandler=true;v.host.bIsModal=true;v.host.bAutoActivate=false;v.host.bAutoRestoreFocus=false
 local border=new('Border');border:SetBrushColor({R=.003,G=.004,B=.006,A=1});border:SetPadding({Left=0,Top=0,Right=0,Bottom=0});border:SetHorizontalAlignment(0);border:SetVerticalAlignment(0);v.tree.RootWidget=border
 local outer=new('Overlay');border:SetContent(outer);fill(add(outer,art('background')))
 local design=new('Overlay');local scaled=new('ScaleBox');scaled:SetStretch(2);scaled:SetContent(size(design,1920,1080));fill(add(outer,scaled))
 v.content=new('VerticalBox');fill(add(design,v.content)):SetPadding({Left=150,Top=70,Right=150,Bottom=90});renderPage()
 local footer=new('HorizontalBox');local slot=add(design,size(footer,1580,48));slot:SetHorizontalAlignment(1);slot:SetVerticalAlignment(3);slot:SetPadding({Left=150,Top=0,Right=0,Bottom=55})
 v.footerButton=button(footer,'Esc  '..tr('BACK'),function()M.close(true)end,220,false)
 v.footerHint=caption('',20);v.footerHint:SetAutoWrapText(false);add(footer,v.footerHint):SetPadding({Left=18,Top=15,Right=0,Bottom=0})
 for _,parent in ipairs(FindAllOf('WBP_PauseMenu_C')or {})do if AI.valid(parent)and parent:IsInViewport()and parent:IsActivated()then v.parent=parent;v.parentBack=parent.bIsBackHandler;v.parentEnabled=parent:GetIsEnabled();parent.bIsBackHandler=false;parent:SetIsEnabled(false);break end end
 v.host:AddToViewport(155);v.host:ActivateWidget();v.lease=assert(Input.acquire(v.pc,v.library,cls('/Script/Engine.Default__GameplayStatics'),v.host))
 write('native-menu-input.txt','');refresh();heartbeat(true);status='Menu open'
end
function M.toggle(pc,owner)
 dependencies();lastPc=pc;controller=owner or controller;assert(controller,'Mount controller missing')
 if v or pending then M.close(true);return true end
 if otherMenu()then status='Close the other menu first';return false,status end
 local pawn,world,worldId,playerId=playerIdentity(pc);if not pawn then status='Wait for the player to finish loading';return false,status end
 serial=serial+1;pending={pc=pc,pawn=pawn,world=world,worldId=worldId,playerId=playerId,session='creature-mounts-'..os.time()..'-'..serial,started=os.time()}
 heartbeat(true);write('ui-control.txt','addon-menu-open:'..constants.owner..':'..pending.session);status='Opening mount menu';return true
end
function M.input(key)
 if not v then return end
 if v.capture then
  if key=='Escape'then v.capture=nil;v.notice='Shortcut change cancelled.';refresh();return end
  if key=='Shift'or key=='LShiftKey'or key=='RShiftKey'then return end
  local ok,why=Keys.set(v.capture,key)
  if ok then v.capture=nil;v.notice='Shortcut saved.';pollKeys(true)else v.notice=why or 'Choose a different shortcut.'end
  refresh();return
 end
 if key=='Escape'then M.close(true);return end
 if key==Keys.get('Menu')then M.close(true);return end
 if key==Keys.get('Mount')then M.close(true);controller:toggleMount();return end
 if key=='Down'or key=='Up'then
  local step=key=='Down'and 1 or -1
  for _=1,#v.buttons do v.focus=(v.focus-1+step)%#v.buttons+1;if v.buttons[v.focus].enabled then break end end
  local b=v.buttons[v.focus];if b.creatureId then pcall(function()v.list:ScrollWidgetIntoView(b.widget,true,0,12)end)end
 elseif key=='Enter'then local b=v.buttons[v.focus];if b and b.enabled and b.action then b.action()end
 elseif key=='Left'or key=='Right'then local b=v.buttons[v.focus];if b and b.enabled and b.adjust then b.adjust(key=='Left'and -1 or 1)end
 end
end
function M.tick(pc,owner)
 dependencies();lastPc=pc or lastPc;controller=owner or controller
 if not lastPc or not controller then return end
 pollKeys(false);heartbeat(false)
 if os.time()~=settingsPollAt then
  settingsPollAt=os.time();local source=read(options.configPath,16384)
  if source~=''and source~=lastSettingsSource then
   lastSettingsSource=source;local latest=Settings.load(source);local changed=false
   for key,value in pairs(latest)do if settings[key]~=value then
    local ok=controller:setSetting(key,value);if ok~=false then settings[key]=value;changed=true else lastSettingsSource=nil end
   end end
   if changed and v then updateLanguage();v.font=nil;renderPage()end
  end
 end
 if os.clock()>=(nextPoll or 0)then
  nextPoll=os.clock()+.1
  local request=read(sharedRuntime..'/'..constants.request,256)
  if request~=''and request~=lastRequest then
   lastRequest=request;request=request:gsub('[\r\n]+$','')
   local stamp,id,action=request:match('^(%d+)\t([%w_-]+)\t([%w]+)$')
   if not stamp then stamp,id=request:match('^(%d+)\t([%w_-]+)$');action='menu'end
   if stamp and os.time()-tonumber(stamp)>=0 and os.time()-tonumber(stamp)<=3 then
    if action=='mount'then
     if v or pending then M.close(true);controller:toggleMount()
     elseif not otherMenu()then controller:toggleMount()end
    elseif action=='menu'then M.toggle(lastPc,controller)end
   end
  end
 end
 if pending then
  if not live(pending)or os.time()-pending.started>5 then M.close();status='Menu unavailable. Close other menus and try again.';return end
  local raw=read(sharedRuntime..'/'..constants.ack,2048):gsub('[\r\n]+$','');local fields={};for field in(raw..'\t'):gmatch('(.-)\t')do fields[#fields+1]=field end
  local stamp=tonumber(fields[3]);local accepted=fields[1]=='COMPANION-UI'and fields[2]=='1'and stamp and os.time()-stamp>=0 and os.time()-stamp<=3 and fields[4]=='1'and fields[5]==pending.session and fields[6]==pending.worldId and fields[7]==pending.playerId
  if accepted then local request=pending;local ok,why=pcall(build,request);if not ok then M.close();status='Could not open mount menu: '..tostring(why);print('[Creature Companion Mounts] '..status..'\n')end end
  return
 end
 if not v then return end
 if not live(v)or not AI.valid(v.host)or not v.host:IsActivated()then M.close();return end
 local current=v;local f=io.open(sharedRuntime..'/native-menu-input.txt','r')
 if f then f:seek('set',v.inputOffset);for _=1,32 do local line=f:read('*l');if not line then break end;current.inputOffset=f:seek();local session,key=line:match('^([^\t]+)\t([%w+]+)$');if session==current.session then M.input(key);if v~=current then break end end end;f:close()end
 if v~=current then return end
 for _,row in ipairs(v.sliders)do
  local d=Settings.fields[row.key];local range=d.max-d.min
  local value=Settings.clamp(row.key,d.min+row.widget:GetValue()*range)
  if value~=row.value then applySetting(row.key,value);row.value=settingValue(row.key);row.widget:SetValue((row.value-d.min)/range);row.fill:SetPercent((row.value-d.min)/range);text(row.label,row.value..d.unit)end
 end
 local pointer
 for i,item in ipairs(v.buttons)do item.hovered=(item.click or item.widget):IsHovered();if item.hovered then pointer=i end end
 if pointer and pointer~=v.hover then v.focus=pointer end;v.hover=pointer
 for i,item in ipairs(v.buttons)do
  local hovered=item.hovered
  if item.slider then
   local focused=v.focus==i
   if focused~=item.focused then item.focused=focused;item.widget:SetSliderHandleColor(focused and {R=1,G=.83,B=.57,A=1}or {R=.65,G=.62,B=.54,A=1})end
  else
  local selected=item.active or item.prominent and item.enabled
  hovered=hovered or v.focus==i
  local visual=selected and 2 or hovered and 1 or 0
  if visual~=item.visual then item.visual=visual;local alpha=Theme.selectionState(item.widget,v.theme,selected,hovered,false);item.widget:SetBackgroundColor({R=1,G=1,B=1,A=alpha})end
  if item.click:GetSelected()then item.click:ClearSelection();if item.enabled then item.action();return end end
  end
 end
 if os.clock()>=(v.refreshAt or 0)then v.refreshAt=os.clock()+.25;refresh()end
end
return M
