local sp    = require"subprocess"
local req   = require"checker.requests"
local json  = require"cjson"
local sleep = require"checker.utils".sleep
local wait  = require"checker.utils".wait

local _C = {}

local cfg_path = "/etc/ckclient.json"

_C.proto = "cloak"

_C.init = function()
  local fd = io.open(cfg_path, "r")
  _C.cfg_tpl = fd:read"*a"
  fd:close()
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
    and res.ss_password
    and res.ss_encryption
    and res.encryption
    and res.uid
    and res.pubkey
    and res.servername
    and res.browsersig
    then
      server.meta = res
    else
      _G.stderr:write(("Ошибка десереализации (или верификации) мета-информации о сервере: %s"):format(res))
      return false
    end
  end

  local replaces = {
    ENCRYPTION = server.meta.encryption,
    UID = server.meta.uid,
    PUBKEY = server.meta.pubkey,
    SERVERNAME = server.meta.servername,
    BROWSER = server.meta.browsersig,
  }
  local srv_cfg = _C.cfg_tpl:gsub("__([A-Za-z0-9_-.]+)__", replaces)

  local fd = io.open(cfg_path, "w+")
  fd:write(srv_cfg)
  fd:flush()
  fd:close()

  local _E = {}
  _C.clk_proc, _E.errmsg, _E.errno = sp.popen{
    "/usr/bin/ck-client",
    "-s", server.meta.server_ip,
    "-c", cfg_path,
    stdout = _G.stdout,
    stderr = _G.stderr,
  }
  if not _C.clk_proc or _C.clk_proc:poll() then
    _G.stderr:write(
      ("[Cloak] Проблема при инициализации! Сообщение об ошибке: %s. Код: %d\n"):format(_E.errmsg, _E.errno)
    )
  end
  sleep(2)
  _C.ss_proc, _E.errmsg, _E.errno = sp.popen{
    "/usr/bin/ss-local",
    "-s", "127.0.0.1",
    "-p", "1984",
    "-k", server.meta.ss_password,
    "-l", "1080",
    "-m", server.meta.ss_encryption,
    "-t", "60",
    stdout = _G.stdout,
    stderr = _G.stderr,
  }
  if not _C.ss_proc or _C.ss_proc:poll() then
    _G.stderr:write(
      ("[ShadowSocks] Проблема при инициализации! Сообщение об ошибке: %s. Код: %d\n"):format(_E.errmsg, _E.errno)
    )
  end
  sleep(3)
  return true
end

_C.disconnect = function(_server)
  if _C.ss_proc then
    _C.ss_proc:terminate()
    _C.ss_proc:wait()
    _C.ss_proc = nil
    sleep(2)
    wait()
  end
  if _C.clk_proc then
    _C.clk_proc:terminate()
    _C.clk_proc:wait()
    _C.clk_proc = nil
    sleep(2)
    wait()
  end
end

_C.checker = function(server)
  local ret = false
  if not (_C.ss_proc and _C.clk_proc) or _C.ss_proc:poll() or _C.clk_proc:poll() then
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
