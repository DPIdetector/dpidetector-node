FROM alpine:latest

ARG TARGETARCH

ARG CLOAK_RELEASE="v2.7.0"

# TODO: move to rust shadowsocks implementation (supports SS2022 + don't require testing repo)
RUN apk add shadowsocks-libev --repository=http://dl-cdn.alpinelinux.org/alpine/edge/testing curl \
  lua5.1-cjson \
  lua5.1-curl \
  lua5.1-subprocess \
  luajit \
  ; \
  if [ ${TARGETARCH}="i386" ]; then CK_ARCH="386"; \
    elif [ ${TARGETARCH}="arm64v8" ]; then CK_ARCH="arm64"; \
    elif [ ${TARGETARCH}="arm32*" ]; then CK_ARCH="arm"; \
    else CK_ARCH=${TARGETARCH}; \
  fi && \
    curl -L https://github.com/cbeuw/Cloak/releases/download/${CLOAK_RELEASE}/ck-client-linux-${CK_ARCH}-${CLOAK_RELEASE} -o /usr/bin/ck-client; chmod +x /usr/bin/ck-client

# WARN: don't forget that all paths are relative to the root of the repo
ADD --link ./checker /usr/share/lua/5.1/checker
ADD --link ./protos/cloak/custom.lua /usr/share/lua/5.1/checker/custom.lua
ADD --link ./protos/cloak/ckclient.json /etc/ckclient.json

CMD ["luajit", "-e", "require'checker'.init()"]
