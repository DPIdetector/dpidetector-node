#!/usr/bin/env bash

MY_LOCATION=$(dirname $0)

OLD_COMMIT=$(git rev-parse @)
git pull -q || exit 1
NEW_COMMIT=$(gitt rev-parse @)

if ! [[ "${OLD_COMMIT}" == "${NEW_COMMIT}" ]]; then
  if [[ -f /usr/libexec/docker/cli-plugins/docker-compose ]]; then
    docker compose up --build --detach --force-recreate
  else
    docker-compose up --build --detach --force-recreate
  fi
fi
