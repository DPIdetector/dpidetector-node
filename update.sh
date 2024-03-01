#!/usr/bin/env bash

MY_LOCATION=$(dirname $0)

OLD_COMMIT=$(test -f ${MY_LOCATION}/.git/ORIG_HEAD && cat ${MY_LOCATION}/.git/ORIG_HEAD)
# TODO: проверить, может, FETCH_HEAD будет лучше
git pull -q || exit 1
NEW_COMMIT=$(test -f ${MY_LOCATION}/.git/ORIG_HEAD && cat ${MY_LOCATION}/.git/ORIG_HEAD)

if ! [[ "${OLD_COMMIT}" == "${NEW_COMMIT}" ]]; then
  if [[ -f /usr/libexec/docker/cli-plugins/docker-compose ]]; then
    docker compose up --build --detach --force-recreate
  else
    docker-compose up --build --detach --force-recreate
  fi
fi
