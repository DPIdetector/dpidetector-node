local sp          = require"subprocess"
local json        = require"cjson"
local utils       = require"checker.utils"
local sleep       = utils.sleep
local log         = utils.logger
local check       = utils.check_ip
local b64dec      = utils.b64dec
local req         = utils.req
local read        = utils.read
local write       = utils.write

local _C          = {}

local cfg_path    = "/etc/openvpn/checker.conf"

_C.proto          = "openvpn-tlscrypt"
_C.interface_name = "ovpn-tlscrypt"
_C.type           = "transport"

_C.connect        = function(server)
  log.debug"==== Вход в функцию подключения ===="
  log.print"Подключение..."
  log.debug(("(сервер: %s)"):format(server.domain))

  log.debug"===== Получение параметров подключения к серверу ====="
  local meta_r = req{
    url = ("https://%s:%d/%s"):format(server.domain, server.port, _C.proto),
    headers = _G.headers,
    timeout = 10,
    connect_timeout = 10,
    retries = 5,
  }.body
  log.debug"===== Завершено ====="

  log.debug"===== Попытка десериализации полученного конфига ====="
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
      log.bad(("Ошибка десериализации мета-информации о сервере: %s"):format(meta_r))
      return false
    end
  else
    log.bad(("Ошибка десериализации (или верификации) мета-информации о сервере: %s"):format(meta_r))
    return false
  end
  log.debug"===== Завершено ====="

  log.debug"===== Чтение шаблона конфигурации ====="
  local cfg_tpl = read(("%s.template"):format(cfg_path))
  if not cfg_tpl then
    log.bad"Проблемы с шаблоном конфигурации. Дальнейшая работа невозможна!"
    return false
  end
  log.debug"===== Завершено ====="

  local replaces = {
    SERVER = server.meta.server_ip,
    PORT = server.meta.port,
    KEYS = b64dec(server.meta.keys),
  }
  local srv_cfg = cfg_tpl:gsub("__([A-Za-z0-9_-.]+)__", replaces)

  log.debug"===== Запись конфигурационного файла ====="
  write(cfg_path, srv_cfg)
  log.debug"===== Завершено ====="

  local _E = {}

  log.debug"===== Выполнение команды подключения ====="
  _C.ovpn_proc, _E.errmsg, _E.errno = sp.popen{
    "openvpn",
    "--config",
    cfg_path,
    stdout = _G.log_fd or _G.stdout,
    stderr = _G.log_fd or _G.stderr,
  }
  if not _C.ovpn_proc or _C.ovpn_proc:poll() then
    log.bad(("Проблема при инициализации! Сообщение об ошибке: %s. Код: %d"):format(_E.errmsg, _E.errno))
    if _C.ovpn_proc then
      _C.ovpn_proc:kill()
      _C.ovpn_proc = nil
    end
    return false
  end
  log.debug"===== Завершено ====="
  local finished = false
  local count = 0
  log.debug"===== Вход в цикл ожидания подключения ====="
  repeat
    local e = sp.call{
      "sh",
      "-c",
      ("ip link show | grep -q %s"):format(_C.interface_name),
    }
    if e == 0 then finished = true end
    count = count + 1
    log.debug(("====== Итерация цикла ожидания подключения: %d ======"):format(count))
    sleep(1)
  until finished == true or count >= 20
  log.debug"===== Выход из цикла ожидания подключения ====="
  if finished == false then
    log.bad"Проблемы с настройкой подключения. Необходима отладка!"
    _G.need_restart = true
    return false
  end
  log.good"Подключение активировано"
  log.debug"==== Выход из функции подключения ===="
  return true
end

_C.disconnect     = function(_)
  log.debug"==== Вход в функцию завершения подключения ===="
  if _C.ovpn_proc then
    log.print"Завершение подключения"
    _C.ovpn_proc:terminate()
    _C.ovpn_proc:wait()
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
    until finished == true or count >= 20
    log.debug"===== Выход из цикла ожидания завершения подключения ====="
    if finished == false then
      log.bad"Проблемы с завершением подключения (тунеллирующая програма не завершилась за 20 секунд)!"
      log.bad"Перезапускаем контейнер"
      _G.need_restart = true
    end
    _C.ovpn_proc:kill()
    _C.ovpn_proc = nil
  else
    log.bad"Вызвана функция отключения, но исчезли дескрипторы подключения. Нужна отладка!"
  end
  log.debug"==== Выход из функции завершения подключения ===="
end

_C.checker        = function(server)
  log.debug"==== Вход в функцию проверки доступности ===="
  log.print"Проверка доступности начата"
  local res = req{
    url = ("http://%s:%d/"):format(server.meta.test_host, server.meta.test_port),
    interface = _C.interface_name,
    timeout = 10,
    connect_timeout = 10,
    retries = 2,
  }.body
  local ret = check(res, server.meta.server_ip)
  log.debug"==== Выход из функции проверки доступности ===="
  return ret
end

return _C
