local ffi = require "ffi"

ffi.cdef"unsigned int sleep(unsigned int seconds);"
ffi.cdef"unsigned int wait();"

local _U = {}

function _U.getenv(name)
  local ret
  ret = os.getenv(name)
  if not ret then
    io.stderr:write(("Вы не указали значение переменной '%s'. Пожалуйста, укажите его в в user.conf"):format(name))
    os.exit(1)
  else
    return ret
  end
end

_U.sleep = ffi.C.sleep

_U.wait = ffi.C.wait

local b='ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/' -- You will need this for encoding/decoding

function _U.b64enc(data)
    return ((data:gsub('.', function(x)
        local r,bb='',x:byte()
        for i=8,1,-1 do r=r..(bb%2^i-bb%2^(i-1)>0 and '1' or '0') end
        return r;
    end)..'0000'):gsub('%d%d%d?%d?%d?%d?', function(x)
        if (#x < 6) then return '' end
        local c=0
        for i=1,6 do c=c+(x:sub(i,i)=='1' and 2^(6-i) or 0) end
        return b:sub(c+1,c+1)
    end)..({ '', '==', '=' })[#data%3+1])
end

function _U.b64dec(data)
    data = string.gsub(data, '[^'..b..'=]', '')
    return (data:gsub('.', function(x)
        if (x == '=') then return '' end
        local r,f='',(b:find(x)-1)
        for i=6,1,-1 do r=r..(f%2^i-f%2^(i-1)>0 and '1' or '0') end
        return r;
    end):gsub('%d%d%d?%d?%d?%d?%d?%d?', function(x)
        if (#x ~= 8) then return '' end
        local c=0
        for i=1,8 do c=c+(x:sub(i,i)=='1' and 2^(8-i) or 0) end
            return string.char(c)
    end))
end

return _U
