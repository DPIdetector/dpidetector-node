#!/usr/bin/env sh

MY_LOCATION=$(dirname $0)
OLD_COMMIT=$(cat ${MY_LOCATION}/.git/ORIG_HEAD 2>&1)
# TODO: проверить, может, FETCH_HEAD будет лучше
git pull -q || exit 1
NEW_COMMIT=$(cat ${MY_LOCATION}/.git/ORIG_HEAD 2>&1)

if ! test "${OLD_COMMIT}" == "${NEW_COMMIT}"; then
  docker compose up --build --detach --force-recreate
fi
