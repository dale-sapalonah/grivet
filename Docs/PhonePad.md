# PhonePad: a phone as Grivet's controller

A phone (built for a Redmi Note 14 in Chrome) becomes an extra controller over
WSS, by USB tether or Wi-Fi. Keyboard and mouse keep working, and the two
combine: hold W on the keyboard and push the phone's stick right, and the player
walks forward-right.

## Launch

**From the game menu (any launcher):** pick **PHONE** on the title screen or
the pause menu. Grivet starts the PhonePad server itself if it isn't running
(hidden, stopped when Grivet quits) and shows a QR code per network, USB
tether first. Scan it with the phone camera, accept the certificate warning
once, tap **FPS**. The page turns green (PHONE CONNECTED) when the phone is
in; go BACK and play. Picking PHONE also turns the PHONE CONTROLLER setting on.
The packages must be installed once (step 2 below does it), and Node.js 18+.

**With the launcher:**

1. Plug the phone in and turn on USB tethering (or put both on the same Wi-Fi).
2. Run `Play Grivet with Phone.bat`. The first run installs PhonePad's locked
   packages (`npm ci --ignore-scripts`: ws 8.23.0, selfsigned 5.5.0,
   qrcode-terminal 0.12.0). Needs Node.js 18+.
3. A "PhonePad" window shows a QR code per usable network (USB tether first).
   Scan it with the phone, accept the certificate warning once, tap **FPS**.
4. Play. The status dot turns green when the phone is connected. Grivet prints
   `PhonePad: phone connected` in its log.

Notes:
- Grivet's PhonePad has its own ports, 8444 (phone) and 8081 (game), so it
  runs beside Reef Rush's (8443 and 8080) and the two can't be mixed up. The
  server says `{"t":"hello","app":"grivet"}` to the game on connect, and the
  PHONE page only shows QR codes from a server that did. The phone page's title
  reads "PhonePad for Grivet". A bookmark of the old :8443 address opens Reef
  Rush's page: scan again.
- Grivet's copy makes its own self-signed certificate (`tools/phonepad/certs/`,
  never committed), so the phone asks once more than it did for Reef Rush. It
  asks again whenever the PC's addresses change (the USB tether subnet is random).
- SETTINGS > PHONE CONTROLLER (PHONEPAD) turns it off. Without a server, Grivet
  quietly retries every 2 s.
- Menus stay on the mouse (their buttons take no keyboard focus).

## Controls (FPS mode, phone sideways)

| Phone | Grivet action |
|---|---|
| Left stick (appears where the thumb lands) | move, analog |
| Stick pushed to the edge | sprint |
| Turning the phone (gyro) | look / aim |
| Dragging on the right panel, or while holding FIRE | look (big turns) |
| FIRE | fire; also skips mission cinematics and retries after MISSION FAILED |
| AIM | aim down sights, as a toggle: a press turns it on and it stays on, the next tap turns it off. While your thumb is on it, AIM is also a small thumbstick: push it off its spot to turn the view (faster the further you push, 90 degrees/s of phone turn at full push), so you can move with the left stick and aim with this one |
| JUMP | jump / mantle; also skips cinematics |
| CROUCH, PRONE | crouch, prone |
| RELOAD, KNIFE | reload, melee (takedowns too) |
| FRAG, FLASH | grenade, flashbang |
| ◀ WPN, WPN ▶ | previous / next weapon |
| PLATE | insert armour plate (hold) |
| Pause (top bar) | pause menu; tap again to resume |
| Lean toggle, then tilting the phone like a steering wheel | lean left / right |
| Gyro toggle | gyro aim on or off |
| Recenter | zero the lean tilt for the current grip |

Motion aim works held upright or flat. Left/right is the gyro's turn about
world-up (from gravity). Up/down follows the phone's angle against gravity:
top edge toward you looks up, away looks down, and putting the phone back
at an angle puts the view back (no gyro drift; tilts under 0.25 degrees are
ignored as jitter). Recenter (or a change of grip) starts it afresh. Sensitivity follows
Grivet's MOUSE SENSITIVITY, ADS multiplier and INVERT MOUSE Y. The base scale is
`look_pixels_per_degree` in `data/input/phone_pad_tuning.tres` (16: one degree
of phone turn is two degrees of view at default sensitivity).

Haptics: a short tick per shot (at most every 60 ms), a buzz when hit (longer
for heavy hits), a triple pulse for the player's kills (shot within 1.5 s of
the death, or the knife), a long one on death. Patterns are in the tuning file.
The phone's HUD bars show health (red) and armour (teal).

Hostages and objectives have no interact key: hostages are freed when their
captor dies, SEARCH completes by standing in the radius, REACH and EXTRACT by
arriving. So no phone button is needed beyond moving and fighting.

## How it fits together

```
phone (Chrome)  --WSS :8444-->  tools/phonepad/server.js  --WS 127.0.0.1:8081-->  PhonePad autoload
  controller.js     binary packets      relays untouched        (game role only)    core/phone_pad.gd
                <-- {t:"haptic"}, {t:"state"} ----------------------------------------
```

- The server listens on 0.0.0.0:8444 (HTTPS + WSS, phone page and controller
  socket) and 127.0.0.1:8081 (game socket and `/api/controller-links`, which
  lists the phone URLs with QR modules; localhost only). Controllers can only
  connect over WSS; the game port refuses the controller role. It serves no
  game files.
- `core/phone_pad.gd` feeds Grivet's own input system, never the OS: held
  actions through `Input.action_press/release` (movement with analog strength,
  pre-stretched past `Input.get_vector`'s circular deadzone), next/previous
  weapon and pause as `InputEventAction` events (their handlers react to
  events), look as synthetic `InputEventMouseMotion` (only while the mouse is
  captured), so `player.gd` applies sensitivity, ADS, invert Y and the pitch
  limit unchanged. Nothing on the LAN can drive anything but this game.
- Look is applied per packet, never scaled by frame time, so it doesn't depend
  on Grivet's frame rate (15 to 60 fps on the HD 630).
- Old input is never acted on: the phone drops a packet rather than queue it
  when `ws.bufferedAmount > 1024`, but keeps the look it carried and any press
  it held for the next packet that goes out. Grivet uses the newest packet's
  buttons and movement, sums every packet's look, and latches presses so a tap
  shorter than a game tick still registers once. No packet for 500 ms
  releases everything.

## Protocol

Binary, little-endian. **v2** (FPS mode, 120 Hz), 14 bytes:

| Offset | Type | Field |
|---|---|---|
| 0 | u8 | type = 2 |
| 1 | u16 | seq (wraps) |
| 3 | u16 | buttons |
| 5 | i16 | move x (right +), ±32767 |
| 7 | i16 | move y (forward +), ±32767 |
| 9 | i16 | look dx, 1/100 degree of phone turn, mouse convention (+ turns right) |
| 11 | i16 | look dy, 1/100 degree (+ looks down) |
| 13 | u8 | flags: bit0 gyro on, bit1 lean by tilt on, bit2 thumb on the look pad |

Look dx/dy are summed on the phone since the last packet that actually went
out. Buttons: bit 0 FIRE, 1 AIM, 2 JUMP, 3 CROUCH, 4 PRONE, 5 SPRINT, 6 RELOAD,
7 MELEE, 8 GRENADE, 9 FLASHBANG, 10 NEXT_WEAPON, 11 PREVIOUS_WEAPON, 12 PAUSE,
13 LEAN_LEFT, 14 LEAN_RIGHT, 15 PLATE.

**v1** (Gamepad and Remote modes, 60 Hz, Reef Rush's format), 15 bytes:
u8 type=1, u16 seq, u8 buttons (A 1, B 2, X 4, Y 8, PAUSE 16, END 32), u8
flags, u8 gesture, u8 gesture seq, i16 stick x/y, i16 tilt x/y. Grivet maps
it as stick = move, A jump, B fire, X reload, Y sprint, PAUSE pause.

Game to phone (JSON text, relayed by the server): `{"t":"haptic","pattern":[ms,...]}`
(on, off, on...) and `{"t":"state","hp":0..1,"energy":0..1,"paused":bool,"over":bool}`
(every 0.25 s while a phone is connected). Server to game:
`{"t":"hello","app":"grivet"}` on connect and `{"t":"controllers","count":n}`.

Decoding, the stale-packet check, latching and the timeout live in
`core/phone_pad_protocol.gd` (PhonePadProtocol, pure, tested by
`tests/core/test_phone_pad_protocol.gd`).

## Testing

- Unit tests: the normal headless test run.
- Menu (windowed): `$GODOT --path . res://tests/probes/phone_menu.tscn [-- shot=<abs path>.png]`
  boots the title, picks PHONE, checks the game starts the server, shows QR
  codes, connects, and says PHONE CONNECTED when the sim phone joins.
- End to end (windowed, needs Node and the installed packages):
  `$GODOT --path . res://tests/probes/phone_pad.tscn`. It starts the server and
  `tools/phonepad/sim/phone_sim.js`, a simulated phone over WSS
  (`rejectUnauthorized: false`) that walks, turns 30 degrees while dropping
  every 7th packet, fires, taps reload and next weapon in single packets, then
  goes silent. The probe checks movement, look (every degree arrives), firing,
  latched taps, the 500 ms release, haptics (fire, damage, kills), pause and
  resume, and that keyboard and mouse still work and combine. If another
  PhonePad holds the ports, set `PHONEPAD_HTTPS_PORT` and `PHONEPAD_GAME_PORT`
  (the server, the sim and the autoload all read them).
- Debug command `phone`: status (connection, phones, packets, look, haptics);
  `phone buzz` vibrates the phone; `phone on|off` toggles it.
