#!/usr/bin/env bash
set -euo pipefail

SERVICE="max-tour-demo-v28"
TARGET="https://max-tour-demo.viiversion.com"
: "${CLOUDFLARE_API_TOKEN:?missing CLOUDFLARE_API_TOKEN}"
: "${CLOUDFLARE_ACCOUNT_ID:?missing CLOUDFLARE_ACCOUNT_ID}"

auth="Authorization: Bearer ${CLOUDFLARE_API_TOKEN}"
content_url="https://api.cloudflare.com/client/v4/accounts/${CLOUDFLARE_ACCOUNT_ID}/workers/services/${SERVICE}/environments/production/content"
settings_url="https://api.cloudflare.com/client/v4/accounts/${CLOUDFLARE_ACCOUNT_ID}/workers/services/${SERVICE}/environments/production/settings"
upload_url="https://api.cloudflare.com/client/v4/accounts/${CLOUDFLARE_ACCOUNT_ID}/workers/scripts/${SERVICE}"

curl -fsS -H "$auth" "$settings_url" -o /tmp/settings-before.json
jq -r '.result.bindings[]?.name' /tmp/settings-before.json | sort > /tmp/bindings-before.txt
curl -fsS -D /tmp/current.headers -H "$auth" "$content_url" -o /tmp/current.multipart

python - <<'PY'
from pathlib import Path
import re
h=Path('/tmp/current.headers').read_text(errors='replace')
b=Path('/tmp/current.multipart').read_bytes()
m=re.search(r'boundary=([^;\r\n]+)',h,re.I)
if not m: raise SystemExit('No multipart boundary')
boundary=m.group(1).strip('"')
module=None
for p in b.split(('--'+boundary).encode()):
    if p.startswith(b'\r\n'): p=p[2:]
    head,sep,data=p.partition(b'\r\n\r\n')
    if sep and b'name="worker-r2.js"' in head:
        if data.endswith(b'\r\n'): data=data[:-2]
        module=data
        break
if module is None: raise SystemExit('worker-r2.js not found')
Path('/tmp/original-worker-r2.js').write_bytes(module)
s=module.decode('utf-8')
if s.count('data-max-tour-card-photo-fix="20260916"') != 1:
    raise SystemExit('Expected deployed photo fix marker exactly once')
old="document.querySelectorAll('.tour-card').forEach"
new="document.querySelectorAll('.tour-card,.wide-card').forEach"
if s.count(old) != 1:
    raise SystemExit(f'Expected selector exactly once, got {s.count(old)}')
s=s.replace(old,new,1)
s=s.replace(".replace(/s+/g,' ').trim()", ".replace(/\\s+/g,' ').trim()", 1)
if s.count(new) != 1:
    raise SystemExit('Updated selector not unique')
Path('/tmp/patched-worker-r2.js').write_text(s)
print('selector updated; bytes',len(module),'->',len(s.encode()))
PY

node --input-type=module --check < /tmp/patched-worker-r2.js
metadata='{"main_module":"worker-r2.js","compatibility_date":"2026-09-09","keep_assets":true,"keep_bindings":["ai","plain_text","d1","r2_bucket"],"bindings":[{"type":"assets","name":"ASSETS"}]}'

upload_module() {
  local file="$1" out="$2" code
  code=$(curl -sS -X PUT -H "$auth" \
    -F "metadata=${metadata};type=application/json" \
    -F "worker-r2.js=@${file};filename=worker-r2.js;type=application/javascript+module" \
    "$upload_url" -o "$out" -w '%{http_code}')
  echo "upload HTTP $code"
  jq '{success,errors,messages}' "$out" 2>/dev/null || head -c 1200 "$out"
  test "$code" = "200"
  test "$(jq -r '.success' "$out")" = "true"
}

verify() {
  local ok=0
  for attempt in $(seq 1 20); do
    if curl -L -fsS --connect-timeout 5 --max-time 25 "${TARGET}/?card_selector=${GITHUB_SHA:-manual}-${attempt}" -o /tmp/live.html; then
      if grep -Fq "document.querySelectorAll('.tour-card,.wide-card')" /tmp/live.html && \
         grep -Fq 'tild6339-3862-4230-a266-343630333034/26.png' /tmp/live.html && \
         grep -Fq 'tild3861-6231-4462-a235-663762633665/ostrov-hon-tam-2.png' /tmp/live.html; then ok=1; break; fi
    fi
    sleep 2
  done
  test "$ok" -eq 1 || return 1

  curl -L -fsS "${TARGET}/api/health?card_selector=${GITHUB_SHA:-manual}" -o /tmp/health.json || return 1
  jq -e '.ok == true' /tmp/health.json >/dev/null || return 1

  curl -fsS -H "$auth" "$settings_url" -o /tmp/settings-after.json || return 1
  jq -r '.result.bindings[]?.name' /tmp/settings-after.json | sort > /tmp/bindings-after.txt
  diff -u /tmp/bindings-before.txt /tmp/bindings-after.txt || return 1
}

if ! upload_module /tmp/patched-worker-r2.js /tmp/upload.json; then
  echo 'Upload rejected; live remains on previous version.' >&2
  exit 1
fi
if ! verify; then
  echo 'Verification failed; restoring previous Worker module.' >&2
  upload_module /tmp/original-worker-r2.js /tmp/rollback.json
  exit 1
fi

echo 'DEPLOY PASS: photo fix covers both tour-card and wide-card catalog cards; bindings and API verified.'
