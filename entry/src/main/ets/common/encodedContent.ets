function hexValue(code: number): number {
  if (code >= 48 && code <= 57) return code - 48; // 0-9
  if (code >= 65 && code <= 70) return code - 65 + 10; // A-F
  if (code >= 97 && code <= 102) return code - 97 + 10; // a-f
  return -1;
}

function percentDecodeToBytes(input: string): Uint8Array | null {
  const bytes: number[] = [];
  for (let i = 0; i < input.length; i++) {
    const code = input.charCodeAt(i);
    if (code > 0x7f) return null;
    if (code !== 37) { // %
      bytes.push(code);
      continue;
    }
    if (i + 2 >= input.length) return null;
    const hi = hexValue(input.charCodeAt(i + 1));
    const lo = hexValue(input.charCodeAt(i + 2));
    if (hi < 0 || lo < 0) return null;
    bytes.push((hi << 4) | lo);
    i += 2;
  }
  return new Uint8Array(bytes);
}

function decodeUtf8(bytes: Uint8Array): string {
  const replacement = 0xfffd;
  let out = '';
  let i = 0;

  while (i < bytes.length) {
    const b0 = bytes[i++];
    if (b0 < 0x80) {
      out += String.fromCharCode(b0);
      continue;
    }

    if (b0 >= 0xc2 && b0 < 0xe0) {
      if (i >= bytes.length) {
        out += String.fromCharCode(replacement);
        break;
      }
      const b1 = bytes[i++];
      if ((b1 & 0xc0) !== 0x80) {
        out += String.fromCharCode(replacement);
        continue;
      }
      out += String.fromCharCode(((b0 & 0x1f) << 6) | (b1 & 0x3f));
      continue;
    }

    if (b0 >= 0xe0 && b0 < 0xf0) {
      if (i + 1 >= bytes.length) {
        out += String.fromCharCode(replacement);
        break;
      }
      const b1 = bytes[i++];
      const b2 = bytes[i++];
      if ((b1 & 0xc0) !== 0x80 || (b2 & 0xc0) !== 0x80) {
        out += String.fromCharCode(replacement);
        continue;
      }
      out += String.fromCharCode(((b0 & 0x0f) << 12) | ((b1 & 0x3f) << 6) | (b2 & 0x3f));
      continue;
    }

    if (b0 >= 0xf0 && b0 < 0xf5) {
      if (i + 2 >= bytes.length) {
        out += String.fromCharCode(replacement);
        break;
      }
      const b1 = bytes[i++];
      const b2 = bytes[i++];
      const b3 = bytes[i++];
      if ((b1 & 0xc0) !== 0x80 || (b2 & 0xc0) !== 0x80 || (b3 & 0xc0) !== 0x80) {
        out += String.fromCharCode(replacement);
        continue;
      }
      const codePoint = ((b0 & 0x07) << 18) | ((b1 & 0x3f) << 12) | ((b2 & 0x3f) << 6) | (b3 & 0x3f);
      if (codePoint > 0x10ffff) {
        out += String.fromCharCode(replacement);
        continue;
      }
      const cp = codePoint - 0x10000;
      out += String.fromCharCode(0xd800 | ((cp >> 10) & 0x3ff), 0xdc00 | (cp & 0x3ff));
      continue;
    }

    out += String.fromCharCode(replacement);
  }

  return out;
}

export function decodeIfEncoded(text: string | undefined, encoded: boolean | undefined): string {
  const raw = text ?? '';
  if (!encoded) return raw;
  const bytes = percentDecodeToBytes(raw);
  if (!bytes) return raw;
  return decodeUtf8(bytes);
}
