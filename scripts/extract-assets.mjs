import { gunzipSync } from "node:zlib";
import { readFileSync, mkdirSync, writeFileSync, existsSync } from "node:fs";
import { dirname, resolve, sep } from "node:path";

const root = resolve(process.cwd());
const publicDir = resolve(root, "public");
const bundles = [1, 2, 3, 4].map((n) => resolve(root, `bundles/assets-${n}.tar.gz`));

function readString(buf, start, length) {
  return buf.subarray(start, start + length).toString("utf8").replace(/\0.*$/, "").trim();
}
function readOctal(buf, start, length) {
  const value = readString(buf, start, length).replace(/\0/g, "").trim();
  return value ? Number.parseInt(value, 8) : 0;
}
function safeTarget(name) {
  const normalized = name.replaceAll("\\", "/").replace(/^\/+/, "");
  const target = resolve(publicDir, normalized);
  if (target !== publicDir && !target.startsWith(publicDir + sep)) throw new Error(`Unsafe asset path: ${name}`);
  return target;
}
function extractTar(buffer) {
  let offset = 0;
  while (offset + 512 <= buffer.length) {
    const header = buffer.subarray(offset, offset + 512);
    if (header.every((byte) => byte === 0)) break;
    const name = readString(header, 0, 100);
    const prefix = readString(header, 345, 155);
    const fullName = prefix ? `${prefix}/${name}` : name;
    const size = readOctal(header, 124, 12);
    const type = readString(header, 156, 1) || "0";
    offset += 512;
    const body = buffer.subarray(offset, offset + size);
    if (type === "0" && fullName) {
      const target = safeTarget(fullName);
      mkdirSync(dirname(target), { recursive: true });
      writeFileSync(target, body);
    }
    offset += Math.ceil(size / 512) * 512;
  }
}

mkdirSync(publicDir, { recursive: true });
for (const bundle of bundles) {
  if (!existsSync(bundle)) throw new Error(`Missing asset bundle: ${bundle}`);
  extractTar(gunzipSync(readFileSync(bundle)));
}
console.log("RIC assets extracted into public/");
