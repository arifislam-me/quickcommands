#!/usr/bin/env bash
# Build the .deb from a clean staging dir. Usage: ./build.sh [--selftest]
#   --selftest   only run the maintainer-script tests, build nothing
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
ROOT=$PWD

if [[ "${1:-}" == "--selftest" ]]; then
  exec bash scripts/test-maintainer-scripts.sh
fi

for s in usr/bin/quickcommands etc/profile.d/quickcommands.sh DEBIAN/postinst DEBIAN/prerm DEBIAN/postrm \
         build.sh scripts/test-maintainer-scripts.sh tests/run.sh; do
  bash -n "$s"
done
echo "syntax ok"
bash tests/run.sh
bash scripts/test-maintainer-scripts.sh

VERSION=$(sed -n 's/^Version: *//p' DEBIAN/control | head -n1)
[[ -n "$VERSION" ]] || { echo "no Version in DEBIAN/control" >&2; exit 1; }

STAGE=$(mktemp -d); trap 'rm -rf "$STAGE"' EXIT
chmod 755 "$STAGE"
install -d -m 755 "$STAGE/DEBIAN" "$STAGE/usr/bin" "$STAGE/etc/profile.d"
install -m 644 DEBIAN/control "$STAGE/DEBIAN/control"
for m in postinst prerm postrm; do install -m 755 "DEBIAN/$m" "$STAGE/DEBIAN/$m"; done
chmod 755 "$STAGE/usr" "$STAGE/etc"
install -m 755 usr/bin/quickcommands "$STAGE/usr/bin/quickcommands"
install -m 644 etc/profile.d/quickcommands.sh "$STAGE/etc/profile.d/quickcommands.sh"

mkdir -p dist
OUT="dist/quickcommands_${VERSION}_all.deb"
rm -f "$OUT" dist/quickcommands.deb
if dpkg-deb --help 2>&1 | grep -q -- --root-owner-group; then
  dpkg-deb --root-owner-group --build "$STAGE" "$OUT"
else
  fakeroot dpkg-deb --build "$STAGE" "$OUT"
fi
cp "$OUT" dist/quickcommands.deb
echo "built: $OUT and dist/quickcommands.deb"
