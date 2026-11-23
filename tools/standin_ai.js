// A stand-in for a voice app's AI link, for Open NPC's in-game tests. It speaks the same three doors a real app does:
//   GET  /v1/models            one model, "stand-in"
//   GET  /v1/wait              answers {call, words, name} at once without ?since, else when one of them changes (or after ms)
//   POST /v1/chat/completions  answers with the next scripted reply: an act tool call, or "nothing to do"
// The test drives it through GET /control?words=+1&call=1&name=Mila&reply=wait and reads the last question at GET /last.
// Every question is also appended to the log file (one JSON per line).
//   node tools/standin_ai.js [port] [log file]
const http = require('http');
const fs = require('fs');

const port = Number(process.argv[2] || 41799);
const logFile = process.argv[3] || '';
const st = { words: 0, call: false, name: 'Yui', reply: 'nothing', asks: 0, last: null };
const waiters = [];

const send = (res, code, obj) => { const b = Buffer.from(JSON.stringify(obj)); res.writeHead(code, { 'Content-Type': 'application/json', 'Content-Length': b.length }); res.end(b); };
const door = () => ({ call: st.call, words: st.words, ...(st.name ? { name: st.name } : {}) });

function wake() {
  for (const w of waiters.splice(0)) {
    clearTimeout(w.timer);
    send(w.res, 200, door());
  }
}

function reply() {
  if (st.reply === 'nothing') return { role: 'assistant', content: 'nothing to do' };
  return { role: 'assistant', content: null, tool_calls: [{ id: 'c' + st.asks, type: 'function', function: { name: 'act', arguments: JSON.stringify({ action: st.reply, args: {} }) } }] };
}

http.createServer((req, res) => {
  const u = new URL(req.url, 'http://x');
  if (req.method === 'GET' && u.pathname.endsWith('/models')) return send(res, 200, { object: 'list', data: [{ id: 'stand-in', object: 'model' }] });
  if (req.method === 'GET' && u.pathname.endsWith('/wait')) {
    if (!u.searchParams.has('since')) return send(res, 200, door());
    const since = Number(u.searchParams.get('since'));
    const call = u.searchParams.get('call') === '1';
    if (st.words > since || st.call !== call) return send(res, 200, door());
    const ms = Math.min(25000, Number(u.searchParams.get('ms') || 25000));
    const w = { res, timer: setTimeout(() => { const i = waiters.indexOf(w); if (i >= 0) waiters.splice(i, 1); send(res, 200, door()); }, ms) };
    waiters.push(w);
    return;
  }
  if (req.method === 'POST' && u.pathname.endsWith('/chat/completions')) {
    let raw = '';
    req.on('data', (c) => { raw += c; });
    req.on('end', () => {
      st.asks++;
      try { st.last = JSON.parse(raw); } catch { st.last = { unreadable: raw.slice(0, 500) }; }
      if (logFile) fs.appendFileSync(logFile, JSON.stringify(st.last) + '\n');
      const msg = reply();
      console.log(new Date().toTimeString().slice(0, 8), 'question', st.asks, '->', st.reply);
      send(res, 200, { id: 'x', object: 'chat.completion', choices: [{ index: 0, message: msg, finish_reason: msg.tool_calls ? 'tool_calls' : 'stop' }] });
    });
    return;
  }
  if (req.method === 'GET' && u.pathname === '/control') {
    const p = u.searchParams;
    if (p.has('reply')) st.reply = p.get('reply');
    if (p.has('call')) st.call = p.get('call') === '1';
    if (p.has('name')) st.name = p.get('name');
    if (p.has('words')) { const w = p.get('words'); st.words = w.startsWith('+') ? st.words + Number(w.slice(1)) : Number(w); }
    send(res, 200, { ...st, last: undefined });
    wake();
    return;
  }
  if (req.method === 'GET' && u.pathname === '/last') return send(res, 200, { asks: st.asks, last: st.last });
  // (how many door questions are waiting right now: a new name set while one waits is answered at once, as in a real app)
  if (req.method === 'GET' && u.pathname === '/parked') return send(res, 200, { parked: waiters.length });
  send(res, 404, { error: 'not here' });
}).listen(port, '127.0.0.1', () => console.log('stand-in AI on 127.0.0.1:' + port));
