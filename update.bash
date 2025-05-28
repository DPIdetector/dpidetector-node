#!/usr/bin/env bash

cd -- "$(dirname -- "${BASH_SOURCE[0]}")"

source .common.bash

lock check && die "В данный момент работает другая копия данного скрипта" \
  "(либо она неожиданно завершилась и не успела снять блокировку." \
  "Если это так - удалите файл ${lockfile} вручную)"
lock do

if [[ -d "${PWD}/.git" ]]; then
  checkutil git || die "Не удалось найти утилиту 'git' (она нужна для скачивания обновлений)"

  released_verion=$(released_version)
  current_version=$(current_version)
  main_branch=dev

  git fetch --quiet --force &>/dev/null
  if [[ $(current_branch) == "${main_branch}" ]]; then
    git pull &>/dev/null || die "Не получилось обновить код"
  else
    git checkout ${main_branch} &>/dev/null || die "Не получилось перключиться на основную ветку"
    git pull &>/dev/null || die "Не получилось обновить код"
  fi

  if ver_lt "${current_version##v}" "${released_verion##v}"; then
    bash start.bash
  fi
else
  echo "Кажется, Вы установили данное ПО не по инструкции (скачав git-репозиторий), а из архива"
  echo "Работоспособность обновления при данном способе не гарантируется, но, всё же, попробуем обновить"

  lock undo
  bash install.bash
fi
finish
