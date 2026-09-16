// icons.js —— 图标与仪表图元（内联 SVG → data URI，无外部资源依赖）
// 深色科技风统一使用细描边线性图标：viewBox 24，stroke-width 默认 1.7。
// ic('lock', '#FFFFFF') → "data:image/svg+xml,..." 直接给 <image src>。
const uri = s => 'data:image/svg+xml,' + encodeURIComponent(s);

const P = {
  // ---------- 底部导航 ----------
  navHome: '<path d="M4.4 11.2l7-6.4c.35-.32.88-.32 1.23 0l7 6.4"/><path d="M6.2 9.9v9.5c0 .6.5 1.1 1.1 1.1h2.9v-5.4h3.6v5.4h2.9c.6 0 1.1-.5 1.1-1.1V9.9"/>',
  navApps: '<rect x="3.8" y="3.8" width="6.8" height="6.8" rx="2"/><rect x="13.4" y="3.8" width="6.8" height="6.8" rx="2"/><rect x="3.8" y="13.4" width="6.8" height="6.8" rx="2"/><rect x="13.4" y="13.4" width="6.8" height="6.8" rx="2"/>',
  navMsg: '<path d="M5.2 5.6c0-.9.7-1.6 1.6-1.6h10.4c.9 0 1.6.7 1.6 1.6v8.3c0 .9-.7 1.6-1.6 1.6h-5.9l-3.9 3.3v-3.3H6.8c-.9 0-1.6-.7-1.6-1.6z"/>',
  navMine: '<circle cx="12" cy="8.1" r="3.5"/><path d="M5.2 19.7c.75-3.2 3.5-5.1 6.8-5.1s6.05 1.9 6.8 5.1"/>',

  // ---------- 箭头 ----------
  chevD: '<path d="M6.2 9.3l5.8 5.8 5.8-5.8"/>',
  chevR: '<path d="M9.3 6.2l5.8 5.8-5.8 5.8"/>',
  chevU: '<path d="M6.2 14.7l5.8-5.8 5.8 5.8"/>',

  // ---------- 车控指令 ----------
  lock: '<rect x="5.4" y="10.4" width="13.2" height="9.6" rx="2.2"/><path d="M8.6 10.4V8.3a3.4 3.4 0 0 1 6.8 0v2.1"/>',
  unlock: '<rect x="5.4" y="10.4" width="13.2" height="9.6" rx="2.2"/><path d="M8.6 10.4V8.3a3.4 3.4 0 0 1 6.7-1.1"/>',
  snow: '<path d="M12 3.4v17.2M5.6 7.9l12.8 8.2M18.4 7.9l-12.8 8.2"/>',
  snowOff: '<path d="M12 3.4v17.2M5.6 7.9l12.8 8.2M18.4 7.9l-12.8 8.2"/><path d="M4.4 4.4l15.2 15.2"/>',
  bulb: '<circle cx="12" cy="10.6" r="4.6"/><path d="M12 15.4v1.6"/><path d="M9.6 19.4h4.8"/><path d="M12 3.2v1.5M5.4 5.4l1.1 1.1M18.6 5.4l-1.1 1.1M3.2 10.6h1.5M19.3 10.6h1.5"/>',
  horn: '<path d="M5.6 10.5h2.7l5.1-3.6v10.2l-5.1-3.6H5.6z"/><path d="M16.9 9.5c1.05 1.2 1.05 3.8 0 5M19.3 6.9c2.25 2.6 2.25 7.6 0 10.2"/>',
  find: '<circle cx="12" cy="12" r="6.6"/><circle cx="12" cy="12" r="1.5"/><path d="M12 3.2v2.2M12 18.6v2.2M3.2 12h2.2M18.6 12h2.2"/>',
  refresh: '<path d="M21.1 3.4v5.6h-5.6"/><path d="M21.3 9A8.7 8.7 0 0 1 12 20.7 8.7 8.7 0 0 1 3.3 12 8.7 8.7 0 0 1 12 3.3c2.6 0 5 1.2 6.6 3.1"/>',

  // ---------- 车辆状态 ----------
  car: '<path d="M8.4 7.6h7.2c1.7 0 3 1.1 3.4 2.6l.9 3.2"/><path d="M3.9 13.4h16.2v3.1c0 .6-.5 1.1-1.1 1.1h-1.8c-.6 0-1.1-.5-1.1-1.1v-.8H8.1v.8c0 .6-.5 1.1-1.1 1.1H5.2c-.6 0-1.1-.5-1.1-1.1v-3.1z"/><circle cx="7.4" cy="17.4" r="1.9"/><circle cx="16.6" cy="17.4" r="1.9"/>',
  door: '<rect x="7.4" y="4.6" width="9.2" height="14.8" rx="1.8"/><path d="M10.4 9.4v2.6"/><circle cx="12.8" cy="12.2" r=".8"/>',
  window: '<rect x="5.6" y="5.2" width="12.8" height="13.6" rx="2"/><path d="M12 5.2v13.6M5.6 11.4h12.8"/>',
  trunk: '<rect x="6" y="6.2" width="12" height="11.6" rx="1.8"/><path d="M6 11.8h12"/><path d="M10.4 8.4h3.2"/>',
  sunroof: '<path d="M8.9 4.8a1.6 1.6 0 0 1 1.6-1.6h3a1.6 1.6 0 0 1 1.6 1.6v1.4"/><rect x="4.6" y="6.2" width="14.8" height="10.4" rx="2"/><path d="M4.6 11.4h14.8"/>',
  tyre: '<circle cx="12" cy="12" r="7.8"/><circle cx="12" cy="12" r="2.4"/><path d="M12 4.2v2.4M12 17.4v2.4M4.2 12h2.4M17.4 12h2.4"/>',
  temp: '<path d="M12 4.6v9.8"/><circle cx="12" cy="17.2" r="3"/><path d="M9.4 6.4h1.6M9.4 9.4h1.6"/>',
  shield: '<path d="M12 3.4l7 2.6v5.1c0 4.3-2.9 7.5-7 9.3-4.1-1.8-7-5-7-9.3V6z"/><path d="M9 11.7l2.1 2.2 3.9-5.2"/>',
  pin: '<path d="M12 21.2c-3.3-3.2-6.1-6.1-6.1-9.5a6.1 6.1 0 0 1 12.2 0c0 3.4-2.8 6.3-6.1 9.5z"/><circle cx="12" cy="11.5" r="2.2"/>',
  wind: '<path d="M3.6 8.3h8.9a2.6 2.6 0 1 0-2.6-2.6"/><path d="M3.6 12.2h13.4a2.6 2.6 0 1 1-2.6 2.6"/><path d="M3.6 16.1h5.6"/>',
  clock: '<circle cx="12" cy="12" r="8.2"/><path d="M12 7.4v4.8l3.3 2"/>',

  // ---------- 状态 / 通用 ----------
  checkc: '<circle cx="12" cy="12" r="8.6"/><path d="M8.4 12.3l2.5 2.5 4.7-5.4"/>',
  xc: '<circle cx="12" cy="12" r="8.6"/><path d="M9.2 9.2l5.6 5.6M14.8 9.2l-5.6 5.6"/>',
  warn: '<path d="M12 4.4l8.8 15.2H3.2z"/><path d="M12 10v4.6"/><path d="M12 17.2h.01"/>',
  info: '<circle cx="12" cy="12" r="8.6"/><path d="M12 10.6v5.4"/><path d="M12 7.2h.01"/>',
  user: '<circle cx="12" cy="8.1" r="3.5"/><path d="M5.2 19.7c.75-3.2 3.5-5.1 6.8-5.1s6.05 1.9 6.8 5.1"/>',
  doc: '<rect x="8.4" y="4.4" width="10.6" height="13" rx="1.8"/><path d="M5 7.6c0-.9.7-1.6 1.6-1.6h1.8"/><path d="M8.4 7.6h6.5a1.8 1.8 0 0 1 1.8 1.8V17.6"/>',
  copy: '<rect x="8.6" y="8.2" width="10.6" height="12" rx="2"/><path d="M5.4 15.4V5.8c0-1 .8-1.8 1.8-1.8h9.6"/>',
  logout: '<path d="M9.2 4.6H6.6A2.6 2.6 0 0 0 4 7.2v9.6a2.6 2.6 0 0 0 2.6 2.6h2.6"/><path d="M14.8 8.2l4 3.8-4 3.8"/><path d="M18.8 12H9.8"/>',
  trash: '<path d="M5 7h14"/><path d="M9.4 7V5.4A1.6 1.6 0 0 1 11 3.8h2a1.6 1.6 0 0 1 1.6 1.6V7"/><path d="M6.4 7l.85 11.1a1.7 1.7 0 0 0 1.7 1.6h6.1a1.7 1.7 0 0 0 1.7-1.6L17.6 7"/><path d="M10.2 10.8v5.4M13.8 10.8v5.4"/>',
  gear: '<path d="M14.7 6.3a1 1 0 0 0 0 1.4l1.6 1.6a1 1 0 0 0 1.4 0l3.77-3.77a6 6 0 0 1-7.94 7.94l-6.91 6.91a2.12 2.12 0 0 1-3-3l6.91-6.91a6 6 0 0 1 7.94-7.94z"/>',
  bolt: '<path d="M13.2 2.8L6.2 13.4h4.3l-1.5 7.8 7.2-11h-4.6z"/>',
  // ---------- 信息类（v7.2 增补） ----------
  soc: '<rect x="6.4" y="9.8" width="11.2" height="6" rx="1.6"/><path d="M17.6 11.8h1.8v1.9h-1.8"/><path d="M9.8 12.1l2.3 2.2 2.5-3.4"/>',
  gauge: '<path d="M4.6 15.6a8.6 8.6 0 0 1 14.8 0"/><path d="M12 15.6l3.4-4.2"/><circle cx="12" cy="15.6" r="1.2"/>',
  road: '<path d="M3.6 5.2L10 19M20.4 5.2L14 19"/><path d="M12 3.6v2M12 18.4v2"/>',
  wifi: '<path d="M4.8 10.2a10 10 0 0 1 14.4 0"/><path d="M7.5 13a6 6 0 0 1 9 0"/><path d="M10.3 15.8a2 2 0 0 1 3.4 0"/><circle cx="12" cy="18.6" r="1"/>',
  seat: '<path d="M6.8 4.8c0-1.2 1-2.2 2.2-2.2h6c1.2 0 2.2 1 2.2 2.2v8.6H6.8z"/><path d="M5.4 13.4h13.2v3.4a1.8 1.8 0 0 1-1.8 1.8H7.2a1.8 1.8 0 0 1-1.8-1.8z"/><path d="M6.2 18.6v2.2M17.8 18.6v2.2"/>',
  phone: '<path d="M6.9 4.4c-.7 0-1.3.6-1.2 1.3.5 4 2.6 7.6 5.7 10.4 3 2.8 6.8 4.5 10.8 4.9.7 0 1.3-.6 1.3-1.3v-3c0-.6-.4-1.1-1-1.2l-3.4-.8c-.5-.1-1 .1-1.3.5l-1.2 1.4a14 14 0 0 1-6-6l1.4-1.2c.4-.3.6-.8.5-1.3l-.8-3.4c-.1-.6-.6-1-1.2-1z"/>',
  calendar: '<rect x="4.6" y="5.4" width="14.8" height="14.6" rx="2.2"/><path d="M4.6 10h14.8M8.8 3.4v3.6M15.2 3.4v3.6"/>',
  key: '<circle cx="8.6" cy="14.6" r="3.6"/><path d="M11.3 11.9L19.8 3.4M16 5.2l3 3M12.8 8.4l2.2 2.2"/>',
  steer: '<circle cx="12" cy="12" r="8.4"/><circle cx="12" cy="12" r="1.8"/><path d="M12 3.6v2M12 18.4v2M3.6 12h2M18.4 12h2"/><path d="M6.6 15.4c1.9-2 3.4-3 5.4-3s3.5 1 5.4 3"/>',
  // 罗盘指针（指北，随 heading 旋转）
  needleN: '<path d="M12 4.4v13.2"/><path d="M12 4.4l-5.6 7.6M12 4.4l5.6 7.6"/><circle cx="12" cy="21.4" r="1.7"/>'
};

// 线性图标
function ic(name, color, sw) {
  const body = P[name];
  if (!body) return '';
  const c = color || '#C9D6E8';
  const w = sw || 1.7;
  return uri(`<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="${c}" stroke-width="${w}" stroke-linecap="round" stroke-linejoin="round">${body}</svg>`);
}

// 圆环进度仪表（SOC / 健康评分）
// opts: { value: 0-100, size, sw, colors: ['#..','#..'], track, round }
function ringURI(opts) {
  const o = opts || {};
  const size = o.size || 72;
  const sw = o.sw || 7;
  const pct = Math.max(0, Math.min(100, Number(o.value) || 0));
  const r = (size - sw) / 2;
  const circ = Math.PI * 2 * r;
  const dash = (circ * pct) / 100;
  const track = o.track || 'rgba(151,168,199,0.16)';
  const colors = o.colors || ['#2F7BFF', '#3BD8FF'];
  const cap = o.round === false ? 'butt' : 'round';
  const cx = size / 2;
  const gid = 'g' + size + '-' + Math.round(pct) + '-' + (colors[0] || 'x').replace(/[^a-zA-Z0-9]/g, '');
  const grad = `<defs><linearGradient id="${gid}" x1="0" y1="0" x2="1" y2="1"><stop offset="0%" stop-color="${colors[0]}"/><stop offset="100%" stop-color="${colors[1] || colors[0]}"/></linearGradient></defs>`;
  return uri(
    `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${size} ${size}">${grad}` +
    `<circle cx="${cx}" cy="${cx}" r="${r}" fill="none" stroke="${track}" stroke-width="${sw}"/>` +
    `<circle cx="${cx}" cy="${cx}" r="${r}" fill="none" stroke="url(#${gid})" stroke-width="${sw}" stroke-linecap="${cap}" stroke-dasharray="${dash.toFixed(2)} ${circ.toFixed(2)}" transform="rotate(-90 ${cx} ${cx})"/>` +
    '</svg>'
  );
}

// 迷你柱状序列（电池单体电压 / 温度探针）→ 横向细柱 SVG data URI
// v7：渐变柱 + 基线 + 中位参考虚线 + 越界柱自动标红（视觉上是“设计过的图表”）
// values: number[]；自动抽样到 ≤ maxBars 根，高度按最大值归一。
function barsURI(values, opts) {
  const o = opts || {};
  const w = o.width || 640;
  const h = o.height || 64;
  const maxBars = o.maxBars || 64;
  // 旧 color 传 alpha≈0.4 表示“温度类”低调渲染（电压亮 / 温度暗）
  const dim = /0\.4/.test(String(o.color || '0.8'));
  const raw = (values || []).map(v => { const n = Number(v); return isNaN(n) ? 0 : n; });
  if (!raw.length) return '';
  const step = Math.max(1, Math.ceil(raw.length / maxBars));
  const sampled = [];
  for (let i = 0; i < raw.length; i += step) sampled.push(raw[i]);
  const pos = sampled.filter(v => v > 0);
  const mx = Math.max.apply(null, sampled.concat([1e-9]));
  const mn = Math.min.apply(null, pos.length ? pos : [1e-9]);
  const sorted = pos.slice().sort((a, b) => a - b);
  const med = sorted.length ? sorted[Math.floor(sorted.length / 2)] : mx;
  const devTh = Math.max((mx - mn) * 0.6, med * 0.004);
  const gap = 3;
  const bw = (w - gap * (sampled.length - 1)) / sampled.length;
  const bx = Math.max(0.8, bw - 1.4);
  const topC = dim ? 'rgba(168,186,220,0.5)' : 'rgba(225,235,255,0.92)';
  const botC = dim ? 'rgba(96,116,160,0.2)' : 'rgba(120,140,190,0.3)';
  const gid = 'bg' + w + '-' + h + (dim ? 'd' : 'b');
  const grad = `<linearGradient id="${gid}" x1="0" y1="1" x2="0" y2="0"><stop offset="0" stop-color="${botC}"/><stop offset="1" stop-color="${topC}"/></linearGradient>`;
  const yRef = (h - 3 - (med / mx) * (h - 9)).toFixed(1);
  let rects = '';
  sampled.forEach((v, i) => {
    const bh = Math.max(v > 0 ? 2 : 0, (v / mx) * (h - 9));
    const x = (i * (bw + gap)).toFixed(1);
    const y = (h - 3 - bh).toFixed(1);
    const bad = v > 0 && Math.abs(v - med) > devTh ? ` fill="#FF5A4F"` : ` fill="url(#${gid})"`;
    rects += `<rect x="${x}" y="${y}" width="${bx.toFixed(1)}" height="${bh.toFixed(1)}" rx="${Math.max(1, bx * 0.3).toFixed(1)}"${bad}/>`;
  });
  return uri(
    `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${w} ${h}">` +
    `<defs>${grad}</defs>` +
    `<line x1="0" y1="${h - 2}" x2="${w}" y2="${h - 2}" stroke="rgba(255,255,255,0.06)" stroke-width="1"/>` +
    `<line x1="0" y1="${yRef}" x2="${w}" y2="${yRef}" stroke="rgba(90,200,250,0.13)" stroke-width="1" stroke-dasharray="4 6"/>` +
    rects + '</svg>'
  );
}

// 去掉行首 emoji / 符号（把 texts.js 组标题转成干净文本）
function stripLeading(t) {
  const s = String(t == null ? '' : t);
  return s.replace(/^[^\u4e00-\u9fa5A-Za-z0-9]+/, '').trim();
}

module.exports = { ic, ringURI, barsURI, stripLeading };
