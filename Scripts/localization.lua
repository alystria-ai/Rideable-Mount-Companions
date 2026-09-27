local source=debug.getinfo(1,'S').source:gsub('^@',''):gsub('\\','/')
local data=dofile(assert(source:match('^(.*)/[^/]+$'))..'/translations.lua')
local M={}
local modifiers={'Brown','White','Alpha','Astral','Dark','Undead','Rabid','Lesser','Greater','Great','Scarred','Small','Albino'}
local function render(template,value,L)return M.text(template,L):gsub('{0}',function()return M.text(value,L)end)end
function M.text(value,L)
 value=tostring(value or'');if L.index<=1 then return value end
 local row=data.rows[value];if row then return row[L.index-1]or value end
 local inherited=L.text(value);if inherited~=value then return inherited end
 local name=value:match('^Loading (.+)%.%.%.$');if name then return render('Loading {0}...',name,L)end
 name=value:match('^(.+) ready%.$');if name then return render('{0} ready.',name,L)end
 for _,prefix in ipairs(modifiers)do
  local rest=value:match('^'..prefix..' (.+)$');if rest then return render(prefix..' {0}',rest,L)end
 end
 return value -- Unknown native errors remain intact for support.
end
function M.help(topic)return topic,data.help[topic]or data.help['Getting started']end
return M
