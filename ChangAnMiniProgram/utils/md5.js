// md5.js —— 纯 JS MD5 实现，输出与桌面版一致的大写十六进制
'use strict';

function utf8Encode(str) {
  const out = [];
  for (let i = 0; i < str.length; i++) {
    let c = str.charCodeAt(i);
    if (c < 0x80) {
      out.push(c);
    } else if (c < 0x800) {
      out.push(0xc0 | (c >> 6), 0x80 | (c & 0x3f));
    } else if (c >= 0xd800 && c <= 0xdbff && i + 1 < str.length) {
      const c2 = str.charCodeAt(i + 1);
      if (c2 >= 0xdc00 && c2 <= 0xdfff) {
        i++;
        const v = 0x10000 + ((c - 0xd800) << 10) + (c2 - 0xdc00);
        out.push(0xf0 | (v >> 18), 0x80 | ((v >> 12) & 0x3f), 0x80 | ((v >> 6) & 0x3f), 0x80 | (v & 0x3f));
        continue;
      }
      out.push(0xef, 0xbf, 0xbd);
    } else if (c < 0x10000) {
      out.push(0xe0 | (c >> 12), 0x80 | ((c >> 6) & 0x3f), 0x80 | (c & 0x3f));
    } else {
      const v = c;
      out.push(0xf0 | (v >> 18), 0x80 | ((v >> 12) & 0x3f), 0x80 | ((v >> 6) & 0x3f), 0x80 | (v & 0x3f));
    }
  }
  return out;
}

function md5(input) {
  const msg = utf8Encode(String(input));
  const n = msg.length;
  const block = [];
  const bitLenLow = (n << 3) >>> 0;
  const bitLenHigh = Math.floor(n / 0x20000000);
  for (let i = 0; i < n; i++) block[i >> 2] |= msg[i] << ((i % 4) * 8);
  block[n >> 2] |= 0x80 << ((n % 4) * 8);
  block[(((n + 8) >> 6) << 4) + 14] = bitLenLow;
  block[(((n + 8) >> 6) << 4) + 15] = bitLenHigh;

  const K = [];
  for (let i = 0; i < 64; i++) K[i] = Math.floor(Math.abs(Math.sin(i + 1)) * 0x100000000);

  const S = [
    7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22,
    5, 9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20,
    4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23,
    6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21
  ];

  let a0 = 0x67452301, b0 = 0xefcdab89, c0 = 0x98badcfe, d0 = 0x10325476;

  const M = new Array(16);
  const words = block.length;
  for (let off = 0; off < words; off += 16) {
    for (let i = 0; i < 16; i++) M[i] = block[off + i] >>> 0;

    let A = a0, B = b0, C = c0, D = d0;
    for (let i = 0; i < 64; i++) {
      let F, g;
      if (i < 16) { F = (B & C) | (~B & D); g = i; }
      else if (i < 32) { F = (D & B) | (~D & C); g = (5 * i + 1) % 16; }
      else if (i < 48) { F = B ^ C ^ D; g = (3 * i + 5) % 16; }
      else { F = C ^ (B | ~D); g = (7 * i) % 16; }
      F = (F + A + K[i] + M[g]) >>> 0;
      const temp = D;
      D = C;
      C = B;
      B = (B + ((F << S[i]) | (F >>> (32 - S[i])))) >>> 0;
      A = temp;
    }
    a0 = (a0 + A) >>> 0;
    b0 = (b0 + B) >>> 0;
    c0 = (c0 + C) >>> 0;
    d0 = (d0 + D) >>> 0;
  }

  return [a0, b0, c0, d0].map(w => {
    const bytes = [w & 0xff, (w >>> 8) & 0xff, (w >>> 16) & 0xff, (w >>> 24) & 0xff];
    return bytes.map(b => b.toString(16).padStart(2, '0')).join('');
  }).join('').toUpperCase();
}

module.exports = md5;
