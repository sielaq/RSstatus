#!/bin/bash


helpJSHON() {
  exec 1>&2
  echo "jshon is required"
  echo "  apt-get install jshon"
}

helpInstall() {
  exec 1>&2
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
  sed 's/("/(/g;
       s/")/)/g;
       s/ : \([A-Z]\)/ : "\1/g;
       s/),/)",/g;
       s/)$/)"/g'
}

shortHost() {
  sed 's/\..*:/:/g'
}

timeToHex() {
  grep -o -P '\d+' |xargs printf "%x:%x\n"
}

fixNull() {
  sed 's/null/1/g'
}

fixHidden() {
  sed 's/null//g;
       s/false//g;
       s/true/(hidden)/g'
}

getDataFromJSON() {
  jshon -Q -C -e members -a -e $1 -u <<< "$2"
}

getComplexDataFromJSON() {
  jshon -e members -a -e $1 -e $2 -u <<< "$3"
}

topLine() {
  printf -- "+-"
  for i in $(seq 1 $1); do
     printf -- "-"
  done
  printf -- "-+"
  echo
}

fixLine() {
  while read data; do
    printf "| "
    printf "$data"
    maxLine=$(echo "$data" | wc -L)
    countMissing=$(( $1 - $maxLine ))
    for i in $(seq 1 $countMissing); do
      printf " "
    done
    printf " |"
    echo
  done
}

sanitizeLine() {
   sed 's/ /_/g'
}

bottomLine() {
  topLine "$1"
}

separateColumns() {
  sed 's/ \([-0-9a-Z(]\)/| \1/g'
}

adjustColumns() {
  column -t -x
}

main() {

  LOGIN="-u readonly -p readonly"
  HEAD="Member Id Up Votes Priority State optime"

  [ $# -ne 0 ] && help && exit 1
  which jshon >/dev/null 2>&1 || { helpJSHON; exit 1; }

  # Determine if login is required (needed for nologin / or STARTUP state)
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

  [[ "$VERSION" =~ ^3\.2|^3\.4\.[1-4]$ ]]  && {
    _OPTIME=$(getComplexDataFromJSON optime ts "$STATUS"| timeToHex)
  } || {
    _OPTIME=$(getDataFromJSON optime "$STATUS"| timeToHex)
  }

  _STATE=$(getDataFromJSON stateStr "$STATUS"| sanitizeLine)
  _UP=$(getDataFromJSON health "$STATUS")

  _STATE=$(paste -d'\0' <(echo "$_STATE") \
                        <(echo "$_HIDDEN") \
  )

  ARRAY=$(paste <(echo "$_HOST") \
                <(echo "$_ID") \
                <(echo "$_UP") \
                <(echo "$_VOTES") \
                <(echo "$_PRIORITY") \
                <(echo "$_STATE") \
                <(echo "$_OPTIME") \
  )

  ARRAY=$(echo -e "${HEAD}\n${ARRAY}" | adjustColumns | separateColumns )
  lenLongestLine=$(echo "$ARRAY" | wc -L)

  topLine $lenLongestLine
  echo "$ARRAY" | fixLine $lenLongestLine
  bottomLine $lenLongestLine

}
main $@
