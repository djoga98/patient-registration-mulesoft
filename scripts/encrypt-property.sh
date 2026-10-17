#!/usr/bin/env bash
# Encrypts one value for Mule Secure Configuration Properties.
#
#   scripts/encrypt-property.sh <16-char-key> <plain-value>
#   -> ![base64-ciphertext]
#
# Matches <secure-properties:encrypt algorithm="AES" mode="CBC"/> with the
# module defaults (PKCS5 padding, useRandomIVs=false, i.e. IV = key bytes).
# This is the same output the MuleSoft Secure Properties Tool produces for
# "string encrypt AES CBC", without needing that jar on the PATH.
#
# Pass values through the environment or a prompt rather than shell history
# where possible, e.g.:  read -rs VALUE; scripts/encrypt-property.sh "$KEY" "$VALUE"
set -euo pipefail

if [[ $# -ne 2 ]]; then
    echo "usage: $0 <16-char-key> <plain-value>" >&2
    exit 2
fi

key="$1"
value="$2"

if [[ ${#key} -ne 16 ]]; then
    echo "error: the key must be exactly 16 characters (AES-128)" >&2
    exit 2
fi

key_hex=$(printf '%s' "$key" | od -An -tx1 | tr -d ' \n')
cipher=$(printf '%s' "$value" | openssl enc -aes-128-cbc -K "$key_hex" -iv "$key_hex" -base64 -A)
printf '![%s]\n' "$cipher"
