#!/usr/bin/env bash
set -euo pipefail
# Never enable xtrace: the Resend credential is read only into memory and LMDB.
umask 077

: "${POSTFIX_HOSTNAME:=edge.asgard.michaelbrusegard.com}"
: "${BACKEND_HOST:=backend.manafishrov.com}"
: "${BACKEND_TLS_SERVERNAME:=$BACKEND_HOST}"
: "${BACKEND_LMTP_PORT:=24}"
: "${BACKEND_SMTP_PORT:=25}"
: "${BACKEND_LOCAL_SMTP_PORT:=26}"
: "${BACKEND_CA_FILE:=/etc/ssl/certs/ca-bundle.crt}"
: "${INBOUND_TLS_CERT_FILE:=/run/secrets/smtp-edge/tls.crt}"
: "${INBOUND_TLS_KEY_FILE:=/run/secrets/smtp-edge/tls.key}"
: "${RESEND_PASSWORD_FILE:=/run/secrets/smtp-edge/resend-api-key}"

fail() { printf 'smtp-edge: %s\n' "$1" >&2; exit 1; }
[[ $EUID == 0 ]] || fail 'Postfix master must run as root'
for name in POSTFIX_HOSTNAME BACKEND_HOST BACKEND_TLS_SERVERNAME; do
  [[ ${!name} =~ ^[A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?$ ]] || fail "invalid $name"
done
for name in BACKEND_LMTP_PORT BACKEND_SMTP_PORT BACKEND_LOCAL_SMTP_PORT; do
  [[ ${!name} =~ ^[0-9]{1,5}$ ]] || fail "invalid $name"
  (( 10#${!name} >= 1 && 10#${!name} <= 65535 )) || fail "invalid $name"
done
for name in BACKEND_CA_FILE INBOUND_TLS_CERT_FILE INBOUND_TLS_KEY_FILE RESEND_PASSWORD_FILE; do
  [[ ${!name} =~ ^/[A-Za-z0-9_./-]+$ && -r ${!name} ]] || fail "invalid or unreadable $name"
done

install -d -m 0755 -o root -g root /run/postfix /var/lib/postfix /var/lib/postfix/queue
install -d -m 0700 -o postfix -g postfix /var/lib/postfix/data
# A non-root restore preserves queue files but cannot restore mixed ownership.
# Normalize only directory ownership; queue-file mode bits carry native flags.
install -d -m 0730 -o postfix -g postdrop /var/lib/postfix/queue/maildrop
install -d -m 0710 -o postfix -g postdrop /var/lib/postfix/queue/public
cp /opt/smtp-edge/main.cf /run/postfix/main.cf
master=$(</opt/smtp-edge/master.cf)
master=${master//@BACKEND_HOST@/$BACKEND_HOST}
master=${master//@BACKEND_SMTP_PORT@/$BACKEND_SMTP_PORT}
master=${master//@BACKEND_LOCAL_SMTP_PORT@/$BACKEND_LOCAL_SMTP_PORT}
master=${master//@BACKEND_CA_FILE@/$BACKEND_CA_FILE}
printf '%s\n' "$master" > /run/postfix/master.cf
unset master
chmod 0644 /run/postfix/{main,master}.cf

# Regexp maps are case-insensitive by default. DUNNO does not bypass verification.
printf '%s\n' '/@manafishrov[.]com$/ DUNNO' '/.*/ REJECT recipient domain not served' > /run/postfix/served-domains
chmod 0644 /run/postfix/served-domains

# An explicit policy match authenticates the configured name, not discovered DNS.
printf '[%s]:%s secure match=%s servername=%s\n' "$BACKEND_HOST" "$BACKEND_LMTP_PORT" "$BACKEND_TLS_SERVERNAME" "$BACKEND_TLS_SERVERNAME" |
  postmap -ir lmdb:/run/postfix/lmtp-tls
chmod 0644 /run/postfix/lmtp-tls.lmdb

password=$(<"$RESEND_PASSWORD_FILE")
[[ -n $password && $password != *[$'\r\n\t ']* ]] || fail 'invalid Resend credential file'
printf '[smtp.resend.com]:465 resend:%s\n' "$password" |
  postmap -ir lmdb:/run/postfix/sasl-passwd
unset password
chmod 0600 /run/postfix/sasl-passwd.lmdb

postconf -e \
  "myhostname = $POSTFIX_HOSTNAME" \
  "address_verify_transport_maps = static:lmtp:inet:[$BACKEND_HOST]:$BACKEND_LMTP_PORT" \
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
