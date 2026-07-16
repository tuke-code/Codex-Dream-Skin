#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd -P)"
NODE="${NODE:-$(command -v node)}"
VERSION="$(tr -d '[:space:]' < "$ROOT/macos/VERSION")"

case "$VERSION" in
  ''|*[!0-9.]*)
    printf 'Invalid macOS VERSION: %s\n' "$VERSION" >&2
    exit 1
    ;;
esac

while IFS= read -r -d '' file; do
  bash -n "$file"
done < <(find "$ROOT/macos" "$ROOT/windows" -type f \( -name '*.sh' -o -name '*.command' \) \
  ! -path '*/release/*' -print0)

while IFS= read -r -d '' file; do
  "$NODE" --check "$file" >/dev/null
done < <(find "$ROOT/macos" "$ROOT/windows" -type f \( -name '*.mjs' -o -name '*.js' \) \
  ! -path '*/release/*' -print0)

PACKAGE_VERSION="$("$NODE" -p 'require(process.argv[1]).version' "$ROOT/macos/package.json")"
[ "$PACKAGE_VERSION" = "$VERSION" ] || {
  printf 'macos/package.json version %s does not match VERSION %s.\n' "$PACKAGE_VERSION" "$VERSION" >&2
  exit 1
}

if grep -R -n -E 'dream-skin-skin|DREAM_SKIN_SKIN|1\.0\.0-rc2' \
  "$ROOT/macos/scripts" "$ROOT/macos/assets" "$ROOT/windows/scripts" "$ROOT/windows/assets" >/dev/null; then
  printf 'Legacy release-candidate identifiers remain in runtime files.\n' >&2
  exit 1
fi
if grep -R -n -E -i '(writeFile|rename|copyFile|rm|replace|move).*app\.asar' \
  "$ROOT/macos/scripts" "$ROOT/windows/scripts" >/dev/null; then
  printf 'A runtime script appears to mutate app.asar.\n' >&2
  exit 1
fi
if grep -n -E '/usr/bin/python3|(^|[[:space:]])eval([[:space:]]|$)' \
  "$ROOT/macos/scripts/common-macos.sh" >/dev/null; then
  printf 'The macOS runtime must not depend on python3 or eval state data.\n' >&2
  exit 1
fi
if grep -n -E 'verified_cdp_endpoint[^|]*\|\|[[:space:]]*cdp_http_ready|\*ChatGPT\*\|\*Codex\*\|\*codex\*' \
  "$ROOT/macos/scripts/common-macos.sh" >/dev/null; then
  printf 'The macOS runtime contains a soft CDP identity bypass.\n' >&2
  exit 1
fi
if grep -R -n -E 'remote-debugging-address[= ]0\.0\.0\.0|http://0\.0\.0\.0|ws://0\.0\.0\.0' \
  "$ROOT/macos" "$ROOT/windows" >/dev/null; then
  printf 'A CDP endpoint is configured outside loopback.\n' >&2
  exit 1
fi
if grep -R -n -F "$VERSION" "$ROOT/macos/scripts" "$ROOT/macos/tests" >/dev/null; then
  printf 'The macOS version is hard-coded outside VERSION/package.json.\n' >&2
  exit 1
fi

"$NODE" "$ROOT/macos/scripts/injector.mjs" --self-test >/dev/null
"$NODE" "$ROOT/macos/scripts/injector.mjs" --check-payload >/dev/null
"$NODE" "$ROOT/windows/scripts/injector.mjs" --self-test >/dev/null
"$NODE" "$ROOT/windows/scripts/injector.mjs" --check-payload >/dev/null
"$NODE" "$ROOT/windows/tests/renderer-inject.test.mjs" >/dev/null

printf 'PASS: cross-platform syntax, payload, version, and security checks.\n'
