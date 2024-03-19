local sp    = require"subprocess"
local req   = require"checker.requests"
local json  = require"cjson"
local sleep = require"checker.utils".sleep
local wait  = require"checker.utils".wait
local log   = require"checker.utils".logger

local _C = {}

_C.proto = "shadowsocks"

_C.init = function()
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
    if ok then
      server.meta = res
    else
      log.error(("Ошибка десереализации мета-информации о сервере: %s"):format(res))
      return false
    end
  end
  local _E = {}
  _C.ss_proc, _E.errmsg, _E.errno = sp.popen{
    "/usr/bin/sslocal",
    "-s", ("%s:%d"):format(server.meta.server_ip, server.meta.port),
    "-k", server.meta.password,
    "-b", "127.0.0.1:1080",
    "-m", server.meta.encryption,
    "--timeout", "60",
    stdout = _G.log_fd or _G.stdout,
    stderr = _G.log_fd or _G.stderr,
  }
  if not _C.ss_proc or _C.ss_proc:poll() then
    log.error(("Проблема при инициализации! Сообщение об ошибке: %s. Код: %d"):format(_E.errmsg, _E.errno))
    if _C.ss_proc then _C.ss_proc:kill() end
    _C.ss_proc = nil
    log.debug"=== перед вызовом wait() ==="
    wait()
    log.debug"=== после вызова wait() ==="
    return false
  end
  sleep(5)
  return true
end

_C.disconnect = function(_server)
  if _C.ss_proc then
    log.verbose"=== Завершение подключения ==="
    _C.ss_proc:terminate()
    _C.ss_proc:wait()
    _C.ss_proc = nil
    sleep(2)
    log.debug"=== перед вызовом wait() ==="
    wait()
    log.debug"=== после вызова wait() ==="
  else
    log.error"Вызвана функция отключения, но что-то случилось c дескрипторами подключения. Нужна отладка!"
  end
  sleep(3)
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
    log.debug(("Ответ сервиса определения IP: %q"):forget(res))
  end
  return ret
end

return _C
