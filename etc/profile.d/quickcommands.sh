# quickcommands: shortcut key + @commands helper.
# Sourced by bash (and installed in /etc/profile.d, which any POSIX shell may
# read), so the guards below use only POSIX syntax. Everything after them is
# bash-only.
[ -n "${BASH_VERSION:-}" ] || return 0 2>/dev/null || exit 0
case $- in *i*) ;; *) return 0 2>/dev/null || exit 0 ;; esac

# An alias from older versions would break the function definitions below.
unalias @commands @saved 2>/dev/null

if command -v quickcommands >/dev/null 2>&1 \
   && command -v fzf >/dev/null 2>&1 \
   && ! shopt -oq posix; then

  # Read the key: QUICKCOMMANDS_KEY, else the KEY= line of the config file
  # (parsed as text, never executed), else the default Ctrl+Q.
  _quickcommands_key() {
    local key="${QUICKCOMMANDS_KEY:-}" cfg line
    local re='^(\\C-[a-zA-Z]|\\e[a-z0-9])$'
    if [ -z "$key" ]; then
      cfg="${XDG_CONFIG_HOME:-$HOME/.config}/quickcommands/config"
      if [ -r "$cfg" ]; then
        while IFS= read -r line || [ -n "$line" ]; do
          case $line in KEY=*) key=${line#KEY=}; break ;; esac
        done < "$cfg"
      fi
    fi
    [[ $key =~ $re ]] || key='\C-q'
    # Keys that would break the terminal or shell fall back to the default.
    case $key in
      '\C-'[cCdDzZsSmMjJiIhH]) key='\C-q' ;;
    esac
    printf '%s' "$key"
  }

  # Called by the key binding: pick a command and put it on the command line.
  _quickcommands_fill_readline() {
    local sel
    sel=$(quickcommands pick) || return 0
    [ -n "$sel" ] || return 0
    READLINE_LINE=$sel
    READLINE_POINT=${#READLINE_LINE}
  }

  # Typed command: pick one, it goes into history so Up brings it back.
  @commands() {
    local sel
    sel=$(quickcommands pick) || return 0
    [ -n "$sel" ] || return 0
    history -s -- "$sel"
    printf '%s\n' "$sel"
  }

  @saved() { @commands "$@"; }

  _quickcommands_bind() {
    local key
    key=$(_quickcommands_key)
    # Ctrl+Q is XON in terminal flow control and would be swallowed.
    [ -t 0 ] && stty -ixon 2>/dev/null
    bind -x "\"$key\": _quickcommands_fill_readline" 2>/dev/null
  }
  _quickcommands_bind
  unset -f _quickcommands_bind
fi
