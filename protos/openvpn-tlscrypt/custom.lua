local sp     = require"subprocess"
local req    = require"checker.requests"
local json   = require"cjson"
local sleep  = require"checker.utils".sleep
local wait   = require"checker.utils".wait
local b64dec = require"checker.utils".b64dec

local _C = {}

local cfg_path = "/etc/openvpn/checker.conf"

_C.proto = "openvpn-tlscrypt"
_C.interface_name = "ovpn-tlscrypt"

_C.init = function()
  local fd = io.open(cfg_path, "r")
  _C.cfg_tpl = fd:read"*a"
  fd:close()
end

_C.connect = function(server)
  if not server.domain then
    _G.stderr:write(
      ("\nЗапись о сервере %s не содержит информации о домене, который стоит использовать для подключения к нему\n")
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
      and res.server_ip
      and res.port
      and res.keys
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
    KEYS = b64dec(server.meta.keys),
  }
  local srv_cfg = _C.cfg_tpl:gsub("__([A-Za-z0-9_-.]+)__", replaces)

  local fd = io.open(cfg_path, "w+")
  fd:write(srv_cfg)
  fd:flush()
  fd:close()

  local _E = {}
  _C.ovpn_proc, _E.errmsg, _E.errno = sp.popen{
    "openvpn",
    "--config",
    cfg_path,
    stdout = _G.stdout,
    stderr = _G.stderr,
  }
  if not _C.ovpn_proc or _C.ovpn_proc:poll() then
    _G.stderr:write(("\nПроблема при инициализации! Сообщение об ошибке: %s. Код: %d\n"):format(_E.errmsg, _E.errno))
    if _C.ovpn_proc then
      _C.ovpn_proc:kill()
      _C.ovpn_proc = nil
      wait()
    end
    return false
  end
  sleep(2)
  return true
end

_C.disconnect = function(_server)
  if _C.ovpn_proc then
    _C.ovpn_proc:terminate()
    _C.ovpn_proc:wait()
    local finished = false
    local count = 0
    repeat
      local e = sp.call{
        "sh",
        "-c",
        ("ip link show | grep -q %s"):format(_C.interface_name),
      }
      if e == 1 then finished = true end
      count = count + 1
      sleep(1)
      wait()
    until finished==true or count>=10
    if finished == false then
      io.stderr:write("\nПроблемы с завершением подключения (необходима отладка)\n")
    end
    _C.ovpn_proc:kill()
    _C.ovpn_proc = nil
    wait()
  else
    io.stderr:write("\nВызвана функция отключения, но что-то случилось c дескрипторами подключения. Нужна отладка!\n")
  end
end

_C.checker = function(server)
  local ret = false
  local res = req{
    url = ("http://%s:%d/"):format(server.meta.test_host, server.meta.test_port),
    interface = _C.interface_name,
  }
  if res:match(server.meta.server_ip) then
    ret = true
  else
    _G.stderr:write("\nПроверка провалилась!\n")
    _G.stderr:write(("\nIP сервера из метаданных: %q\n"):format(server.meta.server_ip))
    _G.stderr:write(("\nОтвет сервиса определения IP: %q\n"):format(res))
  end
  return ret
end

return _C
