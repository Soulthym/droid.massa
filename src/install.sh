#!/bin/bash
# MIT License
#
# Copyright (c) 2024 Thybault Alabarbe
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

set -euo pipefail

scan_installed_dependencies() {
  declare -a -g missing_termux_deps=()
  declare -g has_proot_distro=false
  declare -g has_node=false
  declare -g has_deweb=false
  if ! pkg list-installed tput 2>/dev/null | grep --silent "tput"; then
    pkg install -y ncurses-utils
  fi
  if ! pkg list-installed proot-distro 2>/dev/null | grep --silent "proot-distro"; then
    missing_termux_deps+=("proot-distro")
  fi
  if [ -d "$proot_distro_rootfs" ]; then
    has_proot_distro=true
  fi
  if [ -d "$node_path" ]; then
    has_node=true
  fi
  if [ -d "$deweb_path" ]; then
    has_deweb=true
  fi
}

run_in_proot_distro() {
  cmd="${1}"
  proot-distro login "$vm_name" -- bash -c "$cmd"
}

log() {
  if "$alt_screen"; then
    printf "%s\n" "$@" >> "$logfile"
  else
    printf "%s\n" "$@" >&2
  fi
}

# Initialize the terminal to use the alternate screen
init_altscreen() {
  set +e
  logfile="$tmp/log"

  [ ! -f "$logfile" ] && touch "$logfile"
  # switch to the alternate screen
  declare -g _stty
  _stty="$(stty -g < /dev/tty)"
  stty -echo < /dev/tty
  tput smcup
  # hide the cursor
  tput civis
  alt_screen=true
}

drop_altscreen() {
  stty "$_stty" < /dev/tty
  # switch back to the normal screen
  tput rmcup
  # show the cursor
  tput cnorm
  set -e
  if [ -s "$logfile" ]; then
    echo "Logs:"
    cat "$logfile"
  fi
  rm -f "$logfile"
  alt_screen=false
}

waitrawkey() {
  keyvar=${1:-menu_key}
  acc=""
  while true; do
    read -srN1 -t 0.1 2>/dev/null
    if [[ -z "$REPLY" ]]; then
      if [[ -n "$acc" ]]; then
        break
      fi
    else
      acc+="$REPLY"
      if [[ "$acc" = $'\177' ]]; then
        break
      fi
    fi
  done
  declare -g "$keyvar=$acc"
}

waitkey() {
  waitrawkey key
  case $key in
    $'\E[A') key="UP" ;;
    $'\E[B') key="DOWN" ;;
    $'\E') key="ESC" ;;
    $'\n') key="ENTER" ;;
  esac
}

draw_line() {
  if [ "$1" -lt 0 ]; then
    local row="$(($(tput lines) + $1))"
    tput cup "$row" 0
  else
    tput cup "$1" 0
  fi
  printf "%s" "$2"
}

resize_menu() {
  clear
  menu_loop
}

run_menu() {
  clear
  init_menu
  menu_loop
}

shadow=$'\033[1;30m'
reset=$'\033[0m'

make_styles() {
  size="$1"
  declare -g -a style=("")
  for _ in $(seq 1 "$size"); do
    style+=("$shadow")
  done
  style["$pos"]=""
}

make_boxes() {
  size="$1"
  declare -g -a boxes=()
  for _ in $(seq 1 "$size"); do
    boxes+=(" ")
  done
}

init_menu() {
  declare -g pos=0
  make_styles 6
  make_boxes 6
  draw_line 0 "Welcome to the massa android installer!"
  draw_line 1 "What you would like to do?"
  draw_line -4 "↑/↓: move"
  draw_line -3 "SPACE: select"
  draw_line -2 "ENTER: confirm"
  draw_line -1 "ESC/q: cancel"
}

menu_loop() {
  while true; do
    draw_line 3  "${style[0]} [${boxes[0]}] Install: [De]Select all$reset"
    draw_line 4  "${style[1]}   [${boxes[1]}] node$reset"
    draw_line 5  "${style[2]}   [${boxes[2]}] deweb client$reset"
    draw_line 6  "${style[3]} [${boxes[3]}] Uninstall: [De]Select all$reset"
    draw_line 7  "${style[4]}   [${boxes[4]}] Uninstall the node$reset"
    draw_line 8  "${style[5]}   [${boxes[5]}] Uninstall the deweb client$reset"
    waitkey
    case $key in
      "UP"|"k")
        style["$pos"]="$shadow"
        pos=$((pos>0?pos-1:0))
        style["$pos"]=""
        ;;
      "DOWN"|"j")
        style["$pos"]="$shadow"
        pos=$((pos<5?pos+1:5))
        style["$pos"]=""
        ;;
      " ")
        if [ "${boxes[$pos]}" = " " ]; then
          box="X"
          notbox=" "
        else
          box=" "
          notbox="X"
        fi
        if [ "$pos" -eq 0 ]; then
          # select 0-2
          boxes[0]="$box"
          boxes[1]="$box"
          boxes[2]="$box"
          if [ "$box" = "X" ]; then # only when selecting
            # deselect 3-5
            boxes[3]="$notbox"
            boxes[4]="$notbox"
            boxes[5]="$notbox"
          fi
        elif [ "$pos" -eq 3 ]; then
          if [ "$box" = "X" ]; then
            boxes[0]="$notbox"
            boxes[1]="$notbox"
            boxes[2]="$notbox"
          fi
          boxes[3]="$box"
          boxes[4]="$box"
          boxes[5]="$box"
        else
          boxes["$pos"]="$box"
          sibling=$(((pos+3) % 6))
          if [ "$box" = "X" ]; then
            boxes["$sibling"]=" "
          fi
          if [ "${boxes[1]}" = "X" ] && [ "${boxes[2]}" = "X" ]; then
            boxes[0]="X"
          else
            boxes[0]=" "
          fi
          if [ "${boxes[4]}" = "X" ] && [ "${boxes[5]}" = "X" ]; then
            boxes[3]="X"
          else
            boxes[3]=" "
          fi
        fi
        ;;
      "ENTER") break ;;
      "ESC"|"q") exit ;;
    esac
  done
  on_exit
  declare -g -a instructions=()
  [ "${boxes[1]}" = "X" ] && install_node
  [ "${boxes[2]}" = "X" ] && install_deweb
  [ "${boxes[4]}" = "X" ] && uninstall_node
  [ "${boxes[5]}" = "X" ] && uninstall_deweb
  if [ "${boxes[1]}" = "X" ] || [ "${boxes[2]}" = "X" ]; then
    log "Installation complete"
    log
    log "Tutorial:"
    for instruction in "${instructions[@]}"; do
      echo "$instruction"
    done
  fi
}

on_exit() {
  drop_altscreen
  trap - EXIT
}

start() {
  trap on_exit EXIT
  init_altscreen
  run_menu
}

install_proot_distro_deps() {
  log "installing proot-distro dependencies"
  pkg update
  pkg install -y "${missing_termux_deps[@]}"
  missing_termux_deps=()
}

install_proot_distro() {
  log "installing proot-distro"
  if [ "${#missing_termux_deps[@]}" -gt 0 ]; then
    install_proot_distro_deps
  fi
  if ! $has_proot_distro; then
    log "installing proot-distro vm"
    proot-distro install --override-alias droid.massa ubuntu-oldlts
    log "updating proot-distro vm"
    run_in_proot_distro "apt update && apt upgrade -y"
  fi
}

resolve_latest_release() {
  project="$1"
  prefix="$2"
  curl --location --silent\
    --header "Accept: application/vnd.github+json" \
    --header "X-GitHub-Api-Version: 2022-11-28" \
    "https://api.github.com/repos/massalabs/$project/releases"\
    | sed --silent "/linux_arm64/{s/^.*\\(${prefix}[0-9]\\+\\(\\.[0-9]\\+\\)\\+\\).*$/\\1/p}" \
    | sort --version-sort --unique \
    | tail --lines=1
}

make_proot_distro_command() {
  shared=""
  home="/root"
  for termux_path in "$proot_distro_shared"/*; do
    proot_path="$home/${termux_path##*/}"
    shared+="--bind $termux_path:$proot_path "
  done
  executable="$home${1##"$proot_distro_shared"}"
  printf "proot-distro login %s --bind ~:/termux %s -- bash -c %q" "${vm_name}" "$shared" "$executable"
}

marker_template="# managed by droid.massa: do not modify this line! @%s"

log_run_with() {
  $2 && already=" already" || already=""
  log "$1$already installed"
  instructions+=("$1$already installed")
  instructions+=("run it with the command: $1")
}

write_alias() {
  alias_name="$1"
  alias_command="$2"
  local marker
  eval "printf -v marker ${marker_template@Q} ${alias_name@Q}"
  if ! grep --quiet "$marker" "$HOME/.bashrc"; then
    echo "alias $alias_name=${alias_command@Q} $marker" >> "$HOME/.bashrc"
    source "$HOME/.bashrc"
    log_run_with "$alias_name" false
  else
    log_run_with "$alias_name" true
  fi
}

remove_alias() {
  alias_name="$1"
  local marker
  eval "printf -v marker ${marker_template@Q} ${alias_name@Q}"
  sed --in-place "/^alias $alias_name=.*$marker$/d" "$HOME/.bashrc"
}

install_node() {
  log "installing node"
  install_proot_distro
  if $has_node; then
    log_run_with "massa" true
    return
  fi
  log "fetching the latest node version"
  version="$(resolve_latest_release 'massa' 'MAIN\.')"
  if [ -z "$version" ]; then
    log "failed to get the latest node version"
    return
  fi
  file_name="massa_${version}_release_linux_arm64.tar.gz"
  file_url="https://github.com/massalabs/massa/releases/download/$version/$file_name"
  checksum_url="https://github.com/massalabs/massa/releases/download/$version/checksums.txt"
  checksum="$(curl --location --silent "$checksum_url" 2>/dev/null | grep "$file_name" | awk '{print $1}')"
  if [ -z "$checksum" ]; then
    log "failed to get the checksum for $file_name"
    return
  fi
  run_in_proot_distro "apt update && apt install -y tmux gcc"
  log "downloading $file_name"
  curl --location --silent --output "$tmp/$file_name" "$file_url"
  log "verifying the checksum"
  file_checksum="$(sha256sum "$tmp/$file_name" | awk '{print $1}')"
  if [ "$checksum" != "$file_checksum" ]; then
    log "checksum verification failed"
    log "expected: ${checksum@Q}"
    log "found: ${file_checksum@Q}"
    return
  fi
  log "checksum verification passed"
  log "installing node $version"
  mkdir -p "$proot_distro_shared"
  tar -xzf "$tmp/$file_name" -C "$proot_distro_shared"
  executable="$node_path/run-massa-node.sh"
  cat > "$executable" <<EOF
#!/bin/bash
cd $node_path_in_vm
tmux new-session -d -s massa
tmux send-keys -t massa 'cd massa-node' Enter
tmux send-keys -t massa './massa-node' Enter
tmux split-window -v -t massa
tmux send-keys -t massa 'cd massa-client' Enter
tmux send-keys -t massa './massa-client' Enter
tmux attach-session -t massa
EOF
  chmod +x "$executable"
  cmd="$(make_proot_distro_command "$executable")"
  write_alias "massa" "$cmd"
}

install_deweb() {
  log "installing deweb"
  install_proot_distro
  if $has_deweb; then
    log_run_with "deweb" true
    return
  fi
  log "fetching the latest deweb version"
  version="$(resolve_latest_release 'Deweb' 'v')"
  log "downloading Deweb $version"
  file_name="deweb-server_linux_arm64"
  file_url="https://github.com/massalabs/Deweb/releases/download/$version/$file_name"
  mkdir -p "$deweb_path"
  executable="$deweb_path/run-deweb.sh"
  curl --location --silent --output "$executable" "$file_url"
  log "installing Deweb $version"
  chmod +x "$executable"
  cmd="$(make_proot_distro_command "$executable")"
  write_alias "deweb" "$cmd"
}

uninstall_node() {
  log "uninstalling node"
  if ! $has_node; then
    log "node is not installed"
    remove_alias "massa"
    return
  fi
  log "This will delete all your node data."
  log "Make sure to backup your wallet before proceeding."
  log "Are you sure? [y/N]: "
  while true; do
    read -r key
    case $key in
      "y"|"Y")
        break
        ;;
      "n"|"N")
        return
        ;;
      *)
        log "Invalid input ${key@Q}. Are you sure? [y/n]: "
    esac
  done
  rm -rf "$node_path"
  remove_alias "massa"
  log "node uninstalled"
}

uninstall_deweb() {
  log "uninstalling deweb"
  remove_alias "deweb"
  if ! $has_deweb; then
    log "deweb is not installed"
    return
  fi
  rm -rf "$deweb_path"
  log "deweb uninstalled"
}

tmp="$(mktemp -d)"
vm_name="droid.massa"
proot_distro_rootfs="$PREFIX/var/lib/proot-distro/installed-rootfs/$vm_name"
proot_distro_shared="$HOME/.virtual/proot-distro/$vm_name"
[ ! -d "$proot_distro_shared" ] && mkdir -p "$proot_distro_shared"
node_path="$proot_distro_shared/massa"
node_path_in_vm=$'$HOME/massa'
deweb_path="$proot_distro_shared/deweb"
declare -g alt_screen=false

scan_installed_dependencies

start
