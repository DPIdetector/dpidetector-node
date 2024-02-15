local sp    = require"subprocess"
local req   = require"checker.requests"
local json  = require"cjson"
local sleep = require"checker.utils".sleep
local wait  = require"checker.utils".wait

local _C = {}

_C.proto = "shadowsocks"

_C.init = function()
end
_C.connect = function(server)
  if not server.domain then
    _G.stderr:write(
      ("Запись о сервере %s не содержит информации о домене, который стоит использовать для подключения к нему")
      :format(tostring(server.name))
    )
    return false
  end
  local meta_r = req{
    url = ("https://%s:%d/%s"):format(server.domain, server.port, _C.proto),
    headers = {
      ("Token: %s"):format(_G.token),
    },
  }
  if meta_r:match"^%[" or meta_r:match"^%{" then
      local ok, res = pcall(json.decode, meta_r)
    if ok then
      server.meta = res
    else
      _G.stderr:write(("Ошибка десереализации мета-информации о сервере: %s"):format(res))
      return false
    end
  end
  local _E = {}
  _C.ss_proc, _E.errmsg, _E.errno = sp.popen{
    "/usr/bin/ss-local",
    "-s", server.meta.server_ip,
    "-p", server.meta.port,
    "-k", server.meta.password,
    "-l", "1080",
    "-m", server.meta.encryption,
    "-t", "60",
    stdout = _G.stdout,
    stderr = _G.stderr,
  }
  if not _C.ss_proc or _C.ss_proc:poll() then
    _G.stderr:write(("Проблема при инициализации! Сообщение об ошибке: %s. Код: %d\n"):format(_E.errmsg, _E.errno))
    wait()
    _C.ss_proc = nil
    return false
  end
  sleep(5)
  return true
end

_C.disconnect = function(_server)
  if _C.ss_proc then
    _C.ss_proc:terminate()
    _C.ss_proc:wait()
    wait()
    _C.ss_proc = nil
    sleep(5)
  end
end

_C.checker = function(server)
  local ret = false
  if not _C.ss_proc or _C.ss_proc:poll() then
    _G.stderr:write"Проверка не выполняется, т.к. туннель не был поднят.\n"
  else
    local res = req{
      url = "https://geo.censortracker.org/get-ip/plain",
      proxy = "socks5://127.0.0.1:1080",
    }
    if res:match(server.meta.server_ip) then
      ret = true
    else
      _G.stderr:write("Проверка провалилась!\n")
    end
  end
  return ret
end

return _C
