<p align="center">
  <img src="docs/assets/logo.svg" alt="quickcommands logo" width="96" height="96" />
</p>

# <p align="center">quickcommands</p>

<p align="center"><strong>Save your favourite terminal commands and bring them back with one shortcut key.</strong></p>

<p align="center">
  <a href="LICENSE"><img src="https://img.shields.io/github/license/arifislam-me/quickcommands?style=for-the-badge&label=License" alt="License" /></a>
  <a href="https://github.com/arifislam-me/quickcommands/releases/latest"><img src="https://img.shields.io/github/v/release/arifislam-me/quickcommands?style=for-the-badge&label=Release" alt="Latest release" /></a>
  <img src="https://img.shields.io/badge/platform-Ubuntu%20%7C%20Debian-lightgrey?style=for-the-badge" alt="Platform: Ubuntu and Debian" />
  <img src="https://img.shields.io/badge/shell-bash-4EAA25?style=for-the-badge" alt="Shell: bash" />
</p>

Never retype that long command again. Press `Ctrl+Q`, type a few letters, and pick a saved command from a fast [fzf](https://github.com/junegunn/fzf) menu. The command lands on your command line. You press `Enter` to run it.

## Features

- 🔍 Fuzzy search: type a few letters, find your command.
- ⌨️ One key opens the menu (`Ctrl+Q` by default, and you can change it).
- 🕰️ `Ctrl+R` is not touched. It stays the normal bash history search.
- 🔒 Commands live in `~/.saved_commands`, readable only by you. Do not save secrets there.

## Install

> [!NOTE]
> You need Ubuntu or Debian with **bash**. Zsh and fish are not supported.

```bash
curl -LO https://github.com/arifislam-me/quickcommands/releases/latest/download/quickcommands.deb
```

```bash
sudo apt install ./quickcommands.deb
```

Use `apt install`, not `dpkg -i`. Only `apt` fetches `fzf` for you.

**Open a new terminal after installing.** An old terminal does not know the new key. To use it right now, run `exec bash` in the old one.

## Use it

Press `Ctrl+Q` in a bash terminal.

| Key | What it does |
|---|---|
| `Up` / `Down` | Move through your commands |
| `Enter` | Put the selected command on the command line |
| `Ctrl+S` | Save the text you typed in the menu |
| `Ctrl+D` | Delete the selected command (asks first) |
| `Esc` | Close the menu |

**Quick example:** press `Ctrl+Q`, type `git status`, press `Ctrl+S` to save it. Next time, press `Ctrl+Q`, type `gits`, press `Enter`.

You can also use the command line:

```bash
quickcommands save "git status"
quickcommands list
quickcommands run 2
quickcommands help
```

## Change the key

```bash
quickcommands key set ctrl-g    # or alt-x
quickcommands key reset         # back to Ctrl+Q
```

The new key works in **new terminals**. Keys that would break your terminal (like `Ctrl+C` or `Ctrl+D`) are refused.

> [!NOTE]
> `Ctrl+Q` is normally swallowed by the terminal (XON flow control). quickcommands runs `stty -ixon` in interactive terminals so the key reaches bash.

## Development

```bash
bash tests/run.sh   # run the tests
./build.sh          # check, test, build dist/quickcommands.deb
```

Releases are automatic: push a tag like `v1.0.0` and GitHub builds and publishes the `.deb` (see [release.yml](.github/workflows/release.yml)). Found a bug? [Open an issue](https://github.com/arifislam-me/quickcommands/issues).

## Uninstall

```bash
sudo apt remove quickcommands
```

Your saved commands stay. To delete them too: `rm ~/.saved_commands`

## Author

**Arif Islam** · [arifislam.me](https://arifislam.me) · [@arifislam-me](https://github.com/arifislam-me)

## License

MIT. See the [LICENSE](LICENSE) file.
