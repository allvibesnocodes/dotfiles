# dotfiles

Managed with [GNU Stow](https://www.gnu.org/software/stow/).

## Setup

```bash
git clone --recurse-submodules git@github.com:allvibesnocodes/dotfiles.git ~/dotfiles
# backup if needed
rm -rf ~/.config/nvim ~/.config/tmux ~/.config/i3 ~/.config/tmuxinator
cd ~/dotfiles
stow nvim tmux i3 tmuxinator
```

## Common Commands

```bash
# Stow a tool
stow nvim

# Unstow a tool
stow -D nvim

# Restow a tool (after changes)
stow -R nvim

# Stow everything
stow nvim tmux i3 tmuxinator
```

## Update Submodules

```bash
# All
git submodule update --remote --merge

# One
git submodule update --remote --merge nvim/.config/nvim
```
