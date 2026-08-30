# Chama Backend (Erlang/OTP)

A REST API backend for the `chama-system.jsx` welfare-association frontend.
Built on **cowboy** (HTTP) with a single **gen_server** (`chama_store`) holding
all application state in memory, and **jsx** for JSON encode/decode.

It implements the same operations as the React app's local handlers:
`addMember`, `addPayment`, `recordDeath`, `addExpense`, plus the read
endpoints each screen (dashboard, members, transactions, funerals, reports,
audit log) needs.

## Architecture

```
src/
  chama_app.erl        application callback - starts cowboy + supervisor
  chama_sup.erl         top-level supervisor (one child: chama_store)
  chama_store.erl        gen_server: all state + business logic
  chama_view.erl          record -> JSON-map serializers
  chama_auth.erl          password hashing for the chairperson credential
  chama_router.erl        cowboy route table
  chama_http.erl          shared HTTP reply / JSON body helpers
  chama_util.erl           id generation, date/number helpers
  chama_*_handler.erl        one handler per resource (see API below)
include/
  chama.hrl              record definitions (association, region, member,
                          transaction, funeral, funeral_expense, audit_entry)
config/
  sys.config, vm.args    release configuration (HTTP port defaults to 8080)
```

**State is in-memory and single-node**, matching the frontend's own
in-browser demo state — restarting the release clears all data. Swapping
`chama_store`'s internals for a real database (Postgres via `epgsql`/`ecto`
style repo, or Mnesia for a still-BEAM-native option) is a drop-in change
because every other module only talks to `chama_store`'s public API, never
to its internal record shapes.

## Running it

Requires Erlang/OTP 25+ and [rebar3](https://rebar3.org).

```bash
rebar3 shell
# or, for a release:
rebar3 release
_build/default/rel/chama/bin/chama foreground
```

The server listens on `http://localhost:8080` (change `http_port` in
`config/sys.config`).

## Auth model (mirrors the frontend, with real password hashing)

- **Onboarding** (`POST /api/setup`) happens once: it registers the
  association, its regions, and a **chairperson password** (stored as a
  salted SHA-256 hash, see `chama_auth.erl` — swap for bcrypt/argon2 before
  any real deployment).
- **Chairperson** signs in with that password.
- **Secretary** signs in by picking a region and entering that region's
  code as the "secret" — same behavior as the React `SignIn` component.
  This is intentionally simple (matching the prototype); a production
  version should give each secretary their own credential instead of a
  shared, guessable region code.

There's no session/JWT layer yet — `signin` just validates and returns a
`{role, regionCode}` payload the frontend already treats as its session.
Add a token (e.g. `jose`/JWT or a signed cookie) if you need the API to
authenticate *subsequent* requests rather than trusting the client to
re-send `regionCode` in each call.

## API Reference

All bodies/responses are JSON. Errors are `{"error": "message"}` with an
appropriate HTTP status (400/401/404/405/409).

| Method | Path | Purpose |
|---|---|---|
| GET | `/api/setup` | `{setup: bool, association?, regions?}` |
| POST | `/api/setup` | Onboard: `{name, phone, location, chairPassword, regions:[{code,name}]}` |
| POST | `/api/auth/signin` | `{role: "Chairperson"|"Secretary", regionCode, secret}` |
| GET | `/api/regions` | List regions |
| GET | `/api/members?region=&q=` | List members, optional region/search filter |
| POST | `/api/members` | Add member: `{nationalId, fullName, phone, region, dateJoined, joiningFee, monthly}` |
| GET | `/api/members/:member_id` | Fetch one member |
| POST | `/api/payments` | Record a payment: `{memberId, amount, reference, method}` |
| GET | `/api/transactions?region=&type=&method=&q=` | List transactions |
| GET | `/api/funerals?region=` | List funeral cases |
| POST | `/api/funerals` | Record a death, opens a case: `{memberId, dateOfDeath, allocated, notes}` |
| GET | `/api/funerals/:funeral_id` | Fetch one case |
| POST | `/api/funerals/:funeral_id/expenses` | Log an expense: `{description, amount}` |
| GET | `/api/audit-log` | List audit log entries, newest first |
| GET | `/api/reports/dashboard?region=` | Secretary dashboard stats for a region |
| GET | `/api/reports/region/:region_code` | Same, region in the path |
| GET | `/api/reports/financial` | Association-wide collected/spent/net, by region |
| GET | `/api/reports/funerals` | Association-wide funeral fund summary |

### Example

```bash
curl -X POST localhost:8080/api/setup -H 'content-type: application/json' -d '{
  "name": "Harambee Welfare Association",
  "phone": "0700111222",
  "location": "Nairobi",
  "chairPassword": "s3cret",
  "regions": [{"code":"NRB","name":"Nairobi"},{"code":"MSA","name":"Mombasa"}]
}'

curl -X POST localhost:8080/api/auth/signin -H 'content-type: application/json' \
  -d '{"role":"Secretary","regionCode":"NRB","secret":"NRB"}'

curl -X POST localhost:8080/api/members -H 'content-type: application/json' -d '{
  "nationalId":"32011245","fullName":"Grace Wanjiru","phone":"0712345671",
  "region":"NRB","dateJoined":"2026-01-15","joiningFee":2000,"monthly":500
}'
```

## Not included (out of scope for this pass)

- Persistence beyond process memory (add Mnesia/Postgres behind `chama_store`'s API)
- Authenticated sessions for subsequent requests (currently trust-the-client, like the frontend)
- Rate limiting / CORS headers (add `cowboy_cors` or a custom middleware if the React app is served from a different origin)
