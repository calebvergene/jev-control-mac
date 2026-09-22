#!/bin/zsh
# Create a self-signed code signing certificate for local development.
#
# Why this exists: an ad-hoc signature has no identity, so its designated
# requirement is `cdhash H"..."` — the hash of that exact binary. macOS ties
# Accessibility and Input Monitoring grants to that requirement, so every
# rebuild silently invalidates them while System Settings still shows the box
# ticked.
#
# Signing with a certificate changes the requirement to
#     identifier "ai.jev.control" and certificate leaf = H"..."
# which does not change when the code does. Grant permissions once, rebuild
# freely.
#
# The certificate does NOT need to be trusted. Trust governs verification
# (Gatekeeper), not signing, and the designated requirement is the same either
# way — so there is nothing here that needs your password.
set -e

NAME="${JEV_CERT_NAME:-Jev Control Dev}"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

has_identity() {
  security find-identity -p codesigning 2>/dev/null | grep -q "\"$NAME\""
}

if has_identity; then
  echo "✔ '$NAME' already exists."
  exit 0
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
P12PASS="$(openssl rand -hex 16)"

echo "▸ Generating a self-signed code signing certificate"
openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
  -keyout "$TMP/key.pem" -out "$TMP/cert.pem" \
  -subj "/CN=$NAME" \
  -addext "basicConstraints=critical,CA:false" \
  -addext "keyUsage=critical,digitalSignature" \
  -addext "extendedKeyUsage=critical,codeSigning" 2>/dev/null

# macOS ships LibreSSL as /usr/bin/openssl, which ignores -addext. Without the
# codeSigning extension the certificate imports fine but is never usable as a
# signing identity, which is a confusing way to fail.
if ! openssl x509 -in "$TMP/cert.pem" -noout -text | grep -q "Code Signing"; then
  echo "✗ This openssl ($(openssl version)) did not apply the codeSigning"
  echo "  extension. Install a current OpenSSL (brew install openssl) and put"
  echo "  it first on PATH."
  exit 1
fi

# OpenSSL 3 defaults to AES-256 and a SHA-256 MAC, which macOS's Security
# framework cannot read — the import fails with "MAC verification failed
# (wrong password?)" even though the password is correct. Force the older
# algorithms it understands.
echo "▸ Packaging for the keychain"
openssl pkcs12 -export -out "$TMP/cert.p12" \
  -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
  -passout "pass:$P12PASS" \
  -keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES -macalg sha1

echo "▸ Importing into the login keychain"
security import "$TMP/cert.p12" -k "$KEYCHAIN" -P "$P12PASS" \
  -T /usr/bin/codesign > /dev/null

echo
if has_identity; then
  echo "✔ '$NAME' is ready. Scripts/build.sh picks it up automatically."
  echo "  The first build may ask for keychain access — click 'Always Allow'."
else
  echo "✗ Imported, but not usable as a signing identity. Check Keychain"
  echo "  Access for a '$NAME' entry without a private key attached."
  exit 1
fi
