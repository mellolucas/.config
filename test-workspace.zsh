#!/usr/bin/env zsh
# Exercise only the terminal query, never the AppleScript launcher.
emulate -LR zsh
setopt errexit pipefail

repo=${0:A:h}
if [[ ${1:-} == --child ]]; then
  mode=$2
  code=$(<"$repo/zsh/functions/workspace")
  [[ $code == *'local width=0 height=0'*$'\nlocal output'* ]] || exit 1
  code="local width=0 height=0${${code#*'local width=0 height=0'}%%$'\nlocal output'*}"
  functions[query]="$code"$'\nprint -r -- "RESULT:$width:$height"'
  export TERM_PROGRAM=ghostty
  [[ $mode != other-terminal ]] || TERM_PROGRAM=other
  # Normalize macOS's transient PENDIN bit before comparing saved settings.
  stty echo echonl -icanon < /dev/tty
  [[ $mode == noncanonical ]] || stty icanon < /dev/tty
  [[ $mode != echo-off ]] || stty -echo -echonl < /dev/tty
  before=$(stty -g < /dev/tty)
  trap ':' INT
  # Force the terminal response into the write/read scheduling window.
  printf() {
    builtin printf "$@"
    sleep 0.1
    [[ $mode != write-error ]]
  }
  if [[ $mode == read-error ]]; then
    read() { return 1; }
  fi
  if [[ $mode == (HUP|TERM) ]]; then
    zmodload zsh/system
    read() { kill -s "$mode" "$sysparams[pid]"; return 1; }
  fi
  if [[ $mode == setup-error ]]; then
    stty() {
      command stty "$@"
      [[ $1 != -echo ]]
    }
    # The production code uses command stty; intercept only in this fixture.
    functions[query]=${functions[query]//'command stty'/'stty'}
  fi
  print -r -- READY
  if [[ $mode == non-tty ]]; then
    query < /dev/null
  else
    query
  fi
  after=$(stty -g < /dev/tty)
  [[ $after == $before ]] || print -r -- "STATE_CHANGED:$before:$after"
  if [[ $mode == queued ]]; then
    IFS= read -r queued < /dev/tty
    print -r -- "QUEUED:$queued"
  fi
  print -r -- FINISHED
  exit
fi

zmodload zsh/zpty
typeset -F SECONDS=0
trap 'zpty -d 2>/dev/null || true' EXIT
trap 'exit 1' HUP INT TERM

fail() { print -r -u2 -- "FAIL: $*"; exit 1; }
wait_for() {
  local expected=$1 chunk
  local -F deadline=$(( SECONDS + 4 ))
  until [[ $transcript == *$expected* ]]; do
    if zpty -r terminal chunk; then
      transcript+=$chunk
    else
      (( SECONDS < deadline )) || fail "timeout waiting for ${(qqq)expected}: ${(qqq)transcript}"
      sleep 0.01
    fi
  done
}

for mode in valid noncanonical echo-off queued fragmented leading-zero wrong-code junk zero oversized \
    incomplete multibyte timeout slow length setup-error write-error read-error interrupt HUP TERM \
    other-terminal non-tty; do
  transcript=''
  expected=0:0
  zpty -b terminal zsh -f "$0" --child "$mode"
  if [[ $mode == (setup-error|other-terminal|non-tty) ]]; then
    wait_for READY
  else
    wait_for $'\e[14t'
  fi
  started=$SECONDS
  case $mode in
    valid|noncanonical|echo-off|queued)
      response=$'\e[4;884;2552t'
      [[ $mode != queued ]] || response+=$'typed input\n'
      zpty -w -n terminal "$response"
      expected=2552:884 ;;
    fragmented)
      for response in $'\e[' '4;884;' '2552t'; do
        zpty -w -n terminal "$response"
        sleep 0.05
      done
      expected=2552:884 ;;
    leading-zero)
      zpty -w -n terminal $'\e[4;000884;002552t'
      expected=2552:884 ;;
    wrong-code) zpty -w -n terminal $'\e[8;884;2552t' ;;
    junk) zpty -w -n terminal 'junk4;884;2552t' ;;
    zero) zpty -w -n terminal $'\e[4;0;2552t' ;;
    oversized) zpty -w -n terminal $'\e[4;1234567;2552t' ;;
    incomplete) zpty -w -n terminal $'\e[4;884;' ;;
    multibyte) zpty -w -n terminal $'\xc3' ;;
    slow)
      for response in $'\e' '[' '4' ';' '8' '8'; do
        zpty -w -n terminal "$response"
        sleep 0.15
      done ;;
    length) zpty -w -n terminal "${(l:32::x:)}" ;;
    interrupt) sleep 0.2; zpty -w -n terminal $'\x03' ;;
  esac
  wait_for FINISHED
  (( SECONDS - started < 1.5 )) || fail "$mode: exceeded total deadline"
  [[ $transcript == *RESULT:$expected* ]] || fail "$mode dimensions: ${(qqq)transcript}"
  [[ $transcript != *'4;884;2552t'* ]] || fail "$mode response echoed: ${(qqq)transcript}"
  [[ $transcript != *STATE_CHANGED* ]] || fail "$mode terminal state: ${(qqq)transcript}"
  if [[ $mode == (setup-error|other-terminal|non-tty) ]]; then
    [[ $transcript != *$'\e[14t'* ]] || fail "$mode: unexpected query"
  fi
  [[ $mode != queued || $transcript == *'QUEUED:typed input'* ]] || fail 'queued input lost'
  if [[ $mode == length ]]; then
    (( SECONDS - started < 0.75 )) || fail 'length limit waited for timeout'
  fi
  zpty -d terminal
  print -r -- "ok: $mode"
done
