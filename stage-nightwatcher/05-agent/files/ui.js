// ---------------------------------------------------------------------------
// Author:        David Gilinsky
// File:          /usr/local/lib/nightwatcher-pi/ui.js
// Purpose:       The RPi tab, served by the appliance agent and imported by
//                NightWatcher2's web UI through /api/v1/platform/ui.js. It runs
//                in the daemon's page, on its session, so it can talk to both
//                the agent (host configuration) and NightWatcher2's own API
//                (the export target that feeds the USB drive).
//
//                Self-contained by necessity: app.js exports nothing, so this
//                module brings its own helpers and borrows only its stylesheet.
// Created:       2026-07-27
// Last Modified: 2026-07-27
// Version:       0.1.0
// License:       GPL-3.0-or-later
// ---------------------------------------------------------------------------

const SPOOL_DIR = '/var/lib/nightwatcher-pi/spool/dsn';
const USB_TARGET_ID = 'usb-dsn';

// ---- helpers ---------------------------------------------------------------

function el(tag, attrs, ...kids) {
  const n = document.createElement(tag);
  for (const [k, v] of Object.entries(attrs || {})) {
    if (k === 'onclick') n.addEventListener('click', v);
    else if (k === 'onchange') n.addEventListener('change', v);
    else if (v !== null && v !== undefined) n.setAttribute(k, v);
  }
  for (const kid of kids.flat()) {
    if (kid === null || kid === undefined || kid === false) continue;
    n.append(kid instanceof Node ? kid : document.createTextNode(String(kid)));
  }
  return n;
}

const msg = (kind, text) => el('div', { class: 'msg ' + kind }, text);

async function call(method, path, body) {
  const init = { method, headers: {} };
  if (body !== undefined) {
    init.headers['Content-Type'] = 'application/json';
    init.body = JSON.stringify(body);
  }
  const res = await fetch(path, init);
  const text = await res.text();
  let data = null;
  try { data = text ? JSON.parse(text) : null; } catch (_) { /* not JSON */ }
  if (!res.ok) throw new Error((data && data.error) || res.statusText);
  return data;
}

const platform = (method, path, body) => call(method, '/api/v1/platform' + path, body);
const core = (method, path, body) => call(method, '/api/v1' + path, body);

function card(title, ...kids) {
  return el('div', { class: 'card' }, el('h3', {}, el('span', {}, title)), ...kids);
}

function kvTable(pairs) {
  const box = el('div', { class: 'kv' });
  for (const [k, v] of pairs) {
    if (v === null || v === undefined || v === '') continue;
    box.append(el('b', {}, k), el('span', {}, String(v)));
  }
  return box;
}

const bytes = (n) => {
  const v = Number(n);
  if (!v || Number.isNaN(v)) return '';
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  let i = 0, x = v;
  while (x >= 1024 && i < units.length - 1) { x /= 1024; i++; }
  return `${x.toFixed(x < 10 && i > 0 ? 1 : 0)} ${units[i]}`;
};

// A place for each section to report what happened, without a page of stale
// notices piling up.
function notice(host, kind, text) {
  host.innerHTML = '';
  host.append(msg(kind, text));
}

async function guard(host, working, fn) {
  notice(host, 'warn', working);
  try {
    const out = await fn();
    notice(host, 'ok', out || 'Done.');
    return true;
  } catch (e) {
    notice(host, 'err', e.message);
    return false;
  }
}

// ---- sections --------------------------------------------------------------

function sectionOverview(status) {
  const ap = status.ap || {};
  const up = status.uplink || {};
  return card('This unit',
    kvTable([
      ['Name', status.unit],
      ['Site', status.site],
      ['Hardware', status.model],
      ['Image', 'NightWatcher-Pi ' + status.image_version],
      ['Access point', ap.ssid ? `${ap.ssid} (${ap.state || 'unknown'}, ${ap.clients || 0} client(s))` : 'not configured'],
      ['AP address', ap.address],
      ['Uplink', up.state === 'up' ? `${up.ssid || 'connected'} (${up.signal || '?'}%)` : (up.ethernet ? 'Ethernet ' + up.ethernet : 'none')],
      ['Internet', up.internet === 'yes' ? 'reachable' : 'not reachable'],
    ]));
}

function sectionAccessPoint(status, reload) {
  const ap = status.ap || {};
  const out = el('div', {});
  const ssid = el('input', { type: 'text', value: ap.ssid || '', maxlength: '32' });
  const psk = el('input', { type: 'password', placeholder: 'unchanged', minlength: '8', maxlength: '63' });

  const save = el('button', { class: 'btn', onclick: async () => {
    const body = {};
    if (ssid.value && ssid.value !== ap.ssid) body.ssid = ssid.value;
    if (psk.value) body.passphrase = psk.value;
    if (!Object.keys(body).length) { notice(out, 'warn', 'Nothing changed.'); return; }
    const ok = await guard(out, 'Applying; you will be disconnected from this network…', async () => {
      await platform('POST', '/ap', body);
      return 'Changed. Rejoin the Wi-Fi network with the new details, then reload this page.';
    });
    if (ok) psk.value = '';
  } }, 'Apply');

  return card('Access point',
    el('p', { class: 'muted' },
      'This unit is its own Wi-Fi network, always on. Changing either field '
      + 'disconnects every device currently joined, including this one.'),
    el('form', { class: 'form', onsubmit: 'return false' },
      el('label', {}, 'Network name (SSID)', ssid),
      el('label', {}, 'Passphrase (8 to 63 characters)', psk),
      el('div', { class: 'row' }, save)),
    out);
}

function sectionUplink(status, reload) {
  const up = status.uplink || {};
  const out = el('div', {});
  const list = el('div', {});
  const joined = up.state === 'up';

  const scan = el('button', { class: 'btn ghost sm', onclick: async () => {
    notice(out, 'warn', 'Scanning…');
    try {
      const { networks } = await platform('GET', '/wifi/scan');
      out.innerHTML = '';
      list.innerHTML = '';
      if (!networks.length) { list.append(el('p', { class: 'muted' }, 'No networks found.')); return; }
      for (const n of networks) {
        const psk = el('input', { type: 'password', placeholder: 'passphrase' });
        const row = el('div', { class: 'row', style: 'margin:.3rem 0' },
          el('span', { style: 'min-width:14rem' }, n.ssid),
          el('span', { class: 'pill' }, `${n.signal}%`),
          el('span', { class: 'pill' + (n.band === '5 GHz' ? ' saturated' : '') }, n.band),
          n.security ? el('span', { class: 'muted' }, n.security) : null,
          psk,
          el('button', { class: 'btn sm', onclick: () => guard(out,
            `Joining ${n.ssid}; the access point retunes and clients reconnect…`,
            async () => {
              const r = await platform('POST', '/wifi/join', { ssid: n.ssid, psk: psk.value });
              setTimeout(reload, 4000);
              return `Joined ${r.joined}. ${r.note}`;
            }) }, 'Join'));
        list.append(row);
      }
    } catch (e) { notice(out, 'err', e.message); }
  } }, 'Scan for networks');

  const forget = el('button', { class: 'btn danger sm', onclick: () => guard(out,
    'Disconnecting…', async () => {
      await platform('POST', '/wifi/forget', {});
      setTimeout(reload, 3000);
      return 'Uplink forgotten. The access point is back on its own channel.';
    }) }, 'Forget uplink');

  return card('Internet uplink',
    el('p', { class: 'muted' },
      'An uplink lets this unit upload DSN exports and keep its clock right. '
      + 'One radio serves one channel, so the access point follows whatever '
      + 'network you join here: prefer 2.4 GHz, and expect joined devices to '
      + 'drop for a few seconds. Ethernet, if you have it, needs no setup and '
      + 'costs the access point nothing.'),
    kvTable([
      ['Status', joined ? `connected to ${up.ssid}` : 'not connected'],
      ['Address', up.address],
      ['Ethernet', up.ethernet || 'not connected'],
    ]),
    el('div', { class: 'row', style: 'margin-top:.6rem' }, scan, joined ? forget : null),
    list,
    out);
}

function sectionUsb(status, exportTarget, sensors, reload) {
  const usb = status.usb || {};
  const out = el('div', {});
  const present = usb.present === 'yes';

  const sync = el('button', { class: 'btn sm', onclick: () => guard(out,
    'Mirroring…', async () => {
      await platform('POST', '/usb/sync', {});
      setTimeout(reload, 1500);
      return 'Mirrored. The drive is unmounted again and safe to remove.';
    }) }, 'Sync now');

  // Turning the USB destination on is really turning on a DSN export target
  // that writes to the spool the mirror reads from. The drive is never in the
  // export's path, which is why a missing drive cannot break an export.
  const sensorPick = el('select', {});
  for (const s of sensors) {
    sensorPick.append(el('option', { value: s.id, ...(exportTarget && exportTarget.sensor_id === s.id ? { selected: 'selected' } : {}) },
      s.name ? `${s.name} (${s.id})` : s.id));
  }

  const enabled = !!exportTarget && exportTarget.status === 'active';
  const toggle = el('button', { class: enabled ? 'btn danger sm' : 'btn sm', onclick: () => guard(out,
    enabled ? 'Turning off…' : 'Turning on…', async () => {
      if (enabled) {
        await core('PATCH', '/export-targets/' + USB_TARGET_ID, { status: 'inactive' });
        setTimeout(reload, 800);
        return 'Nightly export to the drive is off. Files already written stay where they are.';
      }
      if (!sensorPick.value) throw new Error('add a sensor first, on the Sensors tab');
      await core('POST', '/export-targets', {
        id: USB_TARGET_ID,
        sensor_id: sensorPick.value,
        name: 'USB data drive',
        target: 'dsn',
        schedule: 'nightly',
        schedule_time: '12:00',
        status: 'active',
        config: { outbox_dir: SPOOL_DIR },
      });
      setTimeout(reload, 800);
      return 'On. A DSN file per month is written nightly and mirrored to any drive that is plugged in.';
    }) }, enabled ? 'Turn off' : 'Turn on');

  const prepare = el('div', {});
  const prepareBtn = el('button', { class: 'btn ghost sm', onclick: async () => {
    prepare.innerHTML = '';
    try {
      const { devices } = await platform('GET', '/usb/devices');
      if (!devices.length) {
        prepare.append(msg('warn', 'No USB drives are plugged in.'));
        return;
      }
      prepare.append(msg('warn', 'Preparing a drive erases everything on it.'));
      for (const d of devices) {
        prepare.append(el('div', { class: 'row', style: 'margin:.3rem 0' },
          el('span', { style: 'min-width:10rem' }, d.device),
          el('span', { class: 'pill' }, d.size),
          el('span', { class: 'muted' }, d.model),
          el('button', { class: 'btn danger sm', onclick: () => {
            if (!window.confirm(`Erase ${d.device} (${d.size} ${d.model}) and format it for NightWatcher data?`)) return;
            guard(out, `Formatting ${d.device}…`, async () => {
              await platform('POST', '/usb/prepare', { device: d.device, confirm: d.confirm });
              setTimeout(reload, 1500);
              return `${d.device} is ready and has been mirrored to.`;
            });
          } }, 'Erase and prepare')));
      }
    } catch (e) { prepare.append(msg('err', e.message)); }
  } }, 'Prepare a drive…');

  return card('USB data drive',
    el('p', { class: 'muted' },
      'A drive labelled NWDATA collects this unit\'s DSN files. It is mounted '
      + 'only while writing, so it can be unplugged at any time without '
      + 'ejecting: insert a drive, wait a few seconds, take it away. The unit '
      + 'keeps its own copy of everything, so a drive that never comes back '
      + 'loses nothing.'),
    kvTable([
      ['Drive', present ? `${usb.device} (${bytes(usb.size)})` : 'not plugged in'],
      ['Free space', present ? bytes(usb.free) : ''],
      ['Files ready to copy', usb.spool_files],
      ['Last mirrored', usb.last_sync || 'never'],
      ['Nightly export', enabled ? `on, from sensor ${exportTarget.sensor_id}` : 'off'],
    ]),
    el('div', { class: 'row', style: 'margin-top:.6rem' },
      enabled ? null : sensorPick, toggle, present ? sync : null, prepareBtn),
    prepare,
    out);
}

function sectionTime(status, reload) {
  const t = status.time || {};
  const out = el('div', {});
  const set = el('button', { class: 'btn ghost sm', onclick: () => guard(out,
    'Setting…', async () => {
      const r = await platform('POST', '/time', { epoch: Math.floor(Date.now() / 1000) });
      setTimeout(reload, 800);
      return 'Clock set from this browser: ' + r.utc;
    }) }, 'Set clock from this device');

  return card('Clock',
    el('p', { class: 'muted' },
      'Readings are only as trustworthy as their timestamps. With an uplink the '
      + 'clock syncs itself; without one, the device you are reading this on is '
      + 'the best time source the unit has.'),
    kvTable([
      ['Unit time (UTC)', t.utc],
      ['Time zone', t.timezone],
      ['Synchronised', t.ntp_synchronized ? 'yes, from the network' : 'no'],
    ]),
    el('div', { class: 'row', style: 'margin-top:.6rem' }, set),
    out);
}

// ---- entry point -----------------------------------------------------------

export async function render() {
  const frag = document.createDocumentFragment();
  frag.append(el('h2', {}, 'Raspberry Pi appliance'));

  const body = el('div', {});
  frag.append(body);

  const reload = async () => {
    body.innerHTML = '';
    body.append(el('p', { class: 'muted' }, 'Reading the unit…'));
    let status;
    try {
      status = await platform('GET', '/status');
    } catch (e) {
      body.innerHTML = '';
      body.append(msg('err', 'The appliance agent is not answering: ' + e.message));
      return;
    }

    // Best effort: the panel is still useful on a unit whose database is not
    // up yet, so a failure here costs the export controls and nothing else.
    let target = null, sensors = [];
    try {
      const targets = await core('GET', '/export-targets');
      target = (targets || []).find((t) => t.id === USB_TARGET_ID) || null;
    } catch (_) { /* leave the export controls in their off state */ }
    try { sensors = (await core('GET', '/sensors')) || []; } catch (_) { sensors = []; }

    body.innerHTML = '';
    const grid = el('div', { class: 'grid' });
    grid.append(sectionOverview(status));
    grid.append(sectionAccessPoint(status, reload));
    grid.append(sectionUplink(status, reload));
    grid.append(sectionUsb(status, target, sensors, reload));
    grid.append(sectionTime(status, reload));
    body.append(grid);
  };

  await reload();
  return frag;
}
