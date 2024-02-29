FROM alpine:latest

RUN apk add \
  curl \
  bash \
  lua5.1-cjson \
  lua5.1-curl \
  lua5.1-subprocess \
  luajit

COPY --from=amneziavpn/amnezia-wg:latest --chmod=755 /usr/bin/wireguard-go /usr/bin/wireguard-go
COPY --from=amneziavpn/amnezia-wg:latest --chmod=755 /usr/bin/wg-quick /usr/bin/wg-quick
COPY --from=amneziavpn/amnezia-wg:latest --chmod=755 /usr/bin/wg /usr/bin/wg

# WARN: don't forget that all paths are relative to the root of the repo
ADD --link --chmod=600 ./protos/wireguard/wg.conf /etc/wireguard/wg.conf
ADD --link ./checker /usr/share/lua/5.1/checker
ADD --link ./protos/wireguard/custom.lua /usr/share/lua/5.1/checker/custom.lua

CMD ["luajit", "-e", "require'checker'.init()"]
