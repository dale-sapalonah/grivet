// PhonePad server for Grivet: serves the phone controller over HTTPS/WSS (LAN + USB
// tether), a localhost-only WebSocket for the game, and relays packets between them.
// Copied from Reef Rush's PhonePad, minus the browser game mounts.
'use strict';

const fs = require('fs');
const os = require('os');
const path = require('path');
const http = require('http');
const https = require('https');
const { WebSocketServer, WebSocket } = require('ws');
const selfsigned = require('selfsigned');
const qrcode = require('qrcode-terminal');
// qrcode-terminal's bundled encoder, reused to give the game page raw QR modules to draw.
const QRCode = require('qrcode-terminal/vendor/QRCode');
const QRErrorCorrectLevel = require('qrcode-terminal/vendor/QRCode/QRErrorCorrectLevel');

function qrModules(text) {
  const q = new QRCode(-1, QRErrorCorrectLevel.M); // M: survives monitor glare and moire better than L
  q.addData(text);
  q.make();
  return q.modules.map((row) => row.map((dark) => (dark ? 1 : 0)).join(''));
}

// Not Reef Rush's 8443/8080: Grivet's PhonePad has its own ports, so the two can't be mixed up.
const HTTPS_PORT = Number(process.env.PHONEPAD_HTTPS_PORT || 8444); // phone
const GAME_PORT = Number(process.env.PHONEPAD_GAME_PORT || 8081);   // Grivet, localhost only
const APP = 'grivet'; // told to the game on connect, so Grivet knows it found its own server
const ROOT = __dirname;
const CERT_DIR = path.join(ROOT, 'certs');

// ---------------------------------------------------------------- networking
// Interfaces that are almost never the one the phone can reach.
const VIRTUAL_IF = /(vethernet|virtualbox|vmware|vbox|docker|br-|veth|wsl|hyper-v|loopback|tailscale|zerotier|utun|tun|tap)/i;
// Android USB tethering (RNDIS). Older Android uses 192.168.42.x; newer builds
// randomise the subnet, so the interface name is the better hint on Windows.
const USB_IF = /(rndis|remote ndis|usb|enx|ncm)/i;

// Windows names adapters "Ethernet 2", "Ethernet 3" etc., so the name alone can't
// tell a USB tether or a VirtualBox host-only adapter apart from a real NIC.
// The hardware description can ("Remote NDIS based...", "VirtualBox Host-Only...").
function adapterDescriptions() {
  if (process.platform !== 'win32') return {};
  try {
    const out = require('child_process').execFileSync('powershell.exe', [
      '-NoProfile', '-NonInteractive', '-Command',
      'Get-NetAdapter | Select-Object Name,InterfaceDescription | ConvertTo-Json -Compress',
    ], { encoding: 'utf8', timeout: 8000, windowsHide: true });
    const list = [].concat(JSON.parse(out) || []);
    return Object.fromEntries(list.map((a) => [a.Name, a.InterfaceDescription || '']));
  } catch { return {}; } // fall back to name-only matching
}

function localIPv4s() {
  const out = [];
  const desc = adapterDescriptions();
  for (const [name, addrs] of Object.entries(os.networkInterfaces())) {
    const label = `${name} ${desc[name] || ''}`;
    for (const a of addrs || []) {
      if (a.family !== 'IPv4' && a.family !== 4) continue;
      if (a.internal) continue;
      if (a.address.startsWith('169.254.')) continue; // link-local, no DHCP
      const usb = USB_IF.test(label) || a.address.startsWith('192.168.42.');
      const virtual = !usb && VIRTUAL_IF.test(label);
      out.push({ name: desc[name] ? `${name}: ${desc[name]}` : name, address: a.address, usb, virtual });
    }
  }
  // USB first (lowest latency), then real NICs, then virtual ones.
  return out.sort((x, y) => (y.usb - x.usb) || (x.virtual - y.virtual));
}

// ---------------------------------------------------------------- certificate
async function loadOrCreateCert(ips) {
  fs.mkdirSync(CERT_DIR, { recursive: true });
  const keyFile = path.join(CERT_DIR, 'key.pem');
  const certFile = path.join(CERT_DIR, 'cert.pem');
  const metaFile = path.join(CERT_DIR, 'meta.json');
  const wanted = ['127.0.0.1', ...ips].sort();

  try {
    const meta = JSON.parse(fs.readFileSync(metaFile, 'utf8'));
    const sameIps = JSON.stringify(meta.ips) === JSON.stringify(wanted);
    const fresh = Date.now() < meta.expires - 7 * 864e5;
    if (sameIps && fresh) {
      return { key: fs.readFileSync(keyFile), cert: fs.readFileSync(certFile), reused: true };
    }
  } catch { /* no usable cert yet */ }

  // A new cert means Chrome on the phone asks once more. We only regenerate
  // when the PC's IPs change (cert SANs must match the address in the URL).
  const notBefore = new Date(Date.now() - 864e5);
  const notAfter = new Date(notBefore);
  notAfter.setFullYear(notAfter.getFullYear() + 1);
  const pems = await selfsigned.generate(
    [{ name: 'commonName', value: 'PhonePad Local' }],
    {
      keyType: 'ec',
      curve: 'P-256',
      algorithm: 'sha256',
      notBeforeDate: notBefore,
      notAfterDate: notAfter,
      extensions: [
        { name: 'basicConstraints', cA: false },
        { name: 'keyUsage', digitalSignature: true, keyEncipherment: true },
        { name: 'extKeyUsage', serverAuth: true },
        {
          name: 'subjectAltName',
          altNames: [
            { type: 2, value: 'localhost' },
            { type: 2, value: os.hostname() },
            ...wanted.map((ip) => ({ type: 7, ip })),
          ],
        },
      ],
    }
  );
  fs.writeFileSync(keyFile, pems.private, { mode: 0o600 });
  fs.writeFileSync(certFile, pems.cert);
  fs.writeFileSync(metaFile, JSON.stringify({ ips: wanted, expires: notAfter.getTime() }));
  return { key: pems.private, cert: pems.cert, reused: false };
}

// ---------------------------------------------------------------- static files
const MIME = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.mjs': 'text/javascript; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.json': 'application/json',
  '.webmanifest': 'application/manifest+json',
  '.png': 'image/png',
  '.svg': 'image/svg+xml',
};

function serveStatic(mounts) {
  return (req, res) => {
    const url = new URL(req.url, 'http://x');
    let p = decodeURIComponent(url.pathname);
    if (p === '/') { res.writeHead(302, { Location: mounts.index }); return res.end(); }
    // Phone keyboards and QR apps drop the trailing slash or capitalise: /controller, /Controller/
    const lower = p.toLowerCase();
    for (const prefix of Object.keys(mounts.dirs)) {
      if (lower === prefix.slice(0, -1) || lower === prefix && p !== prefix) {
        res.writeHead(302, { Location: prefix }); return res.end();
      }
    }
    for (const [prefix, dir] of Object.entries(mounts.dirs)) {
      if (!p.startsWith(prefix)) continue;
      let rel = p.slice(prefix.length) || 'index.html';
      if (rel.endsWith('/')) rel += 'index.html';
      const file = path.resolve(dir, rel);
      if (!file.startsWith(path.resolve(dir) + path.sep)) break; // path traversal guard
      return fs.readFile(file, (err, data) => {
        if (err) { res.writeHead(404); return res.end('Not found'); }
        res.writeHead(200, {
          'Content-Type': MIME[path.extname(file)] || 'application/octet-stream',
          'Cache-Control': 'no-store',
        });
        res.end(data);
      });
    }
    res.writeHead(404); res.end('Not found');
  };
}

// ---------------------------------------------------------------- relay
const controllers = new Set();
const games = new Set();

function broadcast(set, data, isBinary) {
  for (const ws of set) if (ws.readyState === WebSocket.OPEN) ws.send(data, { binary: isBinary });
}
function announce() {
  broadcast(games, JSON.stringify({ t: 'controllers', count: controllers.size }), false);
}

function attachWs(server, allowController) {
  const wss = new WebSocketServer({ noServer: true, perMessageDeflate: false, maxPayload: 4096 });
  server.on('upgrade', (req, socket, head) => {
    const url = new URL(req.url, 'http://x');
    const role = url.searchParams.get('role');
    if (url.pathname !== '/ws' || !['controller', 'game'].includes(role) ||
        (role === 'controller' && !allowController)) {
      socket.destroy();
      return;
    }
    wss.handleUpgrade(req, socket, head, (ws) => {
      ws._socket.setNoDelay(true); // no Nagle batching, every packet goes now
      ws.role = role;
      ws.isAlive = true;
      ws.on('pong', () => { ws.isAlive = true; });
      (role === 'controller' ? controllers : games).add(ws);
      if (role === 'game') ws.send(JSON.stringify({ t: 'hello', app: APP }));
      const who = `${role} ${req.socket.remoteAddress}`;
      console.log(`[+] ${who} connected (controllers: ${controllers.size}, games: ${games.size})`);
      announce();

      ws.on('message', (data, isBinary) => {
        if (role === 'controller') {
          if (isBinary) return broadcast(games, data, true); // input packet, relay untouched
          let msg; try { msg = JSON.parse(data); } catch { return; }
          if (msg.t === 'ping') ws.send(JSON.stringify({ t: 'pong', ts: msg.ts }));
        } else if (!isBinary) {
          let msg; try { msg = JSON.parse(data); } catch { return; }
          if (msg.t === 'haptic' || msg.t === 'state') broadcast(controllers, data.toString(), false);
        }
      });
      ws.on('close', () => {
        controllers.delete(ws); games.delete(ws);
        console.log(`[-] ${who} disconnected`);
        announce();
      });
      ws.on('error', () => {});
    });
  });
  // Drop dead sockets (phone screen off, Wi-Fi roam) so status stays truthful.
  setInterval(() => {
    for (const ws of wss.clients) {
      if (!ws.isAlive) { ws.terminate(); continue; }
      ws.isAlive = false; ws.ping();
    }
  }, 5000).unref();
}

// ---------------------------------------------------------------- main
async function main() {
  const ifaces = localIPv4s();
  const tls = await loadOrCreateCert(ifaces.map((i) => i.address));

  const usable = ifaces.filter((i) => !i.virtual);
  // Controller links (with QR modules) for a game-side scan-to-connect panel. Only
  // served on the localhost game port, so the LAN never sees this list.
  const links = usable.map((i) => {
    const url = `https://${i.address}:${HTTPS_PORT}/controller/`;
    return { label: i.usb ? 'USB cable' : 'Wi-Fi / LAN', adapter: i.name, url, qr: qrModules(url) };
  });

  const phoneServer = https.createServer(
    { key: tls.key, cert: tls.cert },
    serveStatic({ index: '/controller/', dirs: { '/controller/': path.join(ROOT, 'public', 'controller') } })
  );
  // The game port serves no files: only the link list and Grivet's WebSocket.
  const gameServer = http.createServer((req, res) => {
    if (req.url === '/api/controller-links') {
      res.writeHead(200, { 'Content-Type': 'application/json', 'Cache-Control': 'no-store' });
      return res.end(JSON.stringify(links));
    }
    res.writeHead(404); res.end('Not found');
  });
  attachWs(phoneServer, true);
  attachWs(gameServer, false); // localhost, game role only; controllers must use WSS

  const listen = (server, port, host) => new Promise((resolve, reject) => {
    server.once('error', (e) => reject(e.code === 'EADDRINUSE'
      ? new Error(`Port ${port} is already in use. Is PhonePad already running in another window?`) : e));
    server.listen(port, host, resolve);
  });
  await listen(phoneServer, HTTPS_PORT, '0.0.0.0');
  await listen(gameServer, GAME_PORT, '127.0.0.1');

  console.log('\n  PhonePad for Grivet is running');
  console.log(`  Certificate: ${tls.reused ? 'reused' : 'NEW (accept the warning on the phone once)'}`);
  console.log(`  Grivet connects on ws://127.0.0.1:${GAME_PORT}/ws (this PC only).\n`);
  console.log('  Scan a code with the phone camera, accept the certificate once, then tap FPS.\n');
  if (!usable.length) {
    console.log('  No LAN or USB tether interface found. Join Wi-Fi or enable USB tethering, then restart.');
  }
  for (const i of usable) {
    const url = `https://${i.address}:${HTTPS_PORT}/controller/`;
    console.log(`  ${i.usb ? 'USB TETHER' : 'WI-FI/LAN'}  [${i.name}]  ${url}`);
    qrcode.generate(url, { small: true }, (q) => console.log(q.replace(/^/gm, '    ')));
  }
  const skipped = ifaces.filter((i) => i.virtual);
  if (skipped.length) {
    console.log('  Skipped virtual adapters: ' + skipped.map((i) => `${i.name} ${i.address}`).join(', '));
  }
  console.log('  Ctrl+C to stop.\n');
}

main().catch((e) => { console.error(e); process.exit(1); });
