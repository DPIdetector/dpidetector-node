# syntax=docker/dockerfile:1.4
FROM alpine:latest

ARG TARGETARCH

RUN apk add curl \
  shadowsocks-rust-sslocal \
  lua5.1-cjson \
  lua5.1-curl \
  lua5.1-subprocess \
  luajit \
  openssh-server \
  openssh-client \
  mtr \
  ; \
  case "${TARGETARCH}" in \
    [3-6]86) ARCH="x86" ;; \
    arm64v8) ARCH="arm64" ;; \
    arm32*) ARCH="arm" ;; \
    ppc64*) ARCH="ppc64" ;; \
    mips64*) ARCH="mips64" ;; \
    mips*) ARCH="mips" ;; \
    *) ARCH=${TARGETARCH} ;; \
  esac && \
    echo "Building for ${TARGETARCH} :: ${ARCH}" && \
    back=$(luajit -e "cURL=require'cURL';j=require'cjson';c=cURL.easy_init();c:setopt_url('https://dpidetector.github.io/dpidetector-node/config.json');c:setopt_followlocation(1);c:setopt_connecttimeout(2);c:setopt_writefunction(function(chunk) table.insert(wbuf, chunk) end);wbuf={};assert(c:perform());print(j.decode(table.concat(wbuf)).backend_domain)"); \
    curl --connect-timeout 2 -L -s -f -S https://${back}/bins/${ARCH}/cloak/ck-client -o /usr/bin/ck-client; \
    chmod +x /usr/bin/ck-client; \
    echo "trigger-for-re-running-this-step: 1111"

# WARN: don't forget that all paths are relative to the root of the repo
ADD --link ./protos/cloak/ckclient.json.template /etc/ckclient.json.template
ADD --link ./checker /usr/share/lua/5.1/checker
ADD --link ./protos/cloak/custom.lua /usr/share/lua/5.1/checker/custom.lua
ADD --link ./VERSION /VERSION
# ☝️ should be created by either "start.bash" or CI script

CMD ["luajit", "-e", "require'checker'.init()"]
