// data.js —— 全量数据页：把 texts.js 生成的逐字段文本结构化为“组 + 键值行”的专业排版
// 覆盖 kind：status / charge / location / env / user / car / check / analysis（全量分析）
const svc = require('../../utils/service');
const T = require('../../utils/texts');
const AN = require('../../utils/analysis');
const { ic, stripLeading } = require('../../utils/icons');
const app = getApp();

const KINDS = {
  status:   { title: '全量车况数据', build: d => T.statusText(d),      load: c => svc.getControl(c),     cacheKey: 'control' },
  charge:   { title: '充电数据',     build: d => T.chargeText(d),      load: c => svc.getCharge(c),      cacheKey: 'charge' },
  location: { title: '定位数据',     build: d => T.locationText(d),    load: c => svc.getLocation(c),    cacheKey: 'location' },
  env:      { title: '环境与PM2.5',  build: d => T.envText(d),         load: c => svc.getCarPm25(c),     cacheKey: 'pm25' },
  check:    { title: '检测报告原文', build: d => T.checkText(d),       load: c => svc.getCarCheck(c),    cacheKey: 'check' },
  user:     { title: '用户资料',     build: d => T.userText(d),        load: null,                       cacheKey: 'user' },
  car:      { title: '车辆档案原文', build: d => T.carText(d),         load: null,                       cacheKey: 'car' },
  analysis: { title: '全量分析',     build: null,                      load: null,                       cacheKey: null }
};
const EMPTY_TXT = {
  status: '暂无全车状态数据', charge: '暂无充电数据', location: '暂无定位数据',
  env: '暂无环境数据', check: '暂无检测报告', user: '暂无用户资料', car: '暂无车辆档案',
  analysis: '暂无分析数据（请先刷新车况）'
};

// 解析 texts.js 的纯文本 → [{ h, rows:[{k,v}] }]
function parseText(text) {
  const blocks = [];
  let cur = null;
  const lines = String(text || '').split('\n');
  lines.forEach(line => {
    const t = line.replace(/\r/g, '');
    if (!t.trim()) return;
    const trimmed = t.trim();
    // 分隔装饰线
    if (/^[═─━]+$/.test(trimmed)) return;
    // 是否 “键 : 值”（texts 输出固定用中文全角冒号前的空格分割）
    const idx = trimmed.indexOf(' : ');
    if (idx > 0) {
      const k = trimmed.slice(0, idx).trim();
      const v = trimmed.slice(idx + 3).trim();
      if (!cur) { cur = { h: '', rows: [] }; blocks.push(cur); }
      cur.rows.push({ k, v });
      return;
    }
    // 否则视为新组标题（去掉 emoji 等前缀装饰）
    cur = { h: stripLeading(trimmed), rows: [] };
    blocks.push(cur);
  });
  return blocks.filter(b => b.h || b.rows.length);
}

Page({
  data: {
    kind: 'status',
    title: '',
    blocks: [],
    hasData: false,
    loading: true,
    errText: '',
    updatedAt: '',
    icons: {
      copy: ic('copy', '#8E8E93', 1.6),
      refresh: ic('refresh', '#8E8E93', 1.6)
    }
  },

  onLoad(options) {
    const kind = options.kind || 'status';
    const meta = KINDS[kind];
    this.kind = kind;
    this.meta = meta;
    if (!meta) { wx.navigateBack(); return; }
    if (!svc.getTokenCfg()) { wx.reLaunch({ url: '/pages/login/login' }); return; }
    wx.setNavigationBarTitle({ title: meta.title });
    this.setData({ kind, title: meta.title });
    this.renderCache();
    this.load(true);
  },

  onPullDownRefresh() { this.load(false).finally(() => wx.stopPullDownRefresh()); },

  rawSource() {
    const { cacheKey } = this.meta;
    if (cacheKey === 'car') return app.globalData.car;
    if (cacheKey === 'user') return app.globalData.user;
    return app.globalData.caches[cacheKey];
  },

  renderCache() {
    if (this.kind === 'analysis') { this.apply(null, false); return; }
    const raw = this.rawSource();
    if (raw === null || raw === undefined) {
      this.setData({ blocks: [], hasData: false, loading: true });
    } else {
      this.apply(raw, false);
    }
  },

  // 全量分析：统一分析层输出的“结论树”（总评 → 各域结论 → 原因 → 关键指标）
  analysisBlocks() {
    const A = AN.summarize(app.globalData.caches, app.globalData.car);
    const blocks = [];
    blocks.push({
      h: '综合结论',
      rows: [{ k: '状态', v: A.overall.title || '--' }, { k: '说明', v: A.overall.sub || '' }].filter(r => r.v)
    });
    A.domains.forEach(d => {
      const rows = [];
      if (d.title) rows.push({ k: '结论', v: d.title });
      (d.reasons || []).forEach(r => rows.push({
        k: r.cls === 'bad' ? '异常' : (r.cls === 'warn' ? '关注' : '正常'),
        v: r.t
      }));
      (d.metrics || []).forEach(m => rows.push({ k: m.k, v: m.v }));
      blocks.push({ h: d.label, rows });
    });
    return blocks;
  },

  apply(raw, fresh) {
    try {
      let blocks;
      if (this.kind === 'analysis') {
        blocks = this.analysisBlocks();
      } else {
        const text = this.meta.build(raw);
        blocks = parseText(text);
      }
      const totalRows = blocks.reduce((n, b) => n + (b.rows ? b.rows.length : 0), 0);
      this.setData({
        blocks,
        totalRows,
        hasData: true,
        loading: false,
        errText: '',
        updatedAt: fresh ? new Date().toLocaleString('zh-CN', { hour12: false }) : this.data.updatedAt
      });
    } catch (err) {
      this.setData({ loading: false, errText: '数据解析失败：' + err.message });
    }
  },

  async load(fromLoad) {
    if (this.kind === 'analysis') {
      const caches = app.globalData.caches;
      if (caches && caches.control) {
        this.apply(null, true);
      } else {
        this.setData({ loading: false, errText: EMPTY_TXT.analysis });
      }
      return;
    }
    const carId = app.globalData.carId;
    if (!carId && this.meta.load) {
      this.setData({ loading: false, errText: '请先在车况页选择车辆' });
      return;
    }
    try {
      let raw;
      if (this.meta.load) {
        raw = await this.meta.load(carId);
        if (raw === null || raw === undefined) {
          this.setData({ hasData: false, loading: false, errText: EMPTY_TXT[this.kind] || '接口未返回数据' });
          return;
        }
        if (this.meta.cacheKey !== 'user') app.saveCache({ [this.meta.cacheKey]: raw });
      } else {
        // user/car：从全局缓存取，必要时拉取
        if (this.kind === 'user') {
          raw = app.globalData.user || await svc.getUser();
          app.globalData.user = raw;
        } else {
          const cars = app.globalData.cars && app.globalData.cars.length
            ? app.globalData.cars
            : await svc.getCars();
          app.globalData.cars = cars || [];
          raw = (cars || []).find(c => (c.CarId || c.carId) === carId) || app.globalData.car;
        }
        if (!raw) {
          this.setData({ hasData: false, loading: false, errText: EMPTY_TXT[this.kind] || '暂无数据' });
          return;
        }
      }
      this.apply(raw, true);
    } catch (err) {
      this.setData({ loading: false, errText: err.message || '加载失败' });
      if (!fromLoad) wx.showToast({ title: '刷新失败', icon: 'none' });
    }
  },

  copyAll() {
    if (this.kind === 'analysis') {
      try {
        const lines = [];
        this.analysisBlocks().forEach(b => {
          if (b.h) lines.push('【' + b.h + '】');
          (b.rows || []).forEach(r => lines.push(r.k + ' : ' + r.v));
        });
        wx.setClipboardData({
          data: lines.join('\n'),
          success: () => wx.showToast({ title: '已复制全部结论', icon: 'success' })
        });
      } catch (err) {
        wx.showToast({ title: '复制失败', icon: 'none' });
      }
      return;
    }
    const raw = this.rawSource();
    if (raw === null || raw === undefined) {
      wx.showToast({ title: '暂无可复制数据', icon: 'none' });
      return;
    }
    try {
      const text = this.meta.build(raw);
      wx.setClipboardData({
        data: text,
        success: () => wx.showToast({ title: '已复制全部字段', icon: 'success' })
      });
    } catch (err) {
      wx.showToast({ title: '复制失败', icon: 'none' });
    }
  }
});
