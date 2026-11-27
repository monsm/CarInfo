const { ci, s, num, num3, directionText, norm360 } = require('./fmt');

function _vnum(v) {
  if (v === null || v === undefined || v === '') return null;
  const x = Number(v);
  return isNaN(x) ? null : x;
}
const _n0 = v => { const x = _vnum(v); return x === null ? null : String(Math.round(x)); };
const _n1 = v => { const x = _vnum(v); return x === null ? null : x.toFixed(1); };
const _dash = v => (v === null || v === undefined ? '--' : s(v));
const _pick = (o, f) => (o === null || o === undefined ? null : f(o));

function fmtTime(d) {
  const p = n => String(n).padStart(2, '0');
  return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())} ${p(d.getHours())}:${p(d.getMinutes())}:${p(d.getSeconds())}`;
}
function nowText() { return fmtTime(new Date()); }

function carSel(cars, carId) {
  const list = cars || [];
  const options = list.map(c => {
    const v = ci(c);
    return { id: v.CarId, name: `${v.CarName} ${v.PlateNumber || ''}`.trim() };
  });
  let idx = Math.max(0, options.findIndex(o => o.id === carId));
  if (idx < 0) idx = 0;
  return { options, index: idx, car: list[idx] || null, count: list.length };
}

function energy(cache, car) {
  const control = ci(cache && cache.control || null);
  const charge = ci(cache && cache.charge || null);
  const hasCtrl = !!cache.control;
  const c = _pick;

  const soc = (_n0(c(charge, x => x.RemainPower)) || _n0(c(control, x => x.Soc)) || '--');
  const socNum = _vnum(soc);
  const socPct = socNum === null ? 0 : Math.max(0, Math.min(100, socNum));
  const chargeSt = s(charge ? charge.ChrgStatus : null);
  let chargeText = '未充电', chargeCls = 'idle';
  if (chargeSt === '1') { chargeText = '充电中'; chargeCls = 'ok'; }
  else if (chargeSt === '2') { chargeText = '即将充满'; chargeCls = 'ok'; }
  else if (chargeSt === '3') { chargeText = '充电完成'; chargeCls = 'ok'; }

  const range = _dash(_n0(c(charge, x => x.RemainedPowerMile)) || _n0(c(control, x => x.RemainedPowerMile)));
  const voltAmp = hasCtrl ? `${_n1(control.TotalVoltage)}V / ${_n1(control.TotalCurrent)}A` : '--';
  const btLo = _n0(control ? control.MinTemperatureValue : null);
  const btHi = _n0(control ? control.MaxTemperatureValue : null);
  const battTemp = hasCtrl && btLo !== null && btHi !== null ? `${btLo} ~ ${btHi}℃` : '--';
  const insulate = hasCtrl ? `${_n0(control.InsulateResistance)}Ω` : '--';
  const chargePct = _dash(_n0(c(charge, x => x.RemainPower)));

  let charging = null;
  if (chargeSt === '1' || chargeSt === '2') {
    const pow = _vnum(charge.ChargPower || charge.ChargingPower);
    charging = {
      start: _dash(s(charge.ChargeStarttime)) || '--',
      end: _dash(s(charge.ChargeStoptime)) || '--',
      durMin: _dash(_n0(c(charge, x => x.ChargDeltMins))),
      power: pow === null ? '--' : pow + ' kW'
    };
  }

  let online = { text: '离线', cls: 'bad' };
  let updated = '--';
  if (control && control.LastUpdatedTime) {
    const devT = s(control.DeviceTime);
    updated = devT.length > 10 ? devT : nowText();
    online = { text: '在线 · ' + updated, cls: 'ok' };
  }

  return {
    soc: soc === '--' ? '--' : soc,
    socPct,
    socCls: socPct >= 15 ? '' : 'danger',
    socWarn: socPct < 30 && socPct >= 15 ? 'low' : '',
    range,
    chargeText, chargeCls, chargePct, charging,
    voltAmp, battTemp, insulate,
    online, updated,
    carName: car ? `${ci(car).CarName} ${s(ci(car).PlateNumber)}`.trim() : '未绑定车辆'
  };
}

function bodyStatus(cache) {
  const control = ci(cache && cache.control || null);
  const hasCtrl = !!cache.control;

  const mk = (label, ok, text) => ({
    label,
    ok: hasCtrl ? !!ok : null,
    text: hasCtrl ? text : '--',
    cls: !hasCtrl ? 'na' : (ok ? 'ok' : 'bad')
  });

  const chips = [];
  const doorOk = hasCtrl && num(control.Door) === 0;
  chips.push(mk('车门', doorOk, doorOk ? '已关' : '开启'));
  const winOk = hasCtrl && s(control.Window) === '0';
  chips.push(mk('车窗', winOk, winOk ? '已关' : '开启'));
  const trunkOk = hasCtrl && num(control.Trunk) === 0;
  chips.push(mk('后备箱', trunkOk, trunkOk ? '已关' : '开启'));
  const roofOk = hasCtrl && num(control.Sunroof) === 0;
  chips.push(mk('天窗', roofOk, roofOk ? '已关' : '开启'));
  const lockOk = hasCtrl && num(control.DriverDoorLock) === 0;
  chips.push(mk('车锁', lockOk, lockOk ? '已锁' : '未锁'));

  const guard = (label, key) => {
    const x = _vnum(control ? control[key] : null);
    const good = x !== null && x === 0;
    return mk(label, good, x === null ? '--' : (good ? '正常' : '报警'));
  };
  chips.push(guard('制动', 'BrakeSystemAlarm'));
  chips.push(guard('气囊', 'AirbagSystemStatus'));
  return chips;
}

function driveStatus(cache) {
  const control = ci(cache && cache.control || null);
  const hasCtrl = !!cache.control;
  const c = _pick;

  const motorArr = control && (
    (control.DriveMotorData && control.DriveMotorData.length ? control.DriveMotorData : null) ||
    (control.MotorData && control.MotorData.length ? control.MotorData : null)
  );
  const motor = motorArr && motorArr.length > 0 ? ci(motorArr[0]) : null;
  const gearCls = hasCtrl && num(control.ShiftPosition) !== 0 ? 'bad' : '';

  let note = '';
  if (hasCtrl) {
    const hi = c(control, x => x.MaxVoltageBattery), lo = c(control, x => x.MinVoltageBattery);
    if (hi !== null && hi !== undefined && lo !== null && lo !== undefined) {
      note += `单体压差 ${num3(Math.abs(num(hi) - num(lo)))}V`;
    }
    const ht = c(control, x => x.MaxTemperatureValue), lt = c(control, x => x.MinTemperatureValue);
    if (ht !== null && ht !== undefined && lt !== null && lt !== undefined) {
      note += (note ? '  ·  ' : '') + `温差 ${num(ht) - num(lt)}℃`;
    }
  }

  const t = _vnum(motor ? motor.Temperature : null);
  const ct = _vnum(motor ? motor.ControllerTemperature : null);
  return {
    speed: hasCtrl ? _n0(control.VehicleSpeed) : '--',
    mile: hasCtrl ? _n0(control.TotalOdometer) : '--',
    gear: hasCtrl ? (num(control.ShiftPosition) === 0 ? 'P' : 'D') : '--',
    gearSub: hasCtrl ? (num(control.ShiftPosition) === 0 ? '驻车' : '行驶') : '',
    gearCls,
    motorTemp: !motor ? '--' : `${t === null ? '--' : num(t) + '℃'} / ${ct === null ? '--' : num(ct) + '℃'}`,
    batteryNote: note,
    isMoving: hasCtrl && num(control.VehicleSpeed) > 0
  };
}

function comfortStatus(cache) {
  const control = ci(cache && cache.control || null);
  const hasCtrl = !!cache.control;
  const pmRaw = ci(cache && cache.pm25 || null);
  const air = ci((control && control.Air) || null);
  const acOn = air ? s(air.Status) !== '0' : null;

  const pmInRaw = s(pmRaw ? pmRaw.Pm25InnnerCarValue : null);
  const pmIn = pmRaw ? (pmInRaw === '-1' || !pmInRaw ? '--' : pmInRaw + '') : '--';
  const pmOut = pmRaw ? s(pmRaw.Pm25OuterCarValue, '--') : '--';
  const vehTemp = _vnum(pmRaw ? pmRaw.VehicleTemperature : null);

  const envT = _vnum(pmRaw ? pmRaw.EnvironmentalTemperature : null);
  const purifier = _vnum(control ? control.AirPurifierStatus : null);

  return {
    acOn,
    acText: air ? `${acOn ? '运行中' : '已关闭'} · ${s(air.Temperature, '26')}℃ · 风量${s(air.Wind, '0')}档` : '暂无数据',
    acCls: acOn === null ? 'na' : (acOn ? 'ok' : 'off'),
    seatD: hasCtrl ? `通风${num(control.DriverSeatAirStatus) === 1 ? '开' : '关'} · 加热${num(control.DriverSeatHeatStatus) === 1 ? '开' : '关'}` : '--',
    seatP: hasCtrl ? `通风${num(control.PassengerSeatAirStatus) === 1 ? '开' : '关'} · 加热${num(control.PassengerSeatHeatStatus) === 1 ? '开' : '关'}` : '--',
    pmIn, pmOut,
    cabinTemp: vehTemp === null ? '--' : num(vehTemp) + '℃',
    envTemp: envT === null ? '--' : num(envT) + '℃',
    purifier: purifier === null ? '--' : (purifier === 1 ? '运行' : '关闭')
  };
}

function tyreStatus(cache) {
  const control = ci(cache && cache.control || null);
  const hasCtrl = !!cache.control;

  const item = (label, presKey, tempKey, warnKey) => {
    const w = _vnum(control ? control[warnKey] : null);
    const warn = w !== null && w > 0;
    return {
      label,
      kpa: _dash(_n0(_pick(control, x => x[presKey]))),
      temp: _dash(_n0(_pick(control, x => x[tempKey]))),
      cls: hasCtrl ? (warn ? 'bad' : 'ok') : 'na',
      warn
    };
  };
  const items = [
    item('左前', 'LfTyrePressure', 'LeftFrontTireTemperature', 'LfPressureWarning'),
    item('右前', 'RfTyrePressure', 'RightFrontTireTemperature', 'RfPressureWarning'),
    item('左后', 'LrTyrePressure', 'LeftRearTireTemperature', 'LrPressureWarning'),
    item('右后', 'RrTyrePressure', 'RightRearTireTemperature', 'RrPressureWarning')
  ];
  const warnAny = items.some(i => i.warn);
  const temps = control
    ? [control.LeftFrontTireTemperature, control.RightFrontTireTemperature, control.LeftRearTireTemperature, control.RightRearTireTemperature]
      .map(_vnum).filter(x => x !== null)
    : [];
  return {
    items,
    warnAny,
    alarmText: hasCtrl ? (warnAny ? '胎压异常' : '胎压正常') : '--',
    alarmCls: hasCtrl ? (warnAny ? 'bad' : 'ok') : 'na',
    tempRange: temps.length ? `${Math.min(...temps)} ~ ${Math.max(...temps)}℃` : '--'
  };
}

function locStatus(cache) {
  const control = ci(cache && cache.control || null);
  const loc = ci(cache && cache.location || null);
  const hasCtrl = !!cache.control;
  const gpsOk = loc ? !!loc.ValidGps : null;
  const heading = _vnum(loc ? loc.Heading : null);
  const deg = heading === null ? 0 : norm360(heading);
  return {
    addr: loc && loc.AddrDesc ? loc.AddrDesc : '',
    snap: s(loc ? (loc.LocationImgurl || loc.ThumbnailLocationImgUrl || '') : ''),
    gpsText: gpsOk === null ? '--' : (gpsOk ? 'GPS 信号有效' : 'GPS 信号异常'),
    gpsCls: gpsOk === null ? 'na' : (gpsOk ? 'ok' : 'bad'),
    dir: heading === null ? '--' : directionText(deg),
    deg: heading === null ? '--' : String(Math.round(deg)) + '°',
    degNum: heading === null ? 0 : Math.round(deg),
    satAlt: hasCtrl ? `${num(control.SatNum)} 颗 · 海拔 ${_n1(control.Alti)}m` : '--',
    lat: loc && loc.Lat !== null && loc.Lat !== undefined ? s(loc.Lat) : '--',
    lng: loc && loc.Lng !== null && loc.Lng !== undefined ? s(loc.Lng) : '--'
  };
}

function healthModel(checkRaw) {
  const d = ci(checkRaw);
  if (!d) return null;
  const score = _vnum(d.Score);
  const map = {
    normal: { cls: 'ok', cn: '正常' }, ok: { cls: 'ok', cn: '正常' },
    fault: { cls: 'bad', cn: '故障' }, abnormal: { cls: 'bad', cn: '异常' },
    warning: { cls: 'warn', cn: '预警' }, risk: { cls: 'warn', cn: '风险' }
  };
  const systems = (d.Details || []).map(sys => {
    const s2 = ci(sys);
    const children = (s2.Child || []).map(item => {
      const it = ci(item);
      const st = String(it.Status == null ? '' : it.Status).toLowerCase();
      const m = map[st] || { cls: it.Status == null ? 'ok' : 'warn', cn: it.Status == null ? '正常' : s(it.Status) };
      return {
        name: it.ItemName,
        statusCls: m.cls,
        statusText: m.cn,
        desc: it.Description,
        detect: it.DetectValue,
        suggest: it.Suggest
      };
    });
    const hasBad = children.some(x => x.statusCls === 'bad');
    const hasWarn = children.some(x => x.statusCls === 'warn');
    return {
      name: s2.ItemName,
      statusCls: hasBad ? 'bad' : (hasWarn ? 'warn' : 'ok'),
      statusText: hasBad ? '故障' : (hasWarn ? '预警' : '正常'),
      children,
      open: hasBad
    };
  });
  return {
    time: s(d.CheckTime),
    score: score === null ? '--' : String(Math.round(score)),
    scorePct: score === null ? 0 : Math.max(0, Math.min(100, score)),
    counts: [
      { key: '正常', n: _dash(_n0(_pick(d, x => x.NormalCount))), cls: 'ok' },
      { key: '风险', n: _dash(_n0(_pick(d, x => x.RiskCount))), cls: 'warn' },
      { key: '故障', n: _dash(_n0(_pick(d, x => x.FaultCount))), cls: 'bad' }
    ],
    systems,
    id: s(d.CheckHistoryId)
  };
}

function userModel(uRaw) {
  const u = ci(uRaw);
  if (!u) return null;
  const name = u.UserFullname || u.UserNickname || '车主';
  const mobile = s(u.Mobile);
  const authed = u.RealnameAuthed === true || s(u.RealnameAuthed).toLowerCase() === '1' ||
    String(u.RealnameAuthed || '').toLowerCase() === 'authed' || String(u.RealnameAuthed || '').toLowerCase() === 'true';
  return {
    name,
    avatar: (u.UserNickname || name).slice(0, 1).toUpperCase(),
    mobile: mobile.length >= 11 ? mobile.slice(0, 3) + '****' + mobile.slice(7) : (mobile || '--'),
    authed,
    nickname: s(u.UserNickname) || '未设置昵称'
  };
}

function daysFrom(str) {
  const t = s(str).trim();
  if (!t) return null;
  const m = t.match(/^(\d{4})[-/.年](\d{1,2})[-/.月](\d{1,2})/) || t.match(/^(\d{4})(\d{2})(\d{2})/);
  if (!m) return null;
  const d = new Date(+m[1], +m[2] - 1, +m[3]);
  const diff = Math.ceil((d.getTime() - Date.now()) / 86400000);
  return isNaN(diff) ? null : diff;
}

function vehicleSummary(carRaw) {
  const c = ci(carRaw);
  if (!c) return null;
  const pinCN = { exist: '已设置', none: '未设置' };
  const pinKey = String(c.Pin == null ? '' : c.Pin).toLowerCase();
  const insuranceEnd = s(c.InsuranceEndDate);
  const serviceEnd = s(c.TserviceEndtime);
  return {
    name: s(c.CarName),
    plate: s(c.PlateNumber) || '未上牌',
    vin: s(c.Vin),
    isNev: num(c.IsNev) === 1,
    pinText: pinCN[pinKey] || (c.Pin ? s(c.Pin) : '--'),
    pinCls: pinKey === 'exist' ? 'ok' : 'warn',
    model: [s(c.ModelCode), s(c.ConfName)].filter(Boolean).join(' · ') || '--',
    color: s(c.Color) || '--',
    insuranceEnd,
    insuranceDays: daysFrom(insuranceEnd),
    serviceEnd,
    serviceDays: daysFrom(serviceEnd)
  };
}

function bodyDetailModel(cache) {
  const control = ci(cache && cache.control || null);
  const hasCtrl = !!cache.control;
  const c = _pick;
  const n = k => _vnum(c(control, x => x[k]));
  const on = k => { const x = n(k); return x !== null && x !== 0; };

  const boolRow = (label, val, badWhen) => ({
    k: label, v: val, cls: badWhen ? 'bad' : 'ok'
  });

  const doorRows = [
    ['左前门', 'LeftFrontDoor', 'LeftFrontDoorLock'],
    ['右前门', 'RightFrontDoor', 'RightFrontDoorLock'],
    ['左后门', 'LeftRearDoor', 'LeftRearDoorLock'],
    ['右后门', 'RightRearDoor', 'RightRearDoorLock']
  ].map(([label, doorK, lockK]) => {
    const d = n(doorK), lk = n(lockK);
    if (d === null && lk === null) return null;
    const parts = [];
    if (d !== null) parts.push(d === 0 ? '已关' : '开启');
    if (lk !== null) parts.push(lk === 0 ? '已锁' : '未锁');
    const bad = (d !== null && d !== 0) || (lk !== null && lk !== 0);
    return boolRow(label, parts.join(' · '), bad);
  }).filter(Boolean);

  const extraRows = [
    ['前舱盖', 'Hood'], ['后备箱', 'Trunk'], ['天窗', 'Sunroof']
  ].map(([label, k]) => {
    const x = n(k);
    if (x === null) return null;
    return boolRow(label, x === 0 ? '已关闭' : '开启', x !== 0);
  }).filter(Boolean);

  const winDefs = [
    ['左前窗', 'LeftAnteriorWindowDegree', 'LeftFrontDoorrWindow'],
    ['右前窗', 'RightAnteriorWindowDegree', 'RightFrontDoorrWindow'],
    ['左后窗', 'LeftRearWindowDegree', 'LeftRearDoorrWindow'],
    ['右后窗', 'RightRearWindowDegree', 'RightRearWindow']
  ];
  const windowRows = winDefs.map(([label, degK, stateK]) => {
    const deg = n(degK);
    const st = n(stateK);
    if (deg === null && st === null) return null;
    const open = deg !== null ? deg > 0 : st !== 0;
    const v = deg !== null ? (deg === 0 ? '关闭' : `开启 ${Math.round(deg)}°`) : (open ? '开启' : '关闭');
    return boolRow(label, v, open);
  }).filter(Boolean);

  const lampDefs = [
    ['近光灯', 'LowBeam'], ['远光灯', 'HighBeam'],
    ['前雾灯', 'FrontFoglamp', 'FrontFogLight'], ['后雾灯', 'RearFoglamp', 'RearFogLight'],
    ['示廓灯', 'PositionLamp', 'PositionLight'],
    ['左转向灯', 'LeftTurnSignal', 'TurnLndicatorLeft'], ['右转向灯', 'RightTurnSignal', 'TurnLndicatorRight']
  ];
  const lit = [];
  const lampRows = lampDefs.map(([label, ...keys]) => {
    const x = _vnum(c(control, x => x[keys[0]]));
    const y = keys[1] ? _vnum(c(control, x => x[keys[1]])) : null;
    if (x === null && y === null) return null;
    const isOn = (x !== null && x !== 0) || (y !== null && y !== 0);
    if (isOn) lit.push(label);
    return { k: label, v: isOn ? '亮' : '灭', cls: 'ok' };
  }).filter(Boolean);

  const hasAny = hasCtrl && (doorRows.length + windowRows.length + lampRows.length + extraRows.length > 0);
  const badCount = doorRows.concat(windowRows).concat(extraRows).filter(r => r.cls === 'bad').length;
  return {
    has: hasAny,
    summary: hasAny
      ? (badCount ? { text: `${badCount} 项异常`, cls: 'bad' } : { text: '全部正常', cls: 'ok' })
      : { text: '--', cls: 'na' },
    doorRows, extraRows, windowRows, lampRows,
    lit
  };
}

function batteryModel(cache) {
  const control = ci(cache && cache.control || null);
  const charge = ci(cache && cache.charge || null);
  const hasCtrl = !!cache.control;
  const hasChg = !!cache.charge;

  const c = _pick;
  const collect = (listKey, itemKey) => {
    const list = (hasCtrl && Array.isArray(control[listKey])) ? control[listKey] : [];
    const out = [];
    list.forEach(sub => {
      const it = ci(sub);
      const arr = Array.isArray(it[itemKey]) ? it[itemKey] : [];
      arr.forEach(x => { const n = _vnum(x); if (n !== null) out.push(n); });
    });
    return out;
  };
  const cells = collect('NevChargeSystemVoltageDtoList', 'BatteryVoltage');
  const probes = collect('NevChargeSystemTemperatureDtoList', 'ProbeTemperatures');
  const stats = arr => {
    if (!arr.length) return null;
    const min = Math.min.apply(null, arr);
    const max = Math.max.apply(null, arr);
    const avg = arr.reduce((a, b) => a + b, 0) / arr.length;
    return { min, max, avg, count: arr.length };
  };
  const cellStats = stats(cells);
  const probeStats = stats(probes);
  const barsOf = arr => {
    if (!arr.length) return [];
    const step = Math.max(1, Math.ceil(arr.length / 64));
    const out = [];
    for (let i = 0; i < arr.length; i += step) out.push(arr[i]);
    return out;
  };

  const diffV = (() => {
    const hi = _vnum(c(control, x => x.MaxVoltageBattery));
    const lo = _vnum(c(control, x => x.MinVoltageBattery));
    return hi !== null && lo !== null ? Math.abs(num(hi) - num(lo)) : null;
  })();
  const diffT = (() => {
    const hi = _vnum(c(control, x => x.MaxTemperatureValue));
    const lo = _vnum(c(control, x => x.MinTemperatureValue));
    return hi !== null && lo !== null ? Math.abs(num(hi) - num(lo)) : null;
  })();

  const motors = (() => {
    const list = hasCtrl && (
      (Array.isArray(control.DriveMotorData) && control.DriveMotorData.length ? control.DriveMotorData : null) ||
      (Array.isArray(control.MotorData) && control.MotorData.length ? control.MotorData : null)
    );
    return (list || []).map(m => {
      const it = ci(m);
      return {
        num: _dash(_n0(c(it, x => x.Num))),
        state: _dash(s(it.State)),
        rpm: _dash(_n0(c(it, x => x.RevolutionSpeed))),
        torque: _dash(_n0(c(it, x => x.Torque))),
        temp: _dash(_n0(c(it, x => x.Temperature))),
        ctrlTemp: _dash(_n0(c(it, x => x.ControllerTemperature))),
        inputV: _dash(_n1(c(it, x => x.ControllerInputVoltage))),
        dcBus: _dash(_n0(c(it, x => x.ControllerDcBusCurrent)))
      };
    });
  })();

  const faults = (() => {
    const mk = (name, countKey, codeKey) => {
      const n = _vnum(c(control, x => x[countKey]));
      const code = s(c(control, x => x[codeKey]));
      return { name, count: n === null ? 0 : Math.max(0, n), codes: code && code !== '无' ? code : '' };
    };
    const items = [
      mk('发动机', 'EngineFaultCount', 'EngineFaultCodes'),
      mk('驱动电机', 'DriveMotorFaultCount', 'DriveMotorFaultCodes'),
      mk('储能设备', 'RechargeableStorageDevicesFaultCount', 'RechargeableStorageDevicesFaultCodes'),
      mk('其他', 'OtherFaultCount', 'OtherFaultCodes')
    ];
    return { items, total: items.reduce((a, i) => a + (i.count || 0), 0) };
  })();

  const alarms = (() => {
    const flags = [
      ['电池总报警', 'BatteryAlarm'], ['一致性差异', 'BatteryConsistencyDifferenceAlarm'],
      ['绝缘报警', 'InsulationAlarm'], ['高压互锁', 'HighVoltageInterlockStateAlarm'],
      ['单体过压', 'SingleBatteryOverVoltageAlarm'], ['单体欠压', 'SingleBatteryUnderVoltageAlarm'],
      ['SOC 过低', 'SocLowAlarm'], ['SOC 过高', 'SocHighAlarm'], ['SOC 跳变', 'SocJumpAlarm'],
      ['温差过大', 'TemperatureDifferenceAlarm'], ['电机过热', 'DriveMotorTemperatureAlarm'],
      ['控制器过热', 'DriveMotorControllerTemperatureAlarm'], ['储能过压', 'VehicleStorageDeviceOvervoltageAlarm'],
      ['储能欠压', 'VehicleStorageDeviceUndervoltageAlarm'], ['储能不匹配', 'RechargeableStorageDeviceMismatchAlarm'],
      ['过充保护', 'VehiclePureDeviceTypeOvercharge']
    ];
    return flags.filter((f, k) => { const x = _vnum(c(control, x => x[f[1]])); return x !== null && x !== 0; }).map(f => f[0]);
  })();

  const chgSt = s(charge ? charge.ChrgStatus : null);
  const chgText = chgSt === '1' ? '充电中' : (chgSt === '2' ? '即将充满' : (chgSt === '3' ? '充电完成' : '未充电'));
  const chgCls = chgSt === '1' || chgSt === '2' || chgSt === '3' ? 'ok' : '';

  return {
    hasCtrl, hasChg,
    cellStats: cellStats ? { ...cellStats, bars: barsOf(cells) } : null,
    probeStats: probeStats ? { ...probeStats, bars: barsOf(probes) } : null,
    diffV, diffT,
    subsystems: (hasCtrl && Array.isArray(control.NevChargeSystemVoltageDtoList) ? control.NevChargeSystemVoltageDtoList : []).map(sub => {
      const it = ci(sub);
      const list = Array.isArray(it.BatteryVoltage) ? it.BatteryVoltage.map(_vnum).filter(x => x !== null) : [];
      return {
        num: _dash(_n0(c(it, x => x.ChildSystemNum))),
        count: _dash(_n0(c(it, x => x.CurrentBatteryCount)) || _n0(c(it, x => x.BatteryCount))),
        volt: _dash(_n1(c(it, x => x.ChargeSystemVoltage))),
        amp: _dash(_n0(c(it, x => x.ChargeSystemCurrent))),
        vMin: list.length ? Math.min.apply(null, list).toFixed(3) : '--',
        vMax: list.length ? Math.max.apply(null, list).toFixed(3) : '--'
      };
    }),
    tempSubs: (hasCtrl && Array.isArray(control.NevChargeSystemTemperatureDtoList) ? control.NevChargeSystemTemperatureDtoList : []).map(sub => {
      const it = ci(sub);
      const list = Array.isArray(it.ProbeTemperatures) ? it.ProbeTemperatures.map(_vnum).filter(x => x !== null) : [];
      return {
        num: _dash(_n0(c(it, x => x.ChildSystemNum))),
        count: _dash(_n0(c(it, x => x.ChargeTemperatureProbeNum))),
        tMin: list.length ? Math.min.apply(null, list).toFixed(1) : '--',
        tMax: list.length ? Math.max.apply(null, list).toFixed(1) : '--'
      };
    }),
    motors,
    faults,
    alarms,
    charging: {
      text: chgText,
      cls: chgCls,
      soc: _dash(_n0(c(charge, x => x.RemainPower))),
      range: _dash(_n0(c(charge, x => x.RemainedPowerMile)) || _n0(c(control, x => x.RemainedPowerMile))),
      power: (() => { const p = _vnum(charge ? (charge.ChargPower || charge.ChargingPower) : null); return p === null ? '--' : p + ' kW'; })(),
      durMin: _dash(_n0(c(charge, x => x.ChargDeltMins))),
      start: _dash(s(charge ? charge.ChargeStarttime : null)),
      end: _dash(s(charge ? charge.ChargeStoptime : null)),
      powerLine: _vnum(c(charge, x => x.PowerLineStatus)) === 0 ? '正常' : (hasChg ? '异常' : '--'),
      heating: _vnum(c(charge, x => x.BatteryHeatingStatus)) === 1 ? '开启' : (hasChg ? '关闭' : '--'),
      reservation: _vnum(c(charge, x => x.ChargeReservationStatus)) === 1 ? '已预约' : (hasChg ? '未预约' : '--'),
      reserveTime: _dash(s(charge ? charge.ReservationUseVehicleTime : null))
    }
  };
}

module.exports = {
  fmtTime, nowText, carSel,
  energy, bodyStatus, driveStatus, comfortStatus, tyreStatus, locStatus, bodyDetailModel,
  healthModel, userModel, vehicleSummary, batteryModel
};
