const VM = require('./vm');
const { ci, s } = require('./fmt');

const BAD = 'bad', WARN = 'warn', OK = 'ok', NA = 'na';

function daysUntil(str) {
  const t = String(str == null ? '' : str).trim();
  if (!t) return null;
  const m = t.match(/^(\d{4})[-/.年](\d{1,2})[-/.月](\d{1,2})/) || t.match(/^(\d{4})(\d{2})(\d{2})/);
  if (!m) return null;
  const d = new Date(+m[1], +m[2] - 1, +m[3]);
  const diff = Math.ceil((d.getTime() - Date.now()) / 86400000);
  return isNaN(diff) ? null : diff;
}

function _num(v) {
  const x = v === null || v === undefined || v === '' ? null : Number(v);
  return x === null || isNaN(x) ? null : x;
}

function summarize(cache, carRaw) {
  const caches = cache || {};
  const hasCtrl = !!caches.control;
  const control = ci(caches.control || null);
  const domains = [];
  const add = d => { if (d) domains.push(d); };

  add((() => {
    const b = VM.batteryModel(caches);
    const d = { key: 'battery', label: '电池', url: '/pages/battery/battery', cls: NA, short: '--', title: '暂无数据', reasons: [], metrics: [] };
    d.metrics.push({ k: 'SOC', v: b.hasCtrl && b.charging.soc !== '--' ? b.charging.soc + '%' : '--' });
    if (b.diffV !== null) d.metrics.push({ k: '压差', v: Number(b.diffV).toFixed(3) + ' V' });
    if (b.diffT !== null) d.metrics.push({ k: '温差', v: Number(b.diffT).toFixed(1) + ' ℃' });
    if (!b.hasCtrl) return d;
    d.cls = OK; d.short = '正常'; d.title = '电池状态正常';
    if (b.alarms.length) {
      d.cls = BAD; d.short = '异常';
      d.title = `电池告警 ${b.alarms.length} 项`;
      b.alarms.slice(0, 3).forEach(a => d.reasons.push({ t: a + ' 触发', cls: BAD }));
    }
    const vF = b.faults.items.find(f => f.name === '储能设备');
    if (vF && vF.count > 0) {
      if (d.cls !== BAD) { d.cls = BAD; d.short = '异常'; d.title = '储能设备故障码 ' + vF.count + ' 条'; }
      d.reasons.push({ t: `储能故障码 ${vF.count} 条${vF.codes ? '：' + vF.codes : ''}`, cls: BAD });
    }
    if (d.cls === OK && b.diffV !== null && b.diffV >= 0.05) {
      d.cls = WARN; d.short = '关注';
      d.title = '单体一致性偏差';
      d.reasons.push({ t: `压差 ${Number(b.diffV).toFixed(3)}V 偏高`, cls: WARN });
    }
    if (d.cls === OK && b.diffT !== null && b.diffT >= 8) {
      d.cls = WARN; d.short = '关注';
      d.title = '电池温差偏大';
      d.reasons.push({ t: `温差 ${Number(b.diffT).toFixed(1)}℃ 偏大`, cls: WARN });
    }
    if (d.cls === OK && !d.reasons.length) d.reasons.push({ t: '单体一致性正常，无告警', cls: OK });
    if (d.reasons.length > 3) d.reasons.length = 3;
    return d;
  })());

  add((() => {
    const C = VM.batteryModel(caches).charging;
    const d = { key: 'charge', label: '充电', url: '/pages/battery/battery', cls: OK, short: '未充电', title: '未充电', reasons: [], metrics: [] };
    if (!VM.batteryModel(caches).hasChg) { d.cls = NA; d.short = '--'; d.title = '暂无充电数据'; return d; }
    const isChg = C.text === '充电中' || C.text === '即将充满';
    d.short = isChg ? '充电中' : '未充电';
    d.title = isChg ? `充电中 ${C.power}` : '未充电';
    if (C.power !== '--') d.metrics.push({ k: '功率', v: C.power });
    if (C.reserveTime && C.reserveTime !== '--') d.metrics.push({ k: '预约用车', v: C.reserveTime });
    if (C.powerLine === '异常') {
      d.cls = WARN; d.short = '关注';
      d.title = '电源线路异常';
      d.reasons.push({ t: '电源线路状态异常，充电可能中断', cls: WARN });
    } else if (C.powerLine !== '--') {
      d.reasons.push({ t: '电源线路正常', cls: OK });
    }
    return d;
  })());

  add((() => {
    const chips = VM.bodyStatus(caches);
    const bads = chips.filter(c => c.cls === 'bad');
    const d = { key: 'body', label: '车身', url: '', cls: hasCtrl ? OK : NA, short: hasCtrl ? '正常' : '--', title: hasCtrl ? '门窗锁正常' : '暂无数据', reasons: [], metrics: [] };
    if (bads.length) {
      d.cls = BAD; d.short = '异常';
      d.title = `车身 ${bads.length} 项未就绪`;
      bads.slice(0, 4).forEach(c => d.reasons.push({ t: `${c.label}${c.text}`, cls: BAD }));
    } else if (hasCtrl) {
      d.reasons.push({ t: '车门 / 车窗 / 后备箱 / 天窗均已关闭', cls: OK });
    }
    return d;
  })());

  add((() => {
    const t = VM.tyreStatus(caches);
    const d = { key: 'tyre', label: '胎压', url: '', cls: t.alarmCls, short: t.alarmCls === 'bad' ? '异常' : (t.alarmCls === 'ok' ? '正常' : '--'), title: t.alarmText, reasons: [], metrics: [] };
    t.items.forEach(i => {
      if (i.warn) d.reasons.push({ t: `${i.label} 胎压异常`, cls: BAD });
      if (i.kpa !== '--' && i.kpa !== '') d.metrics.push({ k: i.label, v: i.kpa + ' kPa' });
    });
    if (t.alarmCls === 'ok') {
      if (t.tempRange !== '--') d.reasons.push({ t: `四轮胎压正常 · 胎温 ${t.tempRange}`, cls: OK });
      else if (hasCtrl) d.reasons.push({ t: '四轮胎压正常', cls: OK });
    }
    return d;
  })());

  add((() => {
    const conf = VM.comfortStatus(caches);
    const d = { key: 'climate', label: '座舱', url: '/pages/data/data?kind=env', cls: hasCtrl ? OK : NA, short: hasCtrl ? '正常' : '--', title: !hasCtrl ? '暂无数据' : (conf.acOn === null ? '座舱状态正常' : (conf.acOn ? '空调运行中' : '空调已关闭')), reasons: [], metrics: [] };
    const pmIn = conf.pmIn === '--' ? -1 : Number(conf.pmIn);
    if (conf.pmIn !== '--') {
      d.metrics.push({ k: '车内PM2.5', v: conf.pmIn + ' μg/m³' });
      if (pmIn >= 150) { d.cls = BAD; d.short = '异常'; d.reasons.push({ t: `车内 PM2.5 ${pmIn} μg/m³，建议开启内循环或净化`, cls: BAD }); }
      else if (pmIn >= 75) { if (d.cls !== BAD) d.cls = WARN; d.short = '关注'; d.reasons.push({ t: `车内 PM2.5 ${pmIn} μg/m³ 偏高`, cls: WARN }); }
    }
    const cabin = parseFloat(String(conf.cabinTemp).replace('℃', ''));
    if (!isNaN(cabin)) {
      d.metrics.push({ k: '车内温度', v: conf.cabinTemp });
      if (cabin >= 35 || cabin <= 0) { if (d.cls !== BAD) d.cls = WARN; d.short = '关注'; d.reasons.push({ t: `车内温度 ${conf.cabinTemp}，建议提前开启空调`, cls: WARN }); }
    }
    if (d.cls === OK && hasCtrl && !d.reasons.length) d.reasons.push({ t: '温度 / 空气质量正常', cls: OK });
    return d;
  })());

  add((() => {
    const b = VM.batteryModel(caches);
    const d = { key: 'power', label: '动力', url: '/pages/battery/battery', cls: NA, short: '--', title: '暂无数据', reasons: [], metrics: [] };
    const mf = b.faults.items.find(f => f.name === '驱动电机');
    if (b.motors.length) {
      const m = b.motors[0];
      if (m.rpm !== '--') d.metrics.push({ k: '转速', v: m.rpm + ' rpm' });
      if (m.torque !== '--') d.metrics.push({ k: '扭矩', v: m.torque + ' N·m' });
      const t1 = parseFloat(String(m.temp).replace('℃', ''));
      const t2 = parseFloat(String(m.ctrlTemp).replace('℃', ''));
      const tMax = Math.max(isNaN(t1) ? -1 : t1, isNaN(t2) ? -1 : t2);
      d.cls = OK; d.short = '正常'; d.title = '电机系统正常';
      if (tMax >= 75) { d.cls = WARN; d.short = '关注'; d.title = '电机温度偏高'; d.reasons.push({ t: `电机 / 控制器温度 ${tMax}℃`, cls: WARN }); }
      else if (tMax >= 0) d.reasons.push({ t: `电机温度正常（${tMax}℃）`, cls: OK });
    }
    if (mf && mf.count > 0) {
      d.cls = BAD; d.short = '异常'; d.title = '驱动电机故障码 ' + mf.count + ' 条';
      d.reasons.push({ t: `电机故障码 ${mf.count} 条${mf.codes ? '：' + mf.codes : ''}`, cls: BAD });
    }
    if (d.cls === NA && !mf) return null;
    return d;
  })());

  add((() => {
    const chips = VM.bodyStatus(caches);
    const bads = chips.filter(c => (c.label === '制动' || c.label === '气囊') && c.cls === 'bad');
    const d = { key: 'safety', label: '安全', url: '/pages/health/health', cls: hasCtrl ? OK : NA, short: hasCtrl ? '正常' : '--', title: '安全系统正常', reasons: [], metrics: [] };
    if (bads.length) {
      d.cls = BAD; d.short = '异常'; d.title = '安全系统报警';
      bads.forEach(c => d.reasons.push({ t: `${c.label}${c.text}`, cls: BAD }));
    } else if (hasCtrl) {
      const ml = _num(control.MaxAlarmLevel);
      if (ml !== null && ml > 0) {
        d.cls = WARN; d.short = '关注'; d.title = '存在报警等级 ' + ml;
        d.reasons.push({ t: `整车最高报警等级 ${ml}`, cls: WARN });
      } else {
        d.reasons.push({ t: '制动 / 气囊系统正常', cls: OK });
      }
    }
    return d;
  })());

  add((() => {
    const e = VM.energy(caches, null);
    const loc = VM.locStatus(caches);
    const d = { key: 'network', label: '网络', url: '', cls: hasCtrl ? OK : NA, short: hasCtrl ? '在线' : '--', title: hasCtrl ? '车辆在线' : '暂无数据', reasons: [], metrics: [] };
    if (hasCtrl) {
      d.reasons.push({ t: e.online.text, cls: e.online.cls === 'ok' ? OK : WARN });
      if (loc.gpsCls === 'bad') { d.cls = WARN; d.short = '关注'; d.reasons.push({ t: 'GPS 信号异常', cls: WARN }); }
      else if (loc.gpsCls === 'ok') d.reasons.push({ t: 'GPS 信号有效', cls: OK });
      if (loc.satAlt && loc.satAlt !== '--') d.metrics.push({ k: '卫星 / 海拔', v: loc.satAlt });
    }
    return d;
  })());

  add((() => {
    const car = ci(carRaw || null);
    const insDays = daysUntil(car ? car.InsuranceEndDate : null);
    const srvDays = daysUntil(car ? car.TserviceEndtime : null);
    const d = { key: 'service', label: '服务', url: '/pages/vehicle/vehicle', cls: NA, short: '--', title: '暂无到期信息', reasons: [], metrics: [] };
    if (insDays !== null) d.metrics.push({ k: '保险到期', v: insDays < 0 ? `已过 ${-insDays} 天` : `剩 ${insDays} 天` });
    if (srvDays !== null) d.metrics.push({ k: '服务到期', v: srvDays < 0 ? `已过 ${-srvDays} 天` : `剩 ${srvDays} 天` });
    if (insDays === null && srvDays === null) return d;
    d.cls = OK; d.short = '正常'; d.title = '保险 / 服务未到期';
    if ((insDays !== null && insDays < 0) || (srvDays !== null && srvDays < 0)) {
      d.cls = BAD; d.short = '异常'; d.title = '存在已到期项目';
      if (insDays !== null && insDays < 0) d.reasons.push({ t: '保险已到期，请及时续保', cls: BAD });
      if (srvDays !== null && srvDays < 0) d.reasons.push({ t: '车辆服务已到期', cls: BAD });
    } else if ((insDays !== null && insDays <= 30) || (srvDays !== null && srvDays <= 30)) {
      d.cls = WARN; d.short = '关注'; d.title = '即将到期';
      if (insDays !== null && insDays <= 30) d.reasons.push({ t: `保险 ${insDays} 天后到期`, cls: WARN });
      if (srvDays !== null && srvDays <= 30) d.reasons.push({ t: `服务 ${srvDays} 天后到期`, cls: WARN });
    } else {
      d.reasons.push({ t: '保险 / 服务均在有效期内', cls: OK });
    }
    return d;
  })());

  const badN = domains.filter(x => x.cls === BAD).length;
  const warnN = domains.filter(x => x.cls === WARN).length;
  let overall;
  if (!hasCtrl) overall = { cls: NA, title: '等待车辆数据', sub: '下拉刷新获取最新车况' };
  else if (badN === 0 && warnN === 0) overall = { cls: OK, title: '一切正常', sub: `${domains.filter(x => x.cls !== NA).length} 个系统检查完毕` };
  else overall = { cls: badN ? BAD : WARN, title: `${badN + warnN} 项需要注意`, sub: `异常 ${badN} 项 · 关注 ${warnN} 项` };

  return { overall, domains };
}

module.exports = { summarize, daysUntil };