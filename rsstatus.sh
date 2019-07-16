#!/bin/bash


helpJSHON() {
  exec 1>&2
  cat << HELP
  jshon or jq is required
    apt-get install jshon
  or
    apt-get install jq
HELP
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

shortHost() {
  sed 's/\..*:/:/g'
}

timeToHex() {
  xargs printf "%x\n"
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
  last=${!#}
  except_last=${@:1:${#}-1}

  for element in $except_last;
  do
    jshonArgs="${jshonArgs} -e ${element}"
    jqArgs="${jqArgs}.\"${element}\""
  done

  [ $JSHON ] && jshon -Q -C -a ${jshonArgs} -u <<< "$last" && return
  [ $JQ ] && jq .[]${jqArgs} -r <<< "$last" && return
  return 1
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
  sed 's/ \([-0-9a-zA-Z(]\)/| \1/g'
}

adjustColumns() {
  column -t -x
}

main() {

  LOGIN="-u readonly -p readonly"
  HEAD="Member Id Up Votes Priority State optime"

  [ $# -ne 0 ] && help && exit 1

  which jshon >/dev/null 2>&1 && JSHON=true
  which jq >/dev/null 2>&1 && JQ=true

  [ $JSHON ] || [ $JQ ] || {
    helpJSHON
    exit 1
  }

  # Determine if login is required (needed for nologin / or STARTUP state)
  mongo --quiet admin $LOGIN <<< 'rs.conf()' >/dev/null 2>&1  || \
  { mongo --quiet admin <<< 'rs.conf()' >/dev/null 2>&1 && LOGIN=""; }
  [ $? -ne 0 ] && helpInstall && exit 1

  CONF=$(mongo --quiet admin $LOGIN <<< 'JSON.stringify(rs.conf().members.sort((a,b) => a._id - b._id ))')
  STATUS=$(mongo --quiet admin $LOGIN <<< 'JSON.stringify(rs.status().members.sort((a,b) => a._id - b._id ))')
  #VERSION=$(mongo --quiet admin $LOGIN <<< 'JSON.stringify(db.version())')

  _ID=$(getDataFromJSON _id "$CONF")
  _HOST=$(getDataFromJSON host "$CONF"| shortHost)
  _HOST_LONG=$(getDataFromJSON host "$CONF")

  echo "$_HOST" | sort | uniq -c -d | grep . -q  && \
    _HOST="$_HOST_LONG"

  _VOTES=$(getDataFromJSON votes "$CONF"| fixNull)
  _PRIORITY=$(getDataFromJSON priority "$CONF" | fixNull)
  _HIDDEN=$(getDataFromJSON hidden "$CONF"| fixHidden)

  case "$STATUS" in
    # 3.4 / 3.6
    *optime\"*ts*timestamp*)
      _OPTIME_T=$(getDataFromJSON optime ts '$timestamp' t "$STATUS" | timeToHex)
      _OPTIME_I=$(getDataFromJSON optime ts '$timestamp' i "$STATUS" | timeToHex)
      ;;
    # 3.2
    *optime\"*ts*)
      _OPTIME_T=$(getDataFromJSON optime ts t "$STATUS" | timeToHex)
      _OPTIME_I=$(getDataFromJSON optime ts i "$STATUS" | timeToHex)
      ;;
    # 3.4.7
    *timestamp*)
      _OPTIME_T=$(getDataFromJSON optime '$timestamp' t "$STATUS" | timeToHex)
      _OPTIME_I=$(getDataFromJSON optime '$timestamp' i "$STATUS" | timeToHex)
      ;;
    # 2.x
    *)
      _OPTIME_T=$(getDataFromJSON optime t "$STATUS" | timeToHex)
      _OPTIME_I=$(getDataFromJSON optime i "$STATUS" | timeToHex)
      ;;
  esac

  _OPTIME=$(paste -d':' <(echo "$_OPTIME_T") \
                        <(echo "$_OPTIME_I") \
  )

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
