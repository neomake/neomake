#!/bin/sh
#
# A test script that ignores SIGTERM.

# XXX: does not work on Windows (Neovim, does not appear to trap).
# Started via "cmd.exe /s /c C:\projects\neomake\tests/helpers/trap.sh".
trap 'echo not stopping on SIGTERM' TERM
# trap 'echo stopping on SIGHUP; exit' HUP

echo "SHELL: $SHELL"
echo "Started: $$"
c=0
while true; do
  c=$((c + 1))
  echo $c
  sleep .1
done
