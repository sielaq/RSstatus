#!/bin/bash


helpJSHON() {
  echo "jshon is required"
  echo "  apt-get install jshon"
}

helpInstall() {
  cat << INSTALL
  In order to make this script working:
  login to the mongo admin db with your poweruser credentials
  and please create readonly user with clusterMonitor role, like:

  db.createUser({
    "user": "readonly",
    "pwd": "readonly",
    "roles": [{
      "role": "clusterMonitor",
      "db": "admin"
    },]
  })

INSTALL
}

help() {
  echo "Just run $0"
}

fixJSON() {
  while read data; do
    echo "$data" | sed 's/("/(/g;
                        s/")/)/g;
                        s/ : \([A-Z]\)/ : "\1/g;
                        s/),/)",/g;
                        s/)$/)"/g'
  done
}

shortHost() {
  while read data; do
    echo "$data" | sed 's/\..*:/:/g'
  done
}

timeToHex() {
  while read data; do
    echo "$data" | grep -o -P '\d+' | xargs printf "%x:%x\n"
  done
}

fixNull() {
  while read data; do
    echo "$data" | sed 's/null/1/g'
  done
}

fixHidden() {
  while read data; do
    echo "$data" | sed 's/null/ /g;
                        s/false/ /g;
                        s/true/(hidden)/g'
  done
}

getDataFromJSON(){
  jshon -Q -C -e members -a -e $1 -u <<< "$2"
}

getComplexDataFromJSON(){
  jshon -e members -a -e $1 -e $2 -u <<< "$3"
}

top(){
  len=$(echo "$1"| wc -L)
  printf "+";
  for i in $(seq 1 $len); do
     printf "-"
  done
  echo
}

bottom() { top "$1"; }

printArray() {
  echo "$1" | sed  's/ \([0-9a-Z]\)/|\1/g' | awk '{print "|"$NL}'
}


main() {

  LOGIN="-u readonly -p readonly"
  HEAD="Member Id Up Votes Priority State optime"

  [ $# -ne 0 ] && help && exit 1
  which jshon >/dev/null 2>&1 || { helpJSHON; exit 1; }

  # Determine if login is required (needed for nologin / or STARTUP sate)
  mongo --quiet admin $LOGIN <<< 'rs.conf()' >/dev/null 2>&1  || \
  { mongo --quiet admin <<< 'rs.conf()' >/dev/null 2>&1 && LOGIN=""; }
  [ $? -ne 0 ] && helpInstall && exit 1

  CONF=$(mongo --quiet admin $LOGIN <<< 'rs.conf()'| fixJSON)
  STATUS=$(mongo --quiet admin $LOGIN <<< 'rs.status()'| fixJSON)
  VERSION=$(mongo --quiet admin $LOGIN <<< 'db.version()')

  _ID=$(getDataFromJSON _id "$CONF")
  _HOST=$(getDataFromJSON host "$CONF"| shortHost)
  _VOTES=$(getDataFromJSON votes "$CONF"| fixNull)
  _PRIORITY=$(getDataFromJSON priority "$CONF" | fixNull)
  _HIDDEN=$(getDataFromJSON hidden "$CONF"| fixHidden)

  [[ "$VERSION" =~ ^3 ]] && {
    _OPTIME=$(getComplexDataFromJSON optime ts "$STATUS"| timeToHex)
  } || {
    _OPTIME=$(getDataFromJSON optime "$STATUS"| timeToHex)
  }

  _STATE=$(getDataFromJSON stateStr "$STATUS")
  _UP=$(getDataFromJSON health "$STATUS")

  _STATE=$(paste -d'\0' <(echo "$_STATE") <(echo "$_HIDDEN"))

  ARRAY=$(paste <(echo "$_HOST") <(echo "$_ID") <(echo "$_UP") <(echo "$_VOTES") <(echo "$_PRIORITY") <(echo "$_STATE") <(echo "$_OPTIME"))
  ARRAY=$(echo $HEAD; echo "$ARRAY")
  ARRAY=$(echo "$ARRAY"| column -t -x)

  top "$ARRAY"
  printArray "$ARRAY"
  bottom "$ARRAY"
}
main $@
