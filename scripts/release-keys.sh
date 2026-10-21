#!/usr/bin/env bash
# One-time setup of the two keys releases are signed with. Run it once, on the maintainer's Mac.
#
#   scripts/release-keys.sh
#
# 1. The Sparkle update key (EdDSA). The public half goes into Resources/SparklePublicKey.txt (commit it);
#    the private half is kept in the login keychain and exported to ~/.luna/sparkle-private.key for the
#    SPARKLE_PRIVATE_KEY repository secret.
# 2. A self-signed code-signing certificate, "Luna Self-Signed". Signing every release with the same
#    certificate keeps macOS's Accessibility permission (for the brightness keys) across updates; ad-hoc
#    signatures change with every build. Saved to ~/.luna/luna-signing.p12 for LUNA_CERT_P12.
#
# Keep ~/.luna backed up: without the Sparkle key no future update can be signed, and without the
# certificate users re-grant Accessibility once after the next update.
set -euo pipefail
cd "$(dirname "$0")/.."

keys="$HOME/.luna"
mkdir -p "$keys"
chmod 700 "$keys"

swift package resolve >/dev/null
bin=.build/artifacts/sparkle/Sparkle/bin

if [[ -s Resources/SparklePublicKey.txt ]]; then
    echo "› Sparkle key: already set up (Resources/SparklePublicKey.txt)"
else
    "$bin/generate_keys" --account luna >/dev/null
    "$bin/generate_keys" --account luna -p > Resources/SparklePublicKey.txt
    "$bin/generate_keys" --account luna -x "$keys/sparkle-private.key"
    chmod 600 "$keys/sparkle-private.key"
    echo "› Sparkle key: public half in Resources/SparklePublicKey.txt, private half in $keys/sparkle-private.key"
fi

if [[ -s "$keys/luna-signing.p12" ]]; then
    echo "› Signing certificate: already in $keys/luna-signing.p12"
else
    work=$(mktemp -d)
    cat > "$work/cert.cnf" <<'EOF'
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = Luna Self-Signed
O = Luna
[ext]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
EOF
    openssl req -x509 -newkey rsa:2048 -nodes -days 7300 -config "$work/cert.cnf" \
        -keyout "$work/key.pem" -out "$work/cert.pem" 2>/dev/null
    password=$(openssl rand -base64 24)
    # Algorithms macOS's `security import` understands.
    openssl pkcs12 -export -inkey "$work/key.pem" -in "$work/cert.pem" -name "Luna Self-Signed" \
        -keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES -macalg sha1 \
        -passout "pass:$password" -out "$keys/luna-signing.p12"
    printf '%s' "$password" > "$keys/luna-signing.password"
    chmod 600 "$keys/luna-signing.p12" "$keys/luna-signing.password"
    rm -rf "$work"
    echo "› Signing certificate: $keys/luna-signing.p12 (password in $keys/luna-signing.password)"
fi

cat <<EOF

Next, add the repository secrets (GitHub › Settings › Secrets and variables › Actions):

  gh secret set SPARKLE_PRIVATE_KEY < "$keys/sparkle-private.key"
  base64 -i "$keys/luna-signing.p12" | gh secret set LUNA_CERT_P12
  gh secret set LUNA_CERT_PASSWORD < "$keys/luna-signing.password"

and commit Resources/SparklePublicKey.txt. To sign local builds the same way, import the certificate:

  security import "$keys/luna-signing.p12" -P "\$(cat "$keys/luna-signing.password")" -T /usr/bin/codesign
EOF
