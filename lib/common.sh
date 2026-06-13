#!/usr/bin/env bash
# Shared helpers for the dotfiles install wizard (install.sh).
# The parent repo handles system-level setup (apt packages, the Neovim binary,
# Nerd Fonts). App-level plugin managers (TPM, lazy.nvim) self-bootstrap from
# each component's own config on first launch.

# Guard against being sourced twice.
[ -n "${DOTFILES_COMMON_SOURCED:-}" ] && return 0
DOTFILES_COMMON_SOURCED=1

# --- logging -----------------------------------------------------------------

if [ -t 1 ]; then
  _c_blue=$'\033[34m'; _c_yellow=$'\033[33m'; _c_red=$'\033[31m'
  _c_green=$'\033[32m'; _c_bold=$'\033[1m'; _c_reset=$'\033[0m'
else
  _c_blue=; _c_yellow=; _c_red=; _c_green=; _c_bold=; _c_reset=
fi

info()  { printf '%s==>%s %s\n' "$_c_blue"   "$_c_reset" "$*"; }
ok()    { printf '%s ok%s %s\n' "$_c_green"  "$_c_reset" "$*"; }
warn()  { printf '%swarn%s %s\n' "$_c_yellow" "$_c_reset" "$*" >&2; }
err()   { printf '%serr%s  %s\n' "$_c_red"    "$_c_reset" "$*" >&2; }
heading() { printf '\n%s%s%s\n' "$_c_bold" "$*" "$_c_reset"; }

# --- basics ------------------------------------------------------------------

has_cmd() { command -v "$1" >/dev/null 2>&1; }

# confirm "Question?"  -> 0 for yes, 1 for no.
# Honors DOTFILES_AUTO_YES=1 (yes without asking); defaults to no when stdin is
# not a terminal.
confirm() {
  local prompt="$1" reply
  [ "${DOTFILES_AUTO_YES:-0}" = "1" ] && return 0
  [ -t 0 ] || return 1
  read -r -p "$prompt [y/N] " reply
  case "$reply" in
    [yY] | [yY][eE][sS]) return 0 ;;
    *) return 1 ;;
  esac
}

# --- apt ----------------------------------------------------------------------

# apt_install pkg [pkg...] — install any packages not already present.
apt_install() {
  [ "$#" -gt 0 ] || return 0
  if ! has_cmd apt-get; then
    err "apt-get not found; install these manually: $*"
    return 1
  fi

  local pkg missing=()
  for pkg in "$@"; do
    dpkg -s "$pkg" >/dev/null 2>&1 || missing+=("$pkg")
  done

  if [ "${#missing[@]}" -eq 0 ]; then
    ok "apt packages already present: $*"
    return 0
  fi

  if ! confirm "Install apt packages: ${missing[*]}?"; then
    warn "skipped apt install: ${missing[*]}"
    return 1
  fi

  info "apt-get install: ${missing[*]}"
  sudo apt-get update -y && sudo apt-get install -y "${missing[@]}"
}

# apt_install_file FILE — install packages listed one-per-line in FILE,
# ignoring blank lines and # comments.
apt_install_file() {
  local file="$1" pkgs=() line
  [ -f "$file" ] || { warn "package list not found: $file"; return 0; }
  while IFS= read -r line; do
    line="${line%%#*}"
    line="$(echo "$line" | xargs)"
    [ -n "$line" ] && pkgs+=("$line")
  done <"$file"
  apt_install "${pkgs[@]}"
}

# --- PATH / bashrc ------------------------------------------------------------

# add_path_to_bashrc DIR — idempotent PATH export in ~/.bashrc + current shell.
add_path_to_bashrc() {
  local dir="$1" rc="$HOME/.bashrc"
  [ -n "$dir" ] || return 0
  case ":$PATH:" in *":$dir:"*) ;; *) export PATH="$PATH:$dir" ;; esac
  touch "$rc"
  if grep -qF "$dir" "$rc"; then
    ok "PATH already has $dir in ~/.bashrc"
    return 0
  fi
  info "adding $dir to PATH in ~/.bashrc"
  {
    printf '\n# nvim install (added by dotfiles install.sh)\n'
    printf 'export PATH="$PATH:%s"\n' "$dir"
  } >>"$rc"
}

# --- version comparison -------------------------------------------------------

# compare_version A B -> 0 if A >= B (dotted numeric versions).
compare_version() {
  [ "$1" = "$2" ] && return 0
  [ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | head -n1)" = "$2" ]
}

# --- neovim -------------------------------------------------------------------

NVIM_MIN_VERSION="${NVIM_MIN_VERSION:-0.10.0}"

nvim_arch() {
  case "$(uname -m)" in
    x86_64 | amd64) echo "x86_64" ;;
    aarch64 | arm64) echo "arm64" ;;
    *) echo "" ;;
  esac
}

# ensure_neovim — install latest stable Neovim into /opt unless an existing
# install already satisfies NVIM_MIN_VERSION.
ensure_neovim() {
  local current
  if has_cmd nvim; then
    current=$(nvim --version 2>/dev/null | head -n1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -n1 || true)
    if [ -n "$current" ] && compare_version "$current" "$NVIM_MIN_VERSION"; then
      ok "neovim $current already >= $NVIM_MIN_VERSION"
      return 0
    fi
    warn "neovim ${current:-unknown} is older than $NVIM_MIN_VERSION"
  else
    info "neovim not found"
  fi

  confirm "Install latest stable Neovim to /opt?" || {
    warn "skipped Neovim install; LazyVim needs >= $NVIM_MIN_VERSION"
    return 1
  }

  local arch; arch=$(nvim_arch)
  [ -n "$arch" ] || { err "unsupported architecture $(uname -m); install Neovim manually"; return 1; }

  local name="nvim-linux-${arch}"
  local url="https://github.com/neovim/neovim/releases/latest/download/${name}.tar.gz"
  local tmp; tmp=$(mktemp -d)

  info "downloading $url"
  if has_cmd curl; then
    curl -fL# "$url" -o "$tmp/$name.tar.gz" || { err "download failed"; rm -rf "$tmp"; return 1; }
  elif has_cmd wget; then
    wget -O "$tmp/$name.tar.gz" "$url" || { err "download failed"; rm -rf "$tmp"; return 1; }
  else
    err "need curl or wget to download Neovim"; rm -rf "$tmp"; return 1
  fi

  info "installing to /opt/$name (sudo)"
  sudo rm -rf "/opt/$name"
  sudo tar -C /opt -xzf "$tmp/$name.tar.gz"
  rm -rf "$tmp"

  add_path_to_bashrc "/opt/$name/bin"
  ok "neovim installed: $(/opt/$name/bin/nvim --version | head -n1)"
}

# --- nerd font ----------------------------------------------------------------

# ensure_nerd_font [name] — install a Nerd Font into ~/.local/share/fonts.
ensure_nerd_font() {
  local font="${1:-JetBrainsMono}" dest="$HOME/.local/share/fonts"
  if fc-list 2>/dev/null | grep -qi "${font}.*Nerd Font"; then
    ok "$font Nerd Font already installed"; return 0
  fi
  has_cmd unzip || apt_install unzip || { err "unzip required for font install"; return 1; }

  local url="https://github.com/ryanoasis/nerd-fonts/releases/latest/download/${font}.zip"
  local tmp; tmp=$(mktemp -d)
  info "downloading $font Nerd Font"
  if has_cmd curl; then
    curl -fL# "$url" -o "$tmp/$font.zip" || { err "font download failed"; rm -rf "$tmp"; return 1; }
  elif has_cmd wget; then
    wget -O "$tmp/$font.zip" "$url" || { err "font download failed"; rm -rf "$tmp"; return 1; }
  else
    err "need curl or wget to download fonts"; rm -rf "$tmp"; return 1
  fi

  mkdir -p "$dest"
  unzip -o "$tmp/$font.zip" -d "$dest/$font" >/dev/null
  rm -rf "$tmp"
  has_cmd fc-cache && fc-cache -f "$dest" >/dev/null 2>&1
  ok "$font Nerd Font installed to $dest/$font"
}
