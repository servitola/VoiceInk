#!/bin/bash
# Create a self-signed code-signing certificate in the user's login keychain.
# Used by `make local-stable` so VoiceInk gets a stable Designated Requirement
# across rebuilds — TCC permissions (mic, accessibility, screen recording,
# input monitoring, apple events) survive `make local-stable` reinstalls.
#
# Idempotent: if the cert already exists, exits 0 without changes.

set -euo pipefail

CERT_NAME="VoiceInk Local Signing"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if security find-certificate -c "$CERT_NAME" "$KEYCHAIN" >/dev/null 2>&1; then
    echo "Code-signing certificate '$CERT_NAME' already exists in login keychain."
    exit 0
fi

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

CONF="$TMPDIR/cert.cnf"
KEY="$TMPDIR/cert.key"
CRT="$TMPDIR/cert.crt"
P12="$TMPDIR/cert.p12"

cat > "$CONF" <<EOF
[ req ]
default_bits       = 2048
distinguished_name = req_dn
prompt             = no
x509_extensions    = v3_ext

[ req_dn ]
CN = $CERT_NAME

[ v3_ext ]
basicConstraints       = critical, CA:false
keyUsage               = critical, digitalSignature
extendedKeyUsage       = critical, codeSigning
subjectKeyIdentifier   = hash
EOF

echo "Generating self-signed code-signing certificate..."
openssl req -x509 -newkey rsa:2048 -keyout "$KEY" -out "$CRT" -days 3650 -nodes \
    -config "$CONF" -extensions v3_ext >/dev/null 2>&1

P12_PASS="voiceink-local"
# macOS `security import` does not understand modern PKCS12 PBE (SHA256 HMAC).
# OpenSSL 3.x defaults to that, so it needs `-legacy` (RC2/3DES + SHA1) which
# Security.framework supports. LibreSSL (the system `/usr/bin/openssl`) already
# writes the legacy PBE and does NOT recognize the `-legacy` flag — passing it
# there makes the export fail. Detect support and only add the flag when present.
LEGACY_FLAG=""
if openssl pkcs12 -help 2>&1 | grep -q -- "-legacy"; then
    LEGACY_FLAG="-legacy"
fi
openssl pkcs12 -export $LEGACY_FLAG -out "$P12" -inkey "$KEY" -in "$CRT" -password "pass:$P12_PASS" >/dev/null 2>&1

echo "Importing certificate into login keychain..."
security import "$P12" -k "$KEYCHAIN" -P "$P12_PASS" -T /usr/bin/codesign -T /usr/bin/productsign >/dev/null
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "" "$KEYCHAIN" >/dev/null 2>&1 || true

echo "Done. Certificate '$CERT_NAME' is ready for codesign."
echo "Tip: this cert is self-signed and only used locally — macOS will not trust"
echo "the resulting binary on other machines, but it is enough to keep TCC stable."
