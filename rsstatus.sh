#!/bin/bash

[ "${BASH_SOURCE[0]}" != "${0}" ] && alias exit=return

PORT=27017

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

GRN=$(echo -e "\033[32m")
END=$(echo -e "\033[0m")

supportColors() {
  numberOfChars=$(echo -e "${GRN}X${END}\t0\nX\t0" | column -t -x | wc -c)
  [ $numberOfChars -eq 19 ] && return 0
  return 1
}

colorize() {
  supportColors && _GRN=$GRN && _END=$END
  sed 's/'$1'/'${_GRN}${1}${_END}'/g'
}

useMongoSSL() {
  mongo -h | grep -q ssl
}

checkSSL () {
  echo | openssl s_client -connect :$PORT >/dev/null 2>&1
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

fixColors() {
  sed -r 's/\x1B\[(;?[0-9]{1,3})+[mGK]//g'
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
    maxLine=$(echo "$data" | fixColors | wc -L)
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
  sed 's/ \([-0-9a-zA-Z('$END']\)/| \1/g'
}

adjustColumns() {
  column -t -x
}

purifyJSON() {
  eval dirtyJSON=$(echo \$"$1")
  export $1="$(echo "$dirtyJSON" | grep -v ^$DATE)"
  local _warnings=$(echo "$dirtyJSON" | grep ^$DATE)
  [ -n "$_warnings" ] && WARNINGS="${WARNINGS}${_warnings}"$'\n'
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

  HOST_LONG=$(hostname -f)
  HOST=$(echo $HOST_LONG | sed 's/\..*//g')

  # Determine SSL or TLS or none
  ENCRYPTION=""
  checkSSL && {
    encType="tls"
    useMongoSSL && encType="ssl"
    ENCRYPTION="--host $(hostname -f) --authenticationDatabase admin --${encType} --${encType}AllowInvalidCertificates"
  }

  # Determine if login is required (needed for nologin / or STARTUP state)
  mongo --port $PORT --quiet admin $LOGIN $ENCRYPTION <<< 'rs.conf()' >/dev/null 2>&1  || \
  { mongo --port $PORT --quiet admin $ENCRYPTION <<< 'rs.conf()' >/dev/null 2>&1 && LOGIN=""; }
  [ $? -ne 0 ] && helpInstall && exit 1

  VERSION=$(mongo --quiet admin $LOGIN $ENCRYPTION <<< 'JSON.stringify(db.version())')
  [[ "${VERSION#\"}" =~ ^2\. ]] && esc="'"
  [[ "${VERSION#\"}" =~ ^3\.0 ]] && esc="'"

  sorted="${esc}(a,b) => a._id - b._id${esc}"
  CONF=$(mongo --port $PORT --quiet admin $LOGIN $ENCRYPTION <<< "JSON.stringify(rs.conf().members.sort($sorted))")
  STATUS=$(mongo --port $PORT --quiet admin $LOGIN $ENCRYPTION <<< "JSON.stringify(rs.status().members.sort($sorted))")

  DATE=$(date '+%Y-%m-%d')
  purifyJSON CONF
  purifyJSON STATUS
  echo -n "$WARNINGS"

  _ID=$(getDataFromJSON _id "$CONF")
  _HOST=$(getDataFromJSON host "$CONF"| shortHost)
  _HOST_LONG=$(getDataFromJSON host "$CONF")

  echo "$_HOST" | sort | uniq -c -d | grep . -q  && \
    _HOST="$_HOST_LONG" && HOST="$HOST_LONG"

  _HOST=$(echo "$_HOST" | colorize $HOST)
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

  _STATE=$(getDataFromJSON stateStr "$STATUS"| sanitizeLine | colorize PRIMARY)
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
  lenLongestLine=$(echo "$ARRAY" | fixColors | wc -L)

  topLine $lenLongestLine
  echo "$ARRAY" | fixLine $lenLongestLine
  bottomLine $lenLongestLine

}
main $@
