local ffi = require "ffi"

ffi.cdef"unsigned int sleep(unsigned int seconds);"
ffi.cdef"unsigned int wait();"

local _U = {}

function _U.getenv(name)
  local ret
  ret = os.getenv(name)
  if not ret then
    io.stderr:write(("Вы не указали значение переменной '%s'. Пожалуйста, укажите его в user.conf\n"):format(name))
    os.exit(1)
  else
    return ret
  end
end

_U.sleep = ffi.C.sleep

_U.wait = ffi.C.wait

local b='ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/' -- You will need this for encoding/decoding

function _U.b64enc(data)
    return ((data:gsub('.', function(x)
        local r,bb='',x:byte()
        for i=8,1,-1 do r=r..(bb%2^i-bb%2^(i-1)>0 and '1' or '0') end
        return r;
    end)..'0000'):gsub('%d%d%d?%d?%d?%d?', function(x)
        if (#x < 6) then return '' end
        local c=0
        for i=1,6 do c=c+(x:sub(i,i)=='1' and 2^(6-i) or 0) end
        return b:sub(c+1,c+1)
    end)..({ '', '==', '=' })[#data%3+1])
end

function _U.b64dec(data)
    data = string.gsub(data, '[^'..b..'=]', '')
    return (data:gsub('.', function(x)
        if (x == '=') then return '' end
        local r,f='',(b:find(x)-1)
        for i=6,1,-1 do r=r..(f%2^i-f%2^(i-1)>0 and '1' or '0') end
        return r;
    end):gsub('%d%d%d?%d?%d?%d?%d?%d?', function(x)
        if (#x ~= 8) then return '' end
        local c=0
        for i=1,8 do c=c+(x:sub(i,i)=='1' and 2^(8-i) or 0) end
            return string.char(c)
    end))
end

local function gettime()
  local date_t = os.date"*t"
  return ("%.02d/%.02d/%.02d %.02d:%.02d:%.02d")
    :format(date_t.day, date_t.month, date_t.year, date_t.hour, date_t.min, date_t.sec)
  -- return (("%day%/%month%/%year% %hour%:%min%:%sec%"):gsub("%%(%w+)%%",os.date('*t')))
end

local function cmds_to_ansi(str)
  local seqs = {
    reset           = "\27[0m",
    normal          = "\27[0m",
    bold            = "\27[1m",
    bright          = "\27[1m",
    dim             = "\27[2m",
    italic          = "\27[3m",
    underline       = "\27[4m",
    blink           = "\27[5m",
    rapidblink      = "\27[6m",
    reverse         = "\27[7m",
    invert          = "\27[7m",
    hide            = "\27[8m",
    strikethrough   = "\27[9m",

    font0           = "\27[10m",
    font1           = "\27[11m",
    font2           = "\27[12m",
    font3           = "\27[13m",
    font4           = "\27[14m",
    font5           = "\27[15m",
    font6           = "\27[16m",
    font7           = "\27[17m",
    font8           = "\27[18m",
    font9           = "\27[19m",

    fraktur         = "\27[20m",
    gothic          = "\27[20m",

    dblunder        = "\27[21m",
    nobold          = "\27[22m",
    nodim           = "\27[22m",
    noitalic        = "\27[23m",
    nounderline     = "\27[24m",
    noblink         = "\27[25m",
    propspc         = "\27[26m",
    noreverse       = "\27[27m",
    noinvert        = "\27[27m",
    nohide          = "\27[28m",
    reveal          = "\27[28m",
    nostrike        = "\27[29m",

    black           = "\27[30m",
    red             = "\27[31m",
    green           = "\27[32m",
    yellow          = "\27[33m",
    blue            = "\27[34m",
    magenta         = "\27[35m",
    cyan            = "\27[36m",
    white           = "\27[37m",
    fg_256          = "\27[38;5;__C__m",
    fg_rgb          = "\27[38;2;__R__;__G__;__B__m",
    fg_default      = "\27[39m",

    blackbg         = "\27[40m",
    redbg           = "\27[41m",
    greenbg         = "\27[42m",
    yellowbg        = "\27[43m",
    bluebg          = "\27[44m",
    magentabg       = "\27[45m",
    cyanbg          = "\27[46m",
    whitebg         = "\27[47m",
    bg_256          = "\27[48;5;__C__m",
    bg_rgb          = "\27[48;2;__R__;__G__;__B__m",
    bg_default      = "\27[49m",

    nopropspc       = "\27[50m",
    frame           = "\27[51m",
    circle          = "\27[52m",
    overline        = "\27[53m",
    noframe         = "\27[54m",
    nocircle        = "\27[54m",
    nooverline      = "\27[55m",
    undercolor_256  = "\27[58;5;__C__m",
    undercolor_rgb  = "\27[58;2;__R__;__G__;__B__m",
    undercolor_def  = "\27[59m",

    superscript     = "\27[73m",
    subscript       = "\27[74m",
    nosuper         = "\27[75m",

    brightblack     = "\27[90m",
    brightred       = "\27[91m",
    brightgreen     = "\27[92m",
    brightyellow    = "\27[93m",
    brightblue      = "\27[94m",
    brightmagenta   = "\27[95m",
    brightcyan      = "\27[96m",
    brightwhite     = "\27[97m",

    brightblackbg   = "\27[90m",
    brightredbg     = "\27[91m",
    brightgreenbg   = "\27[92m",
    brightyellowbg  = "\27[93m",
    brightbluebg    = "\27[94m",
    brightmagentabg = "\27[95m",
    brightcyanbg    = "\27[96m",
    brightwhitebg   = "\27[97m",
  }

  local function parse_cmds(s)
    local buffer = {}
    for word in s:gmatch("[%w:_]+") do
      local seq
      if word:match":" then
        local C, R, G, B
        local cmd = word:gsub(":.+", "")
        local pat = seqs[cmd]
        if cmd:match"_256$" then
          C = word:match":([^:]+)$"
        elseif cmd:match"_rgb$" then
          R, G, B = word:match":([^:]+):([^:]+):([^:]+)$"
        end
        seq = pat:gsub("__([CRGB])__", {C=C, R=R, G=G, B=B})
      else
        seq = seqs[word] or ""
      end
      table.insert(buffer, seq)
    end
    return table.concat(buffer)
  end

  return (str:gsub("(%%{(.-)})", function(_, s) return parse_cmds(s) end))
end

local function log(t)
  local o = t.opts or {}
  local tpl = o.template or "%s%s [%s] | %s | %s%s\n"
  local fds = {
    info = _G.stdout,
  }
  local signs = {
    bad = "!!",
    warn = "WW",
    good = "OK",
    debug = "DD",
    verbose = "VV",
    print = "..",
  }
  local log_to_console = {
    bad = not(_G.QUIET),
    warn = not(_G.QUIET),
    good = not(_G.QUIET),
    verbose = not(not(_G.VERBOSE)),
    print = not(_G.QUIET),
    debug = not(not(_G.DEBUG)),
  }
  local colors = o.colors or {
    bad = "%{red fg_rgb:250:20:20 bold}",
    warn = "%{yellow fg_rgb:250:250:20 bold}",
    good = "%{green fg_rgb:50:200:50}",
    verbose = "%{cyan fg_rgb:60:180:230}",
    print = "%{fg_default fg_rgb:180:180:180}",
    debug = "%{fg_default fg_rgb:111:111:111}",
    reset = "%{reset}",
    bold = "%{bold}",
  }
  local console_fd = o.fd or fds[t.level] or _G.stderr
  local logfile_fd = _G.log_fd
  local function handle_newlines(str)
    local s = tostring(str)
    local nl_tpl = o.nl_tpl or "%s [%s] | %s | "
    local nl_fmt = o.nl_fmt or {
      _G.proto,
      o.sign or signs[t.level] or "?",
      gettime(),
    }
    return (
      s
      :gsub(
        "\n",
        ("\n%s")
        :format(nl_tpl)
        :format(
          table.unpack(nl_fmt)
        )
      )
      :gsub("\r","")
    )
  end
  local fmt = o.format or {
    colors[t.level] or "",
    _G.proto,
    o.sign or signs[t.level] or "?",
    gettime(),
    handle_newlines(t.text or ""),
    colors.reset or "",
  }
  local logrecord = cmds_to_ansi(
    tpl:format(
      table.unpack(fmt)
    )
  )

  if o.force_console or log_to_console[t.level] then
    console_fd:write(logrecord)
  end
  logfile_fd:write(logrecord)
  logfile_fd:flush()
end

_U.logger = {
  bad = function(text, opts)
    log{level = "bad", text = text, opts = opts}
  end,
  warn = function(text, opts)
    log{level = "warn", text = text, opts = opts}
  end,
  good = function(text, opts)
    log{level = "good", text = text, opts = opts}
  end,
  print = function(text, opts)
    log{level = "print", text = text, opts = opts}
  end,
  verbose = function(text, opts)
    log{level = "verbose", text = text, opts = opts}
  end,
  debug = function(text, opts)
    log{level = "debug", text = text, opts = opts}
  end,
  raw = log,
}

function _U.split(str, spr)
    local sep = spr or "\n"
    local result = {}
    local i = 1
    for c in str:gmatch(string.format("([^%s]+)", sep)) do
        result[i] = c
        i = i + 1
    end
    return result
end

return _U
