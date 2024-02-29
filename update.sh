#!/usr/bin/env sh

MY_LOCATION=$(dirname $0)
OLD_COMMIT=$(cat ${MY_LOCATION}/.git/ORIG_HEAD)
# TODO: проверить, может, FETCH_HEAD будет лучше
git pull -q || exit 1
NEW_COMMIT=$(cat ${MY_LOCATION}/.git/ORIG_HEAD)

if ! [[ "${OLD_COMMIT}" == "${NEW_COMMIT}" ]]; then
  docker compose up --build --detach --force-recreate
fi
