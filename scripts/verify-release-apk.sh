#!/usr/bin/env bash
set -euo pipefail
trap 'echo "APK verification failed at line $LINENO" >&2' ERR

if [ "$#" -ne 6 ]; then
  echo 'usage: verify-release-apk.sh APK CERT_SHA256 PACKAGE VERSION_CODE VERSION_NAME MIN_SDK' >&2
  exit 2
fi

apk=$1
expected_cert=${2,,}
expected_package=$3
expected_code=$4
expected_name=$5
expected_sdk=$6

test -f "$apk"
sdk=${ANDROID_SDK_ROOT:-${ANDROID_HOME:-}}
test -n "$sdk"
tools=$(find "$sdk/build-tools" -mindepth 1 -maxdepth 1 -type d | sort -V | tail -n 1)
test -n "$tools"
printf 'Verifying APK with Android build-tools %s\n' "$(basename "$tools")"

signers=$("$tools/apksigner" verify --print-certs "$apk")
printf 'apksigner certificate report:\n%s\n' "$signers"
signer_count=$(printf '%s\n' "$signers" | grep -Eic '^Signer #[0-9]+ certificate SHA-256 digest:[[:space:]]*[[:xdigit:]]+' || true)
test "$signer_count" -eq 1
actual_cert=$(printf '%s\n' "$signers" | sed -nE 's/^Signer #1 certificate SHA-256 digest:[[:space:]]*([[:xdigit:]]+).*/\1/ip' | tr 'A-F' 'a-f' | tr -d '\r')
test "$actual_cert" = "$expected_cert"

badging=$("$tools/aapt2" dump badging "$apk")
package_line=$(printf '%s\n' "$badging" | grep '^package: ')
[[ "$package_line" == *"name='$expected_package'"* ]]
[[ "$package_line" == *"versionCode='$expected_code'"* ]]
[[ "$package_line" == *"versionName='$expected_name'"* ]]
printf '%s\n' "$badging" | grep -Fx "minSdkVersion:'$expected_sdk'" >/dev/null

(cd "$(dirname "$apk")" && sha256sum "$(basename "$apk")") | tee "$apk.sha256"
printf 'Verified package=%s versionCode=%s versionName=%s minSdk=%s signerSHA256=%s\n' \
  "$expected_package" "$expected_code" "$expected_name" "$expected_sdk" "$actual_cert"
