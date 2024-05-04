#!/usr/bin/env bash

source .common.bash

checkutil git || die "Не удалось найти утилиту 'git'"

function wait_for_conf() {
  if ! [[ -f "${PWD}/user.conf" ]]; then
    echo "Скачайте из панели управления конфигурационный файл для данного узла" \
    "и поместите его в рабочую директорию (${PWD})." \
    "После чего нажмите Enter"
    read
  fi
}

if [[ -f "install.bash" && -f "start.bash" && -f "update.bash" && -f "compose.yml" ]]; then
  # NOTE: Похоже, нас вызвали из директории уже скачанного проекта
  shopt -s dotglob
  if [[ -d "${PWD}/.git" ]]; then
    url="$(git config --local remote.origin.url)"
    if [[ "${url}" == "${REPO_URL}" ]]; then
      git reset --hard
    elif [[ "${url}" == "git@"* ]]; then
      git stash push
    fi
  else
    co "${PWD}/.b" || die "Не удалось скачать репозиторий"
    mv "${PWD}/.b/.git" "${PWD}"
    rm -r "${PWD}/.b"
    git reset --hard
  fi
else # NOTE: Похоже, нас вызвали для первоначальной установки
  CO_DIR="${PWD}/${REPO_URL##*/}"
  co "${CO_DIR}" || die "Не удалось скачать репозиторий"
  cd "${CO_DIR}"
fi

wait_for_conf
bash update.bash
finish
