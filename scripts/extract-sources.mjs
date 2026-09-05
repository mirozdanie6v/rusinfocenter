import { gunzipSync } from "node:zlib";
import { createHash } from "node:crypto";
import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, resolve, sep } from "node:path";

const root = resolve(process.cwd());
const bundlePath = resolve(root, "bundles/source.tar.gz.b64");
const expectedSha256 = "a138d077bc8764c909e8da8c6335dfda90a3f18b35acb8bb872785ccf21f044f";

function readString(buf, start, length) {
  return buf.subarray(start, start + length).toString("utf8").replace(/\0.*$/, "").trim();
}

function readOctal(buf, start, length) {
  const value = readString(buf, start, length).replace(/\0/g, "").trim();
  return value ? Number.parseInt(value, 8) : 0;
}

function safeTarget(name) {
  const normalized = name.replaceAll("\\", "/").replace(/^\/+/, "");
  if (!normalized.startsWith("src/")) throw new Error(`Unexpected source path: ${name}`);
  const target = resolve(root, normalized);
  if (!target.startsWith(root + sep)) throw new Error(`Unsafe source path: ${name}`);
  return target;
}

function extractTar(buffer) {
  let offset = 0;
  let extracted = 0;
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
      extracted += 1;
    }
    offset += Math.ceil(size / 512) * 512;
  }
  return extracted;
}

const base64 = readFileSync(bundlePath, "utf8").trim();
const archive = Buffer.from(base64, "base64");
const actualSha256 = createHash("sha256").update(archive).digest("hex");
if (actualSha256 !== expectedSha256) {
  throw new Error(`Source bundle checksum mismatch: ${actualSha256}`);
}
const extracted = extractTar(gunzipSync(archive));
if (extracted !== 5) throw new Error(`Expected 5 source files, extracted ${extracted}`);
console.log(`RIC TypeScript sources restored (${extracted} files, checksum OK).`);
