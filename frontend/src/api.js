// Small fetch wrapper for the Chama Erlang backend.
// In the combined deployment the frontend is served by the same cowboy
// process as the API, so a relative "/api/..." base works both in
// production and in `vite dev` if you proxy /api (see vite.config.js).

const BASE = "/api";

async function request(method, path, body) {
  const res = await fetch(`${BASE}${path}`, {
    method,
    headers: body ? { "Content-Type": "application/json" } : undefined,
    body: body ? JSON.stringify(body) : undefined,
  });

  let payload = null;
  try {
    payload = await res.json();
  } catch (e) {
    // no/invalid JSON body - leave payload null
  }

  if (!res.ok) {
    const message = (payload && payload.error) || `Request failed (${res.status})`;
    throw new Error(message);
  }
  return payload;
}

export const api = {
  // Setup / onboarding
  getSetupStatus: () => request("GET", "/setup"),
  onboard: (params) => request("POST", "/setup", params),
  resetSetup: () => request("DELETE", "/setup"),

  // Auth
  signIn: (params) => request("POST", "/auth/signin", params),

  // Regions
  listRegions: () => request("GET", "/regions"),

  // Members
  listMembers: () => request("GET", "/members"),
  addMember: (form) => request("POST", "/members", form),

  // Payments / transactions
  listTransactions: () => request("GET", "/transactions"),
  addPayment: (params) => request("POST", "/payments", params),

  // Funerals
  listFunerals: () => request("GET", "/funerals"),
  recordDeath: (params) => request("POST", "/funerals", params),
  addFuneralExpense: (funeralId, expense) =>
    request("POST", `/funerals/${encodeURIComponent(funeralId)}/expenses`, expense),

  // Audit log
  listAuditLog: () => request("GET", "/audit-log"),
};

// Fetches everything the app's `data` object needs in one go.
export async function loadAllData() {
  const [members, transactions, funerals, auditLog] = await Promise.all([
    api.listMembers(),
    api.listTransactions(),
    api.listFunerals(),
    api.listAuditLog(),
  ]);
  return { members, transactions, funerals, auditLog };
}
