// Ape Tag relay server: rooms, tag/horror rules, state + voice relay.
const { WebSocketServer } = require("ws");
const PORT = process.env.PORT || 8080;
const wss = new WebSocketServer({ port: PORT, maxPayload: 16384 });
const rooms = new Map();
const MAX_PLAYERS = 10;
let nextId = 1;

function getRoom(key, mode) {
  if (!rooms.has(key)) {
    rooms.set(key, { mode, players: new Map(), it: 0, caught: new Set(), lastTag: 0, resetting: false });
  }
  return rooms.get(key);
}

function broadcast(room, obj, except) {
  const s = JSON.stringify(obj);
  for (const [id, p] of room.players) {
    if (id !== except && p.ws.readyState === 1) p.ws.send(s);
  }
}

function pickIt(room) {
  const ids = [...room.players.keys()];
  if (room.mode === "sandbox" || ids.length < 2) { room.it = 0; return; }
  room.it = ids[Math.floor(Math.random() * ids.length)];
}

function checkRoundEnd(room) {
  if (room.mode !== "horror" || room.resetting || !room.it) return;
  const alive = [...room.players.keys()].filter((i) => i !== room.it && !room.caught.has(i));
  if (alive.length > 0) return;
  room.resetting = true;
  broadcast(room, { t: "round_end" });
  setTimeout(() => {
    room.caught.clear();
    pickIt(room);
    room.resetting = false;
    broadcast(room, { t: "round_start", it: room.it });
  }, 5000);
}

wss.on("connection", (ws) => {
  let room = null;
  let id = 0;

  ws.on("message", (data, isBinary) => {
    if (isBinary) {
      if (!room || data.length > 4000) return;
      const out = Buffer.alloc(2 + data.length);
      out.writeUInt16LE(id, 0);
      data.copy(out, 2);
      for (const [pid, p] of room.players) {
        if (pid !== id && p.ws.readyState === 1) p.ws.send(out, { binary: true });
      }
      return;
    }
    let m;
    try { m = JSON.parse(data.toString()); } catch { return; }

    if (m.t === "join" && !room) {
      const mode = ["tag", "horror", "sandbox"].includes(m.mode) ? m.mode : "tag";
      const roomName = String(m.room || "public").slice(0, 24);
      const r = getRoom(mode + ":" + roomName, mode);
      if (r.players.size >= MAX_PLAYERS) { ws.close(); return; }
      id = nextId++;
      if (nextId > 65000) nextId = 1;
      room = r;
      const name = String(m.name || "Ape").slice(0, 16);
      room.players.set(id, { ws, name });
      ws.send(JSON.stringify({
        t: "welcome", id, it: room.it, room: roomName,
        players: [...room.players].filter(([i]) => i !== id).map(([i, p]) => ({ id: i, name: p.name })),
      }));
      broadcast(room, { t: "joined", id, name }, id);
      if (!room.it && room.mode !== "sandbox" && room.players.size >= 2) {
        pickIt(room);
        broadcast(room, { t: "it", id: room.it });
      }
    } else if (!room) {
      return;
    } else if (m.t === "s") {
      broadcast(room, { t: "s", id, p: m.p, r: m.r }, id);
    } else if (m.t === "tag") {
      const target = Number(m.id);
      const now = Date.now();
      if (id !== room.it || now - room.lastTag < 1200) return;
      if (!room.players.has(target) || target === id || room.caught.has(target)) return;
      room.lastTag = now;
      if (room.mode === "tag") {
        room.it = target;
        broadcast(room, { t: "it", id: target });
      } else if (room.mode === "horror") {
        room.caught.add(target);
        broadcast(room, { t: "caught", id: target });
        checkRoundEnd(room);
      }
    } else if (m.t === "spawn" && room.mode === "sandbox") {
      broadcast(room, { t: "spawn", k: m.k === "ball" ? "ball" : "block", p: m.p }, id);
    }
  });

  ws.on("close", () => {
    if (!room) return;
    room.players.delete(id);
    room.caught.delete(id);
    broadcast(room, { t: "left", id });
    if (room.players.size === 0) {
      for (const [k, r] of rooms) if (r === room) rooms.delete(k);
      return;
    }
    if (room.it === id) {
      pickIt(room);
      broadcast(room, { t: "it", id: room.it });
    }
    checkRoundEnd(room);
  });
});

console.log("Ape Tag server on port " + PORT);