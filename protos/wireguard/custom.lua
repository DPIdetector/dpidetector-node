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

_C.connect = function(server)
  log.debug"==== Вход в функцию подключения ===="
  log.print"Подключение..."
  log.debug(("(сервер: %s)"):format(server.domain))

  log.debug"===== Получение параметров подключения к серверу ====="
  local meta_r = req{
    url = ("https://%s:%d/%s"):format(server.domain, server.port, _C.proto),
    headers = _G.headers,
  }
  log.debug"===== Завершено ====="

  log.debug"===== Попытка десериализации полученного конфига ====="
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
      log.bad(("Ошибка десереализации мета-информации о сервере: %s"):format(meta_r))
      return false
    end
  end
  log.debug"===== Завершено ====="

  local fd

  log.debug"===== Чтение шаблона конфигурации ====="
  fd = io.open(("%s.template"):format(cfg_path), "r")
  local cfg_tpl = fd:read"*a"
  fd:close()
  log.debug"===== Завершено ====="

  local replaces = {
    SERVER = server.meta.server_ip,
    PORT = server.meta.port,
    PRIVKEY = server.meta.privkey,
    PUBKEY = server.meta.pubkey,
    ADDRESS = server.meta.int_address,
    NETWORK = server.meta.int_net,
  }
  local srv_cfg = cfg_tpl:gsub("__([A-Za-z0-9_-.]+)__", replaces)

  log.debug"===== Запись конфигурационного файла ====="
  fd = io.open(cfg_path, "w+")
  fd:write(srv_cfg)
  fd:flush()
  fd:close()
  log.debug"===== Завершено ====="

  log.debug"===== Выполнение команды подключения ====="
  local exitcode = sp.call{
    "wg-quick",
    "up",
    _C.interface_name,
    stdout = _G.log_fd or _G.stdout,
    stderr = _G.log_fd or _G.stderr,
  }
  log.debug"===== Завершено ====="
  if exitcode ~= 0 then
    log.bad(("Проблема при выполнении `wg-quick up`! Код выхода: %d"):format(exitcode))
    return false
  end
  local finished = false
  local count = 0
  log.debug"===== Вход в цикл ожидания подключения ====="
  repeat
    count = count + 1
    log.debug(("====== Итерация цикла ожидания подключения: %d ======"):format(count))
    local e = sp.call{
      "sh",
      "-c",
      ("ip link show | grep -q %s"):format(_C.interface_name),
    }
    if e == 0 then finished = true end
    sleep(1)
  until finished==true or count>=20
  log.debug"===== Выход из цикла ожидания подключения ====="
  if finished == false then
    log.bad"Проблемы с настройкой подключения. Необходима отладка!"
    return false
  end
  log.good"Подключение активировано"
  log.debug"==== Выход из функции подключения ===="
  return true
end

_C.disconnect = function(_server)
  log.debug"==== Вход в функцию завершения подключения ===="
  local exitcode = sp.call{
    "wg-quick",
    "down",
    _C.interface_name,
    stdout = _G.log_fd or _G.stdout,
    stderr = _G.log_fd or _G.stderr,
  }
  if exitcode ~= 0 then
    log.bad(("Проблема при выполнении `wg-quick down`! Код выхода: %d"):format(exitcode))
  end
  local finished = false
  local count = 0
  log.debug"===== Вход в цикл ожидания завершения подключения ====="
  repeat
    count = count + 1
    log.debug(("====== Итерация цикла ожидания завершения подключения: %d ======"):format(count))
    local e = sp.call{
      "sh",
      "-c",
      ("ip link show | grep -q %s"):format(_C.interface_name),
    }
    if e == 1 then finished = true end
    sleep(1)
  until finished==true or count>=20
  log.debug"===== Выход из цикла ожидания завершения подключения ====="
  if finished == false then
    log.bad"Проблемы с завершением подключения (тунеллирующая програма не завершилась за 20 секунд)!"
    log.bad"Перезапускаем контейнер"
    _G.need_restart = true
  end
  local zombies = true
  count = 0
  log.debug"===== Вход в цикл очистки зомби-процессов ====="
  repeat
    count = count + 1
    log.debug(("====== Итерация цикла очистки зомби-процессов: %d ======"):format(count))
    local e = sp.call{
      "sh",
      "-c",
      "ps -o stat,pid,comm | grep -q '^Z'",
    }
    if e == 1 then zombies = false end
    if zombies == true then
      log.debug"====== перед вызовом wait() ======"
      wait()
      log.debug"====== после вызова wait() ======"
    end
  until zombies==false or count>=20
  log.debug"===== Выход из цикла очистки зомби-процессов ====="
  if zombies == true then
    log.bad"Проблемы с очисткой зомби-процессов (накопилось больше 20 зомби)!"
    log.bad"Перезапускаем контейнер"
    _G.need_restart = true
  end
  log.debug"==== Выход из функции завершения подключения ===="
end

_C.checker = function(server)
  log.debug"==== Вход в функцию проверки доступности ===="
  log.print"Проверка доступности начата"
  local ret = false
  local res = req{
    url = ("http://%s:%d/"):format(server.meta.test_host, server.meta.test_port),
    interface = _C.interface_name,
  }

  if res:match(server.meta.server_ip) then
    ret = true
    log.good"Проверка завершена успешно"
  else
    log.bad"Проверка провалилась!"
    log.debug(("IP сервера (из метаданных): %q"):format(server.meta.server_ip))
    log.debug(("Ответ сервиса определения IP (или ошибка cURL): %q"):format(res))
    if res:match"^%d%d?%d?%.%d%d?%d?%.%d%d?%d?%.%d%d?%d?$" then --- TODO: IPv6 когда докер будет уметь его из коробки
      log.debug"%{bold} Учитывая, что выше не ошибка подключения, а два разных IP, скорее всего проявился какой-то баг"
      log.debug"%{bold} Возможные варианты:"
      log.debug"%{bold} - не отключилось предыдущее подключение"
      log.debug"%{bold} - что-то с обновлением конфига (или шаблоном)"
      log.debug"%{bold} - баг в туннелирующем софте и на предыдущей итерации он отказался отключаться"
      log.debug"%{bold} В любом случае - нужно написать в чат"
    end
  end
  log.debug"==== Выход из функции проверки доступности ===="
  return ret
end

return _C

