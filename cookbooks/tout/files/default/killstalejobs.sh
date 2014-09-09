#!/bin/bash

KILLEM="false"
DEBUG="false"
AUTH="0f781b3c91579fff8fbead396e1fc6"
CURL="/usr/bin/curl"
PS="/bin/ps"
URLBASE="https://api.hipchat.com/v1/rooms/message"
HIPCHAT_ROOM="Engineering"

# Parse the passed args
while getopts dkh flag; do
    case $flag in
      k)
        KILLEM="true"
        ;;
      d)
        DEBUG="true"
        ;;
      h)
         echo "Run from engineyard thus:"; echo
         echo "    ey ssh /data/Tout/$0 --utilities -t -e ToutProduction"; echo
         echo "Run the script with -k to kill off the stale workers"
         echo "Run the script with -d to kill off non-stale workers (test mode)"
         exit
         ;;
      \?)
         echo "Invalid option: $OPTARG" >&2
         exit
         ;;
     esac
done
shift $(( OPTIND - 1 ))
echo Passed parameters are $*

if [ "$DEBUG" == "true" ]; then
    echo -e "\033[1mRequesting shutdown of workers...\033[0m"
    sudo monit stop -g Tout_resque;

    echo -e "\033[1mWaiting for a bit...\033[0m"
    sleep 3
fi

# Roughly speaking, debug is associated with STAGING
if [ "$DEBUG" == "true" ]; then
    environment_name='STAGING'
else
    environment_name='PRODUCTION'
fi

echo -e "\033[1mPreview of stuck workers...\033[0m"
if [ "$DEBUG" != "true" ]; then
    PIDS=$($PS aux |grep -P "\S+\s+\S+\s+\d+\.\d+\s+\d+\.\d+\s+\d+\s+\d+\s+\S+\s+\S+\s+[A-Z][a-z]*\d\d\s+" \
    | grep 'Processing ' | awk '{print $2}')
else
    echo "Inverting the date check"
    PIDS=$($PS aux |grep -P "\S+\s+\S+\s+\d+\.\d+\s+\d+\.\d+\s+\d+\s+\d+\s+\S+\s+\S+\s+\S+:\S+\s+" \
    | grep 'Processing ' |grep -v grep | awk '{print $2}')
fi
echo Targeting processes: [ $PIDS ]

if [ "$KILLEM" == "true" ]; then
  if [ "$PIDS" == "" ]; then
    echo -e "\033[1mNo stuck workers to kill :-)\033[0m"   
    $CURL "$URLBASE?room_id=$HIPCHAT_ROOM&notify=1&color=red&from=DeployMan&auth_token=$AUTH&message=No%20stuck%20workers%20to%20kill%20on%20$environment_name%20environment%20:-)" > /tmp/hipchat
    exit 0
   else
    echo -e "\033[1mForcefully killing stuck worker jobs...\033[0m"
    $CURL "$URLBASE?room_id=$HIPCHAT_ROOM&notify=1&color=red&from=DeployMan&auth_token=$AUTH&message=%5bWARNING%5d%20Forcefully%20killing%20stuck%20worker%20jobs...on%20$environment_name%20environment" > /tmp/hipchat
    kill -9 $PIDS

    echo -e "\033[1mWaiting for a bit before killing recommences...\033[0m"
    sleep 5

    echo -e "\033[1mForcefully killing stuck workers (again, just to be sure)...\033[0m"
    $CURL "$URLBASE?room_id=$HIPCHAT_ROOM&notify=1&color=red&from=DeployMan&auth_token=$AUTH&message=%5bWARNING%5d%20Killing%20stuck%20worker%20jobs%20again...on%20$environment_name%20environment" > /tmp/hipchat
    kill -9 $PIDS
fi

if [ "$DEBUG" == "true" ]; then
    echo -e "\033[1mRestarting the queues\033[0m"
    sudo monit start -g Tout_resque
fi
