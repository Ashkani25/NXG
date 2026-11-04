#!/usr/bin/env bash
# Run AFTER `npx cap add android`. Locks WebView text zoom to 100% so big system fonts don't break the layout.
set -e
F=$(find android/app/src/main/java -name MainActivity.java | head -1)
[ -z "$F" ] && { echo "MainActivity.java not found"; exit 1; }
grep -q setTextZoom "$F" && { echo "already patched"; exit 0; }
python3 - "$F" <<'PY'
import sys,re
p=sys.argv[1];s=open(p).read()
s=s.replace("public class MainActivity extends BridgeActivity {","public class MainActivity extends BridgeActivity {\n    @Override\n    public void onStart() {\n        super.onStart();\n        if (getBridge()!=null && getBridge().getWebView()!=null) getBridge().getWebView().getSettings().setTextZoom(100);\n    }\n",1)
open(p,'w').write(s)
PY
echo patched $F
