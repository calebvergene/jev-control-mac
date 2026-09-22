#!/bin/zsh
# Create a self-signed code signing certificate for local development.
#
# Why this exists: an ad-hoc signature has no identity, so its designated
# requirement is `cdhash H"..."` — the hash of that exact binary. macOS ties
# Accessibility and Input Monitoring grants to that requirement, so every
# rebuild silently invalidates them while System Settings still shows the box
# ticked.
#
# A certificate changes the requirement to
# `identifier "ai.jev.control" and certificate leaf = H"..."`, which does not
# change when the code does. Grant permissions once, rebuild freely.
#
# You will see two prompts: one to trust the new certificate, and one from
# codesign the first time it uses the key — click "Always Allow" on that one.
set -e

NAME="${JEV_CERT_NAME:-Jev Control Dev}"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if security find-certificate -c "$NAME" "$KEYCHAIN" > /dev/null 2>&1; then
  echo "✔ '$NAME' already exists."
  security find-identity -v -p codesigning | grep "$NAME" || {
    echo "⚠ It exists but is not valid for code signing. Delete it in Keychain"
    echo "  Access and run this again."
    exit 1
  }
  exit 0
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "▸ Generating a self-signed code signing certificate"
openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
  -keyout "$TMP/key.pem" -out "$TMP/cert.pem" \
  -subj "/CN=$NAME" \
  -addext "basicConstraints=critical,CA:false" \
  -addext "keyUsage=critical,digitalSignature" \
  -addext "extendedKeyUsage=critical,codeSigning" 2>/dev/null

# macOS ships LibreSSL as /usr/bin/openssl, which ignores -addext. Without the
# codeSigning EKU the certificate imports fine but never becomes a valid
# signing identity, which is a confusing way to fail.
if ! openssl x509 -in "$TMP/cert.pem" -noout -text | grep -q "Code Signing"; then
  echo "✗ This openssl ($(openssl version)) did not apply the codeSigning"
  echo "  extension. Install a current OpenSSL (brew install openssl) and"
  echo "  make sure it comes first on PATH."
  exit 1
fi

openssl pkcs12 -export -out "$TMP/cert.p12" \
  -inkey "$TMP/key.pem" -in "$TMP/cert.pem" -passout pass:

echo "▸ Importing into the login keychain"
security import "$TMP/cert.p12" -k "$KEYCHAIN" -P "" \
  -T /usr/bin/codesign -T /usr/bin/security > /dev/null

echo "▸ Trusting it for code signing (this prompts for your password)"
security add-trusted-cert -r trustRoot -p codeSign -k "$KEYCHAIN" "$TMP/cert.pem"

echo
if security find-identity -v -p codesigning | grep -q "$NAME"; then
  echo "✔ '$NAME' is ready. Scripts/build.sh will pick it up automatically."
else
  echo "⚠ Created, but not showing as a valid signing identity yet."
  echo "  Open Keychain Access, find '$NAME', and set Trust › Code Signing to"
  echo "  'Always Trust'."
  exit 1
fi
