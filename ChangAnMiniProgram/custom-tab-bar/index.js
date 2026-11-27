const { ic } = require('../utils/icons');

const ACTIVE = '#FFFFFF';
const INACTIVE = '#6F7683';

Component({
  data: {
    selected: 0,
    hidden: false,
    list: [
      { pagePath: '/pages/home/home', text: '车况', iconOn: ic('navHome', ACTIVE), iconOff: ic('navHome', INACTIVE) },
      { pagePath: '/pages/control/control', text: '车控', iconOn: ic('navApps', ACTIVE), iconOff: ic('navApps', INACTIVE) },
      { pagePath: '/pages/messages/messages', text: '消息', iconOn: ic('navMsg', ACTIVE), iconOff: ic('navMsg', INACTIVE) },
      { pagePath: '/pages/mine/mine', text: '我的', iconOn: ic('navMine', ACTIVE), iconOff: ic('navMine', INACTIVE) }
    ]
  },
  methods: {
    onTap(e) {
      const { index, path } = e.currentTarget.dataset;
      if (Number(index) === this.data.selected) return;
      wx.switchTab({ url: path });
    }
  }
});
