// dev.js —— 开发者工具 v3（工程入口，隐藏在主流程之外）
const svc = require('../../utils/service');
const C = require('../../utils/config');
const { ic } = require('../../utils/icons');
const app = getApp();

Page({
  data: {
    cloud: true,
    loginDirect: false,
    fnVersion: '',
    modeText: '',
    logOpen: false,
    logText: '',
    logCount: 0,
    envId: '',
    icons: {
      chevD: ic('chevD', '#8E8E93', 1.8),
      chevU: ic('chevU', '#8E8E93', 1.8),
      refresh: ic('refresh', '#8E8E93', 1.6),
      copy: ic('copy', '#8E8E93', 1.6),
      trash: ic('trash', '#FF6B5E', 1.6)
    }
  },

  onLoad() {
    const fnVersion = svc.getFnVersion();
    this.setData({
      cloud: !!C.USE_CLOUD,
      loginDirect: !!C.LOGIN_VIA_DIRECT,
      fnVersion,
      envId: C.CLOUD_ENV || '默认环境',
      modeText: this.buildModeText(fnVersion)
    });
  },

  buildModeText(ver) {
    if (C.USE_CLOUD) {
      let t = '云函数代理 changanProxy';
      if (C.LOGIN_VIA_DIRECT) t += '（登录直连）';
      return ver ? `${t} · v${ver}` : `${t} · 版本未知`;
    }
    return '直连模式（需配置合法域名）';
  },

  toggleLog() {
    const open = !this.data.logOpen;
    this.setData({ logOpen: open });
    if (open) this.refreshLog();
  },
  refreshLog() {
    const logs = svc.getRawLogs();
    this.setData({
      logCount: logs.length,
      logText: logs.length ? logs.join('\n\n──────────\n\n') : '（暂无记录：先发起一次请求，如刷新数据或下发指令）'
    });
  },
  copyLog() {
    if (!this.data.logText) this.refreshLog();
    wx.setClipboardData({
      data: this.data.logText || '（暂无日志）',
      success: () => wx.showToast({ title: '已复制', icon: 'success' })
    });
  },
  clearLog() {
    wx.showModal({
      title: '清空请求日志',
      content: '确定清空本地请求 / 响应原文日志吗？',
      confirmText: '清空',
      confirmColor: '#FF453A',
      success: res => {
        if (!res.confirm) return;
        svc.clearRawLogs();
        this.setData({ logText: '（已清空）', logCount: 0 });
      }
    });
  },

  copyGuide(e) {
    const kind = e.currentTarget.dataset.guide;
    const text = kind === 'deploy'
      ? '云函数部署步骤：\n1. 开发者工具左侧 cloudfunctions/changanProxy 目录\n2. 右键 → 上传并部署：云端安装依赖\n3. 确认 utils/config.js 的 CLOUD_ENV 为环境 ID\n4. 部署后在 云开发 → 云函数 → changanProxy → 日志 确认无报错'
      : '短信 / 登录失败排查：\n1. 重新部署云函数（见部署步骤）后刷新图形验证码重试\n2. 仍失败：utils/config.js 的 LOGIN_VIA_DIRECT 改为 true，勾选“不校验合法域名”直连登录\n3. 真机预览勾选“开启调试”，手机连家里 WiFi（与桌面版同出口 IP）\n4. 将本页请求日志复制给开发者（含 REQ / RES 原文）';
    wx.setClipboardData({
      data: text,
      success: () => wx.showToast({ title: '指引已复制', icon: 'success' })
    });
  },

  clearCache() {
    wx.showModal({
      title: '清除数据缓存',
      content: '删除本地缓存的车辆数据（不影响登录态），下次进入自动重新拉取。',
      confirmText: '清除',
      confirmColor: '#FF453A',
      success: res => {
        if (!res.confirm) return;
        app.saveCache({ charge: null, pm25: null, location: null, control: null, check: null, messages: null });
        wx.showToast({ title: '已清除', icon: 'success' });
      }
    });
  }
});
