// Chama Funeral & Contribution System — API client
// Talks to the real Erlang/Postgres backend deployed on Render. Every
// function here keeps the exact same name and argument shape as the
// old in-memory mock, so App.jsx needed zero changes to switch over.
//
// Offline behaviour: writes (add member, record payment, record death,
// log funeral expense) are queued locally and retried automatically
// when the network is back, using a client-generated id so retries
// can never create duplicates. Reads fall back to the last-cached
// copy when the network is unreachable.

import { offlineStore } from "./offline";

// Change this if the backend ever moves to a different URL.
const API_BASE = "https://chamasysterm.onrender.com";

async function apiFetch(path, { method = "GET", accountCode, body } = {}) {
  const headers = { "Content-Type": "application/json" };
  if (accountCode) headers["X-Account-Code"] = accountCode;

  let res;
  try {
    res = await fetch(`${API_BASE}${path}`, {
      method,
      headers,
      body: body !== undefined ? JSON.stringify(body) : undefined,
    });
  } catch (e) {
    const err = new Error("Could not reach the server. Check your connection and try again.");
    err.isNetworkError = true;
    throw err;
  }

  let data = null;
  try {
    data = await res.json();
  } catch (e) {
    // empty or non-JSON body — leave data as null
  }

  if (!res.ok) {
    const message = (data && data.error) || `Request failed (${res.status})`;
    const err = new Error(message);
    err.status = res.status;
    throw err;
  }
  return data;
}

// Runs a write immediately if possible. If the network is unreachable,
// queues it (using the id already embedded in `body`) and returns an
// optimistic result instead of throwing, so the UI can carry on.
async function sendOrQueue(kind, path, method, accountCode, body) {
  try {
    return await apiFetch(path, { method, accountCode, body });
  } catch (e) {
    if (!e.isNetworkError) throw e; // a real validation/server error — don't queue, surface it
    await offlineStore.queueAdd({ kind, path, method, accountCode, body });
    return { ...body, queued: true };
  }
}

// Runs a read and caches the result. If the network is unreachable,
// serves the last cached copy instead of failing outright.
async function fetchOrCached(cacheKey, fetcher) {
  try {
    const data = await fetcher();
    await offlineStore.cacheSet(cacheKey, data);
    return data;
  } catch (e) {
    if (!e.isNetworkError) throw e;
    const cached = await offlineStore.cacheGet(cacheKey);
    if (cached) return cached.value;
    throw e;
  }
}

// Replays every queued write in order, oldest first. Stops as soon as
// it hits a network error again (rest stay queued for next time), but
// keeps going past a genuine server-rejected item so one bad entry
// doesn't block everything behind it — that item is left in the queue
// marked "failed" for the user to review.
async function drainQueue() {
  const items = await offlineStore.queueAll();
  const results = { synced: 0, failed: 0, remaining: 0 };
  for (const item of items) {
    try {
      await apiFetch(item.path, { method: item.method, accountCode: item.accountCode, body: item.body });
      await offlineStore.queueRemove(item.id);
      results.synced += 1;
    } catch (e) {
      if (e.isNetworkError) {
        results.remaining = items.length - results.synced - results.failed;
        break; // still offline — leave the rest queued, try again later
      }
      await offlineStore.queueUpdate(item.id, { status: "failed", lastError: e.message });
      results.failed += 1;
    }
  }
  return results;
}

let syncTimer = null;
function startAutoSync() {
  if (syncTimer) return; // already running
  const trySync = () => { drainQueue().catch(() => {}); };
  window.addEventListener("online", trySync);
  syncTimer = setInterval(trySync, 30000);
  trySync(); // attempt once immediately in case items are already queued
}

async function getPendingSyncCount() {
  const items = await offlineStore.queueAll();
  return items.filter((i) => i.status === "pending").length;
}


const api = {
  // Directory of every registered association, for the account picker
  // shown at sign-in.
  listAssociations: async () => {
    const list = await apiFetch("/api/associations");
    return list.map((a) => ({ code: a.accountCode, name: a.name, location: a.location }));
  },

  // Look up an account by its exact code, or by association name
  // (exact match preferred, falling back to a substring match).
  findAssociation: async (query) => {
    const q = (query || "").trim();
    if (!q) throw new Error("Enter your association's name or account code.");

    try {
      const assoc = await apiFetch(`/api/associations/${encodeURIComponent(q.toUpperCase())}`);
      return { code: assoc.accountCode, name: assoc.name, regions: assoc.regions };
    } catch (e) {
      if (e.isNetworkError) throw new Error("Could not reach the server to sign you in. Check your connection and try again.");
      if (e.status && e.status !== 404) throw e;
      // not a valid code — fall through to a name search below
    }

    const all = await api.listAssociations();
    const exactName = all.find((a) => a.name.trim().toLowerCase() === q.toLowerCase());
    if (exactName) return api.findAssociation(exactName.code);
    const partial = all.filter((a) => a.name.toLowerCase().includes(q.toLowerCase()));
    if (partial.length === 1) return api.findAssociation(partial[0].code);
    if (partial.length > 1) throw new Error("Multiple associations match that name — try entering the account code instead.");
    throw new Error("We couldn't find an association with that name or account code.");
  },

  // Registers a brand-new association. Never blocked by an existing
  // one — every submission creates its own independent account.
  onboard: async ({ name, phone, location, chairPassword, regions }) => {
    const result = await apiFetch("/api/setup", {
      method: "POST",
      body: { name, phone, location, chairPassword, regions },
    });
    return { code: result.accountCode, association: result.association, regions: result.regions };
  },

  signIn: async ({ associationCode, role, regionCode, secret }) => {
    const result = await apiFetch("/api/auth/signin", {
      method: "POST",
      body: { accountCode: associationCode, role, regionCode, secret },
    });
    return { role: result.role, regionCode: result.regionCode, associationCode: result.accountCode };
  },

  listRegions: async (associationCode) =>
    apiFetch("/api/regions", { accountCode: associationCode }),

  addRegion: async (associationCode, { code, name, password }) =>
    apiFetch("/api/regions", { method: "POST", accountCode: associationCode, body: { code, name, password } }),

  updateRegion: async (associationCode, code, { code: newCodeRaw, name: newName, password: newPassword }) =>
    apiFetch(`/api/regions/${encodeURIComponent(code)}`, {
      method: "PUT",
      accountCode: associationCode,
      body: { code: newCodeRaw, name: newName, password: newPassword },
    }),

  deleteRegion: async (associationCode, code) =>
    apiFetch(`/api/regions/${encodeURIComponent(code)}`, { method: "DELETE", accountCode: associationCode }),

  listMembers: async (associationCode) =>
    fetchOrCached(`${associationCode}:members`, () => apiFetch("/api/members", { accountCode: associationCode })),

  addMember: async (associationCode, form) =>
    sendOrQueue(
      "addMember",
      "/api/members",
      "POST",
      associationCode,
      { ...form, id: form.id || offlineStore.genId("m") }
    ),

  listTransactions: async (associationCode) =>
    fetchOrCached(`${associationCode}:transactions`, () => apiFetch("/api/transactions", { accountCode: associationCode })),

  addPayment: async (associationCode, { memberId, amount, reference, method }) =>
    sendOrQueue(
      "addPayment",
      "/api/payments",
      "POST",
      associationCode,
      { id: offlineStore.genId("t"), memberId, amount, reference, method }
    ),

  listFunerals: async (associationCode) =>
    fetchOrCached(`${associationCode}:funerals`, () => apiFetch("/api/funerals", { accountCode: associationCode })),

  recordDeath: async (associationCode, { memberId, dateOfDeath, allocated, notes }) =>
    sendOrQueue(
      "recordDeath",
      "/api/funerals",
      "POST",
      associationCode,
      { id: offlineStore.genId("f"), memberId, dateOfDeath, allocated, notes }
    ),

  addFuneralExpense: async (associationCode, funeralId, { description, amount }) =>
    sendOrQueue(
      "addFuneralExpense",
      `/api/funerals/${encodeURIComponent(funeralId)}/expenses`,
      "POST",
      associationCode,
      { id: offlineStore.genId("e"), description, amount }
    ),

  listAuditLog: async (associationCode) =>
    fetchOrCached(`${associationCode}:auditLog`, () => apiFetch("/api/audit-log", { accountCode: associationCode })),

  // Projects — community/development initiatives the association funds.
  listProjects: async (associationCode) =>
    fetchOrCached(`${associationCode}:projects`, () => apiFetch("/api/projects", { accountCode: associationCode })),

  addProject: async (associationCode, { name, description, budget, status, startDate, region }) =>
    apiFetch("/api/projects", {
      method: "POST",
      accountCode: associationCode,
      body: { name, description, budget, status, startDate, region },
    }),

  updateProjectStatus: async (associationCode, projectId, status) =>
    apiFetch(`/api/projects/${encodeURIComponent(projectId)}/status`, {
      method: "PUT",
      accountCode: associationCode,
      body: { status },
    }),

  // Contribution schedule — collection dates members are expected to
  // pay by, each with its own expected amount.
  listSchedule: async (associationCode) =>
    fetchOrCached(`${associationCode}:schedule`, () => apiFetch("/api/schedule", { accountCode: associationCode })),

  addScheduleDate: async (associationCode, { date, label, expectedAmount }) =>
    apiFetch("/api/schedule", {
      method: "POST",
      accountCode: associationCode,
      body: { date, label, expectedAmount },
    }),

  updateScheduleDate: async (associationCode, id, { date, label, expectedAmount }) =>
    apiFetch(`/api/schedule/${encodeURIComponent(id)}`, {
      method: "PUT",
      accountCode: associationCode,
      body: { date, label, expectedAmount },
    }),

  deleteScheduleDate: async (associationCode, id) =>
    apiFetch(`/api/schedule/${encodeURIComponent(id)}`, { method: "DELETE", accountCode: associationCode }),

  // Generates a full year of dates from a recurring rule, e.g. "the 1st
  // Sunday of every month".
  generateYearSchedule: async (associationCode, { year, weekday, nth, expectedAmount, label }) =>
    apiFetch("/api/schedule/generate-year", {
      method: "POST",
      accountCode: associationCode,
      body: { year, weekday, nth, expectedAmount, label },
    }),
};

async function loadAllData(associationCode) {
  const [members, transactions, funerals, auditLog, projects, schedule] = await Promise.all([
    api.listMembers(associationCode),
    api.listTransactions(associationCode),
    api.listFunerals(associationCode),
    api.listAuditLog(associationCode),
    api.listProjects(associationCode),
    api.listSchedule(associationCode),
  ]);
  return { members, transactions, funerals, auditLog, projects, schedule };
}

export { api, loadAllData, startAutoSync, drainQueue as syncNow, getPendingSyncCount };
