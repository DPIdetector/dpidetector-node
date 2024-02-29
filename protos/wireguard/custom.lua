local sp    = require"subprocess"
local req   = require"checker.requests"
local json  = require"cjson"
local sleep = require"checker.utils".sleep
local wait  = require"checker.utils".wait
local log   = require"checker.utils".logger

local _C = {}

local cfg_path = "/etc/wireguard/wg.conf"

_C.proto = "wireguard"
_C.interface_name = "wg"

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
      log.error(("Ошибка десереализации мета-информации о сервере: %s"):format(res))
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
    log.error(("Проблема при инициализации! Код выхода: %d"):format(exitcode))
    return false
  end
  local finished = false
  local count = 0
  log.debug"Вход в цикл ожидания подключения"
  repeat
    local e = sp.call{
      "sh",
      "-c",
      ("ip link show | grep -q %s"):format(_C.interface_name),
    }
    if e == 0 then finished = true end
    count = count + 1
    log.debug(("Итерация цикла ожидания подключения: %d"):format(count))
    sleep(1)
  until finished==true or count>=20
  log.debug"Выход из цикла ожидания подключения"
  if finished == false then
    log.error"Проблемы с настройкой подключения. Необходима отладка!"
    return false
  end
  return true
end

_C.disconnect = function(_server)
  log.verbose"=== Завершение подключения ==="
  local exitcode = sp.call{
    "wg-quick",
    "down",
    _C.interface_name,
    stdout = _G.stdout,
    stderr = _G.stderr,
  }
  if exitcode ~= 0 then
    log.error(("Проблема при остановке! Код выхода: %d"):format(exitcode))
  end
  local finished = false
  local count = 0
  log.debug"Вход в цикл ожидания завершения подключения"
  repeat
    local e = sp.call{
      "sh",
      "-c",
      ("ip link show | grep -q %s"):format(_C.interface_name),
    }
    if e == 1 then finished = true end
    count = count + 1
    log.debug(("Итерация цикла ожидания завершения подключения: %d"):format(count))
    sleep(1)
  until finished==true or count>=10
  log.debug"Выход из цикла ожидания завершения подключения"
  if finished == false then
    log.error"Проблемы с завершением подключения. Необходима отладка!"
  end
  local zombies = true
  count = 0
  log.debug"Вход в цикл очистки зомби-процессов"
  repeat
    local e = sp.call{
      "sh",
      "-c",
      "ps -o stat,pid,comm | grep -q '^Z'",
    }
    if e == 1 then zombies = false end
    if zombies == true then
      log.debug"=== перед вызовом wait() ==="
      wait()
      log.debug"=== после вызова wait() ==="
    end
    count = count + 1
    log.debug(("Итерация цикла очистки зомби-процессов: %d"):format(count))
  until zombies==false or count>=20
  log.debug"Выход из цикла очистки зомби-процессов"
  if zombies == true then
    log.error"Проблемы с очисткой зомби-процессов. Необходима отладка!"
  end
end

_C.checker = function(server)
  log.verbose"Проверка начата"
  local ret = false
  local res = req{
    url = ("http://%s:%d/"):format(server.meta.test_host, server.meta.test_port),
    interface = _C.interface_name,
  }
  if res:match(server.meta.server_ip) then
    ret = true
    log.verbose"Проверка завершена успешно"
  else
    log.error"Проверка провалилась!"
    log.debug(("IP сервера из метаданных: %q"):format(server.meta.server_ip))
    log.debug(("Ответ сервиса определения IP: %q"):format(res))
  end
  return ret
end

return _C

