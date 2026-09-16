// scene.js —— v7「夜航」场景美术：纯内联 SVG → data URI（零外部资源）
// v7.2：车身比例重绘（低鼻 fastback：轮距靠前后、座舱后移、玻璃屋带高光、
// 后视镜 / 门缝 / 前后灯 / 轮辐细节），显示尺寸由 WXSS 控制。
const uri = s => 'data:image/svg+xml,' + encodeURIComponent(s);

/* 侧视 EV —— v9「TESLA」：Model S 风格溜背轿跑
   低趴长车头 / 封闭前脸 / 贯穿式前后灯带 / 隐藏式门把手 / 低风阻涡轮轮毂
   opts: { charge?: bool 充电时能量线增亮 + 车底辉光 + 充电口灯效, accent?: '#5AC8FA' }
   viewBox 0 0 560 240 —— 车体 x 76..532，rocker y=196，轮底 y=234 */
function carSideURI(opts) {
  const o = opts || {};
  const acc = o.accent || '#5AC8FA';
  const glow = o.charge
    ? `<ellipse cx="300" cy="228" rx="180" ry="7" fill="${acc}" opacity="0.10"/>
       <ellipse cx="300" cy="230" rx="100" ry="4" fill="${acc}" opacity="0.16"/>`
    : '';
  const accStroke = o.charge ? 'opacity="0.95" stroke-width="2"' : 'opacity="0.5" stroke-width="1.5"';
  // 充电口（左后翼子板，Model S 位）：充电时呼吸光斑
  const portGlow = o.charge
    ? `<circle cx="106" cy="150" r="8" fill="${acc}" opacity="0.22"/>
       <circle cx="106" cy="150" r="3.4" fill="${acc}" opacity="0.95"/>`
    : `<circle cx="106" cy="150" r="3" fill="rgba(210,226,255,0.35)"/>`;

  // 低风阻涡轮轮毂：5 根弯曲辐条（aero turbine），按角度计算而非贴死图形
  function wheel(cx, cy, R) {
    const rim = R * 0.66;
    const blades = [];
    const n = 5;
    for (let i = 0; i < n; i++) {
      const a0 = (Math.PI * 2 * i) / n;
      const a1 = a0 + 0.66;
      const x0 = cx + rim * 0.16 * Math.cos(a0), y0 = cy + rim * 0.16 * Math.sin(a0);
      const x1 = cx + rim * Math.cos(a1), y1 = cy + rim * Math.sin(a1);
      const mx = cx + rim * 0.64 * Math.cos(a0 + 0.36), my = cy + rim * 0.64 * Math.sin(a0 + 0.36);
      blades.push(`<path d="M ${x0.toFixed(1)} ${y0.toFixed(1)} Q ${mx.toFixed(1)} ${my.toFixed(1)} ${x1.toFixed(1)} ${y1.toFixed(1)}" fill="none" stroke="rgba(206,218,238,0.55)" stroke-width="3.4" stroke-linecap="round"/>`);
    }
    return `<g>
      <circle cx="${cx}" cy="${cy}" r="${R}" fill="#060709" stroke="rgba(255,255,255,0.14)" stroke-width="1.2"/>
      <circle cx="${cx}" cy="${cy}" r="${R * 0.92}" fill="none" stroke="rgba(255,255,255,0.06)" stroke-width="1"/>
      <circle cx="${cx}" cy="${cy}" r="${rim}" fill="#141b2b" stroke="rgba(255,255,255,0.2)" stroke-width="1"/>
      ${blades.join('')}
      <circle cx="${cx}" cy="${cy}" r="${R * 0.18}" fill="#2c3a54"/>
      <circle cx="${cx}" cy="${cy}" r="${R * 0.08}" fill="#dfe8fb"/>
    </g>`;
  }

  // 前/后轮中心（面朝右）：长轴距、短悬，Model S 比例
  const rearX = 148, frontX = 416, wy = 198, WR = 36;
  const archR = WR + 8;

  return uri(
    `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 560 240">
<defs>
<linearGradient id="bd" x1="0" y1="0" x2="0" y2="1">
<stop offset="0" stop-color="#414d6b"/><stop offset="0.44" stop-color="#232d43"/><stop offset="0.8" stop-color="#0f131e"/><stop offset="1" stop-color="#090b12"/>
</linearGradient>
<radialGradient id="gd" cx="0.5" cy="0.5" r="0.5">
<stop offset="0" stop-color="rgba(120,160,255,0.22)"/><stop offset="0.7" stop-color="rgba(120,160,255,0.05)"/><stop offset="1" stop-color="rgba(120,160,255,0)"/>
</radialGradient>
<linearGradient id="gl" x1="0" y1="0" x2="0" y2="1">
<stop offset="0" stop-color="rgba(208,226,255,0.82)"/><stop offset="0.5" stop-color="rgba(140,168,230,0.34)"/><stop offset="1" stop-color="rgba(70,90,150,0.1)"/>
</linearGradient>
</defs>

<!-- 地面反光 + 接触阴影 -->
<ellipse cx="300" cy="231" rx="266" ry="8" fill="url(#gd)"/>
<ellipse cx="300" cy="231" rx="210" ry="4" fill="rgba(0,0,0,0.5)"/>
${glow}

<!-- 车体（Model S：低趴溜背、长机盖、封闭前脸、短前后悬） -->
<path fill="url(#bd)"
  d="M 84 196
     C 76 190 74 176 78 164
     C 80 155 88 149 102 147
     C 134 143 156 141 172 137
     C 202 116 232 99 268 92
     C 292 87 322 87 346 92
     C 382 100 412 116 438 132
     C 472 141 502 146 518 151
     C 530 155 534 165 531 175
     C 529 186 525 192 520 196
     Z"/>

<!-- 车顶棱线高光（一整条溜背弧） -->
<path d="M 186 134 C 214 114 244 98 270 92 C 294 87 324 87 348 92 C 382 99 410 115 436 130"
  fill="none" stroke="rgba(214,228,255,0.35)" stroke-width="1.6" stroke-linecap="round"/>

<!-- 玻璃屋（风挡+侧窗连续渐晕，B 柱分隔） -->
<path fill="url(#gl)"
  d="M 436 131
     C 412 114 384 98 352 93
     C 324 88 294 88 270 93
     C 238 100 210 116 188 134
     C 268 139 366 137 436 131 Z"/>
<!-- 风挡（更亮的前挡斜面） -->
<path fill="rgba(224,238,255,0.5)"
  d="M 420 130 C 400 112 376 98 354 92 L 342 92 C 366 102 388 118 404 130 Z"/>
<!-- B 柱 -->
<path d="M 306 90 L 306 137 L 318 137 L 319 90 Z" fill="#1c2536"/>
<!-- 玻璃斜向反射亮带 -->
<path d="M 208 122 C 252 106 322 104 378 116" fill="none" stroke="rgba(255,255,255,0.32)" stroke-width="2" stroke-linecap="round"/>
<path d="M 228 130 C 288 122 342 124 390 130" fill="none" stroke="rgba(255,255,255,0.13)" stroke-width="1.6" stroke-linecap="round"/>

<!-- 肩线（贯穿前后灯带的腰线高光） -->
<path d="M 96 152 C 220 146 380 146 516 152" fill="none" stroke="rgba(228,240,255,0.3)" stroke-width="1.6" stroke-linecap="round"/>
<path d="M 110 168 C 230 162 390 162 500 166" fill="none" stroke="rgba(200,220,250,0.13)" stroke-width="1.2" stroke-linecap="round"/>

<!-- 门缝 / 隐藏式门把手 -->
<path d="M 258 196 C 255 172 253 152 251 136" fill="none" stroke="rgba(255,255,255,0.08)" stroke-width="1.2"/>
<path d="M 344 196 C 341 172 339 154 337 138" fill="none" stroke="rgba(255,255,255,0.08)" stroke-width="1.2"/>
<path d="M 266 152 l 22 1" stroke="rgba(255,255,255,0.3)" stroke-width="1.6" stroke-linecap="round"/>
<path d="M 352 150 l 22 1" stroke="rgba(255,255,255,0.3)" stroke-width="1.6" stroke-linecap="round"/>

<!-- 贯穿式前灯带（封闭前脸上一字横灯） -->
<path d="M 494 158 L 532 160" stroke="rgba(224,238,255,0.95)" stroke-width="2.4" stroke-linecap="round"/>
<path d="M 498 164 L 530 165" stroke="rgba(180,205,255,0.45)" stroke-width="1.6" stroke-linecap="round"/>
<!-- 贯穿式尾灯带（红色一字横灯） -->
<path d="M 78 158 L 122 156" stroke="rgba(255,96,84,0.75)" stroke-width="2.2" stroke-linecap="round"/>
<path d="M 78 164 L 110 162" stroke="rgba(255,120,104,0.4)" stroke-width="1.4" stroke-linecap="round"/>

${portGlow}

<!-- 前唇下缘环境光 -->
<path d="M 88 197 L 114 197" stroke="rgba(170,205,255,0.3)" stroke-width="1.8" stroke-linecap="round"/>

<!-- 能量线（充电时增亮） -->
<path fill="none" stroke="${acc}" stroke-linecap="round" ${accStroke}
  d="M 120 190 C 220 182 400 182 500 190"/>

<!-- 前唇 / 后唇阴影 -->
<path d="M 518 195 l 12 0" stroke="rgba(0,0,0,0.6)" stroke-width="3" stroke-linecap="round"/>
<path d="M 84 195 l -7 0" stroke="rgba(0,0,0,0.6)" stroke-width="3" stroke-linecap="round"/>

<!-- 轮拱（挖空 + 唇缘高光） -->
<path d="M ${rearX - archR} ${wy} A ${archR} ${archR} 0 0 1 ${rearX + archR} ${wy} L ${rearX + archR} ${wy + 18} L ${rearX - archR} ${wy + 18} Z" fill="#05070b"/>
<path d="M ${frontX - archR} ${wy} A ${archR} ${archR} 0 0 1 ${frontX + archR} ${wy} L ${frontX + archR} ${wy + 18} L ${frontX - archR} ${wy + 18} Z" fill="#05070b"/>
<path d="M ${rearX - archR} ${wy} A ${archR} ${archR} 0 0 1 ${rearX + archR} ${wy}" fill="none" stroke="rgba(200,220,250,0.28)" stroke-width="2" stroke-linecap="round"/>
<path d="M ${frontX - archR} ${wy} A ${archR} ${archR} 0 0 1 ${frontX + archR} ${wy}" fill="none" stroke="rgba(200,220,250,0.28)" stroke-width="2" stroke-linecap="round"/>

${wheel(rearX, wy, WR)}
${wheel(frontX, wy, WR)}
</svg>`
  );
}

/* 俯视车（胎压卡底图），viewBox 0 0 560 280，车头朝左
   轮位（viewBox 坐标，即覆盖层徽标中心）：FL(155,90) FR(155,190) RL(405,90) RR(405,190)
   覆盖层换算（display 560rpx 宽）：left = x - 74，top = y - 46（徽标 148×92rpx） */
function carTopURI() {
  return uri(
    `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 560 280">
<defs>
<linearGradient id="tp" x1="0" y1="0" x2="0" y2="1">
<stop offset="0" stop-color="#242b3b"/><stop offset="0.5" stop-color="#161a26"/><stop offset="1" stop-color="#0d1018"/>
</linearGradient>
<radialGradient id="ts" cx="0.42" cy="0.5" r="0.62">
<stop offset="0" stop-color="rgba(150,180,240,0.10)"/><stop offset="1" stop-color="rgba(150,180,240,0)"/>
</radialGradient>
<radialGradient id="tg" cx="0.5" cy="0.5" r="0.5">
<stop offset="0" stop-color="rgba(120,160,255,0.12)"/><stop offset="1" stop-color="rgba(120,160,255,0)"/>
</radialGradient>
</defs>
<!-- 地面光晕 -->
<ellipse cx="280" cy="250" rx="228" ry="15" fill="url(#tg)"/>
<!-- 车身（前窄后宽，溜背式封闭曲线） -->
<path fill="url(#tp)" stroke="rgba(185,205,250,0.16)" stroke-width="1.2"
 d="M 92 140 C 92 108 104 84 138 70 C 180 52 232 44 280 44 C 328 44 380 52 422 70 C 456 84 468 108 468 140 C 468 172 456 196 422 210 C 380 228 328 236 280 236 C 232 236 180 228 138 210 C 104 196 92 172 92 140 Z"/>
<!-- 车身中央高光 -->
<path fill="url(#ts)" d="M 92 140 C 92 108 104 84 138 70 C 180 52 232 44 280 44 C 328 44 380 52 422 70 C 456 84 468 108 468 140 C 468 172 456 196 422 210 C 380 228 328 236 280 236 C 232 236 180 228 138 210 C 104 196 92 172 92 140 Z"/>
<!-- 顶部棱线高光 -->
<path d="M 138 70 C 180 52 232 44 280 44 C 328 44 380 52 422 70" fill="none" stroke="rgba(255,255,255,0.12)" stroke-width="1.5" stroke-linecap="round"/>
<!-- 全景玻璃舱（前挡 + 顶 + 后挡连成一体） -->
<path fill="rgba(175,205,255,0.09)" stroke="rgba(255,255,255,0.10)" stroke-width="1"
 d="M 190 102 C 216 92 246 88 280 88 C 314 88 344 92 370 102 C 376 128 376 152 370 178 C 344 188 314 192 280 192 C 246 192 216 188 190 178 C 184 152 184 128 190 102 Z"/>
<!-- 全景天窗 -->
<rect x="232" y="100" width="96" height="80" rx="20" fill="rgba(160,190,240,0.10)" stroke="rgba(255,255,255,0.10)" stroke-width="1"/>
<!-- 前挡 / 后挡分界线 -->
<path d="M 204 94 C 198 120 198 160 204 186" fill="none" stroke="rgba(255,255,255,0.08)" stroke-width="1.2"/>
<path d="M 356 94 C 362 120 362 160 356 186" fill="none" stroke="rgba(255,255,255,0.08)" stroke-width="1.2"/>
<!-- 机盖特征线 -->
<path d="M 112 112 C 134 100 156 94 178 92" fill="none" stroke="rgba(255,255,255,0.07)" stroke-width="1.2" stroke-linecap="round"/>
<path d="M 112 168 C 134 180 156 186 178 188" fill="none" stroke="rgba(255,255,255,0.07)" stroke-width="1.2" stroke-linecap="round"/>
<!-- 门缝 -->
<path d="M 262 92 C 260 122 260 158 262 188" fill="none" stroke="rgba(255,255,255,0.05)" stroke-width="1"/>
<path d="M 330 92 C 332 122 332 158 330 188" fill="none" stroke="rgba(255,255,255,0.05)" stroke-width="1"/>
<!-- 后视镜 -->
<path d="M 188 98 L 174 86" stroke="rgba(255,255,255,0.18)" stroke-width="2" stroke-linecap="round"/>
<path d="M 188 182 L 174 194" stroke="rgba(255,255,255,0.18)" stroke-width="2" stroke-linecap="round"/>
<ellipse cx="168" cy="83" rx="11" ry="5" fill="#0d1017" stroke="rgba(255,255,255,0.28)" stroke-width="1"/>
<ellipse cx="168" cy="197" rx="11" ry="5" fill="#0d1017" stroke="rgba(255,255,255,0.28)" stroke-width="1"/>
<!-- 日行灯 / 贯穿尾灯 -->
<path d="M 97 118 L 115 110" stroke="rgba(140,200,255,0.5)" stroke-width="2.5" stroke-linecap="round"/>
<path d="M 97 162 L 115 170" stroke="rgba(140,200,255,0.5)" stroke-width="2.5" stroke-linecap="round"/>
<path d="M 463 118 C 469 132 469 148 463 162" stroke="rgba(255,90,79,0.42)" stroke-width="2.5" stroke-linecap="round" fill="none"/>
</svg>`
  );
}

/* SOC 光环：粗圆环（径向呼吸光），按 pct 画进度弧
   opts: { pct: 0-100, size?: 300, sw?: 46 } */
function haloURI(opts) {
  const o = opts || {};
  const size = o.size || 300;
  const sw = o.sw || 46;
  const pct = Math.max(0, Math.min(100, Number(o.pct) || 0));
  const cx = size / 2;
  const r = (size - sw) / 2;
  const circ = Math.PI * 2 * r;
  const dash = (circ * pct) / 100;
  return uri(
    `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${size} ${size}">
<defs>
<linearGradient id="hg" x1="0" y1="1" x2="1" y2="0">
<stop offset="0" stop-color="rgba(90,200,250,0.36)"/><stop offset="1" stop-color="rgba(61,123,255,0.3)"/>
</linearGradient>
</defs>
<circle cx="${cx}" cy="${cx}" r="${r}" fill="none" stroke="rgba(120,160,255,0.07)" stroke-width="${sw}"/>
<circle cx="${cx}" cy="${cx}" r="${r}" fill="none" stroke="url(#hg)" stroke-width="${sw}" stroke-linecap="round"
 stroke-dasharray="${dash.toFixed(1)} ${circ.toFixed(1)}" transform="rotate(-90 ${cx} ${cx})"/>
</svg>`
  );
}

/* 空态插画：月光下的停驻（月晕 + 星 + 一封未读的信 + 车灯下的车）
   消息页空状态用 —— 干巴巴的文字换成有氛围的画面。 */
function nightEmptyURI() {
  return uri(
    `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 720 440">
<defs>
<radialGradient id="ng" cx="0.5" cy="0.5" r="0.5">
<stop offset="0" stop-color="rgba(150,190,255,0.10)"/><stop offset="0.7" stop-color="rgba(150,190,255,0.03)"/><stop offset="1" stop-color="rgba(150,190,255,0)"/>
</radialGradient>
<linearGradient id="nb" x1="1" y1="0" x2="0" y2="0">
<stop offset="0" stop-color="rgba(150,190,255,0.20)"/><stop offset="1" stop-color="rgba(150,190,255,0)"/>
</linearGradient>
</defs>

<!-- 月晕与月光 -->
<circle cx="540" cy="118" r="210" fill="url(#ng)"/>
<circle cx="540" cy="118" r="104" fill="none" stroke="rgba(150,190,255,0.12)" stroke-width="1.5"/>
<circle cx="540" cy="118" r="134" fill="none" stroke="rgba(150,190,255,0.06)" stroke-width="1.5"/>
<circle cx="540" cy="118" r="54" fill="#EDF1F7"/>
<circle cx="522" cy="102" r="11" fill="rgba(160,170,185,0.38)"/>
<circle cx="552" cy="134" r="7.5" fill="rgba(160,170,185,0.3)"/>
<circle cx="560" cy="104" r="4.5" fill="rgba(160,170,185,0.26)"/>

<!-- 星 -->
<path d="M96 96 v-12 M90 90 h12" stroke="rgba(255,255,255,0.5)" stroke-width="2" stroke-linecap="round"/>
<path d="M608 62 v-10 M603 57 h10" stroke="rgba(255,255,255,0.35)" stroke-width="2" stroke-linecap="round"/>
<circle cx="226" cy="56" r="3" fill="rgba(255,255,255,0.35)"/>
<circle cx="330" cy="130" r="2.5" fill="rgba(255,255,255,0.28)"/>
<circle cx="652" cy="238" r="2.5" fill="rgba(255,255,255,0.22)"/>
<circle cx="82" cy="196" r="2" fill="rgba(255,255,255,0.25)"/>
<circle cx="446" cy="66" r="2" fill="rgba(255,255,255,0.3)"/>

<!-- 一封未读的信（消息主题） -->
<g transform="translate(150 132) rotate(-6)">
  <circle cx="0" cy="0" r="66" fill="rgba(150,190,255,0.05)"/>
  <rect x="-42" y="-28" width="84" height="56" rx="9" fill="rgba(255,255,255,0.05)" stroke="rgba(205,215,230,0.6)" stroke-width="2"/>
  <path d="M-42 -22 L0 6 L42 -22" fill="none" stroke="rgba(205,215,230,0.6)" stroke-width="2" stroke-linejoin="round"/>
  <circle cx="20" cy="-36" r="5" fill="rgba(255,255,255,0.85)"/>
</g>

<!-- 地平线与地面反光 -->
<line x1="40" y1="336" x2="680" y2="336" stroke="rgba(255,255,255,0.16)" stroke-width="2"/>
<ellipse cx="345" cy="302" rx="150" ry="9" fill="rgba(120,160,255,0.08)"/>
<ellipse cx="345" cy="303" rx="150" ry="6" fill="rgba(0,0,0,0.45)"/>

<!-- 车灯光束（朝左铺开） -->
<path d="M248 272 L136 256 L136 304 L254 290 Z" fill="url(#nb)"/>

<!-- 停驻的车（侧视，面朝左） -->
<path fill="#0d1017"
  d="M 452 296
     C 458 290 456 280 448 276
     L 418 268
     C 410 266 404 260 398 250
     C 388 238 372 234 352 234
     L 322 234
     C 304 234 292 246 286 260
     L 280 272
     C 274 278 266 280 258 278
     L 246 278
     C 240 280 238 288 240 296
     L 452 296 Z"/>
<path d="M322 238 C 342 238 358 242 370 252 C 374 256 376 260 378 264"
  fill="none" stroke="rgba(205,225,255,0.5)" stroke-width="2" stroke-linecap="round"/>
<path d="M 250 297 L 438 297" stroke="rgba(160,200,255,0.28)" stroke-width="1.4" stroke-linecap="round"/>
<circle cx="246" cy="274" r="3.5" fill="#A8C6FF"/>

<!-- 轮拱腔 + 车轮（嵌入车底） -->
<circle cx="282" cy="292" r="20" fill="rgba(2,3,7,0.5)"/>
<circle cx="420" cy="292" r="20" fill="rgba(2,3,7,0.5)"/>
<g>
  <circle cx="282" cy="296" r="16" fill="#07080d" stroke="rgba(255,255,255,0.18)" stroke-width="1.4"/>
  <circle cx="282" cy="296" r="7" fill="none" stroke="rgba(255,255,255,0.4)" stroke-width="1.4"/>
  <circle cx="282" cy="296" r="2" fill="rgba(255,255,255,0.5)"/>
  <circle cx="420" cy="296" r="16" fill="#07080d" stroke="rgba(255,255,255,0.18)" stroke-width="1.4"/>
  <circle cx="420" cy="296" r="7" fill="none" stroke="rgba(255,255,255,0.4)" stroke-width="1.4"/>
  <circle cx="420" cy="296" r="2" fill="rgba(255,255,255,0.5)"/>
</g>
</svg>`
  );
}

/* 登录页夜场：大灯开启的驻车 —— 品牌感的第一帧
   viewBox 0 0 750 470：车体 x 120..620，基线 y=430，轮心 y=432 */
function loginSceneURI() {
  return uri(
    `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 750 470">
<defs>
<radialGradient id="lg" cx="0.5" cy="0.5" r="0.5">
<stop offset="0" stop-color="rgba(150,190,255,0.12)"/><stop offset="0.65" stop-color="rgba(150,190,255,0.03)"/><stop offset="1" stop-color="rgba(150,190,255,0)"/>
</radialGradient>
<linearGradient id="lb" x1="1" y1="0" x2="0" y2="0">
<stop offset="0" stop-color="rgba(160,200,255,0.20)"/><stop offset="1" stop-color="rgba(160,200,255,0)"/>
</linearGradient>
<linearGradient id="lrk" x1="0" y1="0" x2="1" y2="0">
<stop offset="0" stop-color="rgba(150,190,255,0)"/>
<stop offset="0.5" stop-color="rgba(165,205,255,0.4)"/>
<stop offset="1" stop-color="rgba(150,190,255,0)"/>
</linearGradient>
<linearGradient id="lsh" x1="0" y1="1" x2="0" y2="0">
<stop offset="0" stop-color="rgba(0,0,0,0.5)"/>
<stop offset="1" stop-color="rgba(0,0,0,0)"/>
</linearGradient>
<linearGradient id="lgl" x1="0" y1="0" x2="0" y2="1">
<stop offset="0" stop-color="rgba(190,215,255,0.5)"/>
<stop offset="0.55" stop-color="rgba(120,150,215,0.16)"/>
<stop offset="1" stop-color="rgba(60,80,140,0.06)"/>
</linearGradient>
</defs>

<!-- 月与星 -->
<circle cx="648" cy="88" r="150" fill="url(#lg)"/>
<circle cx="648" cy="88" r="34" fill="#EDF1F7" opacity="0.92"/>
<circle cx="640" cy="80" r="6" fill="rgba(160,170,185,0.4)"/>
<circle cx="656" cy="94" r="4" fill="rgba(160,170,185,0.3)"/>
<path d="M96 60 v-12 M90 54 h12" stroke="rgba(255,255,255,0.4)" stroke-width="2" stroke-linecap="round"/>
<circle cx="240" cy="42" r="2.6" fill="rgba(255,255,255,0.32)"/>
<circle cx="420" cy="74" r="2.2" fill="rgba(255,255,255,0.26)"/>
<circle cx="170" cy="140" r="2" fill="rgba(255,255,255,0.22)"/>
<circle cx="560" cy="180" r="2.2" fill="rgba(255,255,255,0.2)"/>

<!-- 地平线与地面反光 -->
<line x1="36" y1="430" x2="714" y2="430" stroke="rgba(255,255,255,0.14)" stroke-width="2"/>
<ellipse cx="360" cy="438" rx="270" ry="12" fill="rgba(120,160,255,0.10)"/>
<ellipse cx="360" cy="440" rx="290" ry="8" fill="rgba(0,0,0,0.5)"/>

<!-- 大灯光束（向左铺开） -->
<path d="M148 396 L4 300 L4 468 L160 424 Z" fill="url(#lb)"/>
<path d="M152 414 L18 388 L18 468 L158 436 Z" fill="url(#lb)" opacity="0.6"/>

<!-- 轮拱腔 -->
<circle cx="265" cy="426" r="52" fill="rgba(2,3,7,0.55)"/>
<circle cx="525" cy="426" r="52" fill="rgba(2,3,7,0.55)"/>

<!-- 车轮 -->
<g>
  <circle cx="265" cy="432" r="44" fill="#07080d" stroke="rgba(255,255,255,0.13)" stroke-width="1.6"/>
  <circle cx="265" cy="432" r="19" fill="none" stroke="rgba(255,255,255,0.3)" stroke-width="2"/>
  <circle cx="265" cy="432" r="4" fill="rgba(255,255,255,0.5)"/>
  <circle cx="525" cy="432" r="44" fill="#07080d" stroke="rgba(255,255,255,0.13)" stroke-width="1.6"/>
  <circle cx="525" cy="432" r="19" fill="none" stroke="rgba(255,255,255,0.3)" stroke-width="2"/>
  <circle cx="525" cy="432" r="4" fill="rgba(255,255,255,0.5)"/>
</g>

<!-- 车体（与车况页同款低鼻 fastback，放大约 1.5×） -->
<path fill="#0d1017"
  d="M 620 430
     C 634 418 632 392 617 376
     C 608 366 594 364 583 371
     L 540 379
     C 526 375 517 367 508 353
     C 491 328 462 310 430 303
     C 392 293 339 298 307 316
     C 280 330 257 351 236 368
     C 216 381 189 387 164 384
     C 143 386 136 406 141 430
     L 620 430 Z"/>
<!-- 玻璃上缘高光 -->
<path d="M 180 392 C 226 376 262 352 290 332 C 322 308 368 300 402 308 C 430 314 452 328 468 346"
  fill="none" stroke="rgba(200,225,255,0.5)" stroke-width="2.6" stroke-linecap="round"/>

<!-- 玻璃屋（渐晕） -->
<path fill="url(#lgl)"
  d="M 468 346
     C 452 328 430 314 402 308
     C 368 300 322 308 290 332
     L 296 344
     C 350 324 420 324 472 352
     Z"/>
<path d="M 320 336 C 380 326 440 326 470 344" fill="none" stroke="rgba(255,255,255,0.14)" stroke-width="2" stroke-linecap="round"/>
<path d="M 310 328 C 360 316 420 314 460 330" fill="none" stroke="rgba(230,240,255,0.5)" stroke-width="1.6" stroke-linecap="round" opacity="0.8"/>

<!-- 门槛投影 + 侧裙反射 -->
<path fill="url(#lsh)" d="M 120 430 L 620 430 L 620 404 C 480 396 240 396 120 404 Z"/>
<path d="M 168 432 L 590 432" stroke="url(#lrk)" stroke-width="3" stroke-linecap="round"/>

<!-- 门缝 -->
<path d="M 300 428 C 296 396 293 372 291 350" fill="none" stroke="rgba(255,255,255,0.07)" stroke-width="1.6"/>

<!-- 灯 -->
<circle cx="146" cy="402" r="5" fill="#CFE4FF"/>
<path d="M 612 400 l 10 2" stroke="rgba(255,110,96,0.45)" stroke-width="2.2" stroke-linecap="round"/>
<path d="M 140 426 L 172 426" stroke="rgba(160,200,255,0.22)" stroke-width="2.2" stroke-linecap="round"/>
</svg>`
  );
}

module.exports = { carSideURI, carTopURI, haloURI, nightEmptyURI, loginSceneURI };
