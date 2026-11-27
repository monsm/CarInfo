const svc = require('../../utils/service');
const VM = require('../../utils/vm');
const { ic } = require('../../utils/icons');
const { haloURI } = require('../../utils/scene');
const app = getApp();

Page({
  data: {
    score: '--',
    time: '',
    counts: [],
    systems: [],
    ringImg: '',
    hasData: false,
    loading: true,
    errText: '',
    icons: {
      chevU: ic('chevU', '#8E8E93', 1.8),
      chevD: ic('chevD', '#8E8E93', 1.8),
      shield: ic('shield', '#6F7683', 1.6),
      refresh: ic('refresh', '#F5F7FA', 1.6)
    }
  },

  onLoad() {
    if (!svc.getTokenCfg()) { wx.reLaunch({ url: '/pages/login/login' }); return; }
    const cached = app.globalData.caches.check;
    if (cached) this.apply(cached);
    this.load();
  },

  onPullDownRefresh() { this.load().finally(() => wx.stopPullDownRefresh()); },

  async load() {
    const carId = app.globalData.carId;
    if (!carId) { this.setData({ loading: false, errText: '请先在车况页选择车辆' }); return; }
    try {
      const raw = await svc.getCarCheck(carId);
      app.saveCache({ check: raw });
      if (!raw) { this.setData({ loading: false, hasData: false }); return; }
      this.apply(raw);
      this.setData({ loading: false });
    } catch (err) {
      this.setData({ loading: false, hasData: false, errText: err.message });
    }
  },

  apply(raw) {
    const h = VM.healthModel(raw);
    if (!h) { this.setData({ loading: false, hasData: false }); return; }
    const pct = Math.max(0, Math.min(100, parseInt(String(h.score || '0').replace(/[^\d]/g, ''), 10) || 0));
    this.setData({
      score: h.score,
      time: h.time,
      counts: h.counts,
      systems: h.systems,
      ringImg: haloURI({ pct, size: 320, sw: 34 }),
      hasData: true,
      loading: false
    });
  },

  onToggle(e) {
    const idx = Number(e.currentTarget.dataset.idx);
    this.setData({ [`systems[${idx}].open`]: !this.data.systems[idx].open });
  }
});
