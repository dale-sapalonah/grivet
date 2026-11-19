// Simulated phone for tests: connects to the PhonePad server over WSS like the real
// controller page (the self-signed cert is accepted with rejectUnauthorized: false),
// waits until Grivet is connected (its first {t:"state"} message), then plays a fixed
// FPS-mode timeline of v2 packets at 120 Hz. tests/probes/phone_pad.gd checks the result.
//
//   node tools/phonepad/sim/phone_sim.js [--port 8443] [--loop]
//
// Timeline (seconds after the game's first state message):
//   0.0-1.5  stick forward (full)                1.5-2.3  turn right 30 degrees, every 7th packet dropped
//   2.9-3.5  FIRE held                           3.7      RELOAD tapped in one packet
//   4.0      NEXT WEAPON tapped in one packet    4.6      FIRE + forward in one packet, then silence
// After 6.5 s it stays connected and silent for 60 s (or loops with --loop), printing each haptic.
'use strict';

const path = require('path');
const WebSocket = require(path.join(__dirname, '..', 'node_modules', 'ws'));

const args = process.argv.slice(2);
const port = Number(args[args.indexOf('--port') + 1] || process.env.PHONEPAD_HTTPS_PORT || 8443);
const loop = args.includes('--loop');
const B = { FIRE: 1, RELOAD: 1 << 6, NEXT: 1 << 10 };
const HZ = 120;

const ws = new WebSocket(`wss://127.0.0.1:${port}/ws?role=controller`, { rejectUnauthorized: false });
let seq = 0, t0 = 0, tick = 0, haptics = [];
const look = { x: 0, y: 0 };

function packet(buttons, mx, my, lx, ly) {
  const b = Buffer.alloc(14);
  seq = (seq + 1) & 0xffff;
  b.writeUInt8(2, 0); b.writeUInt16LE(seq, 1); b.writeUInt16LE(buttons, 3);
  b.writeInt16LE(Math.round(mx * 32767), 5); b.writeInt16LE(Math.round(my * 32767), 7);
  b.writeInt16LE(lx, 9); b.writeInt16LE(ly, 11); b.writeUInt8(1, 13);
  return b;
}
// Sends like the phone: look summed until a packet actually goes out.
function send(buttons, mx, my, drop = false) {
  if (drop) return;
  const dx = Math.round(look.x * 100), dy = Math.round(look.y * 100);
  ws.send(packet(buttons, mx, my, dx, dy));
  look.x -= dx / 100; look.y -= dy / 100;
}

// Time-based, not tick-based: Node's timers on Windows tick at ~15 ms, not 8.3.
let turned = 0, once = {};
const at = (t, mark) => t >= mark && !once[mark] && (once[mark] = true);
function step() {
  const t = (performance.now() - t0) / 1000;
  tick++;
  if (t < 1.5) send(0, 0, 1);
  else if (t < 2.9) {
    const want = 30 * Math.min(1, (t - 1.5) / 0.8); // turn like a gyro: integrated over time
    look.x += want - turned; turned = want;
    send(0, 0, 0, tick % 7 === 0);
  } else if (t < 3.5) send(B.FIRE, 0, 0);
  else if (at(t, 3.7)) { send(B.RELOAD, 0, 0); send(0, 0, 0); } // press + release, same tick
  else if (at(t, 4.0)) { send(B.NEXT, 0, 0); send(0, 0, 0); }
  else if (at(t, 4.6)) send(B.FIRE, 0, 1); // ...then silence: the game must let go
  else if (t < 4.6) send(0, 0, 0);
  else if (t > 6.5 && !once.done) {
    once.done = true;
    console.log(`SIM done: ${seq} packets, ${haptics.length} haptics so far`);
    if (loop) { t0 = performance.now(); turned = 0; once = {}; }
    // Otherwise stay connected and silent (haptics keep printing) until killed or 60 s.
    else setTimeout(() => process.exit(0), 60000);
  }
}

ws.on('open', () => console.log(`SIM connected to wss://127.0.0.1:${port}`));
ws.on('message', (data, isBinary) => {
  if (isBinary) return;
  let m; try { m = JSON.parse(data); } catch { return; }
  if (m.t === 'haptic') { haptics.push(m.pattern); console.log(`SIM haptic ${JSON.stringify(m.pattern)}`); }
  if (m.t === 'state' && !t0) {
    clearTimeout(giveUp);
    console.log('SIM game is connected, starting the timeline');
    t0 = performance.now();
    setInterval(step, 1000 / HZ);
  }
});
ws.on('error', (e) => { console.error(`SIM error: ${e.message}`); process.exit(1); });
const giveUp = setTimeout(() => { console.error('SIM gave up: no game within 120 s'); process.exit(1); }, 120000);
