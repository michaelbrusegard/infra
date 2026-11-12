#!/usr/bin/env bash
set -euo pipefail
# Never enable xtrace: the Resend credential is read only into memory and LMDB.
umask 077

: "${POSTFIX_HOSTNAME:=edge.asgard.michaelbrusegard.com}"
# Space-separated domain=host routes; each domain is served by one backend.
: "${BACKENDS:=manafishrov.com=backend.manafishrov.com}"
# Fixtures that reach a backend by IP verify one shared certificate name.
: "${BACKEND_TLS_SERVERNAME:=}"
: "${BACKEND_LMTP_PORT:=24}"
: "${BACKEND_SMTP_PORT:=25}"
: "${BACKEND_LOCAL_SMTP_PORT:=26}"
: "${BACKEND_CA_FILE:=/etc/ssl/certs/ca-bundle.crt}"
: "${INBOUND_TLS_CERT_FILE:=/run/secrets/smtp-edge/tls.crt}"
: "${INBOUND_TLS_KEY_FILE:=/run/secrets/smtp-edge/tls.key}"
: "${RESEND_PASSWORD_FILE:=/run/secrets/smtp-edge/resend-api-key}"

fail() { printf 'smtp-edge: %s\n' "$1" >&2; exit 1; }
[[ $EUID == 0 ]] || fail 'Postfix master must run as root'
dns_name='^[A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?$'
[[ $POSTFIX_HOSTNAME =~ $dns_name ]] || fail 'invalid POSTFIX_HOSTNAME'
[[ -z $BACKEND_TLS_SERVERNAME || $BACKEND_TLS_SERVERNAME =~ $dns_name ]] || fail 'invalid BACKEND_TLS_SERVERNAME'
declare -A backend_for=()
read -ra routes <<< "$BACKENDS"
for route in "${routes[@]}"; do
  domain=${route%%=*}
  host=${route#*=}
  domain=${domain,,}
  [[ $route == *=* && $domain =~ $dns_name && $host =~ $dns_name ]] || fail "invalid BACKENDS route: $route"
  [[ -z ${backend_for[$domain]:-} ]] || fail "duplicate BACKENDS domain: $domain"
  backend_for[$domain]=$host
done
(( ${#backend_for[@]} > 0 )) || fail 'BACKENDS has no routes'
for name in BACKEND_LMTP_PORT BACKEND_SMTP_PORT BACKEND_LOCAL_SMTP_PORT; do
  [[ ${!name} =~ ^[0-9]{1,5}$ ]] || fail "invalid $name"
  (( 10#${!name} >= 1 && 10#${!name} <= 65535 )) || fail "invalid $name"
done
for name in BACKEND_CA_FILE INBOUND_TLS_CERT_FILE INBOUND_TLS_KEY_FILE RESEND_PASSWORD_FILE; do
  [[ ${!name} =~ ^/[A-Za-z0-9_./-]+$ && -r ${!name} ]] || fail "invalid or unreadable $name"
done

install -d -m 0755 -o root -g root /run/postfix /var/lib/postfix /var/lib/postfix/queue /var/lib/postfix/queue/pid
install -d -m 0700 -o postfix -g postfix /var/lib/postfix/data
# A non-root restore preserves queue files but cannot restore mixed ownership.
# Normalize only directory ownership; queue-file mode bits carry native flags.
install -d -m 0730 -o postfix -g postdrop /var/lib/postfix/queue/maildrop
install -d -m 0710 -o postfix -g postdrop /var/lib/postfix/queue/public
cp /opt/smtp-edge/main.cf /run/postfix/main.cf
master=$(</opt/smtp-edge/master.cf)
master=${master//@BACKEND_SMTP_PORT@/$BACKEND_SMTP_PORT}
master=${master//@BACKEND_LOCAL_SMTP_PORT@/$BACKEND_LOCAL_SMTP_PORT}
master=${master//@BACKEND_CA_FILE@/$BACKEND_CA_FILE}
printf '%s\n' "$master" > /run/postfix/master.cf
unset master
chmod 0644 /run/postfix/{main,master}.cf

# Absent identity leaves the backup handoff disabled. Only a pinned client can
# submit original peer metadata on this listener, even from a changing WAN IP.
if [[ -n ${BACKUP_CLIENT_FINGERPRINT_FILE:-} && -f $BACKUP_CLIENT_FINGERPRINT_FILE ]]; then
  fingerprint=$(<"$BACKUP_CLIENT_FINGERPRINT_FILE")
  [[ $fingerprint =~ ^([[:xdigit:]]{2}:){31}[[:xdigit:]]{2}$ ]] || fail 'invalid backup client SHA-256 fingerprint'
  printf '%s OK\n' "$fingerprint" > /run/postfix/backup-client
  chmod 0644 /run/postfix/backup-client
  cat /opt/smtp-edge/backup-master.cf >> /run/postfix/master.cf
fi

# Regexp maps are case-insensitive by default. DUNNO does not bypass verification.
# Delivery and recipient verification both follow the recipient's domain.
# An explicit policy match authenticates the configured name, not discovered DNS.
served='' transport='' verify='' tls=''
for domain in "${!backend_for[@]}"; do
  host=${backend_for[$domain]}
  name=${BACKEND_TLS_SERVERNAME:-$host}
  served+="/@${domain//./[.]}\$/ DUNNO"$'\n'
  transport+="$domain forward:$host"$'\n'
  verify+="$domain lmtp:inet:[$host]:$BACKEND_LMTP_PORT"$'\n'
  tls+="[$host]:$BACKEND_LMTP_PORT secure match=$name servername=$name"$'\n'
done
printf '%s%s\n' "$served" '/.*/ REJECT recipient domain not served' > /run/postfix/served-domains
chmod 0644 /run/postfix/served-domains
printf '%s' "$transport" | postmap -ir lmdb:/run/postfix/transport
printf '%s' "$verify" | postmap -ir lmdb:/run/postfix/verify-transport
# Domains sharing a backend repeat its policy key; -r keeps one entry.
printf '%s' "$tls" | postmap -ir lmdb:/run/postfix/lmtp-tls
chmod 0644 /run/postfix/{transport,verify-transport,lmtp-tls}.lmdb

password=$(<"$RESEND_PASSWORD_FILE")
[[ -n $password && $password != *[$'\r\n\t ']* ]] || fail 'invalid Resend credential file'
printf '[smtp.resend.com]:465 resend:%s\n' "$password" |
  postmap -ir lmdb:/run/postfix/sasl-passwd
unset password
chmod 0600 /run/postfix/sasl-passwd.lmdb

postconf -e \
  "myhostname = $POSTFIX_HOSTNAME" \
  "relay_domains = ${!backend_for[*]}" \
  "lmtp_tls_CAfile = $BACKEND_CA_FILE" \
  "smtp_tls_CAfile = /etc/ssl/certs/ca-bundle.crt" \
  "smtpd_tls_cert_file = $INBOUND_TLS_CERT_FILE" \
  "smtpd_tls_key_file = $INBOUND_TLS_KEY_FILE"

# Native check creates missing queue subdirectories with the correct ownership.
# Do not run set-permissions against the immutable Nix installation.
postfix check
case ${1:-start} in
  check) exit 0 ;;
  start) exec postfix start-fg ;;
  *) fail 'expected start or check' ;;
esac
