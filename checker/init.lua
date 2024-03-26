-- luacheck: globals

local interval = 600
_G.version  = "0.0.1"

local json   = require"cjson"
local utils  = require"checker.utils"
local req    = require"checker.requests"
local custom = require"checker.custom"
local sleep  = utils.sleep
local getenv = utils.getenv
local log    = utils.logger

_G.proto     = custom.proto
local token  = getenv"token"
local node_id   = getenv"node_id"

_G.DEBUG = os.getenv"DEBUG" or os.getenv(("%s_DEBUG"):format(_G.proto:gsub("-", "_")))
_G.VERBOSE = os.getenv"VERBOSE" or os.getenv(("%s_VERBOSE"):format(_G.proto:gsub("-", "_")))
_G.QUIET = os.getenv"QUIET" and not(_G.VERBOSE or _G.DEBUG)

_G.devnull = io.output("/dev/null")
if _G.QUIET then
  _G.stdout  = _G.devnull
  _G.stderr  = _G.devnull
else
  _G.stdout = io.stdout
  _G.stderr = io.stderr
  io.output(io.stdout)
end

local log_fn = "/tmp/log"
_G.log_fd = _G.devnull

log.debug"Запуск приложения"

local backend_domain = "dpidetect.org"
local api = ("https://%s/api"):format(backend_domain)
local servers_endpoint = ("%s/servers/"):format(api)
local reports_endpoint = ("%s/reports/"):format(api)

_G.headers = {
  ("Token: %s"):format(token),
  ("Software-Version: %s"):format(_G.version),
  "Content-Type: application/json",
}

log.debug"= Вход в основной рабочий цикл ="
while true do
  log.debug"== Итерация главного цикла начата =="
  local servers = {}

  local geo = req{
    url = "https://geo.dpidetect.org/get-iso/plain"
  }

  if geo:match"RU" then
    -- Выполнять проверки только если нода выходит в интернет в России (например, не через VPN)
    -- т.к. в данный момент нас интересует именно блокировка трафика из/внутри России,
    -- а трафик из заграницы для этих целей бесполезен
    local servers_fetched = req{
      url = servers_endpoint,
      headers = _G.headers,
    }

    if servers_fetched:match"COULDNT_CONNECT" then
      --- HACK: (костыль) если получили ошибку "невозможно соединиться",
      --- то на всякий случай попробуем перезапросить ещё раз
      servers_fetched = req{
        url = servers_endpoint,
        headers = _G.headers,
      }
    end

    if servers_fetched
      and servers_fetched:match"domain"
      and servers_fetched:match"^%["
    then
      local ok, e = pcall(json.decode, servers_fetched)
      if not ok then
        log.bad"Проблема со списком серверов (при частом повторении - попробуйте включить режим отладки)"
        log.verbose"(Не получается десериализовать JSON со списком серверов)"
        log.debug"====== Результат запроса: ======"
        log.debug(servers_fetched)
        log.debug"=================="
        log.debug"====== Результат попытки десериализации: ======"
        log.debug(e)
        log.debug"=================="
      else
        servers = e
      end
    else
      log.bad"Не удалось получить список серверов"
      log.bad"Если данное сообщение имеет разовый характер - можно проигнорировать"
      log.bad"Если появляется при каждой итерации проверки - включите режим отладки и проверьте причину"
      log.debug"====== Результат запроса: ======"
      log.debug(servers_fetched)
      log.debug"=================="
    end
  end

  for idx, server in ipairs(servers) do
    log.debug(("=== [%d] Итерация цикла проверки доступности серверов начата ==="):format(idx))

    _G.log_fd = io.open(log_fn, "w+")

    log.print"Попытка установления соединения с сервером и проверки работоспособности подключения"
    local conn = custom.connect(server)

    local report = {
      node_id = tostring(node_id),
      server_domain = tostring(server.domain),
      protocol = tostring(_G.proto),
    }

    if conn then
      log.debug"=== Функция установки соединения завершилась успешно ==="
      log.debug"=== Запуск функции проверки соединения ==="
      local result = custom.checker and custom.checker(server) or false
      log.debug"=== Запуск функции завершения соединения ==="
      custom.disconnect(server)
      local available = not(not(result))

      report.available = available or false

      if available then
        log.good"Cоединение с сервером не блокируется"
      else
        log.bad"Соединение с сервером, возможно, блокируется"
      end
    else
      report.available = false
      log.bad"Проблемы при подключении к серверу"
    end

    _G.log_fd:flush()
    _G.log_fd:seek"set"

    report.log = _G.log_fd:read"*a"

    log.print"Отправка отчёта"
    local resp_json = req{
      url = reports_endpoint,
      post = json.encode(report),
      headers = _G.headers,
    }
    local ok, resp_t = pcall(json.decode, resp_json)
    if not ok then
      log.bad(
        ("Ошибка обработки ответа бекенда! Ожидался JSON-массив, получено: %s")
          :format(resp_json)
      )
      resp_t = {}
    end
    if resp_t.status == "success" then
      log.good(("Отчёт успешно получен сервером и ему присвоен номер %s"):format(resp_t.uid or "<ошибка>"))
    else
      log.bad"При отправке отчёта произошли ошибки"
      log.bad"Возможно, информация ниже вам пригодится:"
      log.bad(("Ответ сервера: %s"):format(resp_json))
      log.bad"Если из сообщений об ошибках выше ничего не понятно - напишите в чат"
    end

    _G.log_fd:close()
    _G.log_fd = _G.devnull

    log.debug(("=== [%d] Итерация цикла проверки доступности серверов завершена ==="):format(idx))
  end

  log.debug"== Итерация главного цикла окончена =="
  log.debug"== Ожидание следующей итерации цикла проверки =="

  sleep(interval)
end
