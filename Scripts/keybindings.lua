-- Add-on shortcuts always include Shift, leaving shared chat keys available.
local M={revision=0};local path,lastSource
local defaults={Menu='Shift+F5',Mount='Shift+F6'}
local values={Menu=defaults.Menu,Mount=defaults.Mount}
local special={home='Home',['end']='End',pageup='PageUp',pagedown='PageDown',insert='Insert',delete='Delete'}
local function normalize(value)
 local key=tostring(value or''):gsub('%s',''):lower():match('^shift%+(.+)$')
 if not key then return nil,'Keep Shift in each shortcut, for example Shift+F5.'end
 local number=tonumber(key:match('^f(%d+)$'))
 if number and number>=1 and number<=11 and number%1==0 then key='F'..number
 elseif key:match('^[a-z0-9]$')then key=key:upper()
 elseif special[key]then key=special[key]
 else return nil,'Choose Shift with F1 to F11, a letter, a digit, Home, End, PageUp, PageDown, Insert or Delete.'end
 return 'Shift+'..key
end
local function validate(candidate)
 for _,action in ipairs({'Menu','Mount'})do local key,why=normalize(candidate[action]);if not key then return nil,why end;candidate[action]=key end
 if candidate.Menu==candidate.Mount then return nil,'Menu and Mount / dismount need different shortcuts.'end
 return candidate
end
local function apply(candidate)
 local changed=values.Menu~=candidate.Menu or values.Mount~=candidate.Mount
 values=candidate;M.error=nil;if changed then M.revision=M.revision+1 end;return changed
end
function M.load(file)
 if file then path=file end
 local f=path and io.open(path,'r');if not f then return false end
 local source=f:read(4097)or'';f:close()
 if source==lastSource then M.error=nil;return false end
 if #source>4096 then M.error='Shortcut file is too large; keeping the previous bindings.';return false end
 local candidate={Menu=defaults.Menu,Mount=defaults.Mount}
 for action,chord in source:gmatch('([%a]+)%s*=%s*([^\r\n;#]+)')do if defaults[action]then candidate[action]=chord end end
 local checked,why=validate(candidate);if not checked then M.error=why;return false end
 lastSource=source;return apply(checked)
end
function M.get(action)return values[action]end
function M.all()return {Menu=values.Menu,Mount=values.Mount}end
local function save(candidate)
 local checked,why=validate(candidate);if not checked then M.error=why;return false,why end
 local f=path and io.open(path,'w');if not f then M.error='Could not save keybindings.ini.';return false,M.error end
 local source='[Controls]\nMenu = '..checked.Menu..'\nMount = '..checked.Mount..'\n';f:write(source);f:close();lastSource=source;apply(checked);return true
end
function M.set(action,chord)
 if not defaults[action]then return false,'Unknown shortcut'end
 local candidate=M.all();candidate[action]=chord;return save(candidate)
end
function M.reset(action)
 if action then if not defaults[action]then return false,'Unknown shortcut'end;return M.set(action,defaults[action])end
 return save({Menu=defaults.Menu,Mount=defaults.Mount})
end
function M.wire()return table.concat({'COMPANION-UI-KEYS','1',values.Menu,values.Mount},'\t')end
return M
