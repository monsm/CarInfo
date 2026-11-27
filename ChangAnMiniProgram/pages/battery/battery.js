const svc = require('../../utils/service');
const VM = require('../../utils/vm');
const AN = require('../../utils/analysis');
const { barsURI, ic } = require('../../utils/icons');
const { haloURI } = require('../../utils/scene');
const app = getApp();

Page({
  data: {
    ready: false,
    soc: '--',
    chargeTitle: '--',
    chargeCls: '',
    range: '--',
    barV: '',
    barT: '',
    cellText: '',
    probeText: '',
    bhHalo: '',
    cellChips: [],
    tempChips: [],
    cellStats: [],
    tempStats: [],
    cellRows: [],
    tempRows: [],
    chargeRows: [],
    subV: [],
    subT: [],
    motors: [],
    faultTotal: 0,
    faults: [],
    alarms: [],
    updated: '--',
    head: { cls: 'na', title: '', reasons: [] },
    icons: {
      refresh: ic('refresh', '#8E8E93', 1.6),
      soc: ic('soc', '#6F7683', 1.6)
    }
  },

  onLoad() {
    if (!svc.getTokenCfg()) { wx.reLaunch({ url: '/pages/login/login' }); return; }
    if (!app.globalData.carId) { wx.navigateBack(); return; }
    this.renderCache();
    this.load();
  },

  onPullDownRefresh() {
    this.load().finally(() => wx.stopPullDownRefresh());
  },

  renderCache() {
    const cache = app.globalData.caches;
    if (cache && cache.control) this.build(cache);
  },

  async load() {
    const carId = app.globalData.carId;
    if (!carId) return;
    try {
      const [charge, control] = await Promise.all([
        svc.getCharge(carId).catch(() => null),
        svc.getControl(carId).catch(() => null)
      ]);
      const cache = Object.assign({}, app.globalData.caches);
      const patch = {};
      if (charge) { cache.charge = charge; patch.charge = charge; }
      if (control) { cache.control = control; patch.control = control; }
      if (Object.keys(patch).length) app.saveCache(patch);
      this.build(cache);
    } catch (err) {
      if (/未找到|登录|token/i.test(err.message || '')) {
        wx.reLaunch({ url: '/pages/login/login' });
        return;
      }
      const caches = app.globalData.caches || {};
      if (!caches.control) {
        this.setData({ ready: false });
        wx.showToast({ title: '数据获取失败，请下拉重试', icon: 'none' });
      }
    }
  },

  refresh() { this.load(); },

  build(cache) {
    const b = VM.batteryModel(cache);
    const e = VM.energy(cache, app.globalData.car);

    const A = AN.summarize(cache, app.globalData.car);
    const batt = A.domains.find(d => d.key === 'battery') || {};
    const head = {
      cls: batt.cls || 'na',
      title: batt.title || '--',
      reasons: (batt.reasons || []).slice(0, 3)
    };

    const barV = b.cellStats && b.cellStats.bars && b.cellStats.bars.length
      ? barsURI(b.cellStats.bars, { width: 640, height: 64, color: 'rgba(255,255,255,0.8)', maxBars: 64 }) : '';
    const barT = b.probeStats && b.probeStats.bars && b.probeStats.bars.length
      ? barsURI(b.probeStats.bars, { width: 640, height: 64, color: 'rgba(255,255,255,0.42)', maxBars: 64 }) : '';

    let cellText = '', probeText = '', cellRows = [], tempRows = [];
    const cellStats = [], tempStats = [], cellChips = [], tempChips = [];
    if (b.cellStats) {
      cellText = `${b.cellStats.count} 节采样`;
      const diff = b.diffV !== null ? b.diffV : +(b.cellStats.max - b.cellStats.min).toFixed(3);
      const fmt3 = x => Number(x).toFixed(3);
      cellStats.push(
        { k: '最高', v: fmt3(b.cellStats.max) },
        { k: '最低', v: fmt3(b.cellStats.min) },
        { k: '平均', v: fmt3(b.cellStats.avg) }
      );
      cellChips.push(
        { k: '最高', v: fmt3(b.cellStats.max) + ' V' },
        { k: '最低', v: fmt3(b.cellStats.min) + ' V' },
        { k: '压差', v: fmt3(diff) + ' V', cls: diff >= 0.05 ? 'bad' : 'ok' }
      );
      cellRows.push({ k: '压差', v: fmt3(diff) + ' V', cls: diff >= 0.05 ? 'bad' : 'ok' });
    } else {
      cellRows.push({ k: '单体电压', v: '接口未上报（电压列表为空）', cls: '' });
    }
    if (b.probeStats) {
      probeText = `${b.probeStats.count} 个探针`;
      const diff = b.diffT !== null ? b.diffT : +(b.probeStats.max - b.probeStats.min).toFixed(1);
      tempStats.push(
        { k: '最高', v: Number(b.probeStats.max).toFixed(1) },
        { k: '最低', v: Number(b.probeStats.min).toFixed(1) },
        { k: '温差', v: Number(diff).toFixed(1) }
      );
      tempChips.push(
        { k: '最高', v: Number(b.probeStats.max).toFixed(1) + ' ℃' },
        { k: '最低', v: Number(b.probeStats.min).toFixed(1) + ' ℃' },
        { k: '温差', v: Number(diff).toFixed(1) + ' ℃', cls: diff >= 5 ? 'bad' : 'ok' }
      );
    } else {
      tempRows.push({ k: '探针温度', v: '接口未上报（探针列表为空）', cls: '' });
    }

    const C = b.charging;
    const chgRows = [];
    if (C.text !== '未充电') {
      [['当前电量', C.soc !== '--' ? C.soc + '%' : '--'],
        ['剩余续航', C.range !== '--' ? C.range + ' km' : '--'],
        ['充电功率', C.power], ['已充时长', C.durMin !== '--' ? C.durMin + ' 分钟' : '--'],
        ['开始时间', C.start], ['结束时间', C.end]]
        .forEach(r => { if (r[1] !== '--') chgRows.push({ k: r[0], v: r[1], cls: '' }); });
    }
    [['电源线路', C.powerLine], ['电池加热', C.heating],
      ['预约充电', C.reservation], ['预约用车', C.reserveTime]]
      .forEach(r => { if (r[1] !== '--' && r[1] !== '') chgRows.push({ k: r[0], v: r[1], cls: '' }); });
    if (!chgRows.length) chgRows.push({ k: '充电', v: '暂无充电会话数据', cls: '' });

    const subV = b.subsystems.map(sub => ({
      k: sub.num === '--' ? '子系统' : '子系统 ' + sub.num,
      v: [sub.count !== '--' ? sub.count + ' 串' : '', sub.volt !== '--' ? sub.volt + ' V' : '',
        sub.amp !== '--' ? sub.amp + ' A' : '', sub.vMin !== '--' ? sub.vMin + '~' + sub.vMax + ' V' : '']
        .filter(Boolean).join(' · ')
    }));
    const subT = b.tempSubs.map(sub => ({
      k: sub.num === '--' ? '子系统' : '子系统 ' + sub.num,
      v: [sub.count !== '--' ? sub.count + ' 探针' : '', sub.tMin !== '--' ? sub.tMin + '~' + sub.tMax + ' ℃' : '']
        .filter(Boolean).join(' · ')
    }));

    const motors = b.motors.map(m => {
      const rows = [];
      if (m.state !== '--') rows.push({ k: '状态', v: m.state, cls: '' });
      if (m.rpm !== '--') rows.push({ k: '转速', v: m.rpm + ' rpm', cls: '' });
      if (m.torque !== '--') rows.push({ k: '扭矩', v: m.torque + ' N·m', cls: '' });
      if (m.temp !== '--') rows.push({ k: '电机温度', v: m.temp + ' ℃', cls: '' });
      if (m.ctrlTemp !== '--') rows.push({ k: '控制器温度', v: m.ctrlTemp + ' ℃', cls: '' });
      if (m.inputV !== '--') rows.push({ k: '控制器输入电压', v: m.inputV + ' V', cls: '' });
      if (m.dcBus !== '--') rows.push({ k: '母线电流', v: m.dcBus + ' A', cls: '' });
      return { name: m.num === '--' ? '驱动电机' : '驱动电机 #' + m.num, rows };
    });

    const faults = b.faults.items
      .filter(f => f.count > 0)
      .map(f => ({ k: f.name, v: f.count + ' 条', codes: f.codes }));
    const alarmRows = b.alarms.map(a => ({ k: a, v: '触发', cls: 'bad' }));

    const socNum = Math.max(0, Math.min(100, parseInt(String(e.soc || '0').replace(/[^\d]/g, ''), 10) || 0));
    const bhHalo = haloURI({ pct: socNum, size: 420 });
    this.setData({
      ready: true,
      soc: e.soc,
      chargeTitle: e.chargeText,
      chargeCls: e.chargeCls,
      range: e.range,
      barV, barT,
      bhHalo, cellChips, tempChips,
      cellText, probeText,
      cellStats, tempStats, cellRows, tempRows,
      chargeRows: chgRows,
      subV, subT,
      motors,
      faultTotal: b.faults.total,
      faults,
      alarms: alarmRows,
      head,
      updated: e.updated !== '--' && e.updated.length > 10 ? e.updated.slice(5, 16) : '--'
    });
  }
});
