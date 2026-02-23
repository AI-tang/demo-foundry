-- Sprint 3: Multi-Agent Workflow + Writeback + Audit
-- Idempotent schema additions for audit trail and action tracking.

CREATE TABLE IF NOT EXISTS audit_events (
  event_id    TEXT PRIMARY KEY,
  ts          TIMESTAMP NOT NULL DEFAULT now(),
  actor       TEXT NOT NULL,
  action      TEXT NOT NULL,
  input       JSONB,
  output      JSONB,
  status      TEXT NOT NULL DEFAULT 'success'
);

CREATE TABLE IF NOT EXISTS action_requests (
  request_id      TEXT PRIMARY KEY,
  type            TEXT NOT NULL,
  payload         JSONB,
  approval_status TEXT NOT NULL DEFAULT 'auto-approved',
  created_at      TIMESTAMP NOT NULL DEFAULT now()
);
