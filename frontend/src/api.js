// Chama Funeral & Contribution System — API client
// NOTE: this is still the in-memory MOCK backend used for the in-chat
// preview. It matches the shape your real Erlang backend should expose
// (associationCode-scoped calls) but none of this data persists to a
// server. Swap the function bodies below for real fetch() calls to
// your deployed API when that's ready — see the comments inline.

/* ================================================================
   MOCK BACKEND — in-memory, MULTI-TENANT demo data standing in for a
   real API. Each association is fully isolated under its own account
   code (regions/members/transactions/funerals/audit log all scoped to
   it), so many different chamas can each sign up and use this system
   independently — this is a general app, not a single-association
   deployment. When wiring up to a real server, keep every function
   signature here (associationCode always the first argument) and just
   swap the bodies for fetch calls.
================================================================ */
let uidCounter = 1;
const newId = (prefix) => `${prefix}${Date.now()}-${uidCounter++}`;
const today = () => {
  const d = new Date();
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`;
};
const nowTime = () => {
  const d = new Date();
  return `${String(d.getHours()).padStart(2, "0")}:${String(d.getMinutes()).padStart(2, "0")} UTC`;
};
const daysAgo = (n) => {
  const d = new Date();
  d.setDate(d.getDate() - n);
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`;
};
const upper = (s) => (s || "").toUpperCase();
const toNumber = (v) => (typeof v === "number" ? v : Number(v) || 0);
const toIso = (d) => `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`;

// Finds the Nth occurrence of a weekday in a given month.
// weekday: 0=Sun..6=Sat. nth: 1..4, or -1 for "last".
function nthWeekdayOfMonth(year, monthIndex0, weekday, nth) {
  if (nth === -1) {
    const last = new Date(year, monthIndex0 + 1, 0); // last day of month
    const diff = (last.getDay() - weekday + 7) % 7;
    last.setDate(last.getDate() - diff);
    return toIso(last);
  }
  const first = new Date(year, monthIndex0, 1);
  const diff = (weekday - first.getDay() + 7) % 7;
  const day = 1 + diff + (nth - 1) * 7;
  return toIso(new Date(year, monthIndex0, day));
}

// ---------------------------------------------------------------
// MULTI-TENANT STORE — one entry per registered association, keyed by
// a unique account code generated at sign-up (e.g. "HARAMBEE-42").
// Everything (regions, members, transactions, funerals, audit log) is
// nested inside its own association, so accounts never see each
// other's data.
// ---------------------------------------------------------------
let associations = {}; // code -> association record

function slugify(name) {
  const letters = (name || "").replace(/[^a-zA-Z ]/g, "").trim().toUpperCase();
  const first = letters.split(" ").filter(Boolean)[0] || "CHAMA";
  return first.slice(0, 10);
}

function generateAccountCode(name) {
  const base = slugify(name);
  if (!associations[base]) return base;
  let n = 2;
  while (associations[`${base}-${n}`]) n += 1;
  return `${base}-${n}`;
}

function newAssociationRecord({ code, name, phone, location, chairPasswordPlain, regions }) {
  return {
    code, name, phone: phone || "", location: location || "", chairPasswordPlain,
    regions: (regions || []).map((r) => ({ code: upper(r.code), name: r.name, password: r.password || "" })),
    members: {}, transactions: [], funerals: {}, auditLog: [], projects: {}, schedule: {},
  };
}

function requireAssociation(code) {
  const a = associations[upper(code)];
  if (!a) throw new Error("Association not found.");
  return a;
}

function regionName(assoc, code) {
  const r = assoc.regions.find((r) => r.code === code);
  return r ? r.name : code;
}

function addAudit(assoc, user, action, region) {
  assoc.auditLog.unshift({ user, action, date: today(), time: nowTime(), region });
}

// ---------------------------------------------------------------
// DEMO SEED — one pre-populated association (account code HARAMBEE)
// so the preview has something to explore immediately, alongside
// whatever new accounts you create through "Create an Account".
// Flip DEMO_MODE to false to start with zero associations at all,
// forcing every sign-in through the onboarding flow first.
// ---------------------------------------------------------------
const DEMO_MODE = true;

function seedMember(assoc, { nationalId, fullName, phone, region, dateJoined, joiningFee, monthly, paid }) {
  const id = newId("m");
  assoc.members[id] = {
    id, nationalId, fullName, phone, region, dateJoined,
    joiningFee, monthly, status: "Active", paidThisMonth: !!paid,
  };
  return assoc.members[id];
}
function seedPayment(assoc, member, amount, daysBack, method = "M-Pesa", reference = "MPESA") {
  assoc.transactions.unshift({
    id: newId("t"), date: daysAgo(daysBack), memberId: member.nationalId, memberName: member.fullName,
    region: member.region, type: "Payment", amount, method, recordedBy: "Secretary", status: "Completed", reference,
  });
}
function seedExpense(assoc, region, memberId, memberName, description, amount, daysBack) {
  assoc.transactions.unshift({
    id: newId("t"), date: daysAgo(daysBack), memberId, memberName, region, type: "Expense", amount,
    method: "Cash", recordedBy: "Secretary", status: "Completed", reference: description.toUpperCase(),
  });
}

if (DEMO_MODE) {
  const demo = newAssociationRecord({
    code: "HARAMBEE",
    name: "Harambee Welfare Association",
    phone: "0712 345 678",
    location: "Nairobi, Kenya",
    chairPasswordPlain: "chair2026",
    regions: [
      { code: "NAI", name: "Nairobi", password: "nai2026" },
      { code: "KBU", name: "Kiambu", password: "kbu2026" },
      { code: "MKS", name: "Machakos", password: "mks2026" },
      { code: "MRA", name: "Murang'a", password: "mra2026" },
      { code: "NKR", name: "Nakuru", password: "nkr2026" },
    ],
  });
  associations["HARAMBEE"] = demo;

  const m1 = seedMember(demo, { nationalId: "23841057", fullName: "Wanjiru Kamau", phone: "0722 111 222", region: "NAI", dateJoined: daysAgo(420), joiningFee: 2000, monthly: 500, paid: true });
  const m2 = seedMember(demo, { nationalId: "24915830", fullName: "Otieno Odhiambo", phone: "0733 222 333", region: "NAI", dateJoined: daysAgo(390), joiningFee: 2000, monthly: 500, paid: true });
  const m3 = seedMember(demo, { nationalId: "19284756", fullName: "Grace Njeri", phone: "0711 333 444", region: "NAI", dateJoined: daysAgo(300), joiningFee: 2000, monthly: 500, paid: false });
  const m4 = seedMember(demo, { nationalId: "27364810", fullName: "Peter Mwangi", phone: "0700 444 555", region: "KBU", dateJoined: daysAgo(500), joiningFee: 1500, monthly: 400, paid: true });
  const m5 = seedMember(demo, { nationalId: "21938475", fullName: "Susan Wambui", phone: "0755 555 666", region: "KBU", dateJoined: daysAgo(210), joiningFee: 1500, monthly: 400, paid: false });
  const m6 = seedMember(demo, { nationalId: "26473819", fullName: "James Kiprotich", phone: "0766 666 777", region: "MKS", dateJoined: daysAgo(600), joiningFee: 1800, monthly: 450, paid: true });
  const m7 = seedMember(demo, { nationalId: "22847361", fullName: "Mary Achieng", phone: "0788 777 888", region: "MKS", dateJoined: daysAgo(150), joiningFee: 1800, monthly: 450, paid: false });
  const m8 = seedMember(demo, { nationalId: "25918473", fullName: "David Mutua", phone: "0799 888 999", region: "MRA", dateJoined: daysAgo(280), joiningFee: 1500, monthly: 400, paid: true });
  const m9 = seedMember(demo, { nationalId: "20384756", fullName: "Alice Nyambura", phone: "0710 999 000", region: "NKR", dateJoined: daysAgo(90), joiningFee: 1500, monthly: 400, paid: false });

  seedPayment(demo, m1, 500, 3);
  seedPayment(demo, m2, 500, 5);
  seedPayment(demo, m4, 400, 2);
  seedPayment(demo, m6, 450, 8);
  seedPayment(demo, m8, 400, 12);
  seedPayment(demo, m1, 500, 34, "Cash", "MANUAL");
  seedPayment(demo, m2, 2000, 390, "Cash", "JOIN-FEE");

  const m10 = seedMember(demo, { nationalId: "23001199", fullName: "Samuel Kariuki (dec.)", phone: "0701 234 567", region: "NAI", dateJoined: daysAgo(700), joiningFee: 2000, monthly: 500, paid: true });
  demo.members[m10.id].status = "Deceased";
  const funeralId = newId("f");
  demo.funerals[funeralId] = {
    id: funeralId, memberId: m10.id, memberName: m10.fullName, nationalId: m10.nationalId,
    region: "NAI", dateOfDeath: daysAgo(20), allocated: 30000, used: 12500,
    notes: "Funeral fund case opened by the region secretary.",
    expenses: [
      { id: newId("e"), description: "Coffin and transport", amount: 9500, date: daysAgo(19) },
      { id: newId("e"), description: "Tent and chairs hire", amount: 3000, date: daysAgo(17) },
    ],
  };
  seedExpense(demo, "NAI", m10.nationalId, m10.fullName, "Coffin and transport", 9500, 19);
  seedExpense(demo, "NAI", m10.nationalId, m10.fullName, "Tent and chairs hire", 3000, 17);

  addAudit(demo, "Secretary", `Recorded death of member ${m10.fullName}`, "Nairobi");
  addAudit(demo, "Secretary", "Logged funeral expense — Tent and chairs hire, KES 3,000", "Nairobi");
  addAudit(demo, "Secretary", "Logged funeral expense — Coffin and transport, KES 9,500", "Nairobi");
  addAudit(demo, "Secretary", `Recorded payment of KES 2,000 for ${m2.fullName}`, "Nairobi");
  addAudit(demo, "Secretary", `Recorded payment of KES 500 for ${m1.fullName}`, "Nairobi");
  addAudit(demo, "Secretary", `Recorded payment of KES 400 for ${m8.fullName}`, "Murang'a");
  addAudit(demo, "Secretary", `Recorded payment of KES 450 for ${m6.fullName}`, "Machakos");
  addAudit(demo, "Secretary", `Recorded payment of KES 400 for ${m4.fullName}`, "Kiambu");
  addAudit(demo, "Secretary", `Recorded payment of KES 500 for ${m2.fullName}`, "Nairobi");
  [m1, m2, m3, m4, m5, m6, m7, m8, m9, m10].forEach((m) => {
    addAudit(demo, "Secretary", `Added member ID ${m.nationalId} (${m.fullName})`, regionName(demo, m.region));
  });

  const p1 = newId("p");
  demo.projects[p1] = {
    id: p1, name: "Nairobi borehole", description: "Drilling and equipping a shared borehole to reduce members' water costs and support the region's dry-season contingency plan.",
    budget: 450000, spent: 210000, status: "Ongoing", startDate: daysAgo(150), region: "NAI",
  };
  const p2 = newId("p");
  demo.projects[p2] = {
    id: p2, name: "Group land purchase — Machakos", description: "Pooling member contributions to buy a 2-acre plot as a long-term association asset and future meeting site.",
    budget: 1200000, spent: 1200000, status: "Completed", startDate: daysAgo(400), region: "MKS",
  };
  const p3 = newId("p");
  demo.projects[p3] = {
    id: p3, name: "Emergency transport van", description: "A shared van for member emergencies and funeral logistics across all regions, reducing reliance on hired transport.",
    budget: 900000, spent: 0, status: "Planned", startDate: today(), region: "",
  };
  addAudit(demo, "Chairperson", `Started project "${demo.projects[p1].name}"`, "Nairobi");
  addAudit(demo, "Chairperson", `Started project "${demo.projects[p2].name}"`, "Machakos");
  addAudit(demo, "Chairperson", `Marked project "${demo.projects[p2].name}" as Completed`, "Machakos");

  // Contribution schedule: monthly collection dates, most recently
  // passed one set so the seeded payments (2–12 days ago) fall inside
  // its window, and the seeded non-payers (m3, m5, m7, m9) show as
  // having missed it.
  [80, 50, 20, 1].forEach((n) => {
    const id = newId("s");
    demo.schedule[id] = { id, date: daysAgo(n), label: "Monthly contribution — 1st Sunday", expectedAmount: 500 };
  });
  const futureId = newId("s");
  const future = new Date(); future.setDate(future.getDate() + 29);
  demo.schedule[futureId] = {
    id: futureId, date: toIso(future),
    label: "Monthly contribution — 1st Sunday", expectedAmount: 500,
  };
  addAudit(demo, "Chairperson", "Generated 5 collection dates", "All regions");
}

// ---------------------------------------------------------------
// API — every call is scoped by associationCode (except onboard,
// which creates one, and findAssociation, which looks one up).
// ---------------------------------------------------------------
const delay = (ms = 120) => new Promise((res) => setTimeout(res, ms));

const api = {
  // Directory of every registered association, for the account picker
  // shown at sign-in. Regions aren't included here (kept lightweight) —
  // findAssociation below returns full detail once one is picked.
  listAssociations: async () => {
    await delay();
    return Object.values(associations)
      .map((a) => ({ code: a.code, name: a.name, location: a.location, memberCount: Object.keys(a.members).length }))
      .sort((a, b) => a.name.localeCompare(b.name));
  },

  // Look up an account by its exact code, or by association name
  // (exact match preferred, falling back to a substring match) —
  // this is the "which account am I signing into" step.
  findAssociation: async (query) => {
    await delay();
    const q = (query || "").trim();
    if (!q) throw new Error("Enter your association's name or account code.");
    const byCode = associations[upper(q)];
    if (byCode) return { code: byCode.code, name: byCode.name, regions: byCode.regions.map((r) => ({ ...r })) };
    const all = Object.values(associations);
    const exactName = all.find((a) => a.name.trim().toLowerCase() === q.toLowerCase());
    if (exactName) return { code: exactName.code, name: exactName.name, regions: exactName.regions.map((r) => ({ ...r })) };
    const partial = all.filter((a) => a.name.toLowerCase().includes(q.toLowerCase()));
    if (partial.length === 1) return { code: partial[0].code, name: partial[0].name, regions: partial[0].regions.map((r) => ({ ...r })) };
    if (partial.length > 1) throw new Error("Multiple associations match that name — try entering the account code instead.");
    throw new Error("We couldn't find an association with that name or account code.");
  },

  // Registers a brand-new association. Never blocked by an existing
  // one — every submission creates its own independent account.
  onboard: async ({ name, phone, location, chairPassword, regions }) => {
    await delay();
    if (!name) throw new Error("Association name is required");
    if (!chairPassword) throw new Error("Chairperson password is required");
    if (!regions || regions.length === 0) throw new Error("At least one region is required");
    if (regions.some((r) => !r.password)) throw new Error("Every region needs a secretary password");
    const code = generateAccountCode(name);
    const record = newAssociationRecord({ code, name, phone, location, chairPasswordPlain: chairPassword, regions });
    associations[code] = record;
    return {
      code,
      association: { name: record.name, phone: record.phone, location: record.location },
      regions: record.regions.map((r) => ({ ...r })),
    };
  },

  signIn: async ({ associationCode, role, regionCode, secret }) => {
    await delay();
    const assoc = requireAssociation(associationCode);
    if (role === "Chairperson") {
      if (secret === assoc.chairPasswordPlain) return { role: "Chairperson", regionCode: null, associationCode: assoc.code };
      throw new Error("Incorrect chairperson password");
    }
    if (role === "Secretary") {
      const region = assoc.regions.find((r) => r.code === upper(regionCode));
      if (!region) throw new Error("Unknown region");
      if (secret === region.password) return { role: "Secretary", regionCode: region.code, associationCode: assoc.code };
      throw new Error("Incorrect password for that region");
    }
    throw new Error("role must be Chairperson or Secretary");
  },

  listRegions: async (associationCode) => {
    await delay();
    return requireAssociation(associationCode).regions.map((r) => ({ ...r }));
  },

  addRegion: async (associationCode, { code, name, password }) => {
    await delay();
    const assoc = requireAssociation(associationCode);
    const Code = upper(code);
    if (!name) throw new Error("Region name is required");
    if (!Code) throw new Error("Region code is required");
    if (!password) throw new Error("A secretary password is required");
    if (assoc.regions.find((r) => r.code === Code)) throw new Error("A region with that code already exists");
    const region = { code: Code, name, password };
    assoc.regions.push(region);
    addAudit(assoc, "Chairperson", `Added region ${name} (${Code})`, name);
    return region;
  },

  updateRegion: async (associationCode, code, { code: newCodeRaw, name: newName, password: newPassword }) => {
    await delay();
    const assoc = requireAssociation(associationCode);
    const region = assoc.regions.find((r) => r.code === code);
    if (!region) throw new Error("Region not found");
    const NewName = newName || region.name;
    const NewCode = newCodeRaw ? upper(newCodeRaw) : code;
    if (!NewName) throw new Error("Region name is required");
    if (NewCode !== code && assoc.regions.find((r) => r.code === NewCode)) {
      throw new Error("A region with that code already exists");
    }
    region.name = NewName;
    if (newPassword) region.password = newPassword;
    if (NewCode !== code) {
      region.code = NewCode;
      Object.values(assoc.members).forEach((m) => { if (m.region === code) m.region = NewCode; });
      assoc.transactions.forEach((t) => { if (t.region === code) t.region = NewCode; });
      Object.values(assoc.funerals).forEach((f) => { if (f.region === code) f.region = NewCode; });
    }
    addAudit(assoc, "Chairperson", `Updated region ${code} -> ${NewName} (${NewCode})`, NewName);
    return { ...region };
  },

  deleteRegion: async (associationCode, code) => {
    await delay();
    const assoc = requireAssociation(associationCode);
    const region = assoc.regions.find((r) => r.code === code);
    if (!region) throw new Error("Region not found");
    const hasMembers = Object.values(assoc.members).some((m) => m.region === code);
    if (hasMembers) throw new Error("Cannot delete a region that still has members. Move or remove its members first.");
    assoc.regions = assoc.regions.filter((r) => r.code !== code);
    addAudit(assoc, "Chairperson", `Deleted region ${region.name} (${code})`, region.name);
    return { deleted: true };
  },

  listMembers: async (associationCode) => {
    await delay();
    return Object.values(requireAssociation(associationCode).members)
      .map((m) => ({ ...m }))
      .sort((a, b) => a.fullName.localeCompare(b.fullName));
  },

  addMember: async (associationCode, form) => {
    await delay();
    const assoc = requireAssociation(associationCode);
    const missing = ["nationalId", "fullName", "region"].filter((k) => !form[k]);
    if (missing.length) throw new Error(`Missing required fields: ${missing.join(", ")}`);
    const id = newId("m");
    const member = {
      id, nationalId: form.nationalId, fullName: form.fullName, phone: form.phone || "",
      region: form.region, dateJoined: form.dateJoined || today(),
      joiningFee: toNumber(form.joiningFee), monthly: toNumber(form.monthly),
      status: "Active", paidThisMonth: false,
    };
    assoc.members[id] = member;
    addAudit(assoc, "Secretary", `Added member ID ${member.nationalId} (${member.fullName})`, regionName(assoc, member.region));
    return { ...member };
  },

  listTransactions: async (associationCode) => {
    await delay();
    return requireAssociation(associationCode).transactions.map((t) => ({ ...t }));
  },

  addPayment: async (associationCode, { memberId, amount, reference, method }) => {
    await delay();
    const assoc = requireAssociation(associationCode);
    const member = assoc.members[memberId];
    if (!memberId) throw new Error("memberId is required");
    if (!member) throw new Error("Member not found");
    const Amount = toNumber(amount);
    if (Amount <= 0) throw new Error("amount must be greater than zero");
    member.paidThisMonth = true;
    const tx = {
      id: newId("t"), date: today(), memberId: member.nationalId, memberName: member.fullName,
      region: member.region, type: "Payment", amount: Amount, method: method || "Cash",
      recordedBy: "Secretary", status: "Completed", reference: reference || "MANUAL",
    };
    assoc.transactions.unshift(tx);
    addAudit(assoc, "Secretary", `Recorded payment of KES ${Amount.toLocaleString()} for ${member.fullName}`, regionName(assoc, member.region));
    return { ...tx };
  },

  listFunerals: async (associationCode) => {
    await delay();
    return Object.values(requireAssociation(associationCode).funerals)
      .map((f) => ({ ...f, balance: f.allocated - f.used }))
      .sort((a, b) => (a.dateOfDeath < b.dateOfDeath ? 1 : -1));
  },

  recordDeath: async (associationCode, { memberId, dateOfDeath, allocated, notes }) => {
    await delay();
    const assoc = requireAssociation(associationCode);
    const member = assoc.members[memberId];
    if (!member) throw new Error("Member not found");
    member.status = "Deceased";
    const id = newId("f");
    const funeral = {
      id, memberId: member.id, memberName: member.fullName, nationalId: member.nationalId,
      region: member.region, dateOfDeath: dateOfDeath || today(), allocated: toNumber(allocated),
      used: 0, notes: notes || "", expenses: [],
    };
    assoc.funerals[id] = funeral;
    addAudit(assoc, "Secretary", `Recorded death of member ${member.fullName}`, regionName(assoc, member.region));
    return { ...funeral, balance: funeral.allocated };
  },

  addFuneralExpense: async (associationCode, funeralId, { description, amount }) => {
    await delay();
    const assoc = requireAssociation(associationCode);
    const funeral = assoc.funerals[funeralId];
    if (!funeral) throw new Error("Funeral case not found");
    const Amount = toNumber(amount);
    if (Amount <= 0) throw new Error("amount must be greater than zero");
    const expense = { id: newId("e"), description: description || "", amount: Amount, date: today() };
    funeral.used += Amount;
    funeral.expenses.push(expense);
    assoc.transactions.unshift({
      id: newId("t"), date: today(), memberId: funeral.nationalId, memberName: funeral.memberName,
      region: funeral.region, type: "Expense", amount: Amount, method: "Cash",
      recordedBy: "Secretary", status: "Completed", reference: (description || "").toUpperCase(),
    });
    addAudit(assoc, "Secretary", `Logged funeral expense — ${description}, KES ${Amount.toLocaleString()}`, regionName(assoc, funeral.region));
    return { ...funeral, balance: funeral.allocated - funeral.used };
  },

  listAuditLog: async (associationCode) => {
    await delay();
    return requireAssociation(associationCode).auditLog.map((e) => ({ ...e }));
  },

  // Projects — community/development initiatives the association funds
  // (e.g. a borehole, a shared vehicle, a land purchase), separate from
  // welfare contributions and funeral cases.
  listProjects: async (associationCode) => {
    await delay();
    return Object.values(requireAssociation(associationCode).projects)
      .map((p) => ({ ...p, balance: p.budget - p.spent }))
      .sort((a, b) => (a.startDate < b.startDate ? 1 : -1));
  },

  addProject: async (associationCode, { name, description, budget, status, startDate, region }) => {
    await delay();
    const assoc = requireAssociation(associationCode);
    if (!name) throw new Error("Project name is required");
    if (!description) throw new Error("A short description of what the project is for is required");
    const id = newId("p");
    const project = {
      id, name, description, budget: toNumber(budget), spent: 0,
      status: status || "Planned", startDate: startDate || today(), region: region || "",
    };
    assoc.projects[id] = project;
    addAudit(assoc, "Chairperson", `Started project "${name}"`, region ? regionName(assoc, region) : "All regions");
    return { ...project, balance: project.budget };
  },

  updateProjectStatus: async (associationCode, projectId, status) => {
    await delay();
    const assoc = requireAssociation(associationCode);
    const project = assoc.projects[projectId];
    if (!project) throw new Error("Project not found");
    project.status = status;
    addAudit(assoc, "Chairperson", `Marked project "${project.name}" as ${status}`, project.region ? regionName(assoc, project.region) : "All regions");
    return { ...project, balance: project.budget - project.spent };
  },

  // Contribution schedule — the collection dates members are expected to
  // pay by (e.g. the first Sunday of every month), each with its own
  // expected amount. Once a date passes, this is what "who hasn't
  // contributed" is measured against, instead of a single unreliable flag.
  listSchedule: async (associationCode) => {
    await delay();
    return Object.values(requireAssociation(associationCode).schedule)
      .map((s) => ({ ...s }))
      .sort((a, b) => (a.date < b.date ? -1 : 1));
  },

  addScheduleDate: async (associationCode, { date, label, expectedAmount }) => {
    await delay();
    const assoc = requireAssociation(associationCode);
    if (!date) throw new Error("A collection date is required");
    if (!expectedAmount || toNumber(expectedAmount) <= 0) throw new Error("Expected contribution amount is required");
    const id = newId("s");
    const entry = { id, date, label: label || "", expectedAmount: toNumber(expectedAmount) };
    assoc.schedule[id] = entry;
    addAudit(assoc, "Chairperson", `Added collection date ${date} (expected KES ${entry.expectedAmount.toLocaleString()})`, "All regions");
    return { ...entry };
  },

  updateScheduleDate: async (associationCode, id, { date, label, expectedAmount }) => {
    await delay();
    const assoc = requireAssociation(associationCode);
    const entry = assoc.schedule[id];
    if (!entry) throw new Error("Schedule entry not found");
    if (date) entry.date = date;
    if (label !== undefined) entry.label = label;
    if (expectedAmount) entry.expectedAmount = toNumber(expectedAmount);
    addAudit(assoc, "Chairperson", `Updated collection date ${entry.date}`, "All regions");
    return { ...entry };
  },

  deleteScheduleDate: async (associationCode, id) => {
    await delay();
    const assoc = requireAssociation(associationCode);
    const entry = assoc.schedule[id];
    if (!entry) throw new Error("Schedule entry not found");
    delete assoc.schedule[id];
    addAudit(assoc, "Chairperson", `Removed collection date ${entry.date}`, "All regions");
    return { deleted: true };
  },

  // Generates a full year of dates from a recurring rule, e.g. "the 1st
  // Sunday of every month" — one entry per calendar month, same expected
  // amount throughout. Existing entries are left as-is; new ones are added.
  generateYearSchedule: async (associationCode, { year, weekday, nth, expectedAmount, label }) => {
    await delay();
    const assoc = requireAssociation(associationCode);
    if (!expectedAmount || toNumber(expectedAmount) <= 0) throw new Error("Expected contribution amount is required");
    const created = [];
    for (let m = 0; m < 12; m += 1) {
      const date = nthWeekdayOfMonth(Number(year), m, Number(weekday), Number(nth));
      const id = newId("s");
      const entry = { id, date, label: label || "", expectedAmount: toNumber(expectedAmount) };
      assoc.schedule[id] = entry;
      created.push({ ...entry });
    }
    addAudit(assoc, "Chairperson", `Generated ${created.length} collection dates for ${year}`, "All regions");
    return created;
  },
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

export { api, loadAllData };
