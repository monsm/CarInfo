const svc = require('../../utils/service');
const VM = require('../../utils/vm');
const AN = require('../../utils/analysis');
const { ic, barsURI } = require('../../utils/icons');
const { carSideURI, carTopURI, haloURI } = require('../../utils/scene');
const { ci, s } = require('../../utils/fmt');
const app = getApp();

const FULL_MS = 30000;
const QUICK_MS = 8000;

Page({
  data: {
    enter: false,
    carName: '',
    carPlate: '',
    carOptions: [],
    carIndex: 0,
    statusText: '',
    statusCls: '',
    energy: {},
    hasData: false,
    shortTime: '',
    metrics: [],
    comfort: {},
    tyre: {},
    loc: {},
    summary: { overall: {}, domains: [] },
    statusRows: [],
    barV: '',
    cellRows: [],
    powerRows: [],
    bodyRows: [],
    bodyOpen: false,
    greeting: '',
    heroPill: { t: '', cls: '' },
    heroSub: '',
    heroHalo: '',
    heroCar: '',
    tyreTop: carTopURI(),
    qctrl: [],
    icons: {
      refresh: ic('refresh', '#8E8E93', 1.6),
      chevD: ic('chevD', '#8E8E93', 1.9),
      chevR: ic('chevR', '#8E8E93', 1.8),
      check: ic('checkc', '#34C759', 3),
      needle: ic('needleN', '#B9C0CC', 1.6),
      kv: {
        air: ic('snow', '#6F7683', 1.6),
        seat: ic('seat', '#6F7683', 1.6),
        temp: ic('temp', '#6F7683', 1.6),
        pm: ic('wind', '#6F7683', 1.6),
        pur: ic('bulb', '#6F7683', 1.6)
      }
    }
  },

  onLoad() {
    if (!svc.getTokenCfg()) { wx.reLaunch({ url: '/pages/login/login' }); return; }
    this.fullTimer = null;
    this.quickTimer = null;
    this.busyFull = false;
    this.busyQuick = false;
    this.visible = false;
  },

  async onShow() {
    this.setData({ enter: false });
    wx.nextTick(() => this.setData({ enter: true }));
    if (this.getTabBar && this.getTabBar()) this.getTabBar().setData({ selected: 0 });
    if (!svc.getTokenCfg()) { wx.reLaunch({ url: '/pages/login/login' }); return; }
    this.visible = true;
    if (!app.globalData.cars || app.globalData.cars.length === 0) {
      await this.ensureCars();
    } else if (!this.data.carOptions.length) {
      this.syncCarSel();
    }
    this.renderAll();
    this.startTimers();
    this.runFullRefresh();
  },

  onHide() { this.visible = false; this.stopTimers(); },
  onUnload() { this.visible = false; this.stopTimers(); },
  onPullDownRefresh() {
    this.runFullRefresh(true).then(() => wx.stopPullDownRefresh());
  },

  startTimers() {
    this.stopTimers();
    this.fullTimer = setInterval(() => this.runFullRefresh(), FULL_MS);
    this.quickTimer = setInterval(() => this.runQuickLocation(), QUICK_MS);
  },
  stopTimers() {
    if (this.fullTimer) { clearInterval(this.fullTimer); this.fullTimer = null; }
    if (this.quickTimer) { clearInterval(this.quickTimer); this.quickTimer = null; }
  },

  async ensureCars() {
    try {
      const [cars, user] = await Promise.all([svc.getCars(), svc.getUser().catch(() => null)]);
      app.globalData.cars = cars || [];
      app.globalData.user = user;
      if (cars && cars.length > 0 && !app.globalData.car) {
        app.globalData.car = cars[0];
        app.globalData.carId = cars[0].CarId || cars[0].carId || '';
      }
      this.syncCarSel();
    } catch (err) {
      this.showStatus(err.message, 'err');
      if (err.noRefresh || /未找到|登录/i.test(err.message)) {
        wx.reLaunch({ url: '/pages/login/login' });
      }
    }
  },

  syncCarSel() {
    const sel = VM.carSel(app.globalData.cars, app.globalData.carId);
    this.setData({ carOptions: sel.options, carIndex: sel.index });
    if (sel.car && app.globalData.carId !== (sel.car.CarId || sel.car.carId)) {
      app.globalData.car = sel.car;
      app.globalData.carId = sel.car.CarId || sel.car.carId || '';
    }
  },

  onCarChange(e) {
    const idx = Number(e.detail.value);
    const car = app.globalData.cars[idx];
    if (!car) return;
    app.globalData.car = car;
    app.globalData.carId = car.CarId || car.carId || '';
    this.setData({ carIndex: idx });
    this.renderAll();
    this.runFullRefresh();
  },

  onManualRefresh() {
    wx.vibrateShort && wx.vibrateShort({ type: 'light' });
    this.runFullRefresh(true);
  },

  noop() {},

  showStatus(msg, cls) {
    this.setData({ statusText: msg || '', statusCls: cls || '' });
  },

  renderAll() {
    const cache = app.globalData.caches;
    const car = app.globalData.car;
    const cv = ci(car || {});

    const e = VM.energy(cache, car);
    const hasData = !!cache.control;

    const now = new Date();
    const hh = now.getHours();
    const gd = hh < 5 ? '夜深了' : hh < 11 ? '早上好' : hh < 13 ? '中午好' : hh < 18 ? '下午好' : '晚上好';
    const greeting = gd + ' · ' + (now.getMonth() + 1) + '月' + now.getDate() + '日 星期' + '日一二三四五六'[now.getDay()];
    let heroPill = { t: '', cls: '' };
    let heroSub = '车辆在线 · 数据 30 秒自动更新';
    if (e.charging) {
      heroPill = { t: '充电中', cls: 'acc' };
      heroSub = '已充 ' + (e.charging.durMin || '--') + ' 分钟';
    } else if (e.chargeText === '充电完成' || e.chargeText === '已充满') {
      heroPill = { t: '已充满', cls: 'ok' };
      heroSub = '已充满 · 可随时出发';
    } else if (e.chargeText && e.chargeText !== '--') {
      heroPill = { t: '未充电', cls: 'na' };
    }
    const socNum = Math.max(0, Math.min(100, parseInt(String(e.soc || '0').replace(/[^\d]/g, ''), 10) || 0));
    const heroCar = carSideURI({ charge: !!e.charging });

    const d = VM.driveStatus(cache);
    const metrics = [
      { k: '车速', v: d.speed, u: 'km/h' },
      { k: '总里程', v: d.mile, u: 'km' }
    ];

    const tyre = VM.tyreStatus(cache);
    const loc = VM.locStatus(cache);

    const summary = AN.summarize(cache, car);

    const heroHalo = hasData ? haloURI({ pct: socNum, size: 345 }) : '';

    const domains = (summary && summary.domains) || [];
    const ST_ICON = { battery: 'soc', charge: 'bolt', tyre: 'tyre', climate: 'wind', body: 'lock', safety: 'shield' };
    const ST_ORDER = ['battery', 'charge', 'tyre', 'climate', 'body', 'safety'];
    const ST_COLOR = { ok: '#D6DAE2', na: '#63666B', warn: '#FFB340', bad: '#FF5A4F' };
    const stMap = {};
    for (const d of domains) stMap[d.key] = d;
    const statusRows = ST_ORDER.filter(k => stMap[k]).map(k => {
      const d = stMap[k];
      const reasons = (d.cls === 'bad' || d.cls === 'warn') ? (d.reasons || []).map(r => r.t) : [];
      return {
        key: d.key,
        label: d.label,
        short: d.short || '--',
        cls: d.cls,
        title: d.title || '',
        reasons,
        reason: reasons.length ? reasons[0] : '',
        url: d.url || '',
        icon: ic(ST_ICON[k], ST_COLOR[d.cls] || '#63666B', 1.7)
      };
    });

    const b = VM.batteryModel(cache);
    let barV = '';
    const cellRows = [];
    const alarmSet = {};
    b.alarms.forEach(a => { alarmSet[a] = true; });
    if (b.cellStats) {
      barV = barsURI(b.cellStats.bars, { width: 640, height: 64, color: 'rgba(255,255,255,0.8)', maxBars: 64 });
      const dv = b.diffV !== null ? b.diffV : +(b.cellStats.max - b.cellStats.min).toFixed(3);
      cellRows.push({ k: '压差', v: Number(dv).toFixed(3) + ' V', cls: alarmSet['一致性差异'] ? 'bad' : 'ok' });
    } else {
      cellRows.push({ k: '单体电压', v: '接口未上报', cls: 'na' });
    }
    if (b.probeStats) {
      const dt = b.diffT !== null ? b.diffT : +(b.probeStats.max - b.probeStats.min).toFixed(1);
      cellRows.push({ k: '温差', v: Number(dt).toFixed(1) + ' ℃', cls: alarmSet['温差过大'] ? 'bad' : 'ok' });
    }

    const powerRows = [];
    if (b.motors.length) {
      const m = b.motors[0];
      const parts = [];
      if (m.rpm !== '--') parts.push(m.rpm + ' rpm');
      if (m.torque !== '--') parts.push(m.torque + ' N·m');
      if (parts.length) powerRows.push({ k: b.motors.length > 1 ? '驱动电机（' + b.motors.length + ' 台）' : '驱动电机', v: parts.join(' · ') });
      const tParts = [];
      if (m.temp !== '--') tParts.push(m.temp + ' ℃');
      if (m.ctrlTemp !== '--') tParts.push('控制器 ' + m.ctrlTemp + ' ℃');
      if (tParts.length) powerRows.push({ k: '电机温度', v: tParts.join(' · ') });
    }

    const bd = VM.bodyDetailModel(cache);
    const bodyRows = bd.doorRows.concat(bd.extraRows).concat(bd.windowRows).map(r => ({ label: r.k, text: r.v, cls: r.cls }));
    if (bd.lampRows.length) {
      bodyRows.push({ label: '灯光', text: bd.lit.length ? bd.lit.join('、') : '全部关闭', cls: 'ok' });
    }

    const qctrl = [
      { key: 'lock', label: '锁车', icon: ic('lock', '#E8EAEE', 1.9) },
      { key: 'unlock', label: '解锁', icon: ic('unlock', '#E8EAEE', 1.9) },
      { key: 'air', label: '空调', icon: ic('snow', '#5AC8FA', 1.9) },
      { key: 'charge', label: '充电', icon: ic('bolt', '#5AC8FA', 1.9) }
    ];

    this.setData({
      carName: cv.CarName || e.carName,
      carPlate: s(cv.PlateNumber) || '',
      energy: e,
      hasData,
      shortTime: e.updated !== '--' && e.updated.length > 10 ? e.updated.slice(5, 16) : '--',
      statusRows,
      metrics,
      comfort: VM.comfortStatus(cache),
      tyre,
      loc,
      summary,
      barV,
      cellRows,
      powerRows,
      bodyRows,
      bodySummary: bd.summary,
      greeting,
      heroPill,
      heroSub,
      heroHalo,
      heroCar,
      qctrl
    });
  },

  onQuickCtrl(e) {
    const key = e.currentTarget.dataset.key;
    wx.vibrateShort && wx.vibrateShort({ type: 'light' });
    if (key === 'charge') {
      wx.navigateTo({ url: '/pages/battery/battery' });
      return;
    }
    const app2 = getApp();
    app2.globalData.pendingQuickCtrl = key;
    wx.switchTab({ url: '/pages/control/control' });
  },

  toggleBody() {
    this.setData({ bodyOpen: !this.data.bodyOpen });
  },

  goBattery() {
    wx.navigateTo({ url: '/pages/battery/battery' });
  },

  onDomainTap(e) {
    const key = e.currentTarget.dataset.key;
    const item = (this.data.statusRows || []).find(r => r.key === key);
    if (!item) return;
    if (item.reasons && item.reasons.length) {
      wx.showModal({
        title: item.label + ' · ' + (item.title || '状态关注'),
        content: item.reasons.map(t => '· ' + t).join('\n'),
        cancelText: '关闭',
        confirmText: item.url ? '查看详情' : '知道了',
        success: res => {
          if (res.confirm && item.url) wx.navigateTo({ url: item.url });
        }
      });
      return;
    }
    if (key === 'tyre') {
      wx.pageScrollTo({ selector: '#tyreAnchor', duration: 320 });
      return;
    }
    if (item.url) wx.navigateTo({ url: item.url });
  },

  async runFullRefresh(showOk) {
    if (this.busyFull) return;
    const carId = app.globalData.carId;
    if (!carId) return;
    this.busyFull = true;
    try {
      const data = await svc.fetchCore(carId);
      app.saveCache(data);
      this.renderAll();
      if (showOk) wx.showToast({ title: '已更新', icon: 'success', duration: 900 });
    } catch (err) {
      if (this.visible) {
        wx.showToast({ title: '刷新失败', icon: 'none' });
        if (/未找到|登录/.test(err.message)) wx.reLaunch({ url: '/pages/login/login' });
      }
    } finally {
      this.busyFull = false;
    }
  },

  async runQuickLocation() {
    if (this.busyQuick) return;
    const carId = app.globalData.carId;
    if (!carId) return;
    this.busyQuick = true;
    try {
      const loc = await svc.getLocation(carId);
      if (loc) {
        app.saveCache({ location: loc });
        this.renderAll();
      }
    } catch (e) {  }
    finally { this.busyQuick = false; }
  },

  openMap() {
    const { loc } = this.data;
    if (!loc || loc.lat === '--' || loc.lng === '--') {
      wx.showToast({ title: '暂无定位数据', icon: 'none' });
      return;
    }
    wx.openLocation({
      latitude: Number(loc.lat),
      longitude: Number(loc.lng),
      scale: 16,
      name: '车辆位置',
      address: loc.addr || ''
    });
  },

  goHealth() {
    wx.navigateTo({ url: '/pages/health/health' });
  },

  onLocImgErr() {
    this.setData({ 'loc.snap': '' });
  }
});
