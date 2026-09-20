#!/bin/bash
# prove1.sh <model> <prop> [timeout-seconds]
# Selects one psgen property out of build/<model>.aig and proves it with rIC3.
#
# RESULTS ARE TAGGED BY MODEL.  /tmp/proof is shared scratch and several agents
# have written into it against different models; an untagged
# /tmp/proof/core-<Prop>.res cannot be traced back to the model that produced
# it, and a later run silently overwrites an earlier one.  The tag is the
# model's own AIGER header -- L (latches), B (bad states), C (constraints) --
# which changes exactly when the model does.  A convenience symlink
# /tmp/proof/<model>-latest points at the current tag's directory.
cd /opt/verif/h3formal
M=$1; P=$2; TO=${3:-1800}
TAG=$(head -c 80 build/$M.aig | head -1 | awk '{print "L"$4"-B"$7"-C"$8}')
OUT=${PROOF_OUT:-/opt/verif/h3formal/results}/$M-$TAG
mkdir -p build/sel "$OUT"
ln -sfn "$OUT" /tmp/proof/$M-latest
S=build/sel/$M-$P.aig
build/aig-manip build/$M.aig select $S build/$M.ywmap 0 $P > $OUT/$P.sel 2>&1
rm -f $OUT/$P.time
/usr/bin/time -f "TIMEMEM %e %M %P" -o $OUT/$P.time timeout $TO rIC3 $S > $OUT/$P.log 2>&1
RC=$?
case $RC in
  20) V=PROVED ;;
  10) V=CEX ;;
  124) V=TIMEOUT ;;
  *)  V="rc=$RC" ;;
esac
echo "$V $(grep TIMEMEM $OUT/$P.time)" > $OUT/$P.res
echo "$M[$TAG] $P $V"
