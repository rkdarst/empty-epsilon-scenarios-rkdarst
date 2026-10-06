#!/bin/sh
# One-time: extract the pure-Python PyYAML package into vendor/pylibs so
# tools/dsl_check.py runs on hosts without pip/python3-yaml (same no-root
# pattern as get_deps.sh). Uses stdlib urllib only.
set -eu
cd "$(dirname "$0")/.."
mkdir -p vendor/pylibs
python3 - <<'EOF'
import json, urllib.request, tarfile, io, os
j = json.load(urllib.request.urlopen("https://pypi.org/pypi/pyyaml/json"))
url = next(f["url"] for f in j["urls"] if f["packagetype"] == "sdist")
print("fetching", url)
t = tarfile.open(fileobj=io.BytesIO(urllib.request.urlopen(url).read()))
n = 0
for m in t.getmembers():
    if "/lib/yaml/" in m.name and m.isfile():
        p = os.path.join("vendor/pylibs", m.name.split("/lib/", 1)[1])
        os.makedirs(os.path.dirname(p), exist_ok=True)
        open(p, "wb").write(t.extractfile(m).read())
        n += 1
print(f"extracted {n} files -> vendor/pylibs")
EOF