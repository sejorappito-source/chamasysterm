// Offline storage for the Chama app.
//
// Two IndexedDB stores:
//   - "queue": write actions taken while offline, replayed in order
//     once the network is back.
//   - "cache": the last successfully-fetched copy of each list
//     (members, transactions, etc.), so the app still shows something
//     useful with zero signal.
//
// Nothing here talks to the network directly — api.js calls into this
// module, and the actual HTTP retry is driven from there.

const DB_NAME = "chama-offline";
const DB_VERSION = 1;

function openDb() {
  return new Promise((resolve, reject) => {
    const req = indexedDB.open(DB_NAME, DB_VERSION);
    req.onupgradeneeded = () => {
      const db = req.result;
      if (!db.objectStoreNames.contains("queue")) {
        db.createObjectStore("queue", { keyPath: "id" });
      }
      if (!db.objectStoreNames.contains("cache")) {
        db.createObjectStore("cache", { keyPath: "key" });
      }
    };
    req.onsuccess = () => resolve(req.result);
    req.onerror = () => reject(req.error);
  });
}

async function withStore(storeName, mode, fn) {
  const db = await openDb();
  return new Promise((resolve, reject) => {
    const tx = db.transaction(storeName, mode);
    const store = tx.objectStore(storeName);
    const result = fn(store);
    tx.oncomplete = () => resolve(result);
    tx.onerror = () => reject(tx.error);
  });
}

function genId(prefix) {
  return `${prefix}_${Date.now().toString(36)}_${Math.random().toString(36).slice(2, 8)}`;
}

// ---- Queue ----

async function queueAdd(item) {
  const record = { id: genId("q"), createdAt: Date.now(), status: "pending", ...item };
  await withStore("queue", "readwrite", (store) => store.add(record));
  return record;
}

async function queueAll() {
  const db = await openDb();
  return new Promise((resolve, reject) => {
    const tx = db.transaction("queue", "readonly");
    const store = tx.objectStore("queue");
    const req = store.getAll();
    req.onsuccess = () => resolve(req.result.sort((a, b) => a.createdAt - b.createdAt));
    req.onerror = () => reject(req.error);
  });
}

async function queueRemove(id) {
  await withStore("queue", "readwrite", (store) => store.delete(id));
}

async function queueUpdate(id, patch) {
  const db = await openDb();
  return new Promise((resolve, reject) => {
    const tx = db.transaction("queue", "readwrite");
    const store = tx.objectStore("queue");
    const getReq = store.get(id);
    getReq.onsuccess = () => {
      const existing = getReq.result;
      if (!existing) return resolve(null);
      const updated = { ...existing, ...patch };
      store.put(updated);
      resolve(updated);
    };
    getReq.onerror = () => reject(getReq.error);
    tx.oncomplete = () => {};
  });
}

// ---- Cache ----

async function cacheSet(key, value) {
  await withStore("cache", "readwrite", (store) => store.put({ key, value, updatedAt: Date.now() }));
}

async function cacheGet(key) {
  const db = await openDb();
  return new Promise((resolve, reject) => {
    const tx = db.transaction("cache", "readonly");
    const store = tx.objectStore("cache");
    const req = store.get(key);
    req.onsuccess = () => resolve(req.result || null);
    req.onerror = () => reject(req.error);
  });
}

export const offlineStore = {
  genId,
  queueAdd,
  queueAll,
  queueRemove,
  queueUpdate,
  cacheSet,
  cacheGet,
};
