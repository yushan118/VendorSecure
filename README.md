# VendorSecure

Third-party vendor security assessment platform (MIT208 Project 2). Rule-based risk scoring, playbook automation with a
human approval gate, an append-only audit log, and vendor evidence storage.

Stack: Django + Django REST Framework, PostgreSQL, React + Material UI, JWT + TOTP MFA, Celery + Redis, MinIO.

> **Read this first.** The code was written with AI assistance and then checked statically. In the environment where it was
> written, Django, React and Docker could not be installed, so only the pure-Python logic was actually executed
> (`tests/test_scoring.py`, `tests/test_rules.py`: 37 tests, passing). The Django API tests and the frontend have **not been run**.
> Expect to fix small errors on first run. Run everything yourself, read every file, and record real results.

## Layout

```
backend/
  vendorsecure/        settings, urls, celery
  apps/
    accounts/          user model (roles), login, TOTP MFA, permissions, seed_demo, totp_now
    vendors/           Vendor, Assessment, questionnaire controls, queue/detail/portal endpoints
    risk/              engine.py (pure scoring rules), RiskRule, RiskScoreSnapshot, services
    breach/            BreachDisclosure, rules.py (validation gate), endpoints
    playbooks/         logic.py (pure gate rules), executions, approve/override, triggers, Celery task
    evidence/          upload validation, hashing, short-lived links, storage
    audit/             append-only AuditLog, DB trigger, hash chain, read-only view
  tests/               pure tests + Django API tests (map to TC01 to TC10)
frontend/              React + Material UI (sign-in/MFA, queue, detail, vendor portal, audit log)
db/audit_role.sql      optional insert/select-only database role for the audit log
docker-compose.yml     PostgreSQL, Redis, MinIO (development credentials only)
docs/                  UPDATE_YOUR_REPORT.md
```

## First run

Prerequisites: Python 3.11+, Node 18+, Docker (optional: you can use SQLite for a quick start).

```bash
# 1. services (skip if using SQLite)
docker compose up -d db redis minio minio-init

# 2. backend
cd backend
python -m venv .venv
source .venv/bin/activate            # Windows: .venv\Scripts\activate
pip install -r requirements.txt
cp .env.example .env                 # edit if needed; set USE_SQLITE=1 to skip Docker/PostgreSQL

# IMPORTANT: create migrations BEFORE the first migrate (custom user model)
python manage.py makemigrations accounts vendors risk breach playbooks evidence audit
python manage.py migrate
python manage.py seed_demo           # prints passwords and TOTP setup URLs ONCE; copy them
python manage.py runserver           # http://localhost:8000

# 3. frontend (new terminal)
cd frontend
npm install
npm run dev                          # http://localhost:5173
```

Sign in as `s.chen@finorg.example` (analyst) with the printed password. The second step asks for a 6-digit code: add the
printed `otpauth://` URL to an authenticator app, or in development run `python manage.py totp_now s.chen@finorg.example`.

Optional background jobs: `python manage.py run_triggers` does what the hourly Celery task does. With Redis running:
`celery -A vendorsecure worker -l info` and `celery -A vendorsecure beat -l info`.

Optional MinIO storage: set `STORAGE_BACKEND=s3` in `.env` (bucket `evidence` is created by `minio-init`).
`S3_SSE=1` needs MinIO server-side encryption (KMS) configured first.

Do not run `manage.py flush`: the audit log blocks TRUNCATE by design. Drop and recreate the database instead.

## Tests

```bash
cd backend
python -m unittest tests.test_scoring tests.test_rules     # pure tests, no database
python manage.py test                                       # everything (needs the database)
# or: pytest
```

| Test case | Where |
|---|---|
| TC01, TC02 sign-in and MFA | `tests/test_auth_access.py` SignInTests |
| TC03, TC04 access control | `tests/test_auth_access.py` AccessControlTests |
| TC05 scoring boundaries | `tests/test_scoring.py` |
| TC06 unverified breach has no effect | `tests/test_scoring_breach_playbooks.py` BreachAndScoreTests |
| TC07 playbook trace and approval gate | `tests/test_scoring_breach_playbooks.py` PlaybookTests, `tests/test_rules.py` |
| TC08 override needs a reason | `tests/test_scoring_breach_playbooks.py` PlaybookTests |
| TC09 audit log blocks update/delete | `tests/test_audit.py` (PostgreSQL only) |
| TC10 upload rules | `tests/test_evidence_portal.py`, `tests/test_rules.py` |

## What is implemented and what is not

Implemented: JWT sessions (15 min), TOTP MFA for staff roles, role checks on every route, Argon2 hashing, rule-based scoring
with stored breakdown and rule version, vendor questionnaire, evidence upload (type, size and content checks, SHA-256,
5-minute links, integrity check on download), breach reports that stay unverified until an analyst passes a three-condition
gate, two playbooks with an approval gate, approve/override with a required reason, append-only audit log (database trigger
plus hash chain, `manage.py verify_audit_chain`), and the React screens.

Not implemented (be honest about these in your report):
- Playbook actions are **simulated** (written to the trace). No real email or Slack is sent.
- "Needs information" breach reports do **not** auto-close after 5 business days.
- Vendors can report a breach through the API, but the vendor portal has no screen for it.
- No automated breach feed adapter, no malware scan, no password reset or account lockout (only request throttling).
- The frontend holds tokens in memory and does not refresh them: after 15 minutes the user signs in again.
- No Postman collection is included; create one for the routes in Appendix C of your report.

## Security notes

- The Django admin (`/admin/`) is enabled only when `DJANGO_DEBUG=1`, because it signs in with a password only.
- Secrets come from environment variables; `.env` is git-ignored. The Docker credentials are development-only.
- For production-like use run behind HTTPS, set `DJANGO_DEBUG=0` and a long `DJANGO_SECRET_KEY`, and consider
  `db/audit_role.sql` so the application cannot alter audit rows even with direct SQL access.
- Scoring weights and thresholds are initial defaults, not validated values (see `apps/risk/engine.py`).

## Committing honestly

Add the code to Git in stages as you read and run each part (scaffold and accounts, then vendors and risk, then playbooks
and breach, then evidence, then frontend), with commit messages that say what you verified. Do not backdate commits. Your
history should show how the work was actually done.
