-- Shared numeric bounds for file loading, native sliders and rider placement.
local M={}
local source=debug.getinfo(1,'S').source:gsub('^@',''):gsub('\\','/')
local roster=dofile(assert(source:match('^(.*)/Scripts/[^/]+$'))..'/Scripts/roster.lua')
local entries={};for _,r in ipairs(roster)do entries[r.id]=r end
-- Estimated corrections to the existing spine/pelvis seat calibration, in cm.
-- Keep the centreline and allow each definition to retain its own adjustment.
local estimates={wolf={0,0},dog={-4,0},bear={8,-12},boar={4,-4},deer={-2,-10},pig={2,-4},cow={6,-10},goat={-4,-6},sheep={0,-4},gargoyle={12,-18},tatzelwurm={6,-18},beast={6,-12},mare={10,-16}}
function M.isSeat(key)return key=='height'or key=='forward'or key=='side'end
function M.seatDefaults(id)
 local r=entries[id];local e=r and estimates[r.species]or{0,0}
 return {height=e[1],forward=e[2],side=0}
end
function M.seat(values,id)return values.seats and values.seats[id]or M.seatDefaults(id)end
M.fields={
 language={ini='UiLanguage',default=0,min=0,max=10,step=1,unit=''},
 voice={ini='VoiceMode',default=0,min=0,max=2,step=1,unit=''},
 size={ini='SizePercent',default=100,min=50,max=250,step=5,unit='%'},
 speed={ini='RidingSpeedPercent',default=100,min=50,max=250,step=5,unit='%'},
 height={ini='RiderHeightCm',default=0,min=-60,max=100,step=1,unit=' cm'},
 forward={ini='RiderForwardCm',default=0,min=-100,max=100,step=1,unit=' cm'},
 side={ini='RiderSideCm',default=0,min=-75,max=75,step=1,unit=' cm'},
}
function M.clamp(key,value)
 local d=assert(M.fields[key]);local n=tonumber(value)
 if not n or n~=n or math.abs(n)==math.huge then n=d.default end
 return math.max(d.min,math.min(d.max,math.floor(n/d.step+.5)*d.step))
end
function M.load(source)
 local sections={};local section='Mount'
 for line in source:gmatch('[^\r\n]+')do local name=line:match('^%s*%[([^%]]+)%]');if name then section=name else sections[section]=(sections[section]or'')..line..'\n'end end
 local main=sections.Mount or'';local result={seats={}}
 for key,d in pairs(M.fields)do if not M.isSeat(key)then result[key]=M.clamp(key,main:match(d.ini..'%s*=%s*([%d.+-]+)'))end end
 local legacy={};local custom=false
 for _,key in ipairs({'height','forward','side'})do local d=M.fields[key];legacy[key]=M.clamp(key,main:match(d.ini..'%s*=%s*([%d.+-]+)'));if legacy[key]~=0 then custom=true end end
 for _,r in ipairs(roster)do
  local saved=sections['Rider.'..r.id];local base=custom and legacy or M.seatDefaults(r.id);local seat={}
  for _,key in ipairs({'height','forward','side'})do local value=saved and saved:match(M.fields[key].ini..'%s*=%s*([%d.+-]+)');seat[key]=M.clamp(key,value or base[key])end
  result.seats[r.id]=seat
 end
 local replies=(main:match('SpokenReplies%s*=%s*(%w+)')or'on'):lower()
 result.replies=replies~='off'and replies~='0'
 return result
end
function M.serialize(values)
 local out={'[Mount]'}
 for _,key in ipairs({'size','speed','language','voice'})do local d=M.fields[key];out[#out+1]=d.ini..' = '..M.clamp(key,values[key])end
 out[#out+1]='SpokenReplies = '..(values.replies and '1'or'0')
 for _,r in ipairs(roster)do
  out[#out+1]='\n[Rider.'..r.id..']';local seat=M.seat(values,r.id)
  for _,key in ipairs({'height','forward','side'})do out[#out+1]=M.fields[key].ini..' = '..M.clamp(key,seat[key])end
 end
 return table.concat(out,'\n')..'\n'
end
return M
