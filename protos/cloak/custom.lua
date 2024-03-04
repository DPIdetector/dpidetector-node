local sp    = require"subprocess"
local req   = require"checker.requests"
local json  = require"cjson"
local sleep = require"checker.utils".sleep
local wait  = require"checker.utils".wait
local log   = require"checker.utils".logger

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
    log.error(
      "Запись о сервере %s не содержит информации о домене, который стоит использовать для подключения к нему",
      tostring(server.name)
    )
    return false
  end
  log.verbose(("=== Подключение (сервер: %s) ==="):format(server.domain))
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
      log.error(("Ошибка десереализации (или верификации) мета-информации о сервере: %s"):format(res))
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

  local failed

  local _E = {}
  _C.clk_proc, _E.errmsg, _E.errno = sp.popen{
    "/usr/bin/ck-client",
    "-s", server.meta.server_ip,
    "-c", cfg_path,
    stdout = _G.stdout,
    stderr = _G.stderr,
  }
  if not _C.clk_proc or _C.clk_proc:poll() then
    log.error(
      "[Cloak] Проблема при инициализации! Сообщение об ошибке: %s. Код: %d",
      _E.errmsg, _E.errno
    )
    failed = true
  end
  sleep(2)
  _C.ss_proc, _E.errmsg, _E.errno = sp.popen{
    "/usr/bin/sslocal",
    "-s", "127.0.0.1:1984",
    "-k", server.meta.ss_password,
    "-b", "127.0.0.1:1080",
    "-m", server.meta.ss_encryption,
    "--timeout", "60",
    stdout = _G.stdout,
    stderr = _G.stderr,
  }
  if not _C.ss_proc or _C.ss_proc:poll() then
    log.error(
      "[ShadowSocks] Проблема при инициализации! Сообщение об ошибке: %s. Код: %d",
      _E.errmsg, _E.errno
    )
    failed = true
  end
  if failed then
    if _C.ss_proc then _C.ss_proc:kill() end
    if _C.clk_proc then _C.clk_proc:kill() end
    _C.ss_proc = nil
    _C.clk_proc = nil
    log.debug"=== перед вызовом wait() ==="
    wait()
    log.debug"=== после вызова wait() ==="
    return false
  end
  sleep(3)
  return true
end

_C.disconnect = function(_server)
  if _C.ss_proc then
    log.verbose"=== [ShadowSocks] Завершение подключения ==="
    _C.ss_proc:terminate()
    _C.ss_proc:wait()
    _C.ss_proc = nil
    sleep(2)
    log.debug"=== перед вызовом wait() ==="
    wait()
    log.debug"=== после вызова wait() ==="
  else
    log.error"[ShadowSocks] Вызвана функция отключения, но что-то случилось c дескрипторами подключения. Нужна отладка!"
  end
  if _C.clk_proc then
    log.verbose"=== [Cloak] Завершение подключения ==="
    _C.clk_proc:terminate()
    _C.clk_proc:wait()
    _C.clk_proc = nil
    sleep(2)
    log.debug"=== перед вызовом wait() ==="
    wait()
    log.debug"=== после вызова wait() ==="
  else
    log.error(
      "[Cloak] Вызвана функция отключения, но что-то случилось c дескрипторами подключения. Нужна отладка!"
    )
  end
end

_C.checker = function(server)
  log.verbose"=== Проверка начата ==="
  local ret = false
  local res = req{
    url = "https://geo.dpidetect.org/get-ip/plain",
    proxy = "socks5://127.0.0.1:1080",
  }
  if res:match(server.meta.server_ip) then
    ret = true
    log.verbose"=== Проверка завершена успешно ==="
  else
    log.error"=== Проверка провалилась! ==="
    log.debug(("IP сервера из метаданных: %q"):format(server.meta.server_ip))
    log.debug(("Ответ сервиса определения IP: %q"):format(res))
  end
  return ret
end

return _C
