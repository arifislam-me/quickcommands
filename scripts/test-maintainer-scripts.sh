#!/usr/bin/env bash
# Tests DEBIAN/postinst, prerm and postrm against fake bashrc files.
# A stub `getent` makes the scripts see only temp homes; nothing real is touched.
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); }
bad() { FAIL=$((FAIL+1)); echo "FAIL: $1"; }
eqf() { if cmp -s "$2" "$3"; then ok; else bad "$1"; diff "$2" "$3" | head; fi; }

mkdir -p "$T/bin" "$T/alice" "$T/root" "$T/sys" "$T/bob" "$T/nobashrc"
cat > "$T/bin/getent" <<STUB
#!/bin/sh
echo "root:x:0:0:root:$T/root:/bin/bash"
echo "daemon:x:1:1:d:$T/sys:/usr/sbin/nologin"
echo "alice:x:1000:1000:a:$T/alice:/bin/bash"
echo "bob:x:1001:1001:b:$T/bob:/bin/bash"
echo "ghost:x:1002:1002:g:$T/missing:/bin/bash"
echo "nb:x:1003:1003:n:$T/nobashrc:/bin/bash"
STUB
chmod +x "$T/bin/getent"
export PATH="$T/bin:$PATH"

printf 'alias ll="ls -l"\n\n\nexport A=1\n' > "$T/alice/.bashrc"
cp "$T/alice/.bashrc" "$T/alice.orig"
cp "$T/alice/.bashrc" "$T/root/.bashrc"
cp "$T/alice/.bashrc" "$T/sys/.bashrc"
# bob: old v1.0.x install, with unrelated blank lines that must survive
printf 'export B=1\n\n\nalias x=y\n\n# Added by quickcommands package\nsource /etc/profile.d/quickcommands.sh\n\nexport C=1\n' > "$T/bob/.bashrc"
cp "$T/bob/.bashrc" "$T/bob.orig"
chmod 640 "$T/alice/.bashrc"

# postinst: non-configure does nothing
sh "$ROOT/DEBIAN/postinst" abort-upgrade >/dev/null; eqf "postinst abort-upgrade untouched" "$T/alice/.bashrc" "$T/alice.orig"
# configure
out=$(sh "$ROOT/DEBIAN/postinst" configure 2>&1); rc=$?
[ $rc -eq 0 ] && ok || bad "postinst exit $rc"
[[ $out == *Ctrl+Q* && $out == *"key set"* ]] && ok || bad "postinst message"
[ "$(grep -c '# >>> quickcommands >>>' "$T/alice/.bashrc")" = 1 ] && ok || bad "alice has one block"
[ "$(grep -c '# >>> quickcommands >>>' "$T/root/.bashrc")" = 1 ] && ok || bad "root (uid 0) has block"
cmp -s "$T/sys/.bashrc" "$T/alice.orig" && ok || bad "system user uid<1000 untouched"
cmp -s "$T/bob/.bashrc" "$T/bob.orig" && ok || bad "old-style v1.0.x not duplicated"
[ ! -e "$T/nobashrc/.bashrc" ] && ok || bad "no bashrc created"
[ "$(stat -c %a "$T/alice/.bashrc")" = 640 ] && ok || bad "mode kept"
# idempotent
cp "$T/alice/.bashrc" "$T/alice.once"
sh "$ROOT/DEBIAN/postinst" configure >/dev/null; eqf "postinst idempotent" "$T/alice/.bashrc" "$T/alice.once"
# the block must be valid bash and source nothing harmful when file absent
bash -n "$T/alice/.bashrc" && ok || bad "alice bashrc syntax"

# prerm: upgrade must not touch
for a in upgrade failed-upgrade deconfigure; do
  sh "$ROOT/DEBIAN/prerm" $a >/dev/null; eqf "prerm $a untouched" "$T/alice/.bashrc" "$T/alice.once"
done
# prerm remove: alice back to original, bob back to original minus our two lines
sh "$ROOT/DEBIAN/prerm" remove >/dev/null; rc=$?
[ $rc -eq 0 ] && ok || bad "prerm exit"
# postinst added '\n' before the block, so exactly one extra blank line is left
printf 'alias ll="ls -l"\n\n\nexport A=1\n\n' > "$T/alice.expect"
eqf "alice cleaned, other lines/blank lines kept" "$T/alice.expect" "$T/alice/.bashrc"
printf 'export B=1\n\n\nalias x=y\n\n\nexport C=1\n' > "$T/bob.expect"
eqf "bob old-style removed, blank lines kept" "$T/bob.expect" "$T/bob/.bashrc"
[ "$(stat -c %a "$T/alice/.bashrc")" = 640 ] && ok || bad "mode kept after prerm"
# idempotent
cp "$T/alice/.bashrc" "$T/alice.c1"; sh "$ROOT/DEBIAN/prerm" remove >/dev/null
eqf "prerm idempotent" "$T/alice/.bashrc" "$T/alice.c1"
# unterminated block is NOT deleted to EOF
printf 'keep1\n# >>> quickcommands >>>\nkeep2\n' > "$T/alice/.bashrc"
cp "$T/alice/.bashrc" "$T/alice.unt"; sh "$ROOT/DEBIAN/prerm" remove >/dev/null
eqf "unterminated block left alone" "$T/alice/.bashrc" "$T/alice.unt"

# postrm
for a in remove purge; do
  out=$(sh "$ROOT/DEBIAN/postrm" $a); [[ $out == *quickcommands* && $out == *saved_commands* && $out != *savedcmd* ]] && ok || bad "postrm $a message"
done
[ -z "$(sh "$ROOT/DEBIAN/postrm" upgrade)" ] && ok || bad "postrm upgrade silent"

echo "maintainer scripts: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
