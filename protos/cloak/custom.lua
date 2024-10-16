local sp       = require"subprocess"
local json     = require"cjson"
local utils    = require"checker.utils"
local sleep    = utils.sleep
local log      = utils.logger
local getconf  = utils.getconf
local check    = utils.check_ip
local req      = utils.req
local read     = utils.read
local write    = utils.write

local _C       = {}

local cfg_path = "/etc/ckclient.json"

_C.proto       = "cloak"
_C.type        = "transport"

_C.connect     = function(server)
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
  }
  log.debug"===== Завершено ====="

  log.debug"===== Попытка десериализации полученного конфига ====="
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
      log.bad(("Ошибка десериализации (или верификации) мета-информации о сервере: %s"):format(meta_r))
      return false
    end
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
    ENCRYPTION = server.meta.encryption,
    UID = server.meta.uid,
    PUBKEY = server.meta.pubkey,
    SERVERNAME = server.meta.servername,
    BROWSER = server.meta.browsersig,
  }
  local srv_cfg = cfg_tpl:gsub("__([A-Za-z0-9_-.]+)__", replaces)

  log.debug"===== Запись конфигурационного файла ====="
  write(cfg_path, srv_cfg)
  log.debug"===== Завершено ====="

  local failed

  local _E = {}

  log.debug"===== [Cloak] Выполнение команды подключения ====="
  _C.clk_proc, _E.errmsg, _E.errno = sp.popen{
    "ck-client",
    "-s", server.meta.server_ip,
    "-c", cfg_path,
    stdout = _G.log_fd or _G.stdout,
    stderr = _G.log_fd or _G.stderr,
  }
  if not _C.clk_proc or _C.clk_proc:poll() then
    log.bad(("[Cloak] Проблема при инициализации! Сообщение об ошибке: %s. Код: %d"):format(_E.errmsg, _E.errno))
    failed = true
  end
  log.debug"===== Завершено ====="
  sleep(2)
  log.debug"===== [ShadowSocks] Выполнение команды подключения ====="
  _C.ss_proc, _E.errmsg, _E.errno = sp.popen{
    "sslocal",
    "-s", "127.0.0.1:1984",
    "-k", server.meta.ss_password,
    "-b", "127.0.0.1:1080",
    "-m", server.meta.ss_encryption,
    "--timeout", "60",
    stdout = _G.log_fd or _G.stdout,
    stderr = _G.log_fd or _G.stderr,
  }
  if not _C.ss_proc or _C.ss_proc:poll() then
    log.bad(("[ShadowSocks] Проблема при инициализации! Сообщение об ошибке: %s. Код: %d"):format(_E.errmsg, _E.errno))
    failed = true
  end
  if failed then
    if _C.ss_proc then _C.ss_proc:kill() end
    if _C.clk_proc then _C.clk_proc:kill() end
    _C.ss_proc = nil
    _C.clk_proc = nil
    return false
  end
  log.debug"===== Завершено ====="
  log.good"Подключение активировано"
  log.debug"==== Выход из функции подключения ===="
  return true
end

_C.disconnect  = function(_)
  log.debug"==== Вход в функцию завершения подключения ===="
  if _C.ss_proc then
    log.print"[ShadowSocks] Завершение подключения"
    _C.ss_proc:terminate()
    _C.ss_proc:wait()
    _C.ss_proc = nil
  else
    log.bad"[ShadowSocks] Вызвана функция отключения, но исчезли дескрипторы подключения. Нужна отладка!"
  end
  if _C.clk_proc then
    log.print"[Cloak] Завершение подключения"
    _C.clk_proc:terminate()
    _C.clk_proc:wait()
    _C.clk_proc = nil
  else
    log.bad("[Cloak] Вызвана функция отключения, но исчезли дескрипторы подключения. Нужна отладка!")
  end
  log.debug"==== Выход из функции завершения подключения ===="
end

_C.checker     = function(server)
  log.debug"==== Вход в функцию проверки доступности ===="
  log.print"Проверка доступности начата"
  local res = req{
    url = getconf("get_ip_url"),
    proxy = "socks5://127.0.0.1:1080",
    timeout = 10,
    connect_timeout = 10,
    retries = 2,
  }
  local ret = check(res, server.meta.server_ip)
  log.debug"==== Выход из функции проверки доступности ===="
  return ret
end

return _C
