#!/bin/bash
# Create a stable self-signed code-signing certificate in the login keychain.
#
# Why: the app captures audio via Core Audio process taps, which triggers a
# macOS TCC permission prompt the first time. TCC remembers that grant per
# *code-signing identity*. Ad-hoc signing (`codesign --sign -`) has no stable
# identity — every rebuild changes the cdhash, so macOS forgets the grant and
# re-prompts. Signing with this fixed certificate keeps the identity stable
# across rebuilds, so the user is asked only once.
#
# Idempotent: re-running is a no-op once the identity exists.
# To remove later: `security delete-identity -c "$CERT_NAME" ~/Library/Keychains/login.keychain-db`
set -e

CERT_NAME="SoundsSource Self-Signed"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

# NOTE: no -v here. A self-signed cert is "not trusted", so `find-identity -v`
# (valid-only) hides it — but codesign can still sign with it just fine.
if security find-identity -p codesigning "$KEYCHAIN" | grep -q "$CERT_NAME"; then
    echo "✅ Signing identity '$CERT_NAME' already exists — nothing to do."
    exit 0
fi

echo "=== Creating self-signed code-signing certificate: $CERT_NAME ==="
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/cert.cnf" <<EOF
[ req ]
distinguished_name = dn
x509_extensions    = codesign
prompt             = no

[ dn ]
CN = $CERT_NAME

[ codesign ]
basicConstraints   = critical, CA:FALSE
keyUsage           = critical, digitalSignature
extendedKeyUsage   = critical, codeSigning
EOF

openssl req -x509 -newkey rsa:2048 -sha256 -days 3650 -nodes \
    -keyout "$TMP/key.pem" -out "$TMP/cert.pem" -config "$TMP/cert.cnf"

# Apple's `security` uses an old PKCS12 parser. Export with -legacy + SHA1 MAC +
# 3DES PBE so it can read the file (OpenSSL 3's modern defaults fail to import).
# Use a real passphrase — empty-password p12s often fail MAC verification on import.
P12_PW="soundssource"
openssl pkcs12 -export -legacy -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
    -name "$CERT_NAME" -out "$TMP/identity.p12" -passout "pass:$P12_PW" \
    -keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES -macalg sha1

# -A: allow all tools to use the key without an ACL prompt at sign time (local dev cert).
security import "$TMP/identity.p12" -k "$KEYCHAIN" -P "$P12_PW" -A

echo "=== Done ==="
security find-identity -p codesigning "$KEYCHAIN" | grep "$CERT_NAME" || true
echo "Now run ./scripts/build_app.sh — it will sign with this identity automatically."
