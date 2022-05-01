#!/bin/sh

. /root/openstack-env.sh

telegram_notify()
{
  token=$TELEGRAM_API
  chat_id=$TELEGRAM_CHAT_ID
  msg_text=$1
  curl -X POST  \
        -H 'Content-Type: application/json' -d "{\"chat_id\": \"$chat_id\", \"text\":\"$msg_text\", \"disable_notification\":false}"  \
        -s \
        "https://api.telegram.org/bot$token/sendMessage" > /dev/null
}

install_pkg()
{
  pkg_name=$1

  yes | pkg install "$pkg_name"
  telegram_notify  "PFSense init: installed pkg -> $pkg_name"
}

parse_json()
{
  echo "$1" |
    sed -e 's/[{}]/''/g' |
    sed -e 's/", "/'\",\"'/g' |
    sed -e 's/" ,"/'\",\"'/g' |
    sed -e 's/" , "/'\",\"'/g' |
    sed -e 's/","/'\"---SEPERATOR---\"'/g' |
    awk -F=':' -v RS='---SEPERATOR---' "\$1~/\"$2\"/ {print}" |
    sed -e "s/\"$2\"://" |
    tr -d "\n\t" |
    sed -e 's/\\"/"/g' |
    sed -e 's/\\\\/\\/g' |
    sed -e 's/^[ \t]*//g' |
    sed -e 's/^"//' -e 's/"$//'
}