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
curl -fsS -D /tmp/current.headers -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" "$content_url" -o /tmp/current.multipart
cp /tmp/current.multipart /tmp/patched.multipart

python - <<'PY'
from pathlib import Path
p=Path('/tmp/patched.multipart')
raw=p.read_bytes()
old=b'''      const asset = await env.ASSETS.fetch(request);\n      return url.pathname.startsWith("/admin/") ? secureAdminAsset(asset) : asset;'''
if raw.count(old) != 1:
    raise SystemExit(f'Unsafe asset-return target count: {raw.count(old)}')
new=r'''      const asset = await env.ASSETS.fetch(request);
      if (url.pathname === "/" && !url.pathname.startsWith("/admin/") && (asset.headers.get("content-type") || "").includes("text/html")) {
        let html = await asset.text();
        const cardPhotoFix = `<script data-max-tour-card-photo-fix="20260916">(()=>{const fixes=[['Остров Орхидей и Остров Обезьян','https://static.tildacdn.one/tild6339-3862-4230-a266-343630333034/26.png'],['Остров Хон Там','https://static.tildacdn.one/tild3861-6231-4462-a235-663762633665/ostrov-hon-tam-2.png']];const apply=()=>{document.querySelectorAll('.tour-card').forEach(card=>{const text=(card.textContent||'').replace(/\s+/g,' ').trim();const hit=fixes.find(([title])=>text.includes(title));if(!hit)return;const src=hit[1];let wrap=card.querySelector('.img-wrap');let img=wrap&&wrap.querySelector('img');if(!img&&wrap){img=document.createElement('img');wrap.prepend(img)}if(!img)return;if(img.getAttribute('src')!==src)img.setAttribute('src',src);img.removeAttribute('srcset');img.onerror=()=>{img.onerror=null;img.src=src};img.style.display='block';img.style.width='100%';img.style.height='100%';img.style.objectFit='cover';img.style.objectPosition='center'}})};apply();const mo=new MutationObserver(apply);mo.observe(document.documentElement,{childList:true,subtree:true});setTimeout(apply,80);setTimeout(apply,500);setTimeout(apply,1500)})();</script>`;
        html = html.includes("</body>") ? html.replace("</body>", `${cardPhotoFix}</body>`) : `${html}${cardPhotoFix}`;
        const headers = new Headers(asset.headers);
        headers.delete("content-length");
        headers.set("cache-control", "no-store, no-cache, must-revalidate, max-age=0");
        return new Response(html, { status: asset.status, statusText: asset.statusText, headers });
      }
      return url.pathname.startsWith("/admin/") ? secureAdminAsset(asset) : asset;'''.encode('utf-8')
raw=raw.replace(old,new)
if raw.count(b'data-max-tour-card-photo-fix="20260916"') != 1:
    raise SystemExit('Patch marker not unique')
if raw.count('Остров Орхидей и Остров Обезьян'.encode()) != 1:
    raise SystemExit('Orchid title marker not unique')
if raw.count('Остров Хон Там'.encode()) != 1:
    raise SystemExit('Hon Tam title marker not unique')
p.write_bytes(raw)
print('backup bytes',Path('/tmp/current.multipart').stat().st_size,'patched bytes',p.stat().st_size)
PY

ctype=$(grep -i '^content-type:' /tmp/current.headers | tail -n1 | sed -E 's/^[Cc]ontent-[Tt]ype:[[:space:]]*//' | tr -d '\r')
test -n "$ctype"

upload() {
  local file="$1" out="$2" code
  code=$(curl -sS -X PUT \
    -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" \
    -H "Content-Type: ${ctype}" \
    --data-binary "@${file}" \
    "$content_url" -o "$out" -w '%{http_code}')
  echo "upload HTTP $code"
  head -c 1000 "$out" || true
  echo
  test "$code" = "200"
}

verify_patch() {
  local ok=0
  for attempt in $(seq 1 20); do
    if curl -L -fsS --connect-timeout 5 --max-time 30 "${TARGET}/?photo_fix=${GITHUB_SHA:-manual}-${attempt}" -o /tmp/live.html; then
      if grep -q 'data-max-tour-card-photo-fix="20260916"' /tmp/live.html && \
         grep -q 'tild6339-3862-4230-a266-343630333034/26.png' /tmp/live.html && \
         grep -q 'tild3861-6231-4462-a235-663762633665/ostrov-hon-tam-2.png' /tmp/live.html; then
        ok=1
        break
      fi
    fi
    sleep 2
  done
  test "$ok" -eq 1 || return 1
  curl -L -fsS --connect-timeout 5 --max-time 30 "${TARGET}/api/health?photo_fix=${GITHUB_SHA:-manual}" -o /tmp/health.json || return 1
  jq -e '.ok == true' /tmp/health.json >/dev/null || return 1
}

if ! upload /tmp/patched.multipart /tmp/upload.json; then
  echo 'Cloudflare rejected patch; live code unchanged.' >&2
  exit 1
fi

if ! verify_patch; then
  echo 'Verification failed; restoring exact original multipart.' >&2
  upload /tmp/current.multipart /tmp/rollback.json
  curl -L -fsS --connect-timeout 5 --max-time 30 "${TARGET}/api/health?rollback=${GITHUB_SHA:-manual}" -o /tmp/rollback-health.json
  jq -e '.ok == true' /tmp/rollback-health.json >/dev/null
  echo 'Rollback complete.' >&2
  exit 1
fi

echo 'DEPLOY PASS: both tour photo fixes are live; API remains healthy.'
