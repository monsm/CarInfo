const svc = require('../../utils/service');
const VM = require('../../utils/vm');
const { ci, s, num } = require('../../utils/fmt');
const { ic } = require('../../utils/icons');
const app = getApp();

Page({
  data: {
    name: '',
    plate: '',
    isNev: false,
    pinText: '--',
    vin: '',
    groups: [],
    srvChips: [],
    icons: { copy: ic('copy', '#8E8E93', 1.6) }
  },

  onLoad() {
    if (!svc.getTokenCfg()) { wx.reLaunch({ url: '/pages/login/login' }); return; }
    this.render();
  },

  onPullDownRefresh() {
    this.refresh().finally(() => wx.stopPullDownRefresh());
  },

  async refresh() {
    try {
      const cars = await svc.getCars();
      app.globalData.cars = cars || [];
      const cur = (cars || []).find(c => (c.CarId || c.carId) === app.globalData.carId);
      if (cur) app.globalData.car = cur;
      this.render();
    } catch (err) {
      wx.showToast({ title: '刷新失败', icon: 'none' });
    }
  },

  render() {
    const v = ci(app.globalData.car);
    if (!v) { this.setData({ groups: [] }); return; }
    const pinCN = { exist: '已设置', none: '未设置' };
    const pinKey = String(v.Pin == null ? '' : v.Pin).toLowerCase();

    const groups = [];
    const push = (keyVal, name, monoKeys) => {
      const rows = [];
      Object.keys(keyVal).forEach(k => {
        const val = keyVal[k];
        if (val === null || val === undefined || val === '') return;
        rows.push({ k, v: s(val), mono: !!(monoKeys && monoKeys[k]) });
      });
      if (rows.length) groups.push({ name, rows });
    };

    push({
      'VIN': v.Vin,
      '车辆ID': v.CarId,
      '车辆名称': v.CarName,
      '车牌号': v.PlateNumber,
      '能源类型': num(v.IsNev) === 1 ? '新能源' : '燃油车'
    }, '身份信息', { VIN: true, 车辆ID: true });

    push({
      '车型代码': v.ModelCode, '配置': v.ConfName || v.ConfCode,
      '品牌': v.BrandCode, '车系': v.SeriesCode,
      '车辆类型': v.CarType, '颜色': v.Color || '未设置',
      '设备类型': v.CurrentDeviceType, '发动机号': v.EngineNo,
      '租户': v.TenantId
    }, '车型配置');

    const sum = VM.vehicleSummary(app.globalData.car);
    const insD = sum ? sum.insuranceDays : null;
    const srvD = sum ? sum.serviceDays : null;
    const insVal = v.InsuranceEndDate
      ? `${s(v.InsuranceEndDate)}${insD === null ? '' : (insD < 0 ? '（已到期）' : `（剩 ${insD} 天）`)}`
      : null;
    const srvChips = [];
    const pushChip = (label, days) => {
      if (days === null) return;
      srvChips.push({
        label,
        text: days < 0 ? '已到期' : `剩 ${days} 天`,
        cls: days < 0 ? 'bad' : (days <= 30 ? 'warn' : 'ok')
      });
    };
    pushChip('保险', insD);
    pushChip('服务', srvD);

    push({
      '注册时间': v.RegisterTime, '产品时间': v.ProductTime,
      '保险到期': insVal, '保险公司': v.InsuranceCompany,
      '保险电话': v.InsurancePhone
    }, '注册与保险');

    push({
      '保养间隔': v.MaintainSpaceMileage ? `${num(v.MaintainSpaceMileage)} km` : null,
      '上次保养': v.LastMaintainMileage ? `${num(v.LastMaintainMileage)} km` : null,
      '隐私驾驶记录': num(v.IsPrivacyDrvingHistory) === 1 ? '启用' : '关闭',
      '最后在线': v.LastOnlineTime, '激活时间': v.ActiveTime
    }, '服务与保养');

    const ctl = (app.globalData.caches && app.globalData.caches.control) || {};
    push({
      '协议版本': ctl.protocolVer != null ? `V${ctl.protocolVer}` : null,
      '点火时间': ctl.ignitionTime,
      '报文登录时间': ctl.lastLoginTime
    }, '车况报文');

    this.setData({
      name: s(v.CarName),
      plate: s(v.PlateNumber),
      isNev: num(v.IsNev) === 1,
      pinText: pinCN[pinKey] || (v.Pin ? s(v.Pin) : '--'),
      vin: s(v.Vin),
      groups,
      srvChips
    });
  },

  copyVin() {
    const v = ci(app.globalData.car);
    const vin = v && v.Vin;
    if (!vin) return;
    wx.setClipboardData({
      data: s(vin),
      success: () => wx.showToast({ title: 'VIN 已复制', icon: 'success' })
    });
  }
});
