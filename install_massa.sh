#!/bin/bash

set -uo pipefail

log() {
  printf "%s\n" "$@" >> "$logfile"
}

# Initialize the terminal to use the alternate screen
init_altscreen() {
  data="$(mktemp -d)"
  logfile="$data/log"
  touch "$logfile"
  log "init_altscreen"
  # switch to the alternate screen
  declare -g _stty
  _stty="$(stty -g < /dev/tty)"
  stty -echo < /dev/tty
  tput smcup
  # hide the cursor
  tput civis
}

drop_altscreen() {
  log "drop_altscreen"
  stty "$_stty" < /dev/tty
  # switch back to the normal screen
  tput rmcup
  # show the cursor
  tput cnorm
  echo "Logs:"
  cat "$logfile"
  rm -rf "$data"
}

waitrawkey() {
  log "waitrawkey"
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
  log "key: ${acc@Q}"
}

waitkey() {
  log "waitkey"
  waitrawkey key
  case $key in
    $'\E[A') key="UP" ;;
    $'\E[B') key="DOWN" ;;
    $'\E') key="ESC" ;;
    $'\n') key="ENTER" ;;
  esac
  log "key: $key"
}

get_cursor_pos() {
  log "get_cursor_pos"
  IFS=';' read -sdrR -p $'\E[6n' ROW COL
  echo "${ROW#*[}" "${COL}"
}

draw_line() {
  log "draw_line $*"
  if [ "$1" -lt 0 ]; then
    local row="$(($(tput lines) + $1))"
    tput cup "$row" 0
  else
    tput cup "$1" 0
  fi
  printf "%s" "$2"
}

resize_menu() {
  log "resize_menu"
  clear
  menu_loop
}

run_menu() {
  log "run_menu"
  clear
  init_menu
  menu_loop
}

shadow=$'\033[1;30m'
reset=$'\033[0m'
init_menu() {
  log "init_menu"
  declare -g pos=0
  declare -g -a style=("" "$shadow" "$shadow" "$shadow" "$shadow" "$shadow")
  declare -g -a boxes=(" " " " " " " " " " " ")
  declare -g prev_pos=0
  draw_line 0 "Welcome to the massa android installer!"
  draw_line 1 "What you would like to do?"
  draw_line -4 "↑/↓: move"
  draw_line -3 "SPACE: select"
  draw_line -2 "ENTER: confirm"
  draw_line -1 "ESC/q: cancel"
}

menu_loop() {
  log "menu_loop"
  while true; do 
    draw_line 3  "${style[0]} [${boxes[0]}] Install: [De]Select all$reset"
    draw_line 4  "${style[1]}   [${boxes[1]}] node$reset"
    draw_line 5  "${style[2]}   [${boxes[2]}] deweb client$reset"
    draw_line 6  "${style[3]} [${boxes[3]}] Uninstall: [De]Select all$reset"
    draw_line 7  "${style[4]}   [${boxes[4]}] Uninstall the node$reset"
    draw_line 8 "${style[5]}   [${boxes[5]}] Uninstall the deweb client$reset"
    waitkey
    case $key in
      "UP")
        prev_pos=$pos;
        pos=$((pos>0?pos-1:0))
        ;;
      "DOWN")
        prev_pos=$pos;
        pos=$((pos<5?pos+1:5))
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
          log "pos: $pos, sibling: $sibling"
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
    if [ "$prev_pos" -ne "$pos" ]; then
      style["$prev_pos"]="$shadow"
      style["$pos"]=""
    fi
  done
  log "selected:"
  on_exit
  [ "${boxes[1]}" = "X" ] && install_node
  [ "${boxes[2]}" = "X" ] && install_deweb
  [ "${boxes[4]}" = "X" ] && uninstall_node
  [ "${boxes[5]}" = "X" ] && uninstall_deweb
}

on_exit() {
  log "on_exit"
  drop_altscreen
  trap - EXIT
}

on_start() {
  trap on_exit EXIT
  init_altscreen
  run_menu
}

install_node() {
  echo "installing node"
}

uninstall_node() {
  echo "uninstalling node"
}

install_deweb() {
  echo "installing deweb"
}

uninstall_deweb() {
  echo "uninstalling deweb"
}

on_start
