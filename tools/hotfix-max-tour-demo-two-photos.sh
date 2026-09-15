#!/usr/bin/env bash
set -euo pipefail

SERVICE="max-tour-demo-v28"
TARGET="https://max-tour-demo.viiversion.com"
ORCHID="https://static.tildacdn.one/tild6339-3862-4230-a266-343630333034/26.png"
HONTAM="https://static.tildacdn.one/tild3861-6231-4462-a235-663762633665/ostrov-hon-tam-2.png"

: "${CLOUDFLARE_API_TOKEN:?missing CLOUDFLARE_API_TOKEN}"
: "${CLOUDFLARE_ACCOUNT_ID:?missing CLOUDFLARE_ACCOUNT_ID}"

curl -L -fsS --connect-timeout 5 --max-time 30 "${TARGET}/?pre=${GITHUB_SHA:-manual}" -o /tmp/pre.html
grep -q 'MaxTour Vietnam' /tmp/pre.html
for photo in "$ORCHID" "$HONTAM"; do
  curl -L -fsS -D /tmp/photo.h --connect-timeout 5 --max-time 30 "$photo" -o /tmp/photo.bin
  grep -qi '^content-type: image/' /tmp/photo.h
  test "$(wc -c < /tmp/photo.bin)" -gt 10000
done
curl -L -fsS --connect-timeout 5 --max-time 30 "${TARGET}/api/health?pre=${GITHUB_SHA:-manual}" -o /tmp/pre-health.json
jq -e '.ok == true' /tmp/pre-health.json >/dev/null

content_url="https://api.cloudflare.com/client/v4/accounts/${CLOUDFLARE_ACCOUNT_ID}/workers/services/${SERVICE}/environments/production/content"
settings_url="https://api.cloudflare.com/client/v4/accounts/${CLOUDFLARE_ACCOUNT_ID}/workers/services/${SERVICE}/environments/production/settings"
upload_url="https://api.cloudflare.com/client/v4/accounts/${CLOUDFLARE_ACCOUNT_ID}/workers/scripts/${SERVICE}"
auth="Authorization: Bearer ${CLOUDFLARE_API_TOKEN}"

curl -fsS -H "$auth" "$settings_url" -o /tmp/settings-before.json
jq -r '.result.bindings[]?.name' /tmp/settings-before.json | sort > /tmp/bindings-before.txt
curl -fsS -D /tmp/current.headers -H "$auth" "$content_url" -o /tmp/current.multipart

python - <<'PY'
from pathlib import Path
import re
headers=Path('/tmp/current.headers').read_text(errors='replace')
body=Path('/tmp/current.multipart').read_bytes()
m=re.search(r'boundary=([^;\r\n]+)',headers,re.I)
if not m: raise SystemExit('No multipart boundary')
boundary=m.group(1).strip('"')
marker=('--'+boundary).encode()
module=None
for raw_part in body.split(marker):
    if raw_part.startswith(b'\r\n'):
        raw_part=raw_part[2:]
    head,sep,data=raw_part.partition(b'\r\n\r\n')
    if not sep: continue
    if b'name="worker-r2.js"' in head:
        if data.endswith(b'\r\n'):
            data=data[:-2]
        module=data
        break
if module is None: raise SystemExit('worker-r2.js not found')
Path('/tmp/original-worker-r2.js').write_bytes(module)
raw=module
if raw.count(b'data-max-tour-card-photo-fix="20260916"'):
    raise SystemExit('Refusing duplicate photo patch: marker already present')
old=b'''      const asset = await env.ASSETS.fetch(request);\n      return url.pathname.startsWith("/admin/") ? secureAdminAsset(asset) : asset;'''
if raw.count(old) != 1:
    raise SystemExit(f'Unsafe asset-return target count: {raw.count(old)}')
new=r'''      const asset = await env.ASSETS.fetch(request);
      if (url.pathname === "/" && !url.pathname.startsWith("/admin/") && (asset.headers.get("content-type") || "").includes("text/html")) {
        let html = await asset.text();
        const cardPhotoFix = `<script data-max-tour-card-photo-fix="20260916">(()=>{const fixes=[['Остров Орхидей и Остров Обезьян','https://static.tildacdn.one/tild6339-3862-4230-a266-343630333034/26.png'],['Остров Хон Там','https://static.tildacdn.one/tild3861-6231-4462-a235-663762633665/ostrov-hon-tam-2.png']];const apply=()=>{document.querySelectorAll('.tour-card,.wide-card').forEach(card=>{const text=(card.textContent||'').replace(/\s+/g,' ').trim();const hit=fixes.find(([title])=>text.includes(title));if(!hit)return;const src=hit[1];const wrap=card.querySelector('.img-wrap');let img=wrap&&wrap.querySelector('img');if(!img&&wrap){img=document.createElement('img');wrap.prepend(img)}if(!img)return;if(img.getAttribute('src')!==src)img.setAttribute('src',src);img.removeAttribute('srcset');img.onerror=()=>{img.onerror=null;img.src=src};img.style.display='block';img.style.width='100%';img.style.height='100%';img.style.objectFit='cover';img.style.objectPosition='center'}})};apply();const mo=new MutationObserver(apply);mo.observe(document.documentElement,{childList:true,subtree:true});setTimeout(apply,80);setTimeout(apply,500);setTimeout(apply,1500)})();</script>`;
        html = html.includes("</body>") ? html.replace("</body>", `${cardPhotoFix}</body>`) : `${html}${cardPhotoFix}`;
        const headers = new Headers(asset.headers);
        headers.delete("content-length");
        headers.set("cache-control", "no-store, no-cache, must-revalidate, max-age=0");
        return new Response(html, { status: asset.status, statusText: asset.statusText, headers });
      }
      return url.pathname.startsWith("/admin/") ? secureAdminAsset(asset) : asset;'''.encode('utf-8')
patched=raw.replace(old,new)
if patched.count(b'data-max-tour-card-photo-fix="20260916"') != 1:
    raise SystemExit('Patch marker not unique')
if patched.count(b"document.querySelectorAll('.tour-card,.wide-card')") != 1:
    raise SystemExit('Wide-card selector not unique')
Path('/tmp/patched-worker-r2.js').write_bytes(patched)
print('original bytes',len(raw),'patched bytes',len(patched))
PY

node --input-type=module --check < /tmp/original-worker-r2.js
node --input-type=module --check < /tmp/patched-worker-r2.js

metadata='{"main_module":"worker-r2.js","compatibility_date":"2026-09-09","keep_assets":true,"keep_bindings":["ai","plain_text","d1","r2_bucket"],"bindings":[{"type":"assets","name":"ASSETS"}]}'

upload_module() {
  local file="$1" out="$2" code
  code=$(curl -sS -X PUT \
    -H "$auth" \
    -F "metadata=${metadata};type=application/json" \
    -F "worker-r2.js=@${file};filename=worker-r2.js;type=application/javascript+module" \
    "$upload_url" -o "$out" -w '%{http_code}')
  echo "upload HTTP $code"
  jq '{success,errors,messages}' "$out" 2>/dev/null || head -c 1500 "$out"
  test "$code" = "200"
  test "$(jq -r '.success' "$out")" = "true"
}

verify_bindings() {
  curl -fsS -H "$auth" "$settings_url" -o /tmp/settings-after.json || return 1
  jq -r '.result.bindings[]?.name' /tmp/settings-after.json | sort > /tmp/bindings-after.txt
  diff -u /tmp/bindings-before.txt /tmp/bindings-after.txt || return 1
}

verify_patch() {
  local ok=0
  for attempt in $(seq 1 20); do
    if curl -L -fsS --connect-timeout 5 --max-time 30 "${TARGET}/?photo_fix=${GITHUB_SHA:-manual}-${attempt}" -o /tmp/live.html; then
      if grep -Fq 'data-max-tour-card-photo-fix="20260916"' /tmp/live.html && \
         grep -Fq "document.querySelectorAll('.tour-card,.wide-card')" /tmp/live.html && \
         grep -Fq 'tild6339-3862-4230-a266-343630333034/26.png' /tmp/live.html && \
         grep -Fq 'tild3861-6231-4462-a235-663762633665/ostrov-hon-tam-2.png' /tmp/live.html; then
        ok=1
        break
      fi
    fi
    sleep 2
  done
  test "$ok" -eq 1 || return 1
  curl -L -fsS --connect-timeout 5 --max-time 30 "${TARGET}/api/health?photo_fix=${GITHUB_SHA:-manual}" -o /tmp/health.json || return 1
  jq -e '.ok == true' /tmp/health.json >/dev/null || return 1
  verify_bindings || return 1
}

if ! upload_module /tmp/patched-worker-r2.js /tmp/upload.json; then
  echo 'Cloudflare rejected patch; live code unchanged.' >&2
  exit 1
fi

if ! verify_patch; then
  echo 'Post-deploy verification failed; restoring original Worker module.' >&2
  upload_module /tmp/original-worker-r2.js /tmp/rollback.json
  echo 'Rollback complete.' >&2
  exit 1
fi

echo 'DEPLOY PASS: both target photo URLs injected for tour-card and wide-card; assets/bindings preserved and API healthy.'
