#!/bin/bash
#can ONLY be run as root!  sudo to root

USB_DRIVE=$1
out_file=$2

sudo umount $USB_DRIVE

block="M"
if [[ $OSTYPE == 'darwin'* ]]; then
  block="m"
fi

sz=$(($((`ls -al $out_file | awk '{ print $5 }'`)) / 1024 / 1024 ))

# use to adjust number of threads used when writing disk
## this is in megabytes as are all other calculations done in this file
write_per_thread=512
######

thread_ct=$(($((`ls -al $out_file | awk '{ print $5 }'`)) / 1024 / 1024 / $write_per_thread ))
remainder=$(($((`ls -al $out_file | awk '{ print $5 }'`)) / 1024 / 1024 % $write_per_thread ))
echo "Start time is "
begin=0
while [ $begin -le $thread_ct ]; do
  skip=$(($begin * $write_per_thread))
  seek=$(($begin * $write_per_thread))
  if [ $(($begin + 1)) -le $thread_ct ]; then
    echo "starting transfer $begin.  Transferring from block $skip to block $(($(($begin + 1)) * $write_per_thread))"
    echo "nohup dd if=$USB_DRIVE of=$out_file bs=1$block skip=$skip seek=$seek count=$write_per_thread"
    nohup dd if=$USB_DRIVE of=$out_file bs=1$block skip=$skip seek=$seek count=$write_per_thread &
  else
    write_remainder=$(($sz - $(($thread_ct * $write_per_thread))))
    echo "starting transfer $begin.  Transferring from block $skip to block $sz"
    echo "nohup dd if=$USB_DRIVE of=$out_file bs=1$block skip=$skip seek=$seek count=$write_remainder"
    nohup dd if=$USB_DRIVE of=$out_file bs=1$block skip=$skip seek=$seek count=$write_remainder &
  fi

  ((begin++))
done

wait
exit 0