# dotfiles

Personal dotfiles for **i3**, **tmux**, **nvim** (LazyVim) and **tmuxinator**,
managed with [GNU Stow](https://www.gnu.org/software/stow/). Each config lives
in its own git submodule.

## Quick start

```bash
git clone --recurse-submodules https://github.com/allvibesnocodes/dotfiles.git ~/dotfiles
cd ~/dotfiles
./install.sh
```

`install.sh` is an interactive wizard. It asks which configs you want, whether
to auto-install missing dependencies, and whether to install the Nerd Font,
then it stows the configs and installs everything needed:

- **nvim** — installs the latest stable Neovim from the official release into
  `/opt`, adds it to `PATH` in `~/.bashrc`, and installs build tools, ripgrep,
  fd, etc. (LazyVim needs a newer Neovim than apt ships).
- **tmux** — installs tmux + xclip. [TPM](https://github.com/tmux-plugins/tpm)
  and the plugins self-install from `tmux.conf` on first `tmux` launch.
- **i3** — installs i3, feh, kitty, flameshot and friends, plus an optional
  Nerd Font for the bar.
- **tmuxinator** — installs tmuxinator (and its Ruby runtime).

If a config already exists in `~/.config`, the wizard asks whether to back it
up, adopt it into the repo, overwrite it, or skip it.

### Non-interactive / flags

```bash
./install.sh --all -y            # everything, auto-accept all dependency installs
./install.sh -c "nvim tmux"      # only these components
./install.sh --no-stow           # install dependencies only, don't stow
./install.sh --no-font           # don't install the Nerd Font
./install.sh --help              # full flag list
```

After an nvim install, run `source ~/.bashrc` (or open a new shell) so the new
Neovim is on your `PATH`. Plugins install on first launch — both nvim (LazyVim)
and tmux (TPM) bootstrap their plugin managers automatically the first time you
start them.

## Layout

System-level setup (apt packages, the Neovim binary, Nerd Fonts) lives in the
parent repo. App-level plugin managers (TPM, lazy.nvim) self-bootstrap from each
component's own config on first launch, so nothing extra leaks into `~/.config`
when stowed.

```
install.sh          # the wizard
lib/common.sh       # shared helpers + per-component install steps
packages.txt        # apt packages for the wizard itself (stow, git, ...)
packages/<name>.txt # apt packages per component (nvim, tmux, i3, tmuxinator)
```

To install a single component without the wizard:

```bash
./install.sh -c nvim          # deps + Neovim + stow, just for nvim
./install.sh -c nvim --no-stow # deps only
```

## Stow cheatsheet

```bash
stow nvim          # link ~/.config/nvim
stow -D nvim       # unlink
stow -R nvim       # restow after changes
stow nvim tmux i3 tmuxinator
```

## Update submodules

```bash
git submodule update --remote --merge                       # all
git submodule update --remote --merge nvim/.config/nvim      # one
```
