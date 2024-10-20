-- luacheck: globals

_G.config_default = {
  interval       = 300,
  backend_domain = "dpidetect.org",
  get_geo_url    = "https://geo.dpidetect.org/get-iso/plain",
  get_ip_url     = "https://geo.dpidetect.org/get-ip/plain",
}

--- @type file*
_G.devnull        = assert(io.output("/dev/null"))
if _G.QUIET then
  _G.stdout = _G.devnull
  _G.stderr = _G.devnull
else
  _G.stdout = assert(io.stdout)
  _G.stderr = assert(io.stderr)
  io.output(io.stdout)
end
--- @type file*
_G.log_fd = _G.devnull

local json        = require"cjson"
local custom      = require"checker.custom"
local utils       = require"checker.utils"
local sleep       = utils.sleep
local getenv      = utils.getenv
local getconf     = utils.getconf
local log         = utils.logger
local trace       = utils.trace
local ripz        = utils.divine_grenade
local b64enc      = utils.b64enc
local is_locked   = utils.is_locked
local req         = utils.req
local read        = utils.read
local check_ssh   = utils.setup_ssh_tunnel
_G.proto          = custom.proto
_G.node_id        = getenv"node_id"
_G.token          = getenv"token"

_G.version        = (read"/VERSION" or "broken"):match"v?(.-)[\r\n]*$"

_G.DEBUG          = os.getenv"DEBUG" or os.getenv(("%s_DEBUG"):format(_G.proto:gsub("-", "_")))
_G.VERBOSE        = os.getenv"VERBOSE" or os.getenv(("%s_VERBOSE"):format(_G.proto:gsub("-", "_")))
_G.QUIET          = os.getenv"QUIET" and not (_G.VERBOSE or _G.DEBUG)

local log_fn = "/tmp/log"

log.debug"Запуск приложения"

_G.headers = {
  ("Token: %s"):format(_G.token),
  ("Node-Id: %s"):format(_G.node_id),
  ("Software-Version: %s"):format(_G.version),
  "Content-Type: application/json",
}

math.randomseed(
  math.fmod(
    table.concat{
      (("dpidetector/%s"):format(_G.proto)):byte(1, -1)
    } + os.clock(),
    os.time() + os.clock()
  ) ^ (-1 / os.clock())
)

log.debug"= Вход в основной рабочий цикл ="
--- TODO: переписать на `luv`
local cycle = 0
repeat
  log.debug"== Итерация главного цикла начата =="

  _G.current_config_json = req{
    url = "https://dpidetector.github.io/dpidetector-node/config.json" --- NOTE: 🤔
  }

  local api = ("https://%s/api"):format(getconf"backend_domain")
  local servers_endpoint = ("%s/servers/"):format(api)
  local reports_endpoint = ("%s/reports/"):format(api)
  local interval = getconf"interval"
  local geo = req{
    url = getconf"get_geo_url"
  }

  if os.getenv"NO_SSH" then
    log.debug"=== (SSH-функциональность отключена пользователем) ==="
  else
    check_ssh()
  end

  if not is_locked() and geo:match"RU" then
    --- NOTE: 👆
    --- Выполнять проверки только если нода выходит в интернет в России (например, не через VPN)
    --- т.к. в данный момент мы анализируем блокировку трафика на сетях именно российских провайдеров,
    --- а трафик через заграничных для этих целей бесполезен

    if custom.type == "transport" then --- NOTE: vpn/прокси/и т.п.
      local servers_fetched = req{
        url = servers_endpoint,
        headers = _G.headers,
        timeout = 10,
        connect_timeout = 10,
        retries = 10,
      }

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
          local servers = e or {}
          for idx, server in ipairs(servers) do
            log.debug(("=== [%d] Итерация цикла проверки доступности серверов начата ==="):format(idx))

            _G.log_fd = assert(io.open(log_fn, "w+"))

            trace(server.domain and {
              host = server.domain,
              proto = "tcp",
              port = 443,
            })

            sleep(5) --- NOTE: пауза между итерациями проверок
            log.print"Попытка установления соединения с сервером и проверки работоспособности подключения"
            local conn = custom.connect(server)

            local report = {
              server_domain = tostring(server.domain),
              protocol = tostring(_G.proto),
            }

            if conn then
              log.debug"=== Функция установки соединения завершилась успешно ==="
              sleep(5) --- NOTE: дадим время туннелю "устаканиться"
              log.debug"=== Запуск функции проверки соединения ==="
              local result = custom.checker and custom.checker(server) or false
              log.debug"=== Запуск функции завершения соединения ==="
              sleep(3) --- NOTE: небольшая пауза перед отключением после проверки
              custom.disconnect(server)
              local available = not (not (result))

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

            if not report.available then
              report.log = b64enc(_G.log_fd:read"*a" or "")
            end

            log.print"Отправка отчёта"
            local resp_json = req{
              url = reports_endpoint,
              post = json.encode(report),
              headers = _G.headers,
              timeout = 10,
              connect_timeout = 10,
              retries = 0,
            }

            local rok, resp_t = pcall(json.decode, resp_json)
            if not rok then
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

            ripz() --- NOTE: 🔫🧟
            if _G.need_restart then os.exit(1) end
            --- NOTE: ☝️ перезапускаем контейнер, если начала происходить какая-то дичь

            _G.log_fd:close()
            _G.log_fd = _G.devnull

            log.debug(("=== [%d] Итерация цикла проверки доступности серверов завершена ==="):format(idx))
          end
        end
      else
        log.bad"Не удалось получить список серверов"
        log.bad"Если данное сообщение имеет разовый характер - можно проигнорировать"
        log.bad"Если появляется при каждой итерации проверки - включите режим отладки и проверьте причину"
        log.debug"====== Результат запроса: ======"
        log.debug(servers_fetched)
        log.debug"=================="
      end
    elseif custom.type == "service" then --- NOTE: мессенджеры, соцсети, ...
      log.debug(("=== Итерация цикла с заданиями начата ==="))

      -- _G.log_fd = assert(io.open(log_fn, "w+"))

      _ = custom.prepare and custom.prepare()
      _ = custom.perform and custom.perform()
      _ = custom.finish and custom.finish()

      if _G.need_restart then os.exit(1) end
      --- NOTE: ☝️ перезапускаем контейнер, если начала происходить какая-то дичь

      -- _G.log_fd:close()
      -- _G.log_fd = _G.devnull

      log.debug(("=== Итерация цикла с заданиями завершена ==="))
    else
      log.bad"Запускаемый тип проверочного узла на данный момент не поддерживается"
    end
  end

  log.debug"== Итерация главного цикла окончена =="
  log.debug"== Ожидание следующей итерации цикла проверки =="
  sleep(interval)
  cycle = cycle + 1
until cycle >= 86400 / interval + math.random(3, 7)
--- NOTE:    ☝️☝️ раз в сутки (+ рандомизация чтобы перезапускались не все контейнеры одновременно)
log.print("= Плановый перезапуск раз в сутки для очистки контейнера от потенциальных утечек =")
