local ffi = require "ffi"

ffi.cdef"unsigned int sleep(unsigned int seconds);"
ffi.cdef"unsigned int wait();"

local _U = {}

function _U.getenv(name)
  local ret
  ret = os.getenv(name)
  if not ret then
    io.stderr:write(("Вы не указали значение переменной '%s'. Пожалуйста, укажите его в user.conf\n"):format(name))
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

local function gettime()
  local date_t = os.date"*t"
  return ("%.02d/%.02d/%.02d %.02d:%.02d:%.02d"):format(date_t.day, date_t.month, date_t.year, date_t.hour, date_t.min, date_t.sec)
  -- return (("%day%/%month%/%year% %hour%:%min%:%sec%"):gsub("%%(%w+)%%",os.date('*t')))
end

local function log(t)
  local tpl = t.template or "%s [%s] | %s | %s\n"
  local fmt = t.format
  local fds = {
    info = _G.stdout,
  }
  local lvl = {
    error = "E",
    warning = "W",
    info = "I",
    debug = "D",
    verbose = "V",
  }
  local fd = t.fd or fds[t.level] or _G.stderr

  fd:write(
    tpl:format(
      table.unpack(fmt or {
        _G.proto,
        t.sign or lvl[t.level] or "?",
        gettime(),
        tostring(t.text)
      })
    )
  )
end

_U.logger = {
  --- TODO:
  --- - json-логгирование?
  --- - в файл внутри контейнера? С очисткой после отправки?
  --- (цель - отправка на бекенд, чтобы оптимизировать процесс)
  error = function(text, opts)
    log{level = "error", text = text, opts = opts}
  end,
  warning = function(text, opts)
    log{level = "warning", text = text, opts = opts}
  end,
  info = function(text, opts)
    log{level = "info", text = text, opts = opts}
  end,
  verbose = function(text, opts)
    if _G.VERBOSE or _G.DEBUG then
    log{level = "verbose", text = text, opts = opts}
    end
  end,
  debug = function(text, opts)
    if _G.DEBUG then
    log{level = "debug", text = text, opts = opts}
    end
  end,
  raw = log,
}

function _U.split(str, spr)
    local sep = spr or "\n"
    local result = {}
    local i = 1
    for c in str:gmatch(string.format("([^%s]+)", sep)) do
        result[i] = c
        i = i + 1
    end
    return result
end

return _U
