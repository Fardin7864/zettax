ALTER TABLE deposit_requests ADD COLUMN receiving_details JSONB, ADD COLUMN verification_reference TEXT, ADD COLUMN verified_at TIMESTAMP(3), ADD COLUMN verified_by UUID REFERENCES admin_users(id);
ALTER TABLE withdrawal_requests ADD COLUMN approved_by UUID REFERENCES admin_users(id), ADD COLUMN processed_by UUID REFERENCES admin_users(id), ADD COLUMN review_started_by UUID REFERENCES admin_users(id);
CREATE TABLE evidence_files (id UUID PRIMARY KEY,owner_id UUID NOT NULL,owner_type TEXT NOT NULL CHECK(owner_type IN ('USER','ADMIN')),purpose TEXT NOT NULL,object_key TEXT NOT NULL UNIQUE,filename TEXT NOT NULL,mime_type TEXT NOT NULL,sha256 TEXT NOT NULL,size_bytes INTEGER NOT NULL CHECK(size_bytes>0),status TEXT NOT NULL DEFAULT 'CLEAN',claimed_by TEXT UNIQUE,created_at TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP);
CREATE INDEX evidence_files_owner_id_created_at_idx ON evidence_files(owner_id,created_at);
CREATE TABLE admin_credentials (id TEXT PRIMARY KEY,admin_id UUID NOT NULL REFERENCES admin_users(id),public_key BYTEA NOT NULL,counter BIGINT NOT NULL DEFAULT 0,device_type TEXT NOT NULL,created_at TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP);
CREATE INDEX admin_credentials_admin_id_idx ON admin_credentials(admin_id);
CREATE TABLE admin_challenges (id UUID PRIMARY KEY,admin_id UUID NOT NULL REFERENCES admin_users(id),kind TEXT NOT NULL,challenge TEXT NOT NULL,expires_at TIMESTAMP(3) NOT NULL,consumed_at TIMESTAMP(3));
CREATE TABLE treasury_statements (id UUID PRIMARY KEY,account_reference TEXT NOT NULL,category TEXT NOT NULL CHECK(category IN ('CUSTOMER','RESERVE')),balance DECIMAL(24,2) NOT NULL CHECK(balance>=0),as_of TIMESTAMP(3) NOT NULL,evidence_id UUID NOT NULL REFERENCES evidence_files(id),submitted_by UUID NOT NULL REFERENCES admin_users(id),reviewed_by UUID REFERENCES admin_users(id),reviewed_at TIMESTAMP(3),status TEXT NOT NULL DEFAULT 'PENDING',notes TEXT NOT NULL,created_at TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,CHECK(reviewed_by IS NULL OR reviewed_by<>submitted_by));
CREATE INDEX treasury_statements_account_reference_as_of_idx ON treasury_statements(account_reference,as_of);
CREATE TABLE release_approvals (id UUID PRIMARY KEY,version TEXT NOT NULL,gate TEXT NOT NULL,approved_by UUID NOT NULL REFERENCES admin_users(id),evidence_reference TEXT NOT NULL,notes TEXT NOT NULL,expires_at TIMESTAMP(3) NOT NULL,created_at TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,revoked_at TIMESTAMP(3));
CREATE INDEX release_approvals_version_gate_idx ON release_approvals(version,gate);
ALTER TABLE deposit_requests ADD CONSTRAINT deposit_independent_review CHECK(verified_by IS NULL OR reviewed_by IS NULL OR verified_by<>reviewed_by);
ALTER TABLE withdrawal_requests ADD CONSTRAINT withdrawal_independent_review CHECK(approved_by IS NULL OR review_started_by IS NULL OR approved_by<>review_started_by);
CREATE TABLE admin_changes (id UUID PRIMARY KEY,kind TEXT NOT NULL,target_id TEXT NOT NULL,payload JSONB NOT NULL,fingerprint TEXT NOT NULL,requested_by UUID NOT NULL REFERENCES admin_users(id),reviewed_by UUID REFERENCES admin_users(id),status TEXT NOT NULL DEFAULT 'PENDING',created_at TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,reviewed_at TIMESTAMP(3),CHECK(reviewed_by IS NULL OR reviewed_by<>requested_by));
CREATE INDEX admin_changes_status_created_at_idx ON admin_changes(status,created_at);

CREATE FUNCTION protect_evidence_claim() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN
 IF (to_jsonb(NEW)-'claimed_by'-'status') IS DISTINCT FROM (to_jsonb(OLD)-'claimed_by'-'status') OR (OLD.claimed_by IS NOT NULL AND NEW.claimed_by IS DISTINCT FROM OLD.claimed_by) THEN RAISE EXCEPTION 'Evidence content and ownership are immutable; claims cannot be reused'; END IF;
 RETURN NEW; END $$;
CREATE TRIGGER evidence_claim_once BEFORE UPDATE ON evidence_files FOR EACH ROW EXECUTE FUNCTION protect_evidence_claim();
CREATE FUNCTION protect_operation_evidence() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN
 IF TG_OP='DELETE' THEN RAISE EXCEPTION 'Operational evidence cannot be deleted'; END IF;
 IF TG_TABLE_NAME='release_approvals' THEN
  IF (to_jsonb(NEW)-'revoked_at') IS DISTINCT FROM (to_jsonb(OLD)-'revoked_at') OR OLD.revoked_at IS NOT NULL THEN RAISE EXCEPTION 'Release evidence is immutable'; END IF;
 ELSE
  IF OLD.status<>'PENDING' OR (to_jsonb(NEW)-'status'-'reviewed_by'-'reviewed_at') IS DISTINCT FROM (to_jsonb(OLD)-'status'-'reviewed_by'-'reviewed_at') THEN RAISE EXCEPTION 'Reviewed operational evidence is immutable'; END IF;
 END IF;
 RETURN NEW; END $$;
CREATE TRIGGER protect_treasury_statement BEFORE UPDATE OR DELETE ON treasury_statements FOR EACH ROW EXECUTE FUNCTION protect_operation_evidence();
CREATE TRIGGER protect_release_approval BEFORE UPDATE OR DELETE ON release_approvals FOR EACH ROW EXECUTE FUNCTION protect_operation_evidence();
CREATE TRIGGER protect_admin_change BEFORE UPDATE OR DELETE ON admin_changes FOR EACH ROW EXECUTE FUNCTION protect_operation_evidence();
ALTER TABLE treasury_statements ADD CHECK(status IN ('PENDING','APPROVED','REJECTED')), ADD CHECK(status='PENDING' OR (reviewed_by IS NOT NULL AND reviewed_at IS NOT NULL));
ALTER TABLE admin_changes ADD CHECK(status IN ('PENDING','APPROVED','REJECTED')), ADD CHECK(status='PENDING' OR (reviewed_by IS NOT NULL AND reviewed_at IS NOT NULL));

-- Define authorities without assigning or fabricating any release sign-off.
INSERT INTO roles(id,name,description) VALUES(gen_random_uuid(),'operations','Independent funding and operational reviewers') ON CONFLICT(name) DO NOTHING;
INSERT INTO permissions(id,key,description)
SELECT gen_random_uuid(),k,k FROM unnest(ARRAY['operations.read','evidence.read','evidence.write','deposit.verify','deposit.read','deposit.approve','withdrawal.read','withdrawal.approve','withdrawal.mark_paid','funding.configure','trading.configure','treasury.read','treasury.submit','treasury.approve','release.read','audit.read','admin.read','changes.review','users.configure','admin.configure','kyc.configure']) AS k ON CONFLICT(key) DO NOTHING;
INSERT INTO role_permissions(role_id,permission_id) SELECT r.id,p.id FROM roles r CROSS JOIN permissions p WHERE r.name='operations' AND p.key=ANY(ARRAY['operations.read','evidence.read','evidence.write','deposit.verify','deposit.read','deposit.approve','withdrawal.read','withdrawal.approve','withdrawal.mark_paid','funding.configure','trading.configure','treasury.read','treasury.submit','treasury.approve','release.read','audit.read','admin.read','changes.review','users.configure','admin.configure','kyc.configure']) ON CONFLICT DO NOTHING;
INSERT INTO roles(id,name,description) SELECT gen_random_uuid(),'release-'||g,'Authorized release signatory: '||g FROM unnest(ARRAY['engineering','security','compliance','legal','custody','payment_provider','reconciliation','operations','treasury','executive','counterparty_risk']) AS g ON CONFLICT(name) DO NOTHING;
INSERT INTO permissions(id,key,description) SELECT gen_random_uuid(),'release.'||g,'Release authority: '||g FROM unnest(ARRAY['engineering','security','compliance','legal','custody','payment_provider','reconciliation','operations','treasury','executive','counterparty_risk']) AS g ON CONFLICT(key) DO NOTHING;
INSERT INTO role_permissions(role_id,permission_id) SELECT r.id,p.id FROM roles r JOIN permissions p ON p.key='release.'||substring(r.name FROM 9) OR p.key IN ('operations.read','evidence.read','evidence.write','release.read','treasury.read') WHERE r.name LIKE 'release-%' ON CONFLICT DO NOTHING;
