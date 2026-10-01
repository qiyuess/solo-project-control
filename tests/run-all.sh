#!/usr/bin/env bash
# 门禁自测：一套用例锁住 gate.ps1 与 gate-hook.ps1 的行为。
# 改过门禁 / hook 之后就跑一遍——它出 bug 时不会报错，只会给你假绿灯。
# 用法：bash tests/run-all.sh
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
FAILED=0
for t in gate-test.sh gate-test2.sh gate-test3.sh gate-test4.sh gate-test5.sh gate-test6.sh gate-test7.sh gate-test8.sh; do
  echo "########## $t ##########"
  bash "$HERE/$t" || FAILED=$((FAILED + 1))
done
echo
if [ "$FAILED" -eq 0 ]; then
  echo "=== 全部测试通过 ==="
else
  echo "=== $FAILED 个测试脚本未通过 ==="
fi
[ "$FAILED" -eq 0 ]
