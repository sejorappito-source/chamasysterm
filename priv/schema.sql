-- Chama multi-tenant schema
-- Every domain table carries account_code, scoping all data to one
-- association (tenant). Isolation is enforced in application code by
-- always filtering/joining on account_code — see chama_store.erl.

CREATE TABLE IF NOT EXISTS associations (
    account_code         TEXT PRIMARY KEY,
    name                  TEXT NOT NULL,
    phone                 TEXT NOT NULL DEFAULT '',
    location              TEXT NOT NULL DEFAULT '',
    chair_password_hash  TEXT NOT NULL,
    created_at            TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS regions (
    id            SERIAL PRIMARY KEY,
    account_code TEXT NOT NULL REFERENCES associations(account_code) ON DELETE CASCADE,
    code          TEXT NOT NULL,
    name          TEXT NOT NULL,
    password_hash TEXT NOT NULL,
    UNIQUE (account_code, code)
);

CREATE TABLE IF NOT EXISTS members (
    id               TEXT PRIMARY KEY,
    account_code    TEXT NOT NULL REFERENCES associations(account_code) ON DELETE CASCADE,
    national_id      TEXT NOT NULL,
    full_name        TEXT NOT NULL,
    phone            TEXT NOT NULL DEFAULT '',
    region_code     TEXT NOT NULL,
    date_joined      TEXT NOT NULL,
    joining_fee      NUMERIC NOT NULL DEFAULT 0,
    monthly          NUMERIC NOT NULL DEFAULT 0,
    status           TEXT NOT NULL DEFAULT 'active', -- 'active' | 'deceased'
    paid_this_month BOOLEAN NOT NULL DEFAULT false,
    UNIQUE (account_code, national_id)
);
CREATE INDEX IF NOT EXISTS idx_members_account ON members(account_code);
CREATE INDEX IF NOT EXISTS idx_members_region ON members(account_code, region_code);

CREATE TABLE IF NOT EXISTS transactions (
    id            TEXT PRIMARY KEY,
    account_code TEXT NOT NULL REFERENCES associations(account_code) ON DELETE CASCADE,
    date          TEXT NOT NULL,
    member_id    TEXT NOT NULL,   -- national_id, mirrors old design
    member_name  TEXT NOT NULL,
    region_code TEXT NOT NULL,
    type          TEXT NOT NULL,   -- 'payment' | 'expense'
    amount        NUMERIC NOT NULL,
    method        TEXT NOT NULL DEFAULT 'Cash',
    recorded_by  TEXT NOT NULL DEFAULT '',
    status        TEXT NOT NULL DEFAULT 'Completed',
    reference     TEXT NOT NULL DEFAULT '',
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_tx_account ON transactions(account_code);
CREATE INDEX IF NOT EXISTS idx_tx_region ON transactions(account_code, region_code);

CREATE TABLE IF NOT EXISTS funerals (
    id             TEXT PRIMARY KEY,
    account_code  TEXT NOT NULL REFERENCES associations(account_code) ON DELETE CASCADE,
    member_id     TEXT NOT NULL,
    member_name   TEXT NOT NULL,
    national_id   TEXT NOT NULL,
    region_code  TEXT NOT NULL,
    date_of_death TEXT NOT NULL,
    allocated     NUMERIC NOT NULL DEFAULT 0,
    used          NUMERIC NOT NULL DEFAULT 0,
    notes         TEXT NOT NULL DEFAULT ''
);
CREATE INDEX IF NOT EXISTS idx_funerals_account ON funerals(account_code);

CREATE TABLE IF NOT EXISTS funeral_expenses (
    id          TEXT PRIMARY KEY,
    funeral_id TEXT NOT NULL REFERENCES funerals(id) ON DELETE CASCADE,
    account_code TEXT NOT NULL REFERENCES associations(account_code) ON DELETE CASCADE,
    description TEXT NOT NULL,
    amount      NUMERIC NOT NULL,
    date        TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_funeral_expenses_funeral ON funeral_expenses(funeral_id);

CREATE TABLE IF NOT EXISTS audit_log (
    id            SERIAL PRIMARY KEY,
    account_code TEXT NOT NULL REFERENCES associations(account_code) ON DELETE CASCADE,
    user_role    TEXT NOT NULL,
    action        TEXT NOT NULL,
    date          TEXT NOT NULL,
    time          TEXT NOT NULL,
    region_name  TEXT NOT NULL DEFAULT '',
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_audit_account ON audit_log(account_code, created_at DESC);

CREATE TABLE IF NOT EXISTS projects (
    id            TEXT PRIMARY KEY,
    account_code TEXT NOT NULL REFERENCES associations(account_code) ON DELETE CASCADE,
    name          TEXT NOT NULL,
    description   TEXT NOT NULL DEFAULT '',
    budget        NUMERIC NOT NULL DEFAULT 0,
    spent         NUMERIC NOT NULL DEFAULT 0,
    status        TEXT NOT NULL DEFAULT 'Planned', -- 'Planned' | 'Ongoing' | 'Completed'
    start_date    TEXT NOT NULL,
    region_code  TEXT NOT NULL DEFAULT ''
);
CREATE INDEX IF NOT EXISTS idx_projects_account ON projects(account_code);

CREATE TABLE IF NOT EXISTS schedule (
    id               TEXT PRIMARY KEY,
    account_code    TEXT NOT NULL REFERENCES associations(account_code) ON DELETE CASCADE,
    date             TEXT NOT NULL,
    label            TEXT NOT NULL DEFAULT '',
    expected_amount NUMERIC NOT NULL DEFAULT 0
);
CREATE INDEX IF NOT EXISTS idx_schedule_account ON schedule(account_code, date);
