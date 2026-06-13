#!/usr/bin/env bash
# Dotfiles setup wizard.
#
# Interactively (or via flags) installs dependencies and stows the selected
# configs. For each component it:
#   - stows the config into ~/.config (with conflict handling)
#   - installs its system dependencies (apt packages, latest Neovim,
#     optional Nerd Font, ...)
#
# App-level plugin managers self-bootstrap from each config (tmux.conf clones
# TPM, init.lua clones lazy.nvim) on first launch, so they're not handled here.
#
# Usage:
#   ./install.sh                      # interactive wizard
#   ./install.sh --all -y             # install everything, auto-accept deps
#   ./install.sh --components "nvim tmux"
#   ./install.sh --no-stow            # install deps only, don't stow
#
# Flags:
#   --all                 select all components
#   -c, --components LIST  space/comma separated subset (nvim tmux i3 tmuxinator)
#   -y, --yes             auto-install all dependencies without per-package prompts
#   --font / --no-font    install / skip the Nerd Font without asking
#   --no-stow             skip the stow step (dependencies only)
#   -h, --help            show this help
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
. "$REPO/lib/common.sh"

ALL_COMPONENTS=(nvim tmux i3 tmuxinator)

# Print the header comment block (everything after the shebang up to the first
# non-comment line), stripping the leading "# ".
usage() { awk 'NR==1{next} /^#/{sub(/^# ?/,""); print; next} {exit}' "${BASH_SOURCE[0]}"; }

# --- arg parsing --------------------------------------------------------------

selected=()
do_stow=1
font_choice="ask" # ask|yes|no

while [ "$#" -gt 0 ]; do
  case "$1" in
    --all) selected=("${ALL_COMPONENTS[@]}") ;;
    -c | --components)
      shift
      IFS=', ' read -r -a selected <<<"${1:-}"
      ;;
    -y | --yes) export DOTFILES_AUTO_YES=1 ;;
    --font) font_choice="yes" ;;
    --no-font) font_choice="no" ;;
    --no-stow) do_stow=0 ;;
    -h | --help) usage; exit 0 ;;
    *) err "unknown option: $1"; usage; exit 1 ;;
  esac
  shift || true
done

# --- preflight ----------------------------------------------------------------

if ! has_cmd apt-get; then
  err "this wizard targets Debian/Ubuntu (apt-get not found)."
  err "install the dependencies manually, then run: stow ${ALL_COMPONENTS[*]}"
  exit 1
fi

# --- component selection ------------------------------------------------------

is_valid_component() {
  local c
  for c in "${ALL_COMPONENTS[@]}"; do [ "$c" = "$1" ] && return 0; done
  return 1
}

if [ "${#selected[@]}" -eq 0 ]; then
  heading "Which configs do you want to set up?"
  echo "Available: ${ALL_COMPONENTS[*]}"
  if [ -t 0 ]; then
    read -r -p "Enter names (space separated) or 'all' [all]: " answer || true
    answer="${answer:-all}"
  else
    answer="all"
  fi
  if [ "$answer" = "all" ]; then
    selected=("${ALL_COMPONENTS[@]}")
  else
    IFS=', ' read -r -a selected <<<"$answer"
  fi
fi

# validate
for c in "${selected[@]}"; do
  if ! is_valid_component "$c"; then
    err "unknown component: $c (valid: ${ALL_COMPONENTS[*]})"
    exit 1
  fi
done
[ "${#selected[@]}" -gt 0 ] || { err "no components selected"; exit 1; }

info "selected: ${selected[*]}"

# --- cross-cutting questions --------------------------------------------------

if [ "${DOTFILES_AUTO_YES:-0}" != "1" ]; then
  heading "Dependency installation"
  if confirm "Auto-install all missing dependencies without asking per package?"; then
    export DOTFILES_AUTO_YES=1
  fi
fi

# Resolve the font choice once, only if i3 or nvim is selected.
wants_font() { printf '%s\n' "${selected[@]}" | grep -qxE 'i3|nvim'; }
if wants_font; then
  case "$font_choice" in
    yes) export DOTFILES_INSTALL_FONT=1 ;;
    no) export DOTFILES_INSTALL_FONT=0 ;;
    ask)
      heading "Nerd Font"
      if confirm "Install JetBrainsMono Nerd Font? (needed for the i3 bar and nvim icons; declining may show boxes/missing glyphs)"; then
        export DOTFILES_INSTALL_FONT=1
      else
        export DOTFILES_INSTALL_FONT=0
        warn "fonts skipped; some icons/glyphs may not render as intended"
      fi
      ;;
  esac
fi

# --- base dependencies --------------------------------------------------------

heading "Base tools"
apt_install_file "$REPO/packages.txt" || warn "base tools incomplete; stow/clone steps may fail"

# --- stow ---------------------------------------------------------------------

# stow_component NAME — link ~/.config/NAME from this repo, handling conflicts.
stow_component() {
  local name="$1" target="$HOME/.config/$name"

  if [ -L "$target" ]; then
    info "$name: already linked, restowing"
    stow -R -d "$REPO" -t "$HOME" "$name"
    return 0
  fi

  if [ -e "$target" ]; then
    local choice
    if [ "${DOTFILES_AUTO_YES:-0}" = "1" ] || [ ! -t 0 ]; then
      choice="b"
      warn "$name: ~/.config/$name exists; backing it up (auto)"
    else
      warn "$name: ~/.config/$name already exists."
      read -r -p "  [b]ackup / [a]dopt into repo / [o]verwrite / [s]kip? [b] " choice
      choice="${choice:-b}"
    fi
    case "$choice" in
      b | B)
        local bak="$target.bak.$(date +%Y%m%d%H%M%S)"
        mv "$target" "$bak"
        ok "$name: moved existing config to $bak"
        ;;
      a | A)
        info "$name: adopting existing files into the repo (stow --adopt)"
        stow --adopt -d "$REPO" -t "$HOME" "$name"
        warn "$name: repo working tree may now differ; review with 'git -C $REPO/$name status'"
        return 0
        ;;
      o | O)
        rm -rf "$target"
        ok "$name: removed existing config"
        ;;
      s | S | *)
        warn "$name: skipped stow (left existing config in place)"
        return 1
        ;;
    esac
  fi

  stow -d "$REPO" -t "$HOME" "$name"
  ok "$name: stowed to ~/.config/$name"
}

stowed=()
if [ "$do_stow" -eq 1 ]; then
  heading "Stowing configs"
  for c in "${selected[@]}"; do
    if stow_component "$c"; then
      stowed+=("$c")
    fi
  done
else
  info "skipping stow (--no-stow)"
fi

# --- per-component dependencies ----------------------------------------------

# install_component NAME — apt deps (from packages/NAME.txt) plus any extra
# setup that component needs (Neovim runtime, Nerd Font).
install_component() {
  local name="$1" pkgs="$REPO/packages/$name.txt"
  heading "$name: dependencies"
  apt_install_file "$pkgs" || warn "$name: some dependencies were not installed"

  case "$name" in
    nvim)
      heading "nvim: neovim runtime"
      ensure_neovim || warn "Neovim was not installed/updated; LazyVim needs >= ${NVIM_MIN_VERSION}"
      ;;
    i3)
      heading "i3: nerd font"
      if [ "${DOTFILES_INSTALL_FONT:-0}" = "1" ]; then
        ensure_nerd_font JetBrainsMono || warn "font install failed; glyphs may not render as intended"
      else
        warn "skipping font; the i3 bar uses 'JetBrainsMono Nerd Font' and may not render as intended"
      fi
      ;;
  esac
}

# add_path_to_bashrc edits ~/.bashrc in this process; detect via mtime.
bashrc_before=0
if [ -f "$HOME/.bashrc" ]; then bashrc_before="$(stat -c %Y "$HOME/.bashrc" 2>/dev/null || echo 0)"; fi

for c in "${selected[@]}"; do
  install_component "$c"
done

# --- summary ------------------------------------------------------------------

heading "Done"
echo "Components processed: ${selected[*]}"
if [ "${#stowed[@]}" -gt 0 ]; then echo "Stowed: ${stowed[*]}"; fi

bashrc_after=0
if [ -f "$HOME/.bashrc" ]; then bashrc_after="$(stat -c %Y "$HOME/.bashrc" 2>/dev/null || echo 0)"; fi
if [ "$bashrc_after" != "$bashrc_before" ]; then
  echo
  warn "~/.bashrc was updated (Neovim PATH). Run:  source ~/.bashrc   (or open a new shell)"
fi

if printf '%s\n' "${selected[@]}" | grep -qx nvim; then
  echo "- nvim: plugins install automatically on first 'nvim' launch."
fi
if printf '%s\n' "${selected[@]}" | grep -qx tmux; then
  echo "- tmux: TPM and plugins install automatically on first 'tmux' launch."
fi
