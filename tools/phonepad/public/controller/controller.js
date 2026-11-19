// PhonePad controller: touch stick + buttons + tilt + gyro -> binary packets over WSS.
// Three modes: "fps" (landscape, two thumbs, gyro aim; v2 packets at 120 Hz),
// "pad" (landscape, two hands) and "remote" (portrait, one hand, Wii-style); v1 packets at 60 Hz.
(() => {
  'use strict';

  // ------------------------------------------------------------ config
  const SEND_HZ = 60;            // pad / remote (v1)
  const FPS_HZ = 120;            // fps (v2)
  const STICK_RADIUS = 60;       // px of finger travel for full deflection
  const STICK_DEADZONE = 0.08;
  const TILT_DEADZONE = 5;       // degrees around calibrated centre
  const TILT_MAX = 35;           // degrees for full deflection (pad mode)
  const REMOTE_TILT_MAX = 30;    // remote mode: a bit more sensitive, one wrist does the work
  const TILT_SMOOTH = 0.3;       // EMA factor on the gravity vector, higher = snappier
  const FLICK_THRESHOLD = 14;    // pad mode: m/s^2 of linear acceleration
  const FLICK_COOLDOWN = 400;    // ms
  const SWING_THRESHOLD = 300;   // remote mode: deg/s of rotation rate for a swing
  const SWING_COOLDOWN = 450;    // ms, also swallows the wrist's rebound after a swing
  const GESTURE_FREEZE = 250;    // ms of held tilt after a gesture so a swing doesn't lurch the player
  const BTN = { A: 1, B: 2, X: 4, Y: 8, PAUSE: 16, END: 32 };
  const END_CONFIRM_MS = 2500;   // End needs a second tap within this window
  const DEG = 180 / Math.PI;

  // FPS mode tuning. Look travels in degrees of phone rotation; the game scales it.
  const LOOK_UNIT = 100;         // packet look units per degree (i16: +-327 degrees per packet)
  const TOUCH_DEG_PER_PX = 0.22; // right-thumb drag, degrees per CSS px
  const GYRO_DEADBAND = 0.8;     // deg/s: below this the gyro is sensor noise, faded in up to 2x
  const GYRO_YAW_SIGN = 1;       // see fpsMotion: flips the gyro's left/right turn
  const PITCH_BAND = 0.25;       // degrees of phone tilt ignored as jitter before up/down moves
  const BUILD = 6;              // shown on the start screen: proves the phone loaded this version
  const SPRINT_ON = 0.93, SPRINT_OFF = 0.8; // stick magnitude, with hysteresis
  const LEAN_ON = 18, LEAN_OFF = 10;        // degrees of steering-wheel roll, with hysteresis
  const FB = {
    FIRE: 1 << 0, AIM: 1 << 1, JUMP: 1 << 2, CROUCH: 1 << 3, PRONE: 1 << 4, SPRINT: 1 << 5,
    RELOAD: 1 << 6, MELEE: 1 << 7, GRENADE: 1 << 8, FLASH: 1 << 9, NEXT: 1 << 10, PREV: 1 << 11,
    PAUSE: 1 << 12, LEAN_L: 1 << 13, LEAN_R: 1 << 14, PLATE: 1 << 15,
  };

  // v1 packet (little-endian), 15 bytes:
  // u8 type=1 | u16 seq | u8 buttons | u8 flags(bit0 motion) | u8 gestureType | u8 gestureSeq
  // | i16 stickX | i16 stickY | i16 tiltX | i16 tiltY   (axes scaled to +-32767)
  const pkt = new DataView(new ArrayBuffer(15));
  // v2 packet (little-endian), 14 bytes:
  // u8 type=2 | u16 seq | u16 buttons (FB bits) | i16 moveX | i16 moveY (+-32767)
  // | i16 lookDx | i16 lookDy (1/100 degree, summed since the last packet that went out)
  // | u8 flags (bit0 gyro on, bit1 lean by tilt on, bit2 thumb on the look pad)
  const pkt2 = new DataView(new ArrayBuffer(14));
  let sysPulse = 0; // PAUSE/END bits OR'd into the buttons for a moment (see pulse())

  const state = {
    stickX: 0, stickY: 0, buttons: 0,
    motion: true, tiltX: 0, tiltY: 0,
    gestureType: 0, gestureSeq: 0, seq: 0,
  };
  // FPS: held buttons, presses not yet sent (latched), lean and sprint bits, look not yet sent.
  const fps = { buttons: 0, latch: 0, lean: 0, sprint: false, gyro: true, leanTilt: false, lookTouch: 0 };
  const look = { x: 0, y: 0 };

  const $ = (id) => document.getElementById(id);
  const statusEl = $('status'), statusText = $('statusText'), pingEl = $('ping');

  // ------------------------------------------------------------ connection
  let ws = null, retry = 0, lastPong = 0;
  function connect() {
    setStatus('wait', retry ? 'Reconnecting' : 'Connecting');
    ws = new WebSocket(`wss://${location.host}/ws?role=controller`);
    ws.binaryType = 'arraybuffer';
    ws.onopen = () => { retry = 0; setStatus('ok', 'Connected'); sendPing(); sendInput(); };
    ws.onclose = () => {
      setStatus('wait', 'Reconnecting'); pingEl.textContent = '';
      setTimeout(connect, Math.min(2000, 200 * 2 ** retry++));
    };
    ws.onerror = () => ws.close();
    ws.onmessage = (ev) => {
      let m; try { m = JSON.parse(ev.data); } catch { return; }
      if (m.t === 'pong') {
        lastPong = performance.now();
        pingEl.textContent = `${Math.round(lastPong - m.ts)} ms`;
      } else if (m.t === 'haptic' && Array.isArray(m.pattern)) {
        navigator.vibrate?.(m.pattern.slice(0, 20));
      } else if (m.t === 'state') {
        if (typeof m.hp === 'number') $('hpFill').style.width = `${Math.max(0, Math.min(1, m.hp)) * 100}%`;
        if (typeof m.energy === 'number') $('enFill').style.width = `${Math.max(0, Math.min(1, m.energy)) * 100}%`;
        showGameState(!!m.paused, !!m.over);
      }
    };
  }
  function setStatus(cls, text) { statusEl.className = cls; statusText.textContent = text; }
  function sendPing() {
    if (ws?.readyState === 1) ws.send(JSON.stringify({ t: 'ping', ts: performance.now() }));
  }

  const q = (v) => Math.round(Math.max(-1, Math.min(1, v)) * 32767);
  function sendInput() {
    if (mode === 'fps') return sendFps();
    if (ws?.readyState !== 1) return;
    if (ws.bufferedAmount > 1024) return; // link is choking: drop, never queue stale input
    state.seq = (state.seq + 1) & 0xffff;
    pkt.setUint8(0, 1);
    pkt.setUint16(1, state.seq, true);
    pkt.setUint8(3, (state.buttons | sysPulse) & 0xff);
    pkt.setUint8(4, state.motion ? 1 : 0);
    pkt.setUint8(5, state.gestureType);
    pkt.setUint8(6, state.gestureSeq);
    pkt.setInt16(7, q(state.stickX), true);
    pkt.setInt16(9, q(state.stickY), true);
    pkt.setInt16(11, q(state.motion ? state.tiltX : 0), true);
    pkt.setInt16(13, q(state.motion ? state.tiltY : 0), true);
    ws.send(pkt.buffer);
  }

  // A dropped packet loses nothing: look keeps summing in `look` and presses stay in
  // fps.latch until a packet carrying them actually goes out.
  const lookUnits = (deg) => Math.max(-32767, Math.min(32767, Math.round(deg * LOOK_UNIT)));
  function sendFps() {
    if (ws?.readyState !== 1) return;
    if (ws.bufferedAmount > 1024) return; // link is choking: drop, never queue stale input
    const dx = lookUnits(look.x), dy = lookUnits(look.y);
    const buttons = fps.buttons | fps.latch | fps.lean | sysPulse | (fps.sprint ? FB.SPRINT : 0);
    state.seq = (state.seq + 1) & 0xffff;
    pkt2.setUint8(0, 2);
    pkt2.setUint16(1, state.seq, true);
    pkt2.setUint16(3, buttons & 0xffff, true);
    pkt2.setInt16(5, q(state.stickX), true);
    pkt2.setInt16(7, q(state.stickY), true);
    pkt2.setInt16(9, dx, true);
    pkt2.setInt16(11, dy, true);
    pkt2.setUint8(13, (fps.gyro ? 1 : 0) | (fps.leanTilt ? 2 : 0) | (fps.lookTouch ? 4 : 0));
    ws.send(pkt2.buffer);
    look.x -= dx / LOOK_UNIT; look.y -= dy / LOOK_UNIT; // keep the remainder for next time
    fps.latch = 0;
  }

  // ------------------------------------------------------------ thumbstick (dynamic)
  const zone = $('stickZone'), base = $('stickBase'), knob = $('stickKnob');
  let stickId = null, cx = 0, cy = 0;
  zone.addEventListener('touchstart', (e) => {
    e.preventDefault();
    if (stickId !== null) return;
    const t = e.changedTouches[0], r = zone.getBoundingClientRect();
    stickId = t.identifier; cx = t.clientX; cy = t.clientY;
    base.style.left = `${cx - r.left}px`; base.style.top = `${cy - r.top}px`;
    base.classList.add('active');
    moveStick(cx, cy);
  }, { passive: false });
  zone.addEventListener('touchmove', (e) => {
    e.preventDefault();
    for (const t of e.changedTouches) if (t.identifier === stickId) moveStick(t.clientX, t.clientY);
  }, { passive: false });
  const endStick = (e) => {
    for (const t of e.changedTouches) {
      if (t.identifier !== stickId) continue;
      stickId = null; state.stickX = state.stickY = 0;
      knob.style.transform = ''; base.classList.remove('active');
      setSprint(false);
      sendInput();
    }
  };
  zone.addEventListener('touchend', endStick);
  zone.addEventListener('touchcancel', endStick);

  function moveStick(x, y) {
    let dx = x - cx, dy = y - cy;
    const len = Math.hypot(dx, dy);
    if (len > STICK_RADIUS) { dx *= STICK_RADIUS / len; dy *= STICK_RADIUS / len; }
    knob.style.transform = `translate(${dx}px, ${dy}px)`;
    let nx = dx / STICK_RADIUS, ny = -dy / STICK_RADIUS; // up = +Y
    const mag = Math.hypot(nx, ny);
    if (mag < STICK_DEADZONE) { nx = ny = 0; }
    else { const s = (mag - STICK_DEADZONE) / (1 - STICK_DEADZONE) / mag; nx *= s; ny *= s; }
    state.stickX = nx; state.stickY = ny;
    // FPS: the stick pushed to its edge sprints.
    if (mode === 'fps') setSprint(fps.sprint ? len / STICK_RADIUS > SPRINT_OFF : len / STICK_RADIUS > SPRINT_ON);
  }
  function setSprint(on) {
    if (on === fps.sprint) return;
    fps.sprint = on;
    if (on) { fps.latch |= FB.SPRINT; navigator.vibrate?.(10); }
    base.classList.toggle('sprint', on);
    sendInput();
  }

  // ------------------------------------------------------------ buttons (multi-touch, slide between)
  const btnZone = $('buttons');
  const btnEls = [...document.querySelectorAll('.btn')];
  function refreshButtons(e) {
    e.preventDefault();
    let mask = 0;
    for (const t of e.touches) {
      const el = document.elementFromPoint(t.clientX, t.clientY)?.closest('.btn');
      if (el && btnZone.contains(el)) mask |= Number(el.dataset.b);
    }
    const pressed = mask & ~state.buttons;
    if (pressed) navigator.vibrate?.(15);
    for (const el of btnEls) el.classList.toggle('down', !!(mask & Number(el.dataset.b)));
    if (mask !== state.buttons) { state.buttons = mask; sendInput(); } // send edges immediately
  }
  for (const ev of ['touchstart', 'touchmove', 'touchend', 'touchcancel']) {
    btnZone.addEventListener(ev, refreshButtons, { passive: false });
  }

  // ------------------------------------------------------------ FPS panel: buttons + look pad
  // Each touch keeps the button it started on (no sliding between: a thumb rolling off
  // FIRE must not press RELOAD). A touch that starts on the bare panel, or on FIRE or
  // AIM, also turns the view as it drags.
  const fpsPanel = $('fpsPanel');
  const fbEls = [...fpsPanel.querySelectorAll('.fb')];
  const fpsTouches = new Map(); // identifier -> { bit, look, x, y }
  function fpsTouchStart(e) {
    e.preventDefault();
    for (const t of e.changedTouches) {
      const el = t.target.closest?.('.fb');
      fpsTouches.set(t.identifier, {
        bit: el ? FB[el.dataset.fb] || 0 : 0,
        look: !el || el.dataset.look === '1',
        x: t.clientX, y: t.clientY,
      });
    }
    refreshFps();
  }
  function fpsTouchMove(e) {
    e.preventDefault();
    for (const t of e.changedTouches) {
      const s = fpsTouches.get(t.identifier);
      if (!s) continue;
      if (s.look) {
        look.x += (t.clientX - s.x) * TOUCH_DEG_PER_PX;
        look.y += (t.clientY - s.y) * TOUCH_DEG_PER_PX; // drag down = look down
      }
      s.x = t.clientX; s.y = t.clientY;
    }
  }
  function fpsTouchEnd(e) {
    e.preventDefault();
    for (const t of e.changedTouches) fpsTouches.delete(t.identifier);
    refreshFps();
  }
  function refreshFps() {
    let mask = 0, lookTouch = 0;
    for (const s of fpsTouches.values()) { mask |= s.bit; if (s.look) lookTouch++; }
    fps.lookTouch = lookTouch;
    const pressed = mask & ~fps.buttons;
    if (pressed) { fps.latch |= pressed; navigator.vibrate?.(12); }
    for (const el of fbEls) el.classList.toggle('down', !!(mask & FB[el.dataset.fb]));
    if (mask !== fps.buttons) { fps.buttons = mask; sendInput(); } // send edges immediately
  }
  fpsPanel.addEventListener('touchstart', fpsTouchStart, { passive: false });
  fpsPanel.addEventListener('touchmove', fpsTouchMove, { passive: false });
  fpsPanel.addEventListener('touchend', fpsTouchEnd, { passive: false });
  fpsPanel.addEventListener('touchcancel', fpsTouchEnd, { passive: false });
  function releaseFps() {
    fpsTouches.clear(); fps.buttons = fps.latch = fps.lean = 0; fps.sprint = false;
    look.x = look.y = 0;
    for (const el of fbEls) el.classList.remove('down');
  }

  // ------------------------------------------------------------ screen axes
  // Device axes (W3C): +X right edge, +Y top edge, +Z out of the screen, as held in portrait.
  // R and U are the screen's right and up directions in device axes for the current rotation.
  function screenAngle() {
    const a = screen.orientation?.angle ?? window.orientation ?? 0;
    return ((a % 360) + 360) % 360;
  }
  function axes() {
    switch (screenAngle()) {
      case 90:  return { R: [0, -1, 0], U: [1, 0, 0] };   // landscape-primary, top edge on the left
      case 180: return { R: [-1, 0, 0], U: [0, -1, 0] };
      case 270: return { R: [0, 1, 0], U: [-1, 0, 0] };   // landscape-secondary
      default:  return { R: [1, 0, 0], U: [0, 1, 0] };    // portrait
    }
  }
  const dot = (a, b) => a[0] * b[0] + a[1] * b[1] + a[2] * b[2];
  const wrap = (d) => ((d + 540) % 360) - 180;

  // ------------------------------------------------------------ tilt (gravity vector)
  // Tilt comes from the gravity vector, not Euler angles. Euler beta/gamma flip near
  // vertical, which made the old pad mode drift; gravity has no such seam in any normal
  // grip, so the same maths works flat (gamepad), upright, or pointed like a Wii Remote.
  //   pitch = angle of gravity in the screen-up/screen-normal plane (0 flat, 90 upright)
  //   roll  = elevation of the screen's right edge
  let grav = null;       // smoothed gravity, device axes, pointing world-up (+9.8 on Z when flat)
  let centre = null;     // gravity vector captured by Recenter
  let lastPitch = 0, freezeUntil = 0;

  function angles(g) {
    const { R, U } = axes();
    const r = dot(g, R), u = dot(g, U), z = g[2];
    const pz = Math.hypot(u, z);
    // Phone stood on its side edge: pitch is undefined there, keep the last value.
    const pitch = pz > 0.2 * Math.hypot(r, pz) ? Math.atan2(u, z) * DEG : lastPitch;
    return { pitch, roll: Math.atan2(r, pz) * DEG };
  }

  function updateTilt() {
    if (!grav) return;
    if (!centre) recenter();
    if (performance.now() < freezeUntil) return; // hold tilt through a swing
    const now = angles(grav), zero = angles(centre);
    lastPitch = now.pitch;
    const max = mode === 'remote' ? REMOTE_TILT_MAX : TILT_MAX;
    state.tiltX = shape(-(now.roll - zero.roll), max);           // right edge down = right
    state.tiltY = shape(-wrap(now.pitch - zero.pitch), max);     // top edge away/down = forward
    root.style.setProperty('--x', state.tiltX.toFixed(3));
    root.style.setProperty('--y', state.tiltY.toFixed(3));
  }
  function shape(deg, max) {
    const a = Math.abs(deg);
    if (a < TILT_DEADZONE) return 0;
    return Math.sign(deg) * Math.min(1, (a - TILT_DEADZONE) / (max - TILT_DEADZONE));
  }
  function recenter() {
    if (!grav) { centre = null; return; }
    centre = grav.slice();
    state.tiltX = state.tiltY = 0;
    fps.lean = 0;
    aimPitch = null; // new grip: up/down follows from here, no jump
  }
  const root = document.documentElement;

  // ------------------------------------------------------------ devicemotion: gravity + gestures
  let lastGesture = 0;
  function onMotion(e) {
    const gi = e.accelerationIncludingGravity;
    if (!gi || gi.x == null) return;
    const la = e.acceleration;
    const fused = la && la.x != null;
    // Chrome gives both readings on Android: their difference is the sensor-fused gravity,
    // which ignores hand shake and swings. Without it, fall back to a slow low-pass.
    const g = fused ? [gi.x - la.x, gi.y - la.y, gi.z - la.z] : [gi.x, gi.y, gi.z];
    const k = fused ? TILT_SMOOTH : 0.12;
    grav = grav ? grav.map((v, i) => v + (g[i] - v) * k) : g;
    if (mode === 'fps') return fpsMotion(e);
    if (state.motion) updateTilt();

    if (!state.motion) return;
    const now = performance.now();
    if (now - lastGesture < (mode === 'remote' ? SWING_COOLDOWN : FLICK_COOLDOWN)) return;
    const type = mode === 'remote' ? swing(e.rotationRate) : flick(fused ? [la.x, la.y, la.z] : g.map((v, i) => v - grav[i]));
    if (type) fireGesture(type, now);
  }

  // FPS motion aim. Left/right: the gyro's turn rate about world-up (from gravity), so
  // it works held upright or flat, integrated here at sensor rate. Up/down: the change
  // in the phone's angle against gravity, not the gyro rate. Gravity is a fixed
  // reference, so pitch never drifts (gyro bias made the view creep down) and putting
  // the phone back at an angle puts the view back where it was (slow tilts used to
  // vanish under the gyro deadband, so tilting back didn't undo tilting forward).
  let lastMotionT = 0;
  let aimPitch = null;   // phone angle the view's pitch is following, degrees

  // The phone's forward/back tilt against gravity in degrees (0 flat, 90 upright),
  // unaffected by steering-wheel roll; null when stood on a side edge.
  function phonePitch(g) {
    const { R, U } = axes();
    const r = dot(g, R), u = dot(g, U), z = g[2];
    const pz = Math.hypot(u, z);
    return pz > 0.35 * Math.hypot(r, pz) ? Math.atan2(u, z) * DEG : null;
  }
  function fpsMotion(e) {
    const t = e.timeStamp || performance.now();
    const dt = lastMotionT ? Math.min(0.05, Math.max(0, (t - lastMotionT) / 1000)) : 0;
    lastMotionT = t;
    if (!fps.gyro) { aimPitch = null; }
    const rr = e.rotationRate;
    if (fps.gyro && rr && rr.alpha != null && grav && dt > 0) {
      const w = [rr.beta || 0, rr.gamma || 0, rr.alpha || 0]; // deg/s about device X, Y, Z
      const gl = Math.hypot(grav[0], grav[1], grav[2]) || 1;
      const yaw = dot(w, grav) / gl;            // + = counter-clockwise from above = turn left
      const fade = Math.max(0, Math.min(1, (Math.abs(yaw) - GYRO_DEADBAND) / GYRO_DEADBAND));
      // Mouse convention: +x turns right. On the Redmi Note 14 (Chrome, HyperOS) the
      // yaw rate comes out the other way round from the maths above (steering the
      // phone left turned right), so GYRO_YAW_SIGN corrects it.
      look.x += GYRO_YAW_SIGN * yaw * fade * dt;
    }
    const pitch = fps.gyro && grav ? phonePitch(grav) : null; // null on its side edge: hold still
    if (pitch !== null) {
      if (aimPitch === null) aimPitch = pitch;
      // Follow the phone's angle, but only once it leaves a small band: sensor jitter
      // never shakes the view, and every real tilt still comes back exactly.
      const diff = wrap(pitch - aimPitch);
      if (Math.abs(diff) > PITCH_BAND) {
        const step = diff - Math.sign(diff) * PITCH_BAND;
        aimPitch = wrap(aimPitch + step);
        // Pitch here: 0 flat, 90 upright. Top edge toward you lowers it = look up,
        // which is -y in mouse convention: so the change goes straight into look.y.
        look.y += step;
      }
    }
    if (fps.leanTilt && grav) {
      if (!centre) recenter();
      // + = lean right: right edge down, the same sign as the pad mode's tilt.
      const roll = -(angles(grav).roll - angles(centre).roll);
      const held = fps.lean === FB.LEAN_R ? roll > LEAN_OFF : fps.lean === FB.LEAN_L ? roll < -LEAN_OFF : false;
      const lean = held ? fps.lean : roll > LEAN_ON ? FB.LEAN_R : roll < -LEAN_ON ? FB.LEAN_L : 0;
      if (lean !== fps.lean) { fps.lean = lean; if (lean) { fps.latch |= lean; navigator.vibrate?.(10); } }
    }
  }

  // Pad mode: jerk the whole phone up (out of the screen) to jump, or away from you to attack.
  function flick(lin) {
    const { U, R } = axes();
    const up = lin[2], fwd = dot(lin, U), side = Math.abs(dot(lin, R));
    if (up > FLICK_THRESHOLD && up > Math.abs(fwd) && up > side) return 1;
    if (fwd > FLICK_THRESHOLD && fwd > Math.abs(up) && fwd > side) return 2;
    return 0;
  }

  // Remote mode, Wii style, from the gyroscope:
  //   flick the tip up (pitch rate)                              -> jump
  //   swing sideways (yaw), twist the wrist (roll) or chop down  -> shockwave attack
  function swing(rr) {
    if (!rr || rr.alpha == null) return 0;
    const w = [rr.beta || 0, rr.gamma || 0, rr.alpha || 0]; // deg/s about device X, Y, Z
    const { R, U } = axes();
    const pitch = dot(w, R), roll = Math.abs(dot(w, U)), yaw = Math.abs(w[2]);
    if (pitch > SWING_THRESHOLD && pitch > roll && pitch > yaw) return 1;
    if (Math.max(roll, yaw, -pitch) > SWING_THRESHOLD) return 2;
    return 0;
  }

  const flashEl = $('gestureFlash');
  let flashTimer = 0;
  function fireGesture(type, now) {
    lastGesture = now;
    freezeUntil = now + GESTURE_FREEZE;
    state.gestureType = type;
    state.gestureSeq = (state.gestureSeq + 1) & 0xff;
    navigator.vibrate?.(30);
    sendInput();
    flashEl.textContent = type === 1 ? 'JUMP' : 'ATTACK';
    flashEl.className = type === 1 ? 'jump show' : 'attack show';
    clearTimeout(flashTimer);
    flashTimer = setTimeout(() => { flashEl.className = ''; }, 350);
  }

  // ------------------------------------------------------------ modes
  // fps: landscape, stick + gyro/drag look + FPS buttons. pad: landscape, stick + ABXY,
  // tilt optional. remote: portrait, one hand, tilt always on.
  const MODES = ['fps', 'pad', 'remote'];
  let mode = 'fps';
  try { if (MODES.includes(localStorage.getItem('phonepad.mode'))) mode = localStorage.getItem('phonepad.mode'); } catch {}
  const motionBox = $('motion'), gyroBox = $('gyro'), leanBox = $('lean');
  let padMotion = true;
  try {
    padMotion = localStorage.getItem('phonepad.padMotion') !== '0';
    fps.gyro = localStorage.getItem('phonepad.gyro') !== '0';
    fps.leanTilt = localStorage.getItem('phonepad.leanTilt') === '1';
  } catch {}
  motionBox.checked = padMotion; gyroBox.checked = fps.gyro; leanBox.checked = fps.leanTilt;

  function applyMode() {
    document.body.classList.toggle('remote', mode === 'remote');
    document.body.classList.toggle('fps', mode === 'fps');
    state.motion = mode === 'remote' ? true : mode === 'pad' ? padMotion : false;
    $('tiltDot').classList.toggle('hidden', !state.motion);
    $('rotateText').textContent = mode === 'remote' ? 'Turn the phone upright' : 'Rotate to landscape';
    for (const b of document.querySelectorAll('.modeBtn')) b.classList.toggle('last', b.dataset.mode === mode);
    if (!state.motion) state.tiltX = state.tiltY = 0;
    if (mode !== 'fps') releaseFps();
    state.buttons = 0;
    for (const el of btnEls) el.classList.remove('down');
  }
  async function lockOrientation() {
    try { await screen.orientation.lock(mode === 'remote' ? 'portrait-primary' : 'landscape'); return true; }
    catch { return false; }
  }
  // Recenter once the new grip has settled (rotation animation, hands moving).
  let recenterTimer = 0;
  function scheduleRecenter(ms = 700) { clearTimeout(recenterTimer); recenterTimer = setTimeout(recenter, ms); }

  // ------------------------------------------------------------ pause / end
  // Sent as a short pulse on spare button bits; the game's press latch
  // catches it even if the pulse lands between two game frames.
  function pulse(bit) {
    sysPulse |= bit; sendInput();
    setTimeout(() => { sysPulse &= ~bit; sendInput(); }, 120);
  }
  const pauseBtn = $('pauseBtn'), endBtn = $('endBtn');
  let endArmed = 0;
  pauseBtn.addEventListener('click', () => { pulse(mode === 'fps' ? FB.PAUSE : BTN.PAUSE); navigator.vibrate?.(20); });
  endBtn.addEventListener('click', () => {
    if (endBtn.disabled) return;
    if (performance.now() < endArmed) {
      endArmed = 0; disarmEnd();
      pulse(BTN.END); navigator.vibrate?.([40, 30, 80]);
    } else {
      endArmed = performance.now() + END_CONFIRM_MS;
      endBtn.classList.add('confirm'); endBtn.querySelector('span').textContent = 'Tap to end';
      navigator.vibrate?.(15);
      setTimeout(() => { if (performance.now() >= endArmed) disarmEnd(); }, END_CONFIRM_MS + 50);
    }
  });
  function disarmEnd() { endBtn.classList.remove('confirm'); endBtn.querySelector('span').textContent = 'End'; }
  function showGameState(paused, over) {
    pauseBtn.classList.toggle('on', paused);
    pauseBtn.querySelector('i').className = paused ? 'ico play' : 'ico pause';
    pauseBtn.querySelector('span').textContent = paused ? 'Resume' : 'Pause';
    pauseBtn.disabled = over;
    endBtn.disabled = over;
    if (over) { endArmed = 0; disarmEnd(); }
  }

  // ------------------------------------------------------------ utility bar
  $('recenter').addEventListener('click', () => { recenter(); navigator.vibrate?.([20, 40, 20]); });
  $('recenter2').addEventListener('click', () => { recenter(); navigator.vibrate?.([20, 40, 20]); });
  $('modeBtn').addEventListener('click', () => $('start').classList.remove('hidden')); // pick again
  motionBox.addEventListener('change', () => {
    padMotion = motionBox.checked;
    try { localStorage.setItem('phonepad.padMotion', padMotion ? '1' : '0'); } catch {}
    applyMode();
    if (state.motion) recenter();
    sendInput();
  });
  gyroBox.addEventListener('change', () => {
    fps.gyro = gyroBox.checked;
    try { localStorage.setItem('phonepad.gyro', fps.gyro ? '1' : '0'); } catch {}
  });
  leanBox.addEventListener('change', () => {
    fps.leanTilt = leanBox.checked;
    try { localStorage.setItem('phonepad.leanTilt', fps.leanTilt ? '1' : '0'); } catch {}
    fps.lean = 0;
    if (fps.leanTilt) recenter();
    sendInput();
  });
  screen.orientation?.addEventListener('change', () => { if (started) scheduleRecenter(); });

  // ------------------------------------------------------------ start / connect
  let wakeLock = null;
  async function acquireWakeLock() {
    try { wakeLock = await navigator.wakeLock?.request('screen'); } catch { /* not fatal */ }
  }
  document.addEventListener('visibilitychange', () => {
    if (document.visibilityState === 'visible' && started) acquireWakeLock();
  });

  let started = false;
  async function start(m) {
    mode = m;
    try { localStorage.setItem('phonepad.mode', m); } catch {}
    applyMode();
    $('start').classList.add('hidden');
    const errs = [];
    if (!document.fullscreenElement) {
      try { await document.documentElement.requestFullscreen({ navigationUI: 'hide' }); }
      catch { errs.push('fullscreen'); }
    }
    if (!(await lockOrientation())) errs.push('orientation lock');
    await acquireWakeLock();
    // iOS-style permission gate; Chrome on Android resolves immediately or has no method.
    if (typeof window.DeviceMotionEvent?.requestPermission === 'function') {
      try { await DeviceMotionEvent.requestPermission(); } catch { errs.push('motion permission'); }
    }
    if (!window.isSecureContext) errs.push('page is not HTTPS, motion sensors will be blocked');
    if (!started) window.addEventListener('devicemotion', onMotion);
    navigator.vibrate?.(40);

    started = true;
    checkRotate();
    if (errs.length) console.warn('Start warnings:', errs.join(', '));
    if (!ws) connect();
    sendInput();
    scheduleRecenter(); // let the rotation and grip settle, then zero
  }
  for (const b of document.querySelectorAll('.modeBtn')) b.addEventListener('click', () => start(b.dataset.mode));

  const portrait = matchMedia('(orientation: portrait)');
  const checkRotate = () => {
    const wrong = mode === 'remote' ? !portrait.matches : portrait.matches;
    $('rotate').classList.toggle('hidden', !(started && wrong));
  };
  portrait.addEventListener('change', checkRotate);
  document.addEventListener('fullscreenchange', checkRotate);
  applyMode();
  document.querySelector('.hint').textContent += ` (build ${BUILD})`;

  // ------------------------------------------------------------ loops
  // One 120 Hz clock: fps sends every tick, pad and remote every other tick (60 Hz).
  let tick = 0;
  setInterval(() => {
    tick++;
    if (mode === 'fps' || tick % (FPS_HZ / SEND_HZ) === 0) sendInput();
  }, 1000 / FPS_HZ);
  setInterval(() => {
    sendPing();
    if (ws?.readyState === 1 && lastPong && performance.now() - lastPong > 3500) ws.close(); // stale link
  }, 1000);
  document.addEventListener('contextmenu', (e) => e.preventDefault());
})();
