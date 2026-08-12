#!/usr/bin/env bash
set -euo pipefail

IDENTITY_NAME="Perch Local Development"
SECURITY_TOOL="${SECURITY_TOOL:-/usr/bin/security}"
OPENSSL_TOOL="${OPENSSL_TOOL:-/usr/bin/openssl}"
LOGIN_KEYCHAIN="${LOGIN_KEYCHAIN:-$HOME/Library/Keychains/login.keychain-db}"

find_identity() {
    "$SECURITY_TOOL" find-identity -p codesigning -v "$LOGIN_KEYCHAIN" 2>/dev/null \
        | /usr/bin/awk -v identity_name="$IDENTITY_NAME" '
            index($0, "\"" identity_name "\"") { print $2; exit }
        '
}

if [[ -n "$(find_identity)" ]]; then
    echo "$IDENTITY_NAME is already installed."
    exit 0
fi

if [[ ! -x "$OPENSSL_TOOL" ]]; then
    echo "error: OpenSSL is required to create the optional local signing identity" >&2
    exit 1
fi

TEMP_ROOT="${TMPDIR:-/tmp}"
TEMP_DIR="$(mktemp -d "$TEMP_ROOT/perch-local-signing.XXXXXX")"
IMPORTED_IDENTITY=false
SETUP_COMPLETE=false
CERTIFICATE_HASH=""
cleanup() {
    if [[ "$IMPORTED_IDENTITY" == true && "$SETUP_COMPLETE" == false && -n "$CERTIFICATE_HASH" ]]; then
        "$SECURITY_TOOL" delete-identity \
            -Z "$CERTIFICATE_HASH" \
            -t \
            "$LOGIN_KEYCHAIN" \
            >/dev/null 2>&1 || true
    fi
    case "$TEMP_DIR" in
        */perch-local-signing.*)
            rm -rf -- "$TEMP_DIR"
            ;;
    esac
}
trap cleanup EXIT

PRIVATE_KEY="$TEMP_DIR/local-development.key"
CERTIFICATE="$TEMP_DIR/local-development.crt"
ARCHIVE="$TEMP_DIR/local-development.p12"
ARCHIVE_PASSWORD="$($OPENSSL_TOOL rand -hex 32)"

"$OPENSSL_TOOL" req \
    -new \
    -newkey rsa:2048 \
    -x509 \
    -sha256 \
    -days 3650 \
    -nodes \
    -subj "/CN=$IDENTITY_NAME/O=Perch Development/OU=LOCALDEV" \
    -addext "keyUsage=critical,digitalSignature" \
    -addext "extendedKeyUsage=codeSigning" \
    -keyout "$PRIVATE_KEY" \
    -out "$CERTIFICATE" \
    >/dev/null 2>&1
CERTIFICATE_HASH="$($OPENSSL_TOOL x509 -in "$CERTIFICATE" -noout -fingerprint -sha256 \
    | /usr/bin/awk -F= '{ value = $2; gsub(":", "", value); print value }')"

if "$OPENSSL_TOOL" version 2>/dev/null | /usr/bin/grep -Eq '^OpenSSL 3\.'; then
    PKCS12_COMPATIBILITY="-legacy"
else
    PKCS12_COMPATIBILITY=""
fi
"$OPENSSL_TOOL" pkcs12 \
    -export \
    ${PKCS12_COMPATIBILITY:+$PKCS12_COMPATIBILITY} \
    -out "$ARCHIVE" \
    -inkey "$PRIVATE_KEY" \
    -in "$CERTIFICATE" \
    -passout "pass:$ARCHIVE_PASSWORD" \
    -name "$IDENTITY_NAME"

"$SECURITY_TOOL" import "$ARCHIVE" \
    -k "$LOGIN_KEYCHAIN" \
    -P "$ARCHIVE_PASSWORD" \
    -x \
    -T /usr/bin/codesign \
    -T /usr/bin/security \
    >/dev/null
IMPORTED_IDENTITY=true
"$SECURITY_TOOL" add-trusted-cert \
    -r trustRoot \
    -p codeSign \
    -k "$LOGIN_KEYCHAIN" \
    "$CERTIFICATE"

IDENTITY_HASH="$(find_identity)"
if [[ -z "$IDENTITY_HASH" ]]; then
    echo "error: the local signing identity was created but is not available to codesign" >&2
    exit 1
fi
SETUP_COMPLETE=true

echo "Installed $IDENTITY_NAME ($IDENTITY_HASH)."
echo "Local Perch rebuilds will now keep a stable signing identity."
