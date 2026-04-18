require('dotenv').config();
const http = require('http');
const { WebSocketServer } = require('ws');
const SessionManager = require('./session-manager');

const PORT = parseInt(process.env.PORT || '3100');
const AUTH_TOKEN = process.env.AUTH_TOKEN;
const sm = new SessionManager();

const server = http.createServer((req, res) => {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET, POST, DELETE, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type, Authorization');
  if (req.method === 'OPTIONS') { res.writeHead(204); res.end(); return; }

  const auth = req.headers.authorization;
  if (auth !== `Bearer ${AUTH_TOKEN}`) {
    res.writeHead(401, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ error: 'Unauthorized' }));
    return;
  }

  const url = new URL(req.url, `http://${req.headers.host}`);
  const path = url.pathname;

  if (path === '/api/sessions' && req.method === 'GET') { json(res, sm.list()); return; }

  if (path === '/api/sessions' && req.method === 'POST') {
    readBody(req, (body) => {
      try {
        const { name, projectDir } = body;
        if (!name) { json(res, { error: 'name required' }, 400); return; }
        json(res, sm.create(name, projectDir), 201);
      } catch (e) { json(res, { error: e.message }, 500); }
    });
    return;
  }

  const sessionMatch = path.match(/^\/api\/sessions\/([a-f0-9-]+)$/);
  if (sessionMatch && req.method === 'GET') {
    const s = sm.get(sessionMatch[1]);
    if (!s?.id) { json(res, { error: 'not found' }, 404); return; }
    json(res, s);
    return;
  }

  const startMatch = path.match(/^\/api\/sessions\/([a-f0-9-]+)\/start$/);
  if (startMatch && req.method === 'POST') {
    try { json(res, sm.startSession(startMatch[1])); }
    catch (e) { json(res, { error: e.message }, 500); }
    return;
  }

  const stopMatch = path.match(/^\/api\/sessions\/([a-f0-9-]+)\/stop$/);
  if (stopMatch && req.method === 'POST') {
    try { sm.stopSession(stopMatch[1]); json(res, { ok: true }); }
    catch (e) { json(res, { error: e.message }, 500); }
    return;
  }

  const deleteMatch = path.match(/^\/api\/sessions\/([a-f0-9-]+)$/);
  if (deleteMatch && req.method === 'DELETE') {
    try { sm.deleteSession(deleteMatch[1]); json(res, { ok: true }); }
    catch (e) { json(res, { error: e.message }, 500); }
    return;
  }

  if (path === '/api/health') {
    json(res, { status: 'ok', uptime: process.uptime(), sessions: sm.list().length });
    return;
  }

  json(res, { error: 'not found' }, 404);
});

const wss = new WebSocketServer({ server });

wss.on('connection', (ws, req) => {
  const url = new URL(req.url, `http://${req.headers.host}`);
  const token = url.searchParams.get('token');
  if (token !== AUTH_TOKEN) { ws.close(4001, 'Unauthorized'); return; }

  console.log('[WS] Client connected');
  let subscribedSession = null;

  const onEvent = (event) => {
    if (subscribedSession && event.sessionId !== subscribedSession) return;
    ws.send(JSON.stringify(event));
  };
  sm.on('event', onEvent);

  ws.on('message', (raw) => {
    try {
      const msg = JSON.parse(raw.toString());
      switch (msg.action) {
        case 'subscribe': {
          subscribedSession = msg.sessionId;
          const buffer = sm.getBuffer(msg.sessionId);
          if (buffer.length > 0) ws.send(JSON.stringify({ type: 'replay', events: buffer }));
          ws.send(JSON.stringify({ type: 'subscribed', sessionId: msg.sessionId }));
          break;
        }
        case 'unsubscribe': { subscribedSession = null; break; }
        case 'prompt': {
          if (!msg.sessionId || !msg.content) {
            ws.send(JSON.stringify({ type: 'error', content: 'sessionId and content required' }));
            break;
          }
          try { sm.sendPrompt(msg.sessionId, msg.content); }
          catch (e) { ws.send(JSON.stringify({ type: 'error', content: e.message })); }
          break;
        }
      }
    } catch (e) {
      ws.send(JSON.stringify({ type: 'error', content: 'Invalid JSON' }));
    }
  });

  ws.on('close', () => { sm.removeListener('event', onEvent); console.log('[WS] Client disconnected'); });
});

server.listen(PORT, '0.0.0.0', () => {
  console.log(`[CCC] Server on port ${PORT}`);
  console.log(`[CCC] Auth: ${AUTH_TOKEN.slice(0, 15)}...`);
});

function json(res, data, code = 200) {
  res.writeHead(code, { 'Content-Type': 'application/json' });
  res.end(JSON.stringify(data));
}
function readBody(req, cb) {
  let body = '';
  req.on('data', c => body += c);
  req.on('end', () => { try { cb(JSON.parse(body)); } catch { cb({}); } });
}
