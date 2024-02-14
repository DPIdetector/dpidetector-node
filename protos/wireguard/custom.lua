local sp    = require"subprocess"
local req   = require"checker.requests"
local json  = require"cjson"
local sleep = require"checker.utils".sleep
local wait  = require"checker.utils".wait

local _C = {}

local cfg_path = "/etc/wireguard/wg.conf"

_C.proto = "wireguard"

_C.init = function()
  _C.cfg_fd = io.open(cfg_path, "r+")
  _C.cfg_tpl = _C.cfg_fd:read"*a"
  _C.cfg_fd:seek"set" -- курсор в начало файла (нам потом туда писать конфиг)
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
    if ok
      and res.port
      and res.server_ip
      and res.int_net
      and res.int_address
      and res.pubkey
      and res.privkey
      and res.test_host
      and res.test_port
    then
      server.meta = res
    else
      _G.stderr:write(("Ошибка десереализации мета-информации о сервере: %s"):format(res))
      return false
    end
  end

  local replaces = {
    SERVER = server.meta.server_ip,
    PORT = server.meta.port,
    PRIVKEY = server.meta.privkey,
    PUBKEY = server.meta.pubkey,
    ADDRESS = server.meta.int_address,
    NETWORK = server.meta.int_net,
  }
  local srv_cfg = _C.cfg_tpl:gsub("__([A-Za-z0-9_-.]+)__", replaces)

  _C.cfg_fd:write(srv_cfg)
  _C.cfg_fd:seek"set"
  _C.cfg_fd:flush()

  local exitcode = sp.call{
    "wg-quick",
    "up",
    "wg",
    stdout = _G.stdout,
    stderr = _G.stderr,
  }
  if exitcode ~= 0 then
    _G.stderr:write(("Проблема при инициализации! Код выхода: %d\n"):format(exitcode))
  end
  sleep(5)
  return true
end

_C.disconnect = function(_server)
  if not _C.failed then
    local exitcode = sp.call{
      "wg-quick",
      "down",
      "wg",
      stdout = _G.stdout,
      stderr = _G.stderr,
    }
    if exitcode ~= 0 then
      _G.stderr:write(("Проблема при остановке! Код выхода: %d\n"):format(exitcode))
    end
  end
  wait()
end

_C.checker = function(server)
  local ret = false
  if _C.failed then
    _G.stderr:write"Проверка не выполняется, т.к. туннель не был поднят.\n"
  else
    local res = req{
      url = ("http://%s:%d/"):format(server.meta.test_host, server.meta.test_port),
      interface = "wg",
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

