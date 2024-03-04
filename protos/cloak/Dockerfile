FROM alpine:latest

ARG TARGETARCH

ARG CLOAK_RELEASE="v2.8.0"

RUN apk add curl \
  shadowsocks-rust-sslocal \
  lua5.1-cjson \
  lua5.1-curl \
  lua5.1-subprocess \
  luajit \
  ; \
  case "${TARGETARCH}" in \
    i386) CK_ARCH="386" ;; \
    arm64v8) CK_ARCH="arm64" ;; \
    arm32*) CK_ARCH="arm" ;; \
    *) CK_ARCH=${TARGETARCH} ;; \
  esac && \
    curl -L \
      https://github.com/cbeuw/Cloak/releases/download/${CLOAK_RELEASE}/ck-client-linux-${CK_ARCH}-${CLOAK_RELEASE} \
    -o /usr/bin/ck-client; \
    chmod +x /usr/bin/ck-client

# WARN: don't forget that all paths are relative to the root of the repo
ADD --link ./protos/cloak/ckclient.json /etc/ckclient.json
ADD --link ./checker /usr/share/lua/5.1/checker
ADD --link ./protos/cloak/custom.lua /usr/share/lua/5.1/checker/custom.lua

CMD ["luajit", "-e", "require'checker'.init()"]
