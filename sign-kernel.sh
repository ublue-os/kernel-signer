#!/usr/bin/bash

set -ouex pipefail

kernel_version=""

if command -v rpm; then
  kernel_version=$(rpm -qa | grep -P 'kernel-(|'"$KERNEL_SUFFIX"'-)(\d+\.\d+\.\d+)' | sed -E 's/kernel-(|'"$KERNEL_SUFFIX"'-)//')
fi

if command -v rpm-ostree; then
  rpm-ostree install sbsigntools openssl
elif command -v dnf; then
  dnf install sbsigntools openssl
elif command -v dnf5; then
  dnf5 install sbsigntools openssl
fi

# Private key
if [[ "${PRIVKEY}" == /* ]]; then
  PRIVKEY_PATH="${PRIVKEY}"
else
  PRIVKEY_PATH="/tmp/private_key.priv"
  if [[ "${PRIVKEY}" == ./* ]]; then
    cp "${PRIVKEY}" "${PRIVKEY_PATH}"
  elif [[ "${PRIVKEY}" == http* ]]; then
    wget -q "${PRIVKEY}" -O "${PRIVKEY_PATH}"
  else
    echo "${PRIVKEY}" > "${PRIVKEY_PATH}"
  fi
fi

# Public key
if [[ "${PUBKEY}" == /* ]]; then
  PUBKEY_PATH="${PUBKEY}"
else
  PUBKEY_PATH="/etc/pki/kernel/public/public_key.der"
  mkdir -p "$(dirname "$PUBKEY_PATH")"
  if [[ "${PUBKEY}" == ./* ]]; then
    cp "${PUBKEY}" "${PUBKEY_PATH}"
  elif [[ "${PUBKEY}" == http* ]]; then
    wget -q "${PUBKEY}" -O "${PUBKEY_PATH}"
  else
    echo "${PUBKEY}" > "${PUBKEY_PATH}"
  fi
fi

echo "Signing kernel..."

CRT_PATH=$(echo $(dirname "$PUBKEY_PATH")/public_key.crt)

openssl x509 -in $PUBKEY_PATH -out $CRT_PATH
if [[ "${STRIP}" == true ]]; then
  EXISTING_SIGNATURES="$(sbverify --list /usr/lib/modules/$kernel_version/vmlinuz | grep '^signature \([0-9]\+\)$' | sed 's/^signature \([0-9]\+\)$/\1/')" || true
  if [[ -n $EXISTING_SIGNATURES ]]; then
    for SIGNUM in $EXISTING_SIGNATURES
    do
      echo "Found existing signature at signum $SIGNUM, removing..."
      sbattach --remove /usr/lib/modules/$kernel_version/vmlinuz
    done
  fi
fi
sbsign --cert $CRT_PATH --key $PRIVKEY_PATH /usr/lib/modules/$kernel_version/vmlinuz --output /usr/lib/modules/$kernel_version/vmlinuz
rm -rf $PRIVKEY_PATH
sbverify --list /usr/lib/modules/$kernel_version/vmlinuz

if command -v ostree; then
  rm -rf /tmp/* /var/*
  mkdir -p /var/lib/bluetooth
  ostree container commit
fi
