#!/usr/bin/env bash
# Postfix supplies protected queue attributes, not message headers. All SMTP,
# TLS and DATA framing is handled by curl; Stalwart performs authentication.
set -u
export LC_ALL=C

fail() { printf '4.3.0 %s\n' "$1"; exit 75; }
[[ $# == 8 ]] || fail 'invalid delivery configuration'
backend=$1
smtp_port=$2
local_port=$3
ca_file=$4
# pipe(8) exposes Postfix's protected log address, whose IPv6 form carries
# the SMTP "IPv6:" prefix. curl expects only the numeric address.
client_ip=${5#IPv6:}
[[ -z $5 || -n $client_ip ]] || fail 'invalid queued client address'
helo=$6
sender=$7
recipient=$8
[[ -n $backend && -n $recipient ]] || fail 'missing delivery destination'
for value in "$backend" "$client_ip" "$helo" "$sender" "$recipient"; do
  case $value in *$'\r'*|*$'\n'*) fail 'invalid delivery metadata';; esac
done

# Encode the EHLO as a URL path. Quoting alone does not protect URL delimiters.
urlencode() {
  local value=$1 char index
  for ((index=0; index<${#value}; index++)); do
    char=${value:index:1}
    case $char in
      [a-zA-Z0-9._~-]) printf '%s' "$char";;
      *) printf '%%%02X' "'$char";;
    esac
  done
}

args=(--disable --silent --output /dev/null --write-out '%{response_code}'
      --proxy '' --noproxy '*' --globoff --ssl-reqd --cacert "$ca_file"
      --connect-timeout 30 --max-time 600 --upload-file - --mail-rcpt "$recipient")
if [[ -n $client_ip ]]; then
  case $client_ip in *[!0-9a-fA-F:.]*) fail 'invalid queued client address';; esac
  [[ -n $helo ]] || fail 'missing queued client greeting'
  args+=(--haproxy-clientip "$client_ip")
  port=$smtp_port
else
  # Only locally generated queue records lack client attributes. An Internet
  # null-envelope message still has an IP and MUST take the authenticated path.
  port=$local_port
  helo=smtp-edge
fi
# curl rejects an empty --mail-from argument. Omitting it sends MAIL FROM:<>.
[[ -z $sender ]] || args+=(--mail-from "$sender")
args+=(--url "smtp://${backend}:${port}/$(urlencode "$helo")")

if code=$(curl "${args[@]}"); then
  # curl succeeds only after DATA acceptance. Do not retry an accepted message
  # because a subsequent QUIT/connection cleanup fails.
  exit 0
else
  case $code in
    5[0-9][0-9]) printf '5.0.0 backend rejected delivery (%s)\n' "$code"; exit 69;;
    *) fail 'backend delivery temporarily unavailable';;
  esac
fi
