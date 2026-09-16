// messages.js —— 消息中心 v4（极简列表 + 内联展开详情）
// 注意：真实报文里 MessageItem 只有 Id/Title/Content/CreatedAt/ReadStatus/RealReceiverId，
// 且桌面版实测把 Content 当作“地点”使用——正文可能为空或被服务端放在其它字段。
// 因此这里对正文做多字段防御解析，命中什么就展示什么；列表默认两行预览，点击展开全文。
const svc = require('../../utils/service');
const { ic } = require('../../utils/icons');
const { nightEmptyURI } = require('../../utils/scene');
const { ci, num, s } = require('../../utils/fmt');
const app = getApp();

// 正文候选字段（按优先级）：服务端把通知正文放在哪个字段就用哪个
const BODY_KEYS = ['content', 'detail', 'description', 'msgcontent', 'body', 'pushcontent', 'message', 'msg', 'text'];
function resolveBody(it) {
  for (const k of BODY_KEYS) {
    const v = it[k];
    if (v !== null && v !== undefined && String(v).trim() && String(v) !== 'null' && String(v) !== '无') {
      return String(v);
    }
  }
  return '';
}

// 日期分组：从服务端时间串里取 YYYY-MM-DD，归入 今天/昨天/前天/月日/年 组；
// 解析不出日期的（历史遗留报文）统一归入“更早”组，排在最末。
function dayKey(t) {
  const m = String(t || '').match(/(\d{4})[-/](\d{1,2})[-/](\d{1,2})/);
  return m ? `${m[1]}-${String(m[2]).padStart(2, '0')}-${String(m[3]).padStart(2, '0')}` : '';
}
function dayLabel(key) {
  if (!key) return '更早';
  const d = new Date(key + 'T00:00:00');
  const now = new Date();
  const today = new Date(now.getFullYear(), now.getMonth(), now.getDate());
  const diff = Math.round((today - d) / 86400000);
  if (diff === 0) return '今天';
  if (diff === 1) return '昨天';
  if (diff === 2) return '前天';
  if (d.getFullYear() === now.getFullYear()) return `${d.getMonth() + 1}月${d.getDate()}日`;
  return `${d.getFullYear()}年${d.getMonth() + 1}月${d.getDate()}日`;
}

Page({
  data: {
    enter: false,
    items: [],
    total: 0,
    unread: 0,
    loading: true,
    groups: [],
    icons: {
      refresh: ic('refresh', '#8E8E93', 1.6)
    },
    emptyScene: nightEmptyURI()
  },

  onShow() {
    // tab 切换入场：每次 onShow 重放淡入上浮
    this.setData({ enter: false });
    wx.nextTick(() => this.setData({ enter: true }));
    if (this.getTabBar && this.getTabBar()) this.getTabBar().setData({ selected: 2 });
    if (!svc.getTokenCfg()) { wx.reLaunch({ url: '/pages/login/login' }); return; }
    this.load();
  },

  onPullDownRefresh() {
    this.load().finally(() => wx.stopPullDownRefresh());
  },

  async load() {
    if (!svc.getTokenCfg()) return;
    try {
      const list = await svc.getMessages();
      app.saveCache({ messages: list });
      this.apply(list || []);
    } catch (err) {
      const cached = app.globalData.caches.messages;
      if (cached && cached.length) this.apply(cached);
      this.setData({ loading: false });
      wx.showToast({ title: '消息获取失败', icon: 'none' });
    }
  },

  // 消息分类：按标题/正文关键词归入 报警/充电/定位（与 v2 语义一致，但克制为标签形式）
  classify(title, content) {
    const t = String(title || '') + String(content || '');
    if (/报警|故障|异常|预警|警告|胎压|低电量/.test(t)) return { tag: '报警', cls: 'alarm' };
    if (/充电|充满|电量|续航|预约充电|充电桩/.test(t)) return { tag: '充电', cls: 'charge' };
    if (/定位|位置|行驶|轨迹|围栏/.test(t)) return { tag: '定位', cls: 'locate' };
    return { tag: '', cls: '' };
  },

  apply(list) {
    const items = list.map((m, idx) => {
      const it = ci((m && typeof m === 'object') ? m : {});
      const title = s(it.Title) || '车辆通知';
      const body = resolveBody(it);
      // Content 可能是正文，也可能是“地点”（桌面版如此标注）；两者相同时只展示一次
      const rawLoc = s(it.Content);
      const location = (rawLoc && rawLoc !== 'null' && rawLoc !== '无' && rawLoc !== body) ? rawLoc : '';
      const cat = this.classify(title, body || location);
      return {
        id: s(it.Id) || 'row-' + idx,
        title,
        body,
        location,
        time: s(it.CreatedAt) || '',
        plate: s(it.RealReceiverId) || '',
        read: num(it.ReadStatus) === 1,
        tag: cat.tag,
        tagCls: cat.cls,
        open: false
      };
    });
    // 按日期分组（新在前；无日期归入“更早”最后）
    const map = new Map();
    for (const it of items) {
      const key = dayKey(it.time);
      if (!map.has(key)) map.set(key, { key, label: dayLabel(key), items: [], unread: 0 });
      map.get(key).items.push(it);
    }
    const groups = [...map.values()].sort((a, b) => {
      if (!a.key) return 1;
      if (!b.key) return -1;
      return a.key < b.key ? 1 : -1;
    });
    for (const g of groups) g.unread = g.items.filter(i => !i.read).length;
    this.setData({
      groups,
      total: items.length,
      unread: items.filter(i => !i.read).length,
      loading: false
    });
  },

  refresh() { this.load(); },

  onTapItem(e) {
    const g = Number(e.currentTarget.dataset.g);
    const idx = Number(e.currentTarget.dataset.idx);
    const group = this.data.groups[g];
    const item = group && group.items[idx];
    if (!item) return;
    // 展开 / 收起本条，完整正文、地点、时间就地展示
    this.setData({ [`groups[${g}].items[${idx}].open`]: !item.open });
  }
});
