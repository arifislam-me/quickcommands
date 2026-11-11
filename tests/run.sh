#!/usr/bin/env bash
# Tests for quickcommands. Plain bash, no framework. Run: bash tests/run.sh
# Uses a throw-away HOME and a fake fzf (tests/stub-bin/fzf); real fzf is not needed.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
QC_BIN="$ROOT/usr/bin/quickcommands"
PROFILE="$ROOT/etc/profile.d/quickcommands.sh"
STUB_DIR="$ROOT/tests/stub-bin"
PLACEHOLDER="No commands found. Write your first command and press Ctrl+S"

PASS=0; FAIL=0; SKIP=0
BASE=$(mktemp -d) || exit 2
trap 'rm -rf "$BASE"' EXIT

pass() { PASS=$((PASS + 1)); }
fail() { FAIL=$((FAIL + 1)); printf 'FAIL: %s\n' "$1"; [[ -n "${2:-}" ]] && printf '      %s\n' "$2"; }
check() { # check <name> <command...>   passes when the command succeeds
  local name=$1; shift
  if "$@"; then pass; else fail "$name"; fi
}
eq() { # eq <name> <expected> <actual>
  if [[ "$2" == "$3" ]]; then pass; else fail "$1" "expected [$2] got [$3]"; fi
}
has() { # has <name> <haystack> <needle>
  if [[ "$2" == *"$3"* ]]; then pass; else fail "$1" "[$2] does not contain [$3]"; fi
}
hasnt() {
  if [[ "$2" != *"$3"* ]]; then pass; else fail "$1" "[$2] contains [$3]"; fi
}

# Fresh sandbox for every test group.
setup() {
  T=$(mktemp -d "$BASE/t.XXXXXX")
  export HOME="$T/home"; mkdir -p "$HOME" "$T/tmp"
  unset XDG_CONFIG_HOME QUICKCOMMANDS_KEY
  export TMPDIR="$T/tmp"
  export PATH="$STUB_DIR:$ROOT/usr/bin:$ORIG_PATH"
  export FZF_STUB_PLAN="$T/plan" FZF_STUB_STATE="$T/state" FZF_STUB_STDIN="$T/stdin"
  : > "$FZF_STUB_PLAN"; rm -f "$FZF_STUB_STATE" "$FZF_STUB_STDIN"
  SF="$HOME/.saved_commands"
  CFG="$HOME/.config/quickcommands/config"
  cd "$T" || exit 2
}
plan() { printf '%s\n' "$@" > "$FZF_STUB_PLAN"; rm -f "$FZF_STUB_STATE"; }
qc() { "$QC_BIN" "$@"; }
mode() { stat -c %a "$1"; }
lines() { awk 'END { print NR }' "$SF"; }
ORIG_PATH=$PATH
BASH_BIN=$(command -v bash)

# ------------------------------------------------------------ syntax
bash -n "$QC_BIN" && pass || fail "bash -n quickcommands"
bash -n "$PROFILE" && pass || fail "bash -n profile.d script"
if grep -n 'Ctrl+R\|ctrl-r\|C-r' "$QC_BIN" "$PROFILE" | grep -v 'normal\|reverse history\|r) printf' >/dev/null; then
  fail "stale Ctrl+R mention"; else pass; fi
if grep -n 'echo -e' "$QC_BIN" "$PROFILE" >/dev/null; then fail "echo -e used"; else pass; fi

# ------------------------------------------------------------ basics
setup
eq "--version" "quickcommands 1.0.0" "$(qc --version)"
out=$(qc list)
has "first run seeds echo hello" "$out" "echo hello"
has "first run seeds whoami" "$out" "whoami"
eq "save file mode 600" 600 "$(mode "$SF")"
chmod 644 "$SF"; qc list >/dev/null
eq "loose mode fixed to 600" 600 "$(mode "$SF")"
has "help mentions key set" "$(qc help)" "key set"
has "help mentions ctrl-q" "$(qc help)" "Ctrl+Q"
hasnt "help has no Ctrl+R" "$(qc help)" "Ctrl+R"

# ------------------------------------------------------------ save
setup; : > /dev/null
qc clear <<< yes >/dev/null            # start empty (file exists, so no re-seed)
qc save "git status" >/dev/null; eq "save single arg verbatim" "git status" "$(sed -n 1p "$SF")"
qc save grep "a b" >/dev/null;   eq "save multi-arg keeps quoting" 'grep a\ b' "$(sed -n 2p "$SF")"
out=$(qc save "git status"); has "duplicate message" "$out" "already saved"; eq "duplicate not added" 2 "$(lines)"
qc save "" >/dev/null 2>&1; eq "empty save rejected" 1 $?
qc save "   " >/dev/null 2>&1; eq "blank save rejected" 1 $?
qc save >/dev/null 2>&1; eq "save without args rejected" 1 $?
qc save $'one\ntwo' >/dev/null 2>&1; eq "newline save rejected" 1 $?
qc save echo $'x\ny' >/dev/null 2>&1; eq "newline in multi-arg rejected" 1 $?
eq "nothing added by rejected saves" 2 "$(lines)"
qc save "  ls -la  " >/dev/null; eq "save trims whitespace" "ls -la" "$(sed -n 3p "$SF")"
qc save -- "-n" >/dev/null 2>&1; qc save "-n" >/dev/null 2>&1
check "command starting with -n stored intact" grep -qxF -- "-n" "$SF"
eq "file mode stays 600 after saves" 600 "$(mode "$SF")"
out=$(qc list); has "list numbered" "$out" " 1. git status"

# ------------------------------------------------------------ run
setup
qc clear <<< yes >/dev/null
qc save "echo RUNOK" >/dev/null
out=$(qc run 1); has "run valid prints output" "$out" "RUNOK"
for bad in 0 abc 99 "1;w x" '1,$' "" "-1" "1 " "01" "99999999999999999999"; do
  out=$(qc run "$bad" 2>&1); rc=$?
  eq "run '$bad' fails" 1 "$rc"
done
check "run '1;w x' did not create file x" test ! -e "$T/x"
eq "run invalid keeps the file" 1 "$(lines)"

# ------------------------------------------------------------ rm
setup
qc clear <<< yes >/dev/null
for c in aa bb cc; do qc save "$c" >/dev/null; done
qc rm '1,$' >/dev/null 2>&1; eq "rm '1,\$' fails" 1 $?
eq "rm '1,\$' deleted nothing" 3 "$(lines)"
qc rm 0 >/dev/null 2>&1; eq "rm 0 fails" 1 $?
qc rm 99 >/dev/null 2>&1; eq "rm 99 fails" 1 $?
qc rm x >/dev/null 2>&1; eq "rm x fails" 1 $?
qc rm "1d;1" >/dev/null 2>&1; eq "rm injection fails" 1 $?
eq "failed rm keep 3 lines" 3 "$(lines)"
qc rm 2 >/dev/null; eq "rm 2 ok" "aa cc" "$(tr '\n' ' ' < "$SF" | sed 's/ $//')"
eq "mode 600 after rm" 600 "$(mode "$SF")"

# ------------------------------------------------------------ clear / no re-seed
setup
qc list >/dev/null
qc clear <<< yes >/dev/null
eq "list empty after clear" "" "$(qc list)"
eq "no re-seed after clear (file)" 0 "$(wc -c < "$SF")"
plan "cancel"; qc pick >/dev/null
eq "no re-seed after pick on empty" 0 "$(wc -c < "$SF")"
qc clear <<< no >/dev/null; qc save "x" >/dev/null; qc clear <<< nope >/dev/null
eq "clear needs exact yes" 1 "$(lines)"

# ------------------------------------------------------------ pick
setup
qc clear <<< yes >/dev/null; qc save "echo one" >/dev/null; qc save 'echo a\\b $HOME' >/dev/null
plan 'print:echo one'
out=$(qc pick); rc=$?
eq "pick exit 0" 0 $rc
eq "pick prints chosen command on stdout" "echo one" "$out"
plan 'print:echo a\\b $HOME'
eq "pick keeps backslashes" 'echo a\\b $HOME' "$(qc pick)"
plan 'cancel'
out=$(qc pick); rc=$?
eq "cancel prints nothing" "" "$out"; eq "cancel exit 0" 0 $rc
check "default subcommand is pick" bash -c "plan() { :; }; true"
plan 'print:echo one'; eq "no-arg quickcommands picks" "echo one" "$(qc)"
args=$(FZF_STUB_ARGS="$T/args" bash -c 'printf "print:echo one\n" > "$FZF_STUB_PLAN"; "$0" pick >/dev/null; cat "$FZF_STUB_ARGS"' "$QC_BIN")
has "header says Enter: SELECT" "$args" "Enter: SELECT"
check "temp dir cleaned after pick" test -z "$(ls -A "$TMPDIR")"

# placeholder is shown when empty and never returned or saved
setup
qc clear <<< yes >/dev/null
plan "print:$PLACEHOLDER" "cancel"
out=$(qc pick); eq "placeholder never returned" "" "$out"
has "placeholder shown when empty" "$(cat "$FZF_STUB_STDIN")" "$PLACEHOLDER"
eq "placeholder not saved" 0 "$(wc -c < "$SF")"
plan "delete:$PLACEHOLDER" "cancel"; qc pick >/dev/null
eq "placeholder not deletable" 0 "$(wc -c < "$SF")"
check "temp dir cleaned (placeholder)" test -z "$(ls -A "$TMPDIR")"

# Ctrl+S save inside the menu
setup
qc clear <<< yes >/dev/null
plan 'save:  my new cmd ' 'save:my new cmd' 'save:-n' 'save:' 'print:my new cmd'
out=$(qc pick)
eq "pick after ctrl-s returns selection" "my new cmd" "$out"
eq "ctrl-s saved trimmed once; -n kept; empty skipped" "my new cmd|-n" "$(paste -sd'|' "$SF")"
plan "save:it's \"quoted\" \$x \\y" 'cancel'; qc pick >/dev/null
check "ctrl-s keeps quotes and backslashes" grep -qxF -- "it's \"quoted\" \$x \\y" "$SF"
eq "mode 600 after UI save" 600 "$(mode "$SF")"

# Ctrl+D delete inside the menu (backslash command)
setup
qc clear <<< yes >/dev/null
bs='echo a\\b\tc \$HOME'
printf '%s\n' "keep me" "$bs" "echo a\\b" >> "$SF"
plan "delete:$bs" "grep:NO" 'cancel'
qc pick >/dev/null
eq "confirm NO keeps command" 3 "$(lines)"
plan "delete:$bs" "grep:YES" 'cancel'
qc pick >/dev/null
check "backslash command deleted" bash -c '! grep -qxF -- "$1" "$2"' _ "$bs" "$SF"
eq "only the exact line deleted" "keep me|echo a\\b" "$(paste -sd'|' "$SF")"
eq "mode 600 after UI delete" 600 "$(mode "$SF")"
plan "delete:keep me" "grep:YES" "delete:echo a\\b" "grep:YES" 'cancel'
qc pick >/dev/null; rc=$?
eq "deleting last lines leaves empty file, no crash" 0 "$(wc -c < "$SF")"
eq "pick exit 0 after emptying" 0 $rc
check "no tmp leftovers beside save file" test "$(ls -A "$HOME" | wc -l)" = 1
check "temp dir cleaned (delete)" test -z "$(ls -A "$TMPDIR")"

# interactive 'delete' subcommand
setup
qc clear <<< yes >/dev/null
printf '%s\n' 'echo a\\b' 'other' >> "$SF"
plan 'grep:a\\b'
qc delete <<< y >/dev/null
eq "delete subcommand removes chosen backslash line" "other" "$(cat "$SF")"
plan 'grep:other'
qc delete <<< n >/dev/null
eq "delete subcommand 'n' keeps" "other" "$(cat "$SF")"

# ------------------------------------------------------------ key command
setup
out=$(qc key); has "default key shown" "$out" "ctrl-q"; has "default source" "$out" "default"
out=$(qc key set ctrl-g 2>&1); rc=$?
eq "key set ctrl-g ok" 0 $rc
has "set prints NEW terminals note" "$out" "NEW terminals"
eq "config content" 'KEY=\C-g' "$(cat "$CFG")"
eq "config file mode 600" 600 "$(mode "$CFG")"
eq "config dir mode 700" 700 "$(mode "$(dirname "$CFG")")"
has "key shows ctrl-g" "$(qc key)" "ctrl-g"
qc key set alt-x >/dev/null; eq "alt-x stored as \\ex" 'KEY=\ex' "$(cat "$CFG")"
has "key shows alt-x" "$(qc key)" "alt-x"
qc key set 'CTRL-K' >/dev/null 2>&1; eq "CTRL-K normalised" 'KEY=\C-k' "$(cat "$CFG")"
qc key set '\C-g' >/dev/null; eq "raw \\C-g accepted" 'KEY=\C-g' "$(cat "$CFG")"
qc key set '\ey' >/dev/null; eq "raw \\ey accepted" 'KEY=\ey' "$(cat "$CFG")"
qc key set '\eO' >/dev/null 2>&1; eq "raw \\eO refused (arrow-key prefix)" 1 $?
eq "config unchanged after refused \\eO" 'KEY=\ey' "$(cat "$CFG")"
qc key set 'alt-O' >/dev/null 2>&1; eq "alt-O normalised to \\eo" 'KEY=\eo' "$(cat "$CFG")"
qc key set ctrl-q >/dev/null 2>&1; eq "ctrl-q allowed" 0 $?
eq "ctrl-q stored" 'KEY=\C-q' "$(cat "$CFG")"
qc key set ctrl-g >/dev/null
for bad in ctrl-c ctrl-d ctrl-z ctrl-s ctrl-m ctrl-j ctrl-i ctrl-h 'ctrl-[' '\C-c' '\C-[' CTRL-C; do
  out=$(qc key set "$bad" 2>&1); rc=$?
  eq "key set $bad refused" 1 $rc
  has "refusal explains ($bad)" "$out" "Refused"
done
eq "refused keys do not touch config" 'KEY=\C-g' "$(cat "$CFG")"
for bad in "" "   " foo ctrl-1 'ctrl-' 'alt-' '\C-' '\x' 'ctrl-ab' '\C-q;touch x' '$(id)' 'alt-1'; do
  qc key set "$bad" >/dev/null 2>&1; eq "key set '$bad' rejected" 1 $?
done
qc key set >/dev/null 2>&1; eq "key set without arg rejected" 1 $?
qc key bogus >/dev/null 2>&1; eq "key bogus rejected" 1 $?
for warnkey in ctrl-a ctrl-e ctrl-r ctrl-l ctrl-w ctrl-u ctrl-k ctrl-b ctrl-f ctrl-p ctrl-n ctrl-y ctrl-t; do
  out=$(qc key set $warnkey 2>&1 >/dev/null); rc=$?
  eq "$warnkey allowed" 0 $rc
  has "$warnkey warns" "$out" "Warning"
done
out=$(qc key set ctrl-g 2>&1); hasnt "ctrl-g no warning" "$out" "Warning"
out=$(qc key reset); has "reset says NEW terminals" "$out" "NEW terminals"
check "reset removes config" test ! -e "$CFG"
has "after reset key is ctrl-q" "$(qc key)" "ctrl-q"
out=$(QUICKCOMMANDS_KEY='\C-t' qc key); has "env overrides (shows ctrl-t)" "$out" "ctrl-t"; has "env source" "$out" "QUICKCOMMANDS_KEY"
qc key set ctrl-g >/dev/null
out=$(QUICKCOMMANDS_KEY='\C-t' qc key); has "env beats config" "$out" "ctrl-t"
XDG_CONFIG_HOME="$T/xdg" qc key set alt-z >/dev/null
eq "XDG_CONFIG_HOME respected" 'KEY=\ez' "$(cat "$T/xdg/quickcommands/config")"
eq "XDG dir mode 700" 700 "$(mode "$T/xdg/quickcommands")"

# config is data, not code
setup
mkdir -p "$(dirname "$CFG")"
printf 'KEY=\\C-q; touch %s/pwned\n' "$T" > "$CFG"
out=$(qc key 2>&1)
check "config parse: no code execution (quickcommands key)" test ! -e "$T/pwned"
has "unsafe key falls back to default" "$out" "ctrl-q"
printf '$(touch %s/pwned2)\nKEY=\\C-g\n' "$T" > "$CFG"
out=$(qc key 2>&1)
check "config parse: other lines ignored" test ! -e "$T/pwned2"
has "KEY= line found after junk" "$out" "ctrl-g"

# ------------------------------------------------------------ profile.d: non-interactive and non-bash
setup
out=$(bash -c ". '$PROFILE'; echo done" 2>&1); rc=$?
eq "bash -c source: only 'done'" "done" "$out"; eq "bash -c source rc" 0 $rc
out=$(sh -c ". '$PROFILE'; echo done" 2>&1); rc=$?
eq "sh (dash) source: only 'done'" "done" "$out"; eq "sh source rc" 0 $rc
out=$(sh "$PROFILE" 2>&1); rc=$?
eq "sh execute: silent" "" "$out"; eq "sh execute rc" 0 $rc
out=$(bash "$PROFILE" 2>&1); rc=$?
eq "bash execute (non-interactive): silent" "" "$out"; eq "bash execute rc" 0 $rc
out=$(bash -c ". '$PROFILE'; type @commands 2>&1; bind -X 2>&1" 2>&1)
hasnt "non-interactive defines no @commands" "$out" "function"
hasnt "non-interactive binds nothing" "$out" "quickcommands"
if command -v dash >/dev/null 2>&1 || [[ -x /bin/sh ]]; then
  out=$(sh -ic ". '$PROFILE'; echo done" 2>&1 </dev/null); rc=$?
  has "sh -i source finishes" "$out" "done"
  hasnt "sh -i prints no profile errors" "$out" "quickcommands"
fi

# ------------------------------------------------------------ profile.d: interactive bash through a pty
ibash() { # ibash <PATH value> <commands...>; prints cleaned output
  local p=$1; shift
  local cmds; cmds=$(printf '%s\n' "$@" 'exit')
  printf '%s\n' "$cmds" | HOME="$HOME" TERM=dumb \
    script -qec "env PATH='$p' $BASH_BIN --norc --noprofile -i" /dev/null 2>&1 | tr -d '\r'
}

if command -v script >/dev/null 2>&1; then
  P="$STUB_DIR:$ROOT/usr/bin:$ORIG_PATH"

  setup
  out=$(ibash "$P" ". '$PROFILE'" 'echo "RES:binding=$(bind -X | grep -c quickcommands_fill_readline)"' \
        'bind -X | grep -F "C-q"' 'echo "RES:ctrlr=$(bind -X | grep -c "C-r")"' \
        'echo "RES:atcommands=$(type -t @commands)"' 'echo "RES:atsaved=$(type -t @saved)"' \
        'echo "RES:alias=$(alias @commands 2>&1 | wc -l)"')
  has "interactive: key bound" "$out" "RES:binding=1"
  has "interactive: default key is \\C-q" "$out" '"\C-q" "_quickcommands_fill_readline"'
  has "interactive: Ctrl+R not rebound" "$out" "RES:ctrlr=0"
  has "@commands is a function" "$out" "RES:atcommands=function"
  has "@saved is a function" "$out" "RES:atsaved=function"
  out=$(ibash "$P" "alias @commands='quickcommands pick'" ". '$PROFILE'" 'echo "RES:atcommands=$(type -t @commands)"')
  has "old alias replaced by function" "$out" "RES:atcommands=function"

  # Ctrl+Q reaches readline only if flow control (IXON) is off
  out=$(ibash "$P" ". '$PROFILE'" 'echo "RES:ixon=$(stty -a | grep -c -- "-ixon")"')
  has "stty -ixon applied" "$out" "RES:ixon=1"

  # custom key from the config file
  setup
  qc key set alt-x >/dev/null
  out=$(ibash "$P" ". '$PROFILE'" 'bind -X | grep -F quickcommands')
  has "config key \\ex bound" "$out" '"\ex" "_quickcommands_fill_readline"'
  qc key set ctrl-g >/dev/null
  out=$(ibash "$P" ". '$PROFILE'" 'bind -X | grep -F quickcommands')
  has "config key \\C-g bound" "$out" '"\C-g" "_quickcommands_fill_readline"'
  out=$(QUICKCOMMANDS_KEY='\C-t' ibash "$P" ". '$PROFILE'" 'bind -X | grep -F quickcommands')
  has "QUICKCOMMANDS_KEY env bound" "$out" '"\C-t" "_quickcommands_fill_readline"'

  # malicious / dangerous config values
  setup; mkdir -p "$(dirname "$CFG")"
  printf 'KEY=\\C-q; touch %s/pwned\n' "$T" > "$CFG"
  out=$(ibash "$P" ". '$PROFILE'" 'bind -X | grep -F quickcommands')
  check "profile.d: config not executed" test ! -e "$T/pwned"
  has "profile.d: unsafe value falls back to \\C-q" "$out" '"\C-q" "_quickcommands_fill_readline"'
  printf 'KEY=\\C-c\n' > "$CFG"
  out=$(ibash "$P" ". '$PROFILE'" 'bind -X | grep -F quickcommands')
  has "profile.d: ctrl-c in config falls back" "$out" '"\C-q" "_quickcommands_fill_readline"'
  hasnt "profile.d: ctrl-c never bound" "$out" '"\C-c"'
  printf 'KEY="; touch %s/pwned3; "\n' "$T" > "$CFG"
  ibash "$P" ". '$PROFILE'" >/dev/null
  check "profile.d: quote-injection not executed" test ! -e "$T/pwned3"

  # @commands: output + history
  setup
  qc clear <<< yes >/dev/null; qc save "echo from-history" >/dev/null
  plan 'print:echo from-history'
  out=$(ibash "$P" ". '$PROFILE'" '@commands' 'echo "RES:hist=$(history | tail -n 3 | grep -c "echo from-history")"')
  has "@commands prints the pick" "$out" "echo from-history"
  has "@commands adds it to history" "$out" "RES:hist="
  hasnt "@commands history count is not zero" "$out" "RES:hist=0"
  plan 'cancel'
  out=$(ibash "$P" ". '$PROFILE'" '@commands' 'echo "RES:after=$?"')
  has "@commands cancel returns 0" "$out" "RES:after=0"

  # the key binding fills READLINE_LINE via the function (call it directly)
  setup
  qc clear <<< yes >/dev/null; qc save "echo filled" >/dev/null
  plan 'print:echo filled'
  out=$(ibash "$P" ". '$PROFILE'" 'READLINE_LINE=x; _quickcommands_fill_readline; echo "RES:line=$READLINE_LINE pt=$READLINE_POINT"')
  has "fill_readline sets READLINE_LINE" "$out" "RES:line=echo filled pt=11"

  # missing fzf / quickcommands: nothing bound, nothing printed
  setup
  mkdir -p "$T/nofzf"
  ln -s "$(command -v bash)" "$T/nofzf/bash"; ln -s "$(command -v env)" "$T/nofzf/env"
  ln -s "$QC_BIN" "$T/nofzf/quickcommands"
  out=$(ibash "$T/nofzf" ". '$PROFILE'" 'b=$(bind -X); case $b in *quickcommands*) echo "RES:bound=1";; *) echo "RES:bound=0";; esac' 'echo "RES:fn=$(type -t @commands)"')
  has "no fzf: nothing bound" "$out" "RES:bound=0"
  has "no fzf: no @commands" "$out" "RES:fn="
  hasnt "no fzf: no function defined" "$out" "RES:fn=function"
  hasnt "no fzf: no error output" "$out" "command not found"
  mkdir -p "$T/noqc"; ln -s "$(command -v bash)" "$T/noqc/bash"; ln -s "$(command -v env)" "$T/noqc/env"
  ln -s "$STUB_DIR/fzf" "$T/noqc/fzf"
  out=$(ibash "$T/noqc" ". '$PROFILE'" 'b=$(bind -X); case $b in *quickcommands*) echo "RES:bound=1";; *) echo "RES:bound=0";; esac')
  has "no quickcommands: nothing bound" "$out" "RES:bound=0"

  # bash in POSIX mode: no invalid function names, no errors
  setup
  out=$(printf '%s\n' ". '$PROFILE'" 'echo "RES:ok"' 'exit' | HOME="$HOME" TERM=dumb \
        script -qec "env PATH='$P' $BASH_BIN --posix --norc --noprofile -i" /dev/null 2>&1 | tr -d '\r')
  has "posix mode: sourcing finishes" "$out" "RES:ok"
  hasnt "posix mode: no 'not a valid identifier'" "$out" "valid identifier"
else
  SKIP=$((SKIP + 1)); printf 'SKIP: `script` not available, interactive profile.d tests skipped\n'
fi

# ------------------------------------------------------------ summary
printf '\n%d passed, %d failed, %d skipped\n' "$PASS" "$FAIL" "$SKIP"
[[ $FAIL -eq 0 ]]
