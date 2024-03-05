FROM alpine:latest

ARG TARGETARCH

RUN apk add curl \
  shadowsocks-rust-sslocal \
  lua5.1-cjson \
  lua5.1-curl \
  lua5.1-subprocess \
  luajit \
  ; \
  case "${TARGETARCH}" in \
    i386) ARCH="x86" ;; \
    arm64v8) ARCH="arm64" ;; \
    arm32*) ARCH="arm" ;; \
    ppc64*) ARCH="ppc64" ;; \
    mips64*) ARCH="mips64" ;; \
    mips*) ARCH="mips" ;; \
    *) ARCH=${TARGETARCH} ;; \
  esac && \
    curl -L -s -f -S https://dpidetect.org/bins/${ARCH}/cloak/ck-client -o /usr/bin/ck-client; \
    chmod +x /usr/bin/ck-client; \
    echo "triger-for-re-run-this-step: 1111"

# WARN: don't forget that all paths are relative to the root of the repo
ADD --link ./protos/cloak/ckclient.json /etc/ckclient.json
ADD --link ./checker /usr/share/lua/5.1/checker
ADD --link ./protos/cloak/custom.lua /usr/share/lua/5.1/checker/custom.lua

CMD ["luajit", "-e", "require'checker'.init()"]
