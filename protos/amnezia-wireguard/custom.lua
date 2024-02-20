local sp    = require"subprocess"
local req   = require"checker.requests"
local json  = require"cjson"
local sleep = require"checker.utils".sleep
local wait  = require"checker.utils".wait

local _C = {}

local cfg_path = "/etc/wireguard/awg.conf"

_C.proto = "amnezia-wireguard"
_C.interface_name = "awg"

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
      and res.port
      and res.server_ip
      and res.int_net
      and res.int_address
      and res.pubkey
      and res.privkey
      and res.jc
      and res.jmin
      and res.jmax
      and res.s1
      and res.s2
      and res.h1
      and res.h2
      and res.h3
      and res.h4
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
    JC = server.meta.jc,
    JMIN = server.meta.jmin,
    JMAX = server.meta.jmax,
    S1 = server.meta.s1,
    S2 = server.meta.s2,
    H1 = server.meta.h1,
    H2 = server.meta.h2,
    H3 = server.meta.h3,
    H4 = server.meta.h4,
  }
  local srv_cfg = _C.cfg_tpl:gsub("__([A-Za-z0-9_-.]+)__", replaces)

  local fd = io.open(cfg_path, "w+")
  fd:write(srv_cfg)
  fd:flush()
  fd:close()

  local exitcode = sp.call{
    "wg-quick",
    "up",
    _C.interface_name,
    stdout = _G.stdout,
    stderr = _G.stderr,
  }
  if exitcode ~= 0 then
    _G.stderr:write(("\nПроблема при инициализации! Код выхода: %d\n"):format(exitcode))
    return false
  end
  local finished = false
  local count = 0
  repeat
    local e = sp.call{
      "sh",
      "-c",
      ("ip link show | grep -q %s"):format(_C.interface_name),
    }
    if e == 0 then finished = true end
    count = count + 1
    sleep(1)
  until finished==true or count>=20
  if finished == false then
    io.stderr:write("\nПроблемы с настройкой подключения (необходима отладка)\n")
    return false
  end
  return true
end

_C.disconnect = function(_server)
  local exitcode = sp.call{
    "wg-quick",
    "down",
    _C.interface_name,
    stdout = _G.stdout,
    stderr = _G.stderr,
  }
  if exitcode ~= 0 then
    _G.stderr:write(("\nПроблема при остановке! Код выхода: %d\n"):format(exitcode))
  end
  local finished = false
  local count = 0
  repeat
    local e = sp.call{
      "sh",
      "-c",
      ("ip link show | grep -q awg"):format(_C.interface_name),
    }
    if e == 1 then finished = true end
    count = count + 1
    sleep(1)
  until finished==true or count>=10
  if finished == false then
    io.stderr:write("\nПроблемы с завершением подключения (необходима отладка)\n")
  end
  local zombies = true
  count = 0
  repeat
    local e = sp.call{
      "sh",
      "-c",
      "ps -o stat,pid,comm | grep -q '^Z'",
    }
    if e == 1 then zombies = false end
    if zombies == true then
      if _G.DEBUG then _G.stderr:write("\n=== перед вызовом wait() ===\n") end
      wait()
      if _G.DEBUG then _G.stderr:write("\n=== после вызова wait() ===\n") end
    end
      count = count + 1
    until zombies==false or count>=20
    if zombies == true then
      io.stderr:write("\nПроблемы с очисткой дерева процессов (необходима отладка)\n")
    end
end

_C.checker = function(server)
  local ret
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
