#!/bin/bash
# usage: run_gm_test.sh test.sql   -> runs all games migrations + test inside one transaction, always rolled back.
# The test's DO block should end with: raise exception 'RESULT %', <json>;  (that also forces the rollback)
D=/workspace/work/nexora/supabase
F=$(mktemp)
{ echo "begin;";
  for m in $D/migrations/2026111210*.sql $D/migrations/2026111410*.sql; do cat "$m"; echo; done
  cat "$1"; echo; echo "rollback;"; } > $F
bash /workspace/work/q.sh -f $F | python3 -c "import json,sys; d=sys.stdin.read();
try:
  j=json.loads(d)
  print(j.get('message', j) if isinstance(j, dict) else j)
except Exception: print(d[:4000])"
rm -f $F
