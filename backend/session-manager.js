const { spawn } = require('child_process');
const { v4: uuidv4 } = require('uuid');
const db = require('./db');
const EventEmitter = require('events');

class SessionManager extends EventEmitter {
  constructor() {
    super();
    this.sessions = new Map();
  }

  list() {
    const rows = db.prepare('SELECT * FROM sessions ORDER BY created_at DESC').all();
    return rows.map(r => {
      const live = this.sessions.get(r.id);
      return { ...r, status: live?.status || r.status };
    });
  }

  get(id) {
    const row = db.prepare('SELECT * FROM sessions WHERE id = ?').get(id);
    const live = this.sessions.get(id);
    return { ...row, isLive: !!live, status: live?.status || row?.status || 'idle' };
  }

  create(name, projectDir) {
    const id = uuidv4();
    db.prepare('INSERT INTO sessions (id, name, project_dir, status) VALUES (?, ?, ?, ?)')
      .run(id, name, projectDir || '/home/lanccc', 'idle');
    return { id, name, projectDir };
  }

  async startSession(id) {
    const session = db.prepare('SELECT * FROM sessions WHERE id = ?').get(id);
    if (!session) throw new Error('Session not found');

    const sessionState = {
      claudeSessionId: null,
      status: 'active',
      buffer: [],
      activeProcess: null,
      projectDir: session.project_dir || '/home/lanccc',
      promptCount: 0,
      lastActivity: Date.now()
    };

    this.sessions.set(id, sessionState);
    db.prepare("UPDATE sessions SET status = 'active', updated_at = datetime('now') WHERE id = ?").run(id);
    this._emitEvent(id, { type: 'system', content: 'Session initialized. Ready for commands.' });

    return { id, status: 'active' };
  }

  sendPrompt(id, prompt) {
    const session = this.sessions.get(id);
    if (!session) throw new Error('Session not started. Click play first.');

    if (session.activeProcess) {
      throw new Error('Claude is still processing. Please wait.');
    }

    const msgResult = db.prepare('INSERT INTO messages (session_id, role, content) VALUES (?, ?, ?)')
      .run(id, 'user', prompt);
    this._emitEvent(id, { type: 'user_message', content: prompt, messageId: msgResult.lastInsertRowid });
    this._emitEvent(id, { type: 'status', content: 'processing' });

    session.promptCount++;

    const escapedPrompt = prompt.replace(/'/g, "'\\''");
    let claudeCmd = `cd '${session.projectDir}' && claude -p '${escapedPrompt}' --output-format stream-json --verbose --dangerously-skip-permissions`;

    if (session.claudeSessionId) {
      claudeCmd += ` --resume '${session.claudeSessionId}'`;
    }

    const proc = spawn('su', ['-', 'lanccc', '-c', claudeCmd], {
      env: { ...process.env, HOME: '/home/lanccc' },
      stdio: ['pipe', 'pipe', 'pipe']
    });

    session.activeProcess = proc;
    session.status = 'processing';

    let outputBuffer = '';

    proc.stdout.on('data', (chunk) => {
      outputBuffer += chunk.toString();
      const lines = outputBuffer.split('\n');
      outputBuffer = lines.pop() || '';

      for (const line of lines) {
        if (!line.trim()) continue;
        try {
          const event = JSON.parse(line);
          if (event.type === 'system' && event.subtype === 'init' && event.session_id) {
            session.claudeSessionId = event.session_id;
          }
          this._handleEvent(id, event);
        } catch {
          if (line.trim()) {
            this._emitEvent(id, { type: 'raw', content: line });
          }
        }
      }
      session.lastActivity = Date.now();
    });

    proc.stderr.on('data', (chunk) => {
      const text = chunk.toString().trim();
      if (text && !text.includes('Warning: no stdin')) {
        this._emitEvent(id, { type: 'stderr', content: text });
      }
    });

    proc.on('close', (code) => {
      if (outputBuffer.trim()) {
        try {
          const event = JSON.parse(outputBuffer);
          if (event.type === 'system' && event.subtype === 'init' && event.session_id) {
            session.claudeSessionId = event.session_id;
          }
          this._handleEvent(id, event);
        } catch {
          if (outputBuffer.trim()) {
            this._emitEvent(id, { type: 'raw', content: outputBuffer });
          }
        }
      }

      session.activeProcess = null;
      session.status = 'active';
      db.prepare("UPDATE sessions SET status = 'active', updated_at = datetime('now') WHERE id = ?").run(id);
      this._emitEvent(id, { type: 'status', content: 'ready' });
    });

    proc.on('error', (err) => {
      session.activeProcess = null;
      session.status = 'error';
      db.prepare("UPDATE sessions SET status = 'error', updated_at = datetime('now') WHERE id = ?").run(id);
      this._emitEvent(id, { type: 'error', content: err.message });
    });
  }

  stopSession(id) {
    const session = this.sessions.get(id);
    if (session) {
      if (session.activeProcess) {
        session.activeProcess.kill('SIGTERM');
        setTimeout(() => {
          if (session.activeProcess && !session.activeProcess.killed) {
            session.activeProcess.kill('SIGKILL');
          }
        }, 5000);
      }
    }
    this.sessions.delete(id);
    db.prepare("UPDATE sessions SET status = 'idle', updated_at = datetime('now') WHERE id = ?").run(id);
  }

  deleteSession(id) {
    this.stopSession(id);
    db.prepare('DELETE FROM tool_calls WHERE session_id = ?').run(id);
    db.prepare('DELETE FROM messages WHERE session_id = ?').run(id);
    db.prepare('DELETE FROM sessions WHERE id = ?').run(id);
  }

  _handleEvent(id, event) {
    if (event.type === 'system') {
      if (['hook_started', 'hook_response', 'init'].includes(event.subtype)) return;
      return;
    }

    if (event.type === 'assistant' && event.message) {
      const content = event.message.content || [];
      for (const block of content) {
        if (block.type === 'text') {
          db.prepare('INSERT INTO messages (session_id, role, content) VALUES (?, ?, ?)')
            .run(id, 'assistant', block.text);
          this._emitEvent(id, { type: 'assistant_text', content: block.text });
        } else if (block.type === 'tool_use') {
          const tcResult = db.prepare('INSERT INTO tool_calls (session_id, tool_name, tool_input, status) VALUES (?, ?, ?, ?)')
            .run(id, block.name, JSON.stringify(block.input), 'running');
          this._emitEvent(id, {
            type: 'tool_call',
            toolCallId: tcResult.lastInsertRowid,
            name: block.name,
            input: block.input,
            status: 'running'
          });
        }
      }
    } else if (event.type === 'tool_result' || event.type === 'tool') {
      const lastTc = db.prepare('SELECT id FROM tool_calls WHERE session_id = ? ORDER BY id DESC LIMIT 1').get(id);
      if (lastTc) {
        db.prepare("UPDATE tool_calls SET status = 'done', tool_result = ? WHERE id = ?")
          .run(JSON.stringify(event.content || event.result || ''), lastTc.id);
      }
      this._emitEvent(id, { type: 'tool_result', result: event.content || event.result });
    } else if (event.type === 'result' || event.type === 'rate_limit_event') {
      return;
    }
  }

  _emitEvent(id, event) {
    const payload = { sessionId: id, timestamp: Date.now(), ...event };
    this.emit('event', payload);
    const session = this.sessions.get(id);
    if (session) {
      session.buffer.push(payload);
      if (session.buffer.length > 500) session.buffer.shift();
    }
  }

  getBuffer(id) {
    const session = this.sessions.get(id);
    return session?.buffer || [];
  }

  getHistory(id, limit = 50) {
    const messages = db.prepare('SELECT * FROM messages WHERE session_id = ? ORDER BY created_at DESC LIMIT ?').all(id, limit).reverse();
    const tools = db.prepare('SELECT * FROM tool_calls WHERE session_id = ? ORDER BY created_at DESC LIMIT ?').all(id, limit * 2).reverse();
    return { messages, tools };
  }
}

module.exports = SessionManager;
