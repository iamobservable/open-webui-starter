#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
CERT_DIR="$PROJECT_ROOT/conf/fluent-bit/certs"
LOKI_DIR="$PROJECT_ROOT/conf/loki/tls"
CA_KEY="$CERT_DIR/logging-ca.key"
CA_CERT="$CERT_DIR/logging-ca.crt"

mkdir -p "$CERT_DIR" "$LOKI_DIR"

generate_cert() {
  local name="$1"
  local cn="$2"
  local san="$3"
  local dir="$4"

  local key="$dir/${name}.key"
  local csr="$dir/${name}.csr"
  local crt="$dir/${name}.crt"
  local cfg="$dir/${name}.cnf"

  cat >"$cfg" <<EOF
[ req ]
default_bits       = 2048
distinguished_name = req_distinguished_name
req_extensions     = v3_req
prompt             = no

[ req_distinguished_name ]
CN = $cn

[ v3_req ]
subjectAltName = $san
extendedKeyUsage = serverAuth,clientAuth
EOF

  openssl req -new -nodes -sha256 \
    -keyout "$key" \
    -out "$csr" \
    -config "$cfg" >/dev/null 2>&1

  openssl x509 -req -sha256 \
    -in "$csr" \
    -CA "$CA_CERT" \
    -CAkey "$CA_KEY" \
    -CAcreateserial \
    -out "$crt" \
    -days 825 \
    -extensions v3_req \
    -extfile "$cfg" >/dev/null 2>&1

  rm -f "$csr" "$cfg"
  chmod 600 "$key" "$crt"
}

if [[ ! -f "$CA_CERT" || ! -f "$CA_KEY" ]]; then
  openssl req -x509 -new -nodes -sha256 \
    -subj "/CN=ERNI-KI Logging CA" \
    -keyout "$CA_KEY" \
    -out "$CA_CERT" \
    -days 3650 >/dev/null 2>&1
  chmod 600 "$CA_KEY" "$CA_CERT"
  echo "Generated CA certificate at $CA_CERT"
fi

if [[ ! -f "$CERT_DIR/fluent-bit.crt" ]]; then
  generate_cert "fluent-bit" "fluent-bit.logging.svc" "DNS:fluent-bit,DNS:localhost,IP:127.0.0.1" "$CERT_DIR"
  echo "Generated Fluent Bit server certificate."
fi

if [[ ! -f "$CERT_DIR/logging-client.crt" ]]; then
  generate_cert "logging-client" "logging-client" "DNS:logging-client" "$CERT_DIR"
  echo "Generated mutual TLS client certificate."
fi

if [[ ! -f "$LOKI_DIR/loki.crt" ]]; then
  cp "$CA_CERT" "$LOKI_DIR/logging-ca.crt"
  generate_cert "loki" "loki.logging.svc" "DNS:loki,DNS:erni-ki-loki,IP:127.0.0.1" "$LOKI_DIR"
  echo "Generated Loki TLS certificate."
fi

echo "TLS material ready under $CERT_DIR and $LOKI_DIR"
