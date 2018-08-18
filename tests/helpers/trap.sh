#!/usr/bin/env bash
#
# A test script that ignores SIGTERM.
# XXX: trapping SIGTERM does not appear to work on Windows/AppVeyor.
# (https://ci.appveyor.com/project/blueyed/neomake/build/job/15d8b5thbpdgpu0m#L279)

trap 'echo not stopping on SIGTERM' TERM

echo "SHELL: $SHELL"
echo "Started: $$"
c=0
while true; do
  c=$((c + 1))
  echo $c
  sleep .1
done
