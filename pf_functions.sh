#!/bin/sh

telegram_notify()
{
  token=$1
  chat_id=$2
  msg_text=$3
  curl -X POST  \
        -H 'Content-Type: application/json' -d "{\"chat_id\": \"$chat_id\", \"text\":\"$msg_text\", \"disable_notification\":false}"  \
        -s \
        https://api.telegram.org/bot$token/sendMessage > /dev/null
}

install_pkg()
{
  pkg_name=$1
  telegram_api=$2
  telegram_chat_id=$3

  yes | pkg install $pkg_name
  telegram_notify $telegram_api $telegram_chat_id "PFSense init: installed pkg -> $pkg_name"
}