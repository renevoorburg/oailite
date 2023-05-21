#!/bin/bash

# dbstore.sh
# helper script to dbwalker.sh
# part of https://github.com/renevoorburg/oailite
# 2023-05-21

set +H

if [ -z $DEST_DB ]     ; then echo 'Error, $DEST_DB not defined or empty.'    ; exit 1 ; fi
if [ -z $DEST_TABLE ]  ; then echo 'Error, $DEST_TABLE not defined or empty.' ; exit 1 ; fi
if [ -z $RECORD_ID ]   ; then echo 'Error, $RECORD_ID not defined or empty.'  ; exit 1 ; fi

PIPED=`cat <&0`

if  [  ! -z "$PIPED" ] ; then
    sqlite3 -batch $DEST_DB "pragma busy_timeout=20000; replace into $DEST_TABLE (id, timestamp, sourcedata) values ('$RECORD_ID', datetime(), '$(echo "$PIPED" | perl -pe "s@'@''@g")');" > /dev/null
fi
