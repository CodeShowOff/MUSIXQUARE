-- MUSIXQUARE Developer API uses a dedicated D1 database. Do not merge these
-- tables into the admin metrics database: key revocation and audit retention
-- are a separate security boundary.

CREATE TABLE IF NOT EXISTS mxqr_developer_api_room_generation_tombstones (
  room_code TEXT NOT NULL
    CHECK (length(room_code) = 6 AND room_code GLOB '0[0-9][0-9][0-9][0-9][0-9]'),
  room_generation INTEGER NOT NULL DEFAULT 0 CHECK (room_generation >= 0),
  request_id TEXT NOT NULL,
  decommissioned_at INTEGER NOT NULL CHECK (decommissioned_at >= 0),
  PRIMARY KEY (room_code, room_generation)
);

-- Decommission fences are permanent. Idempotent repair may move the observed
-- deletion time earlier, but it may never rename an incarnation, replace the
-- originating request, postpone its fence, or remove the row.
CREATE TRIGGER IF NOT EXISTS trg_mxqr_developer_api_room_generation_tombstones_monotonic
BEFORE UPDATE ON mxqr_developer_api_room_generation_tombstones
WHEN NEW.room_code <> OLD.room_code
  OR NEW.room_generation <> OLD.room_generation
  OR NEW.request_id <> OLD.request_id
  OR NEW.decommissioned_at > OLD.decommissioned_at
BEGIN
  SELECT RAISE(ABORT, 'developer_api_room_generation_tombstone_immutable');
END;

CREATE TRIGGER IF NOT EXISTS trg_mxqr_developer_api_room_generation_tombstones_no_delete
BEFORE DELETE ON mxqr_developer_api_room_generation_tombstones
BEGIN
  SELECT RAISE(ABORT, 'developer_api_room_generation_tombstone_immutable');
END;

-- Exact-incarnation fence shared by ownership transfer/account deletion and
-- operator key issuance. Keeping the fence in the Developer D1 database makes
-- "fence + revoke" and "issue only when unfenced" serialize atomically.
CREATE TABLE IF NOT EXISTS mxqr_developer_api_room_authority_fences (
  room_code TEXT NOT NULL
    CHECK (length(room_code) = 6 AND room_code GLOB '0[0-9][0-9][0-9][0-9][0-9]'),
  room_generation INTEGER NOT NULL DEFAULT 0 CHECK (room_generation >= 0),
  status TEXT NOT NULL CHECK (status IN ('active', 'cleared')),
  reason TEXT NOT NULL
    CHECK (reason IN ('owner_account_deleted', 'ownership_transfer_pending')),
  fence_digest TEXT NOT NULL
    CHECK (length(fence_digest) = 43 AND fence_digest NOT GLOB '*[^A-Za-z0-9_-]*'),
  fenced_at INTEGER NOT NULL CHECK (fenced_at >= 0),
  updated_at INTEGER NOT NULL CHECK (updated_at >= fenced_at),
  PRIMARY KEY (room_code, room_generation)
);

CREATE INDEX IF NOT EXISTS idx_mxqr_developer_api_room_authority_fences_status
  ON mxqr_developer_api_room_authority_fences (status, room_code, room_generation);

CREATE TABLE IF NOT EXISTS mxqr_developer_api_keys (
  key_id TEXT PRIMARY KEY NOT NULL
    CHECK (length(key_id) = 16 AND key_id NOT GLOB '*[^A-Za-z0-9_-]*'),
  room_code TEXT NOT NULL
    CHECK (length(room_code) = 6 AND room_code GLOB '0[0-9][0-9][0-9][0-9][0-9]'),
  room_generation INTEGER NOT NULL DEFAULT 0 CHECK (room_generation >= 0),
  authority_epoch INTEGER NOT NULL DEFAULT 0 CHECK (authority_epoch >= 0),
  label TEXT NOT NULL CHECK (length(label) BETWEEN 1 AND 64),
  secret_digest TEXT NOT NULL UNIQUE
    CHECK (length(secret_digest) = 43 AND secret_digest NOT GLOB '*[^A-Za-z0-9_-]*'),
  digest_version INTEGER NOT NULL DEFAULT 1 CHECK (digest_version = 1),
  scope_mask INTEGER NOT NULL CHECK (scope_mask BETWEEN 1 AND 255),
  status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'revoked')),
  created_at INTEGER NOT NULL CHECK (created_at >= 0),
  updated_at INTEGER NOT NULL CHECK (updated_at >= created_at),
  expires_at INTEGER NOT NULL CHECK (expires_at > created_at),
  revoked_at INTEGER,
  last_used_hour INTEGER,
  CHECK (
    (status = 'active' AND revoked_at IS NULL) OR
    (status = 'revoked' AND revoked_at IS NOT NULL AND revoked_at >= created_at)
  )
);

CREATE TRIGGER IF NOT EXISTS trg_mxqr_developer_api_keys_incarnation_immutable
BEFORE UPDATE OF room_code, room_generation ON mxqr_developer_api_keys
WHEN NEW.room_code <> OLD.room_code
  OR NEW.room_generation <> OLD.room_generation
BEGIN
  SELECT RAISE(ABORT, 'developer_api_key_incarnation_immutable');
END;

CREATE TRIGGER IF NOT EXISTS trg_mxqr_developer_api_keys_authority_epoch_immutable
BEFORE UPDATE OF authority_epoch ON mxqr_developer_api_keys
WHEN NEW.authority_epoch <> OLD.authority_epoch
BEGIN
  SELECT RAISE(ABORT, 'developer_api_key_authority_epoch_immutable');
END;

CREATE INDEX IF NOT EXISTS idx_mxqr_developer_api_keys_room_status_expiry
  ON mxqr_developer_api_keys (room_code, room_generation, status, expires_at);

-- The scheduled global expiry sweep cannot use the room-prefixed operator
-- index above. Keep its active-and-expired lookup bounded as key volume grows.
CREATE INDEX IF NOT EXISTS idx_mxqr_developer_api_keys_status_expiry
  ON mxqr_developer_api_keys (status, expires_at);

CREATE TRIGGER IF NOT EXISTS trg_mxqr_developer_api_keys_decommissioned_room
BEFORE INSERT ON mxqr_developer_api_keys
WHEN EXISTS (
  SELECT 1 FROM mxqr_developer_api_room_generation_tombstones
  WHERE room_code = NEW.room_code AND room_generation = NEW.room_generation
)
BEGIN
  SELECT RAISE(ABORT, 'PRO_ROOM_DECOMMISSIONED');
END;

CREATE TRIGGER IF NOT EXISTS trg_mxqr_developer_api_keys_authority_fenced_insert
BEFORE INSERT ON mxqr_developer_api_keys
WHEN EXISTS (
  SELECT 1 FROM mxqr_developer_api_room_authority_fences
  WHERE room_code = NEW.room_code
    AND room_generation = NEW.room_generation
    AND status = 'active'
)
BEGIN
  SELECT RAISE(ABORT, 'DEVELOPER_API_AUTHORITY_FENCED');
END;

CREATE TRIGGER IF NOT EXISTS trg_mxqr_developer_api_keys_authority_fenced_update
BEFORE UPDATE OF status ON mxqr_developer_api_keys
WHEN NEW.status = 'active' AND EXISTS (
  SELECT 1 FROM mxqr_developer_api_room_authority_fences
  WHERE room_code = NEW.room_code
    AND room_generation = NEW.room_generation
    AND status = 'active'
)
BEGIN
  SELECT RAISE(ABORT, 'DEVELOPER_API_AUTHORITY_FENCED');
END;

-- Credential fan-out is deliberately bounded. Rotation must
-- revoke an old key before issuing a fourth active key for the same room.
CREATE TRIGGER IF NOT EXISTS trg_mxqr_developer_api_keys_active_insert
BEFORE INSERT ON mxqr_developer_api_keys
WHEN NEW.status = 'active' AND (
  SELECT count(*) FROM mxqr_developer_api_keys
  WHERE room_code = NEW.room_code
    AND room_generation = NEW.room_generation
    AND status = 'active'
) >= 3
BEGIN
  SELECT RAISE(ABORT, 'developer_api_active_key_limit');
END;

CREATE TRIGGER IF NOT EXISTS trg_mxqr_developer_api_keys_active_update
BEFORE UPDATE OF status, room_code, room_generation ON mxqr_developer_api_keys
WHEN NEW.status = 'active'
  AND (
    OLD.status <> 'active'
    OR OLD.room_code <> NEW.room_code
    OR OLD.room_generation <> NEW.room_generation
  )
  AND (
  SELECT count(*) FROM mxqr_developer_api_keys
  WHERE room_code = NEW.room_code
    AND room_generation = NEW.room_generation
    AND status = 'active'
    AND key_id <> NEW.key_id
) >= 3
BEGIN
  SELECT RAISE(ABORT, 'developer_api_active_key_limit');
END;

-- Mutation audit only. Never store raw keys, request bodies, filenames,
-- titles, participant names, PINs, or presigned URLs in this table.
CREATE TABLE IF NOT EXISTS mxqr_developer_api_audit (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  request_id TEXT NOT NULL,
  key_id TEXT NOT NULL,
  room_code TEXT NOT NULL,
  room_generation INTEGER NOT NULL DEFAULT 0 CHECK (room_generation >= 0),
  action TEXT NOT NULL,
  result TEXT NOT NULL,
  status_code INTEGER NOT NULL,
  created_at INTEGER NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_mxqr_developer_api_audit_created_at
  ON mxqr_developer_api_audit (created_at);

CREATE TRIGGER IF NOT EXISTS trg_mxqr_developer_api_audit_decommissioned_room
BEFORE INSERT ON mxqr_developer_api_audit
WHEN EXISTS (
  SELECT 1 FROM mxqr_developer_api_room_generation_tombstones
  WHERE room_code = NEW.room_code AND room_generation = NEW.room_generation
)
BEGIN
  SELECT RAISE(IGNORE);
END;

-- Access-gated operator actions use an HMAC pseudonym in actor_id. Raw Access
-- identity and the one-time full API key are never persisted.
CREATE TABLE IF NOT EXISTS mxqr_developer_api_admin_audit (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  actor_id TEXT NOT NULL,
  action TEXT NOT NULL,
  result TEXT NOT NULL,
  key_id TEXT NOT NULL,
  room_code TEXT NOT NULL,
  room_generation INTEGER NOT NULL DEFAULT 0 CHECK (room_generation >= 0),
  created_at INTEGER NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_mxqr_developer_api_admin_audit_created_at
  ON mxqr_developer_api_admin_audit (created_at);

CREATE TRIGGER IF NOT EXISTS trg_mxqr_developer_api_admin_audit_decommissioned_room
BEFORE INSERT ON mxqr_developer_api_admin_audit
WHEN EXISTS (
  SELECT 1 FROM mxqr_developer_api_room_generation_tombstones
  WHERE room_code = NEW.room_code AND room_generation = NEW.room_generation
)
BEGIN
  SELECT RAISE(IGNORE);
END;

-- A key ID is never reactivated or reused. Keep concurrent idempotent revoke
-- requests from producing more than one operator audit row.
CREATE UNIQUE INDEX IF NOT EXISTS idx_mxqr_developer_api_admin_audit_key_revoke
  ON mxqr_developer_api_admin_audit (key_id, action)
  WHERE action = 'key.revoke';

-- Natural expiry is represented as a revocation at the credential's exact
-- expiry instant. The trigger makes the lifecycle transition and its audit
-- entry one SQLite transaction. The partial unique index plus OR IGNORE keeps
-- an accidental later reactivation/expiry from duplicating the audit record.
CREATE UNIQUE INDEX IF NOT EXISTS idx_mxqr_developer_api_admin_audit_key_expiry
  ON mxqr_developer_api_admin_audit (key_id, action)
  WHERE action = 'key.expire';

CREATE TRIGGER IF NOT EXISTS trg_mxqr_developer_api_keys_natural_expiry_audit
AFTER UPDATE OF status, revoked_at, updated_at ON mxqr_developer_api_keys
WHEN OLD.status = 'active'
  AND NEW.status = 'revoked'
  AND NEW.expires_at = OLD.expires_at
  AND NEW.revoked_at = OLD.expires_at
  AND NEW.updated_at = CASE
    WHEN OLD.updated_at > OLD.expires_at THEN OLD.updated_at
    ELSE OLD.expires_at
  END
BEGIN
  INSERT OR IGNORE INTO mxqr_developer_api_admin_audit
    (actor_id, action, result, key_id, room_code, room_generation, created_at)
  VALUES
    (
      'system:expiry',
      'key.expire',
      'expired',
      NEW.key_id,
      NEW.room_code,
      NEW.room_generation,
      NEW.expires_at
    );
END;


-- --- SQUASHED MIGRATIONS --- --


-- Sourced from: developer-api.effects-scopes.migration.sql

-- Expand the Developer API scope mask for effects:read (64) and
-- effects:control (128). Active credentials that previously held every
-- available scope inherit the two new scopes; narrower and revoked keys keep
-- their original least-privilege mask.

CREATE TABLE mxqr_developer_api_keys_effects_v2 (
  key_id TEXT PRIMARY KEY NOT NULL
    CHECK (length(key_id) = 16 AND key_id NOT GLOB '*[^A-Za-z0-9_-]*'),
  room_code TEXT NOT NULL
    CHECK (length(room_code) = 6 AND room_code GLOB '0[0-9][0-9][0-9][0-9][0-9]'),
  label TEXT NOT NULL CHECK (length(label) BETWEEN 1 AND 64),
  secret_digest TEXT NOT NULL UNIQUE
    CHECK (length(secret_digest) = 43 AND secret_digest NOT GLOB '*[^A-Za-z0-9_-]*'),
  digest_version INTEGER NOT NULL DEFAULT 1 CHECK (digest_version = 1),
  scope_mask INTEGER NOT NULL CHECK (scope_mask BETWEEN 1 AND 255),
  status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'revoked')),
  created_at INTEGER NOT NULL CHECK (created_at >= 0),
  updated_at INTEGER NOT NULL CHECK (updated_at >= created_at),
  expires_at INTEGER NOT NULL CHECK (expires_at > created_at),
  revoked_at INTEGER,
  last_used_hour INTEGER,
  CHECK (
    (status = 'active' AND revoked_at IS NULL) OR
    (status = 'revoked' AND revoked_at IS NOT NULL AND revoked_at >= created_at)
  )
);

INSERT INTO mxqr_developer_api_keys_effects_v2 (
  key_id,
  room_code,
  label,
  secret_digest,
  digest_version,
  scope_mask,
  status,
  created_at,
  updated_at,
  expires_at,
  revoked_at,
  last_used_hour
)
SELECT
  key_id,
  room_code,
  label,
  secret_digest,
  digest_version,
  CASE WHEN status = 'active' AND scope_mask = 63 THEN 255 ELSE scope_mask END,
  status,
  created_at,
  updated_at,
  expires_at,
  revoked_at,
  last_used_hour
FROM mxqr_developer_api_keys;

DROP TRIGGER IF EXISTS trg_mxqr_developer_api_keys_active_insert;
DROP TRIGGER IF EXISTS trg_mxqr_developer_api_keys_active_update;
DROP TRIGGER IF EXISTS trg_mxqr_developer_api_keys_expiry_audit;
DROP TRIGGER IF EXISTS trg_mxqr_developer_api_keys_natural_expiry_audit;
DROP INDEX IF EXISTS idx_mxqr_developer_api_keys_room_status_expiry;
DROP INDEX IF EXISTS idx_mxqr_developer_api_keys_status_expiry;
DROP TABLE mxqr_developer_api_keys;
ALTER TABLE mxqr_developer_api_keys_effects_v2 RENAME TO mxqr_developer_api_keys;

CREATE INDEX idx_mxqr_developer_api_keys_room_status_expiry
  ON mxqr_developer_api_keys (room_code, status, expires_at);

CREATE INDEX idx_mxqr_developer_api_keys_status_expiry
  ON mxqr_developer_api_keys (status, expires_at);

-- Rebuilding mxqr_developer_api_keys drops every trigger attached to the old
-- table. Restore the permanent room-tombstone fence before credentials can be
-- issued against the migrated table.
CREATE TRIGGER trg_mxqr_developer_api_keys_decommissioned_room
BEFORE INSERT ON mxqr_developer_api_keys
WHEN EXISTS (
  SELECT 1 FROM mxqr_developer_api_room_tombstones
  WHERE room_code = NEW.room_code
)
BEGIN
  SELECT RAISE(ABORT, 'PRO_ROOM_DECOMMISSIONED');
END;

CREATE TRIGGER trg_mxqr_developer_api_keys_natural_expiry_audit
AFTER UPDATE OF status, revoked_at, updated_at ON mxqr_developer_api_keys
WHEN OLD.status = 'active'
  AND NEW.status = 'revoked'
  AND NEW.expires_at = OLD.expires_at
  AND NEW.revoked_at = OLD.expires_at
  AND NEW.updated_at = CASE
    WHEN OLD.updated_at > OLD.expires_at THEN OLD.updated_at
    ELSE OLD.expires_at
  END
BEGIN
  INSERT OR IGNORE INTO mxqr_developer_api_admin_audit
    (actor_id, action, result, key_id, room_code, created_at)
  VALUES
    ('system:expiry', 'key.expire', 'expired', NEW.key_id, NEW.room_code, NEW.expires_at);
END;

CREATE TRIGGER trg_mxqr_developer_api_keys_active_insert
BEFORE INSERT ON mxqr_developer_api_keys
WHEN NEW.status = 'active' AND (
  SELECT count(*) FROM mxqr_developer_api_keys
  WHERE room_code = NEW.room_code AND status = 'active'
) >= 3
BEGIN
  SELECT RAISE(ABORT, 'developer_api_active_key_limit');
END;

CREATE TRIGGER trg_mxqr_developer_api_keys_active_update
BEFORE UPDATE OF status, room_code ON mxqr_developer_api_keys
WHEN NEW.status = 'active' AND OLD.status <> 'active' AND (
  SELECT count(*) FROM mxqr_developer_api_keys
  WHERE room_code = NEW.room_code AND status = 'active' AND key_id <> NEW.key_id
) >= 3
BEGIN
  SELECT RAISE(ABORT, 'developer_api_active_key_limit');
END;


-- Sourced from: developer-api-room-generation.migration.sql

-- Forward-only migration: bind every Developer API credential and audit row to
-- one immutable PRO-room incarnation. Existing rows become generation zero.
-- Apply only when PRAGMA table_info(mxqr_developer_api_keys) does not yet
-- contain room_generation; the current baseline already contains this shape.

CREATE TABLE IF NOT EXISTS mxqr_developer_api_room_generation_tombstones (
  room_code TEXT NOT NULL
    CHECK (length(room_code) = 6 AND room_code GLOB '0[0-9][0-9][0-9][0-9][0-9]'),
  room_generation INTEGER NOT NULL DEFAULT 0 CHECK (room_generation >= 0),
  request_id TEXT NOT NULL,
  decommissioned_at INTEGER NOT NULL CHECK (decommissioned_at >= 0),
  PRIMARY KEY (room_code, room_generation)
);

INSERT OR IGNORE INTO mxqr_developer_api_room_generation_tombstones
  (room_code, room_generation, request_id, decommissioned_at)
SELECT room_code, 0, request_id, decommissioned_at
FROM mxqr_developer_api_room_tombstones;

DROP TRIGGER IF EXISTS trg_mxqr_developer_api_room_tombstones_monotonic;
CREATE TRIGGER trg_mxqr_developer_api_room_tombstones_monotonic
BEFORE UPDATE ON mxqr_developer_api_room_tombstones
WHEN NEW.room_code <> OLD.room_code
  OR NEW.request_id <> OLD.request_id
  OR NEW.decommissioned_at > OLD.decommissioned_at
BEGIN
  SELECT RAISE(ABORT, 'developer_api_room_tombstone_immutable');
END;

DROP TRIGGER IF EXISTS trg_mxqr_developer_api_room_tombstones_no_delete;
CREATE TRIGGER trg_mxqr_developer_api_room_tombstones_no_delete
BEFORE DELETE ON mxqr_developer_api_room_tombstones
BEGIN
  SELECT RAISE(ABORT, 'developer_api_room_tombstone_immutable');
END;

DROP TRIGGER IF EXISTS trg_mxqr_developer_api_room_generation_tombstones_monotonic;
CREATE TRIGGER trg_mxqr_developer_api_room_generation_tombstones_monotonic
BEFORE UPDATE ON mxqr_developer_api_room_generation_tombstones
WHEN NEW.room_code <> OLD.room_code
  OR NEW.room_generation <> OLD.room_generation
  OR NEW.request_id <> OLD.request_id
  OR NEW.decommissioned_at > OLD.decommissioned_at
BEGIN
  SELECT RAISE(ABORT, 'developer_api_room_generation_tombstone_immutable');
END;

DROP TRIGGER IF EXISTS trg_mxqr_developer_api_room_generation_tombstones_no_delete;
CREATE TRIGGER trg_mxqr_developer_api_room_generation_tombstones_no_delete
BEFORE DELETE ON mxqr_developer_api_room_generation_tombstones
BEGIN
  SELECT RAISE(ABORT, 'developer_api_room_generation_tombstone_immutable');
END;

ALTER TABLE mxqr_developer_api_keys
  ADD COLUMN room_generation INTEGER NOT NULL DEFAULT 0 CHECK (room_generation >= 0);
ALTER TABLE mxqr_developer_api_audit
  ADD COLUMN room_generation INTEGER NOT NULL DEFAULT 0 CHECK (room_generation >= 0);
ALTER TABLE mxqr_developer_api_admin_audit
  ADD COLUMN room_generation INTEGER NOT NULL DEFAULT 0 CHECK (room_generation >= 0);

DROP TRIGGER IF EXISTS trg_mxqr_developer_api_keys_incarnation_immutable;
CREATE TRIGGER trg_mxqr_developer_api_keys_incarnation_immutable
BEFORE UPDATE OF room_code, room_generation ON mxqr_developer_api_keys
WHEN NEW.room_code <> OLD.room_code
  OR NEW.room_generation <> OLD.room_generation
BEGIN
  SELECT RAISE(ABORT, 'developer_api_key_incarnation_immutable');
END;

DROP INDEX IF EXISTS idx_mxqr_developer_api_keys_room_status_expiry;
CREATE INDEX idx_mxqr_developer_api_keys_room_status_expiry
  ON mxqr_developer_api_keys (room_code, room_generation, status, expires_at);

DROP TRIGGER IF EXISTS trg_mxqr_developer_api_keys_decommissioned_room;
CREATE TRIGGER trg_mxqr_developer_api_keys_decommissioned_room
BEFORE INSERT ON mxqr_developer_api_keys
WHEN EXISTS (
  SELECT 1 FROM mxqr_developer_api_room_generation_tombstones
  WHERE room_code = NEW.room_code AND room_generation = NEW.room_generation
)
OR (
  NEW.room_generation = 0 AND EXISTS (
    SELECT 1 FROM mxqr_developer_api_room_tombstones
    WHERE room_code = NEW.room_code
  )
)
BEGIN
  SELECT RAISE(ABORT, 'PRO_ROOM_DECOMMISSIONED');
END;

DROP TRIGGER IF EXISTS trg_mxqr_developer_api_keys_active_insert;
CREATE TRIGGER trg_mxqr_developer_api_keys_active_insert
BEFORE INSERT ON mxqr_developer_api_keys
WHEN NEW.status = 'active' AND (
  SELECT count(*) FROM mxqr_developer_api_keys
  WHERE room_code = NEW.room_code
    AND room_generation = NEW.room_generation
    AND status = 'active'
) >= 3
BEGIN
  SELECT RAISE(ABORT, 'developer_api_active_key_limit');
END;

DROP TRIGGER IF EXISTS trg_mxqr_developer_api_keys_active_update;
CREATE TRIGGER trg_mxqr_developer_api_keys_active_update
BEFORE UPDATE OF status, room_code, room_generation ON mxqr_developer_api_keys
WHEN NEW.status = 'active'
  AND (
    OLD.status <> 'active'
    OR OLD.room_code <> NEW.room_code
    OR OLD.room_generation <> NEW.room_generation
  )
  AND (
    SELECT count(*) FROM mxqr_developer_api_keys
    WHERE room_code = NEW.room_code
      AND room_generation = NEW.room_generation
      AND status = 'active'
      AND key_id <> NEW.key_id
  ) >= 3
BEGIN
  SELECT RAISE(ABORT, 'developer_api_active_key_limit');
END;

DROP TRIGGER IF EXISTS trg_mxqr_developer_api_audit_decommissioned_room;
CREATE TRIGGER trg_mxqr_developer_api_audit_decommissioned_room
BEFORE INSERT ON mxqr_developer_api_audit
WHEN EXISTS (
  SELECT 1 FROM mxqr_developer_api_room_generation_tombstones
  WHERE room_code = NEW.room_code AND room_generation = NEW.room_generation
)
OR (
  NEW.room_generation = 0 AND EXISTS (
    SELECT 1 FROM mxqr_developer_api_room_tombstones
    WHERE room_code = NEW.room_code
  )
)
BEGIN
  SELECT RAISE(IGNORE);
END;

DROP TRIGGER IF EXISTS trg_mxqr_developer_api_admin_audit_decommissioned_room;
CREATE TRIGGER trg_mxqr_developer_api_admin_audit_decommissioned_room
BEFORE INSERT ON mxqr_developer_api_admin_audit
WHEN EXISTS (
  SELECT 1 FROM mxqr_developer_api_room_generation_tombstones
  WHERE room_code = NEW.room_code AND room_generation = NEW.room_generation
)
OR (
  NEW.room_generation = 0 AND EXISTS (
    SELECT 1 FROM mxqr_developer_api_room_tombstones
    WHERE room_code = NEW.room_code
  )
)
BEGIN
  SELECT RAISE(IGNORE);
END;

DROP TRIGGER IF EXISTS trg_mxqr_developer_api_keys_natural_expiry_audit;
CREATE TRIGGER trg_mxqr_developer_api_keys_natural_expiry_audit
AFTER UPDATE OF status, revoked_at, updated_at ON mxqr_developer_api_keys
WHEN OLD.status = 'active'
  AND NEW.status = 'revoked'
  AND NEW.expires_at = OLD.expires_at
  AND NEW.revoked_at = OLD.expires_at
  AND NEW.updated_at = CASE
    WHEN OLD.updated_at > OLD.expires_at THEN OLD.updated_at
    ELSE OLD.expires_at
  END
BEGIN
  INSERT OR IGNORE INTO mxqr_developer_api_admin_audit
    (actor_id, action, result, key_id, room_code, room_generation, created_at)
  VALUES
    (
      'system:expiry',
      'key.expire',
      'expired',
      NEW.key_id,
      NEW.room_code,
      NEW.room_generation,
      NEW.expires_at
    );
END;


-- Sourced from: developer-api.launch-cleanup.migration.sql

-- Forward-only launch cutover: decommission fences always identify an exact
-- room generation.

DROP TRIGGER IF EXISTS trg_mxqr_developer_api_room_tombstones_monotonic;
DROP TRIGGER IF EXISTS trg_mxqr_developer_api_room_tombstones_no_delete;
DROP TABLE IF EXISTS mxqr_developer_api_room_tombstones;


-- Sourced from: developer-api.authority-fence.migration.sql

-- Forward-only exact-incarnation ownership authority fence. App Worker
-- ownership sagas activate the fence and revoke keys in one D1 batch; key
-- issuance uses the same table as an atomic insertion predicate.
CREATE TABLE mxqr_developer_api_room_authority_fences (
  room_code TEXT NOT NULL
    CHECK (length(room_code) = 6 AND room_code GLOB '0[0-9][0-9][0-9][0-9][0-9]'),
  room_generation INTEGER NOT NULL DEFAULT 0 CHECK (room_generation >= 0),
  status TEXT NOT NULL CHECK (status IN ('active', 'cleared')),
  reason TEXT NOT NULL
    CHECK (reason IN ('owner_account_deleted', 'ownership_transfer_pending')),
  fence_digest TEXT NOT NULL
    CHECK (length(fence_digest) = 43 AND fence_digest NOT GLOB '*[^A-Za-z0-9_-]*'),
  fenced_at INTEGER NOT NULL CHECK (fenced_at >= 0),
  updated_at INTEGER NOT NULL CHECK (updated_at >= fenced_at),
  PRIMARY KEY (room_code, room_generation)
);

CREATE INDEX idx_mxqr_developer_api_room_authority_fences_status
  ON mxqr_developer_api_room_authority_fences (status, room_code, room_generation);

CREATE TRIGGER trg_mxqr_developer_api_keys_authority_fenced_insert
BEFORE INSERT ON mxqr_developer_api_keys
WHEN EXISTS (
  SELECT 1 FROM mxqr_developer_api_room_authority_fences
  WHERE room_code = NEW.room_code
    AND room_generation = NEW.room_generation
    AND status = 'active'
)
BEGIN
  SELECT RAISE(ABORT, 'DEVELOPER_API_AUTHORITY_FENCED');
END;


CREATE TRIGGER trg_mxqr_developer_api_keys_authority_fenced_update
BEFORE UPDATE OF status ON mxqr_developer_api_keys
WHEN NEW.status = 'active' AND EXISTS (
  SELECT 1 FROM mxqr_developer_api_room_authority_fences
  WHERE room_code = NEW.room_code
    AND room_generation = NEW.room_generation
    AND status = 'active'
)
BEGIN
  SELECT RAISE(ABORT, 'DEVELOPER_API_AUTHORITY_FENCED');
END;


-- Sourced from: developer-api.authority-epoch.migration.sql

-- Forward-only key-to-owner-authority incarnation binding. Existing keys are
-- bound to epoch zero; the canonical PRO room rejects them after any owner
-- authority transition that advanced its epoch.
ALTER TABLE mxqr_developer_api_keys
  ADD COLUMN authority_epoch INTEGER NOT NULL DEFAULT 0 CHECK (authority_epoch >= 0);

CREATE TRIGGER trg_mxqr_developer_api_keys_authority_epoch_immutable
BEFORE UPDATE OF authority_epoch ON mxqr_developer_api_keys
WHEN NEW.authority_epoch <> OLD.authority_epoch
BEGIN
  SELECT RAISE(ABORT, 'developer_api_key_authority_epoch_immutable');
END;

