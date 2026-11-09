-- Optional defence in depth (run once as a PostgreSQL superuser AFTER migrations).
-- Creates a role that can only INSERT and SELECT audit rows. Point the app at this role in production,
-- and run migrations with a separate owner role.
--   psql -U postgres -d vendorsecure -f db/audit_role.sql
CREATE ROLE vendorsecure_app LOGIN PASSWORD 'change-me';
GRANT CONNECT ON DATABASE vendorsecure TO vendorsecure_app;
GRANT USAGE ON SCHEMA public TO vendorsecure_app;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO vendorsecure_app;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO vendorsecure_app;
REVOKE UPDATE, DELETE, TRUNCATE ON audit_log FROM vendorsecure_app;
