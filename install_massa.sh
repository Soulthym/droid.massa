#!/bin/bash

set -euo pipefail

scan_installed_dependencies() {
  declare -a -g missing_termux_deps=()
  declare -g has_proot_distro=false
  declare -g has_node=false
  declare -g has_deweb=false
  if ! pkg list-installed proot-distro 2>/dev/null | grep -q "proot-distro"; then
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
  proot-distro login "$proot_distro_rootfs" -- bash -c "${@@Q}"
}

log() {
  printf "%s\n" "$@" >> "$logtmp"
  if ! "$alt_screen"; then
    printf "%s\n" "$@"
  fi
}

# Initialize the terminal to use the alternate screen
init_altscreen() {
  set +e
  [ ! -f "$logfile" ] && touch "$logfile"
  [ ! -f "$logtmp" ] && touch "$logtmp"
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
  echo "Logs:"
  cat "$logtmp"
  printf "[%s]\n" "$start_time" >> "$logfile"
  cat "$logtmp" >> "$logfile"
  rm "$logtmp"
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

get_cursor_pos() {
  IFS=';' read -sdrR -p $'\E[6n' ROW COL
  echo "${ROW#*[}" "${COL}"
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
      "UP")
        style["$pos"]="$shadow"
        pos=$((pos>0?pos-1:0))
        style["$pos"]=""
        ;;
      "DOWN")
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
  drop_altscreen
  [ "${boxes[1]}" = "X" ] && install_node
  [ "${boxes[2]}" = "X" ] && install_deweb
  [ "${boxes[4]}" = "X" ] && uninstall_node
  [ "${boxes[5]}" = "X" ] && uninstall_deweb
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
  pkg install "${missing_termux_deps[@]@Q}"
  missing_termux_deps=()
}

install_proot_distro() {
  log "installing proot-distro"
  log "${#missing_termux_deps[@]}"
  if [ "${#missing_termux_deps[@]}" -gt 0 ]; then
    install_proot_distro_deps
  fi
  log "checking proot-distro vm"
  log "$has_proot_distro"
  if ! $has_proot_distro; then
    log "installing proot-distro vm"
    proot-distro install --override-alias droid.massa ubuntu-oldlts
    log "updating proot-distro vm"
    run_in_proot_distro "apt update && apt upgrade -y"
  fi
}

install_node() {
  log "installing node"
  install_proot_distro
}

uninstall_node() {
  log "uninstalling node"
}

install_deweb() {
  log "installing deweb"
}

uninstall_deweb() {
  log "uninstalling deweb"
}

data="$HOME/.config/droid.massa"

logfile="$data/log"
start_time="$(date)"
logtmp="$data/log$(date +%s)"

[ ! -d "$data" ] && mkdir -p "$data"
vm_name="droid.massa"
proot_distro_rootfs="$PREFIX/var/lib/proot-distro/installed-rootfs/$vm_name"
proot_distro_shared="$HOME/.virtual/proot-distro/$vm_name"
[ ! -d "$proot_distro_shared" ] && mkdir -p "$proot_distro_shared"
node_path="$proot_distro_shared/node"
deweb_path="$proot_distro_shared/deweb"
declare -g alt_screen=false

scan_installed_dependencies

start
