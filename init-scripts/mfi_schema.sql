-- ============================================================================
-- MFI Banking System - Database Schema
-- Version: 1.0
-- Database: PostgreSQL 14+
-- Created: February 17, 2026
-- ============================================================================

-- ============================================================================
-- EXTENSIONS
-- ============================================================================

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- ============================================================================
-- REFERENCE TABLES (Create First)
-- ============================================================================

-- ----------------------------------------------------------------------------
-- Table: activity_type
-- Description: List of activities across portals
-- ----------------------------------------------------------------------------
CREATE TABLE activity_type (
    id SERIAL PRIMARY KEY,
    name TEXT NOT NULL UNIQUE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

COMMENT ON TABLE activity_type IS 'List of activity types across portals';
COMMENT ON COLUMN activity_type.id IS 'Activity type ID';
COMMENT ON COLUMN activity_type.name IS 'Activity type name';

-- ----------------------------------------------------------------------------
-- Table: mfi_country
-- Description: Country list for MFI locations
-- ----------------------------------------------------------------------------
CREATE TABLE mfi_country (
    id SERIAL PRIMARY KEY,
    name TEXT NOT NULL UNIQUE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

COMMENT ON TABLE mfi_country IS 'Country list for MFI locations';
COMMENT ON COLUMN mfi_country.id IS 'Country ID';
COMMENT ON COLUMN mfi_country.name IS 'Country name';

-- ----------------------------------------------------------------------------
-- Table: mfi_type
-- Description: MFI type classification (MFI, NDFI, etc.)
-- ----------------------------------------------------------------------------
CREATE TABLE mfi_type (
    id SERIAL PRIMARY KEY,
    name TEXT NOT NULL UNIQUE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

COMMENT ON TABLE mfi_type IS 'MFI type classification (e.g., MFI, NDFI, etc.)';
COMMENT ON COLUMN mfi_type.id IS 'Type ID';
COMMENT ON COLUMN mfi_type.name IS 'Type name';

-- ----------------------------------------------------------------------------
-- Table: platform_type
-- Description: Type of digital platform (mobile app, web app, etc.)
-- ----------------------------------------------------------------------------
CREATE TABLE platform_type (
    id SERIAL PRIMARY KEY,
    name TEXT NOT NULL UNIQUE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

COMMENT ON TABLE platform_type IS 'Type of digital platform (mobile app, web app, etc.)';
COMMENT ON COLUMN platform_type.id IS 'Platform type ID';
COMMENT ON COLUMN platform_type.name IS 'Platform type name';

-- ============================================================================
-- PORTALS MODULE
-- ============================================================================

-- ----------------------------------------------------------------------------
-- Table: portals
-- Description: List of active management portals
-- ----------------------------------------------------------------------------
CREATE TABLE portals (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name TEXT NOT NULL,
    description TEXT,
    realm_id TEXT NOT NULL,
    client_id TEXT NOT NULL,
    dev_url TEXT,
    uat_url TEXT,
    prod_url TEXT,
    on_prod BOOLEAN DEFAULT FALSE,
    is_active BOOLEAN DEFAULT FALSE,
    created_on TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

COMMENT ON TABLE portals IS 'List of active management portals';
COMMENT ON COLUMN portals.id IS 'Globally unique identifier';
COMMENT ON COLUMN portals.realm_id IS 'Name of the realm (hardcoded in app.env)';
COMMENT ON COLUMN portals.client_id IS 'Name of the client in realm';

CREATE INDEX idx_portals_realm_id ON portals(realm_id);
CREATE INDEX idx_portals_is_active ON portals(is_active);

-- ----------------------------------------------------------------------------
-- Table: portal_groups
-- Description: List of groups created in Keycloak (IAM)
-- CRITICAL: Groups MUST be created in Keycloak first, then synced to this table
-- ----------------------------------------------------------------------------
CREATE TABLE portal_groups (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    iam_group_id UUID NOT NULL UNIQUE,
    name TEXT NOT NULL,
    description TEXT,
    group_path TEXT NOT NULL,
    parent_iam_group_id UUID,
    created_on TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

COMMENT ON TABLE portal_groups IS 'List of groups created in Keycloak (IAM)';
COMMENT ON COLUMN portal_groups.iam_group_id IS 'Group ID fetched from IAM (Keycloak)';
COMMENT ON COLUMN portal_groups.group_path IS 'Group path fetched from IAM';

CREATE INDEX idx_portal_groups_iam_group_id ON portal_groups(iam_group_id);
CREATE INDEX idx_portal_groups_name ON portal_groups(name);

-- ----------------------------------------------------------------------------
-- Table: portal_users
-- Description: All portal users (except MFI-specific users)
-- ----------------------------------------------------------------------------
CREATE TABLE portal_users (
    id SERIAL PRIMARY KEY,
    id_iam UUID NOT NULL UNIQUE,
    username TEXT NOT NULL,
    fname TEXT NOT NULL,
    lname TEXT,
    email TEXT NOT NULL,
    temp_lock BOOLEAN DEFAULT FALSE,
    email_verified BOOLEAN DEFAULT FALSE,
    profile_img_url TEXT,
    last_password_changed TIMESTAMP,
    last_login_at TIMESTAMP,
    id_group UUID NOT NULL,
    created_on TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    created_by UUID,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_by UUID,
    
    CONSTRAINT fk_portal_users_group FOREIGN KEY (id_group) 
        REFERENCES portal_groups(iam_group_id) ON DELETE RESTRICT,
    CONSTRAINT fk_portal_users_created_by FOREIGN KEY (created_by) 
        REFERENCES portal_users(id_iam) ON DELETE SET NULL,
    CONSTRAINT fk_portal_users_updated_by FOREIGN KEY (updated_by) 
        REFERENCES portal_users(id_iam) ON DELETE SET NULL
);

COMMENT ON TABLE portal_users IS 'All portal users (except MFI-specific users)';
COMMENT ON COLUMN portal_users.id_iam IS 'User ID received from IAM (Keycloak)';
COMMENT ON COLUMN portal_users.id_group IS 'Group ID (must be set in IAM also)';

CREATE INDEX idx_portal_users_id_iam ON portal_users(id_iam);
CREATE INDEX idx_portal_users_email ON portal_users(email);
CREATE INDEX idx_portal_users_id_group ON portal_users(id_group);
CREATE INDEX idx_portal_users_temp_lock ON portal_users(temp_lock);

-- ----------------------------------------------------------------------------
-- Table: user_groups
-- Description: Mapping of users with groups for portal access
-- ----------------------------------------------------------------------------
CREATE TABLE user_groups (
    id SERIAL PRIMARY KEY,
    user_id UUID NOT NULL,
    group_id UUID NOT NULL,
    assigned_by UUID,
    assigned_on TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    
    CONSTRAINT fk_user_groups_user FOREIGN KEY (user_id) 
        REFERENCES portal_users(id_iam) ON DELETE CASCADE,
    CONSTRAINT fk_user_groups_group FOREIGN KEY (group_id) 
        REFERENCES portal_groups(iam_group_id) ON DELETE CASCADE,
    CONSTRAINT fk_user_groups_assigned_by FOREIGN KEY (assigned_by) 
        REFERENCES portal_users(id_iam) ON DELETE SET NULL,
    CONSTRAINT uk_user_groups UNIQUE (user_id, group_id)
);

COMMENT ON TABLE user_groups IS 'Mapping of users with groups for portal access';
COMMENT ON COLUMN user_groups.assigned_by IS 'Reference to portal_users who assigned the group';

CREATE INDEX idx_user_groups_user_id ON user_groups(user_id);
CREATE INDEX idx_user_groups_group_id ON user_groups(group_id);

-- ============================================================================
-- MFIs MODULE
-- ============================================================================

-- ----------------------------------------------------------------------------
-- Table: mfi_clients
-- Description: MFI client information
-- ----------------------------------------------------------------------------
CREATE TABLE mfi_clients (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL,
    schema TEXT NOT NULL,
    realm_id UUID NOT NULL,
    client_id UUID NOT NULL,
    id_country INTEGER,
    location TEXT,
    address TEXT,
    expected_clients BIGINT,
    branches INTEGER,
    id_type INTEGER,
    logo_url TEXT,
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    created_by UUID,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_by UUID,
    
    CONSTRAINT fk_mfi_clients_country FOREIGN KEY (id_country) 
        REFERENCES mfi_country(id) ON DELETE SET NULL,
    CONSTRAINT fk_mfi_clients_type FOREIGN KEY (id_type) 
        REFERENCES mfi_type(id) ON DELETE SET NULL,
    CONSTRAINT fk_mfi_clients_created_by FOREIGN KEY (created_by) 
        REFERENCES portal_users(id_iam) ON DELETE SET NULL,
    CONSTRAINT fk_mfi_clients_updated_by FOREIGN KEY (updated_by) 
        REFERENCES portal_users(id_iam) ON DELETE SET NULL
);

COMMENT ON TABLE mfi_clients IS 'MFI client information';
COMMENT ON COLUMN mfi_clients.schema IS 'Database schema name for this MFI';
COMMENT ON COLUMN mfi_clients.realm_id IS 'Keycloak realm ID (fetched from IAM)';
COMMENT ON COLUMN mfi_clients.client_id IS 'Keycloak client ID (fetched from IAM)';

CREATE INDEX idx_mfi_clients_schema ON mfi_clients(schema);
CREATE INDEX idx_mfi_clients_realm_id ON mfi_clients(realm_id);
CREATE INDEX idx_mfi_clients_is_active ON mfi_clients(is_active);
CREATE INDEX idx_mfi_clients_name ON mfi_clients(name);

-- ----------------------------------------------------------------------------
-- Table: mfi_groups
-- Description: List of MFI IAM groups
-- CRITICAL: Groups MUST be created in Keycloak first, then synced to this table
-- ----------------------------------------------------------------------------
CREATE TABLE mfi_groups (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    iam_group_id UUID NOT NULL UNIQUE,
    id_mfi UUID NOT NULL,
    name TEXT NOT NULL,
    description TEXT,
    group_path TEXT NOT NULL,
    parent_iam_group_id UUID,
    created_on TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    
    CONSTRAINT fk_mfi_groups_mfi FOREIGN KEY (id_mfi) 
        REFERENCES mfi_clients(id) ON DELETE CASCADE
);

COMMENT ON TABLE mfi_groups IS 'List of MFI IAM groups';
COMMENT ON COLUMN mfi_groups.iam_group_id IS 'Group ID fetched from IAM (Keycloak)';
COMMENT ON COLUMN mfi_groups.id_mfi IS 'Reference to MFI client';

CREATE INDEX idx_mfi_groups_iam_group_id ON mfi_groups(iam_group_id);
CREATE INDEX idx_mfi_groups_id_mfi ON mfi_groups(id_mfi);
CREATE INDEX idx_mfi_groups_name ON mfi_groups(name);

-- ----------------------------------------------------------------------------
-- Table: mfi_users
-- Description: All MFI portal users
-- ----------------------------------------------------------------------------
CREATE TABLE mfi_users (
    id SERIAL PRIMARY KEY,
    id_iam UUID NOT NULL UNIQUE,
    id_mfi UUID NOT NULL,
    username TEXT NOT NULL,
    fname TEXT NOT NULL,
    lname TEXT,
    email TEXT NOT NULL,
    temp_lock BOOLEAN DEFAULT FALSE,
    email_verified BOOLEAN DEFAULT FALSE,
    profile_img_url TEXT,
    last_password_changed_at TIMESTAMP,
    last_login_at TIMESTAMP,
    id_group UUID NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    created_by UUID,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_by UUID,
    
    CONSTRAINT fk_mfi_users_mfi FOREIGN KEY (id_mfi) 
        REFERENCES mfi_clients(id) ON DELETE CASCADE,
    CONSTRAINT fk_mfi_users_group FOREIGN KEY (id_group) 
        REFERENCES mfi_groups(iam_group_id) ON DELETE RESTRICT,
    CONSTRAINT fk_mfi_users_created_by FOREIGN KEY (created_by) 
        REFERENCES portal_users(id_iam) ON DELETE SET NULL,
    CONSTRAINT fk_mfi_users_updated_by FOREIGN KEY (updated_by) 
        REFERENCES portal_users(id_iam) ON DELETE SET NULL
);

COMMENT ON TABLE mfi_users IS 'All MFI portal users';
COMMENT ON COLUMN mfi_users.id_iam IS 'User ID received from IAM (Keycloak)';
COMMENT ON COLUMN mfi_users.id_group IS 'Group ID (must be set in IAM also)';

CREATE INDEX idx_mfi_users_id_iam ON mfi_users(id_iam);
CREATE INDEX idx_mfi_users_id_mfi ON mfi_users(id_mfi);
CREATE INDEX idx_mfi_users_email ON mfi_users(email);
CREATE INDEX idx_mfi_users_id_group ON mfi_users(id_group);
CREATE INDEX idx_mfi_users_temp_lock ON mfi_users(temp_lock);

-- ============================================================================
-- DIGITAL PLATFORMS MODULE
-- ============================================================================

-- ----------------------------------------------------------------------------
-- Table: digital_platforms
-- Description: List of all active digital platforms
-- ----------------------------------------------------------------------------
CREATE TABLE digital_platforms (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL UNIQUE,
    is_active BOOLEAN DEFAULT TRUE,
    id_type INTEGER,
    current_version TEXT,
    last_app_update TIMESTAMP,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT fk_digital_platforms_type FOREIGN KEY (id_type)
        REFERENCES platform_type(id) ON DELETE SET NULL
);

COMMENT ON TABLE digital_platforms IS 'List of all active digital platforms (mobile app, internet, etc.)';
COMMENT ON COLUMN digital_platforms.id_type IS 'Reference to platform_type';

CREATE INDEX idx_digital_platforms_is_active ON digital_platforms(is_active);
CREATE INDEX idx_digital_platforms_id_type ON digital_platforms(id_type);

-- ----------------------------------------------------------------------------
-- Table: mfi_platforms
-- Description: Digital platforms provisioned to each MFI
-- ----------------------------------------------------------------------------
CREATE TABLE mfi_platforms (
    id SERIAL PRIMARY KEY,
    mfi_id UUID NOT NULL,
    platform_id UUID NOT NULL,
    assigned_by UUID,
    assigned_on TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    status INTEGER DEFAULT 0,

    CONSTRAINT fk_mfi_platforms_mfi FOREIGN KEY (mfi_id)
        REFERENCES mfi_clients(id) ON DELETE CASCADE,
    CONSTRAINT fk_mfi_platforms_platform FOREIGN KEY (platform_id)
        REFERENCES digital_platforms(id) ON DELETE CASCADE,
    CONSTRAINT fk_mfi_platforms_assigned_by FOREIGN KEY (assigned_by)
        REFERENCES portal_users(id_iam) ON DELETE SET NULL,
    CONSTRAINT uk_mfi_platforms UNIQUE (mfi_id, platform_id),
    CONSTRAINT chk_mfi_platforms_status CHECK (status IN (0, 1, 2))
);

COMMENT ON TABLE mfi_platforms IS 'Digital platforms provisioned to each MFI';
COMMENT ON COLUMN mfi_platforms.status IS '0=Pending; 1=Active; 2=Rejected';

CREATE INDEX idx_mfi_platforms_mfi_id ON mfi_platforms(mfi_id);
CREATE INDEX idx_mfi_platforms_platform_id ON mfi_platforms(platform_id);
CREATE INDEX idx_mfi_platforms_status ON mfi_platforms(status);

-- ============================================================================
-- ACTIVITIES & AUDIT MODULE
-- ============================================================================

-- ----------------------------------------------------------------------------
-- Table: user_auth_logs
-- Description: User authentication event logs
-- ----------------------------------------------------------------------------
CREATE TABLE user_auth_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    iam_event_id TEXT,
    iam_user_id UUID,
    event_type TEXT NOT NULL,
    client_id TEXT NOT NULL,
    realm_id UUID NOT NULL,
    session_id TEXT,
    ip_address TEXT,
    error TEXT,
    event_time TIMESTAMP NOT NULL,
    details JSONB,
    created_on TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

COMMENT ON TABLE user_auth_logs IS 'User authentication event logs';
COMMENT ON COLUMN user_auth_logs.details IS 'Additional event details in JSON format';

CREATE INDEX idx_user_auth_logs_event_time ON user_auth_logs(event_time);
CREATE INDEX idx_user_auth_logs_iam_user_id ON user_auth_logs(iam_user_id);
CREATE INDEX idx_user_auth_logs_event_type ON user_auth_logs(event_type);
CREATE INDEX idx_user_auth_logs_realm_id ON user_auth_logs(realm_id);
CREATE INDEX idx_user_auth_logs_created_on ON user_auth_logs(created_on);

-- ----------------------------------------------------------------------------
-- Table: admin_event_logs
-- Description: Admin event logs (configuration changes, realm management)
-- ----------------------------------------------------------------------------
CREATE TABLE admin_event_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    event_id UUID NOT NULL,
    realm_id UUID NOT NULL,
    auth_details JSONB,
    operation_type TEXT,
    resource_type TEXT,
    resource_path JSONB,
    representation JSONB,
    details JSONB,
    created_on TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

COMMENT ON TABLE admin_event_logs IS 'Admin event logs (configuration changes, realm management)';
COMMENT ON COLUMN admin_event_logs.auth_details IS 'Authentication details in JSON format';
COMMENT ON COLUMN admin_event_logs.representation IS 'Resource representation in JSON format';

CREATE INDEX idx_admin_event_logs_event_id ON admin_event_logs(event_id);
CREATE INDEX idx_admin_event_logs_realm_id ON admin_event_logs(realm_id);
CREATE INDEX idx_admin_event_logs_operation_type ON admin_event_logs(operation_type);
CREATE INDEX idx_admin_event_logs_resource_type ON admin_event_logs(resource_type);
CREATE INDEX idx_admin_event_logs_created_on ON admin_event_logs(created_on);

-- ----------------------------------------------------------------------------
-- Table: user_activity_logs
-- Description: User activity on the portal
-- ----------------------------------------------------------------------------
CREATE TABLE user_activity_logs (
    id SERIAL PRIMARY KEY,
    user_id TEXT NOT NULL,
    event_type_id INTEGER NOT NULL,
    ip_address TEXT,
    error TEXT,
    details JSONB,
    event_time TIMESTAMP,
    created_on TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    
    CONSTRAINT fk_user_activity_logs_event_type FOREIGN KEY (event_type_id) 
        REFERENCES activity_type(id) ON DELETE RESTRICT
);

COMMENT ON TABLE user_activity_logs IS 'User activity on the portal';
COMMENT ON COLUMN user_activity_logs.details IS 'Activity details in JSON format';

CREATE INDEX idx_user_activity_logs_user_id ON user_activity_logs(user_id);
CREATE INDEX idx_user_activity_logs_event_type_id ON user_activity_logs(event_type_id);
CREATE INDEX idx_user_activity_logs_event_time ON user_activity_logs(event_time);
CREATE INDEX idx_user_activity_logs_created_on ON user_activity_logs(created_on);

-- ----------------------------------------------------------------------------
-- Table: mfi_user_activity_logs
-- Description: MFI user activity on the portal
-- ----------------------------------------------------------------------------
CREATE TABLE mfi_user_activity_logs (
    id SERIAL PRIMARY KEY,
    user_id TEXT NOT NULL,
    event_type_id INTEGER NOT NULL,
    ip_address TEXT,
    error TEXT,
    details JSONB,
    event_time TIMESTAMP,
    created_on TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    
    CONSTRAINT fk_mfi_user_activity_logs_event_type FOREIGN KEY (event_type_id) 
        REFERENCES activity_type(id) ON DELETE RESTRICT
);

COMMENT ON TABLE mfi_user_activity_logs IS 'MFI user activity on the portal';
COMMENT ON COLUMN mfi_user_activity_logs.details IS 'Activity details in JSON format';

CREATE INDEX idx_mfi_user_activity_logs_user_id ON mfi_user_activity_logs(user_id);
CREATE INDEX idx_mfi_user_activity_logs_event_type_id ON mfi_user_activity_logs(event_type_id);
CREATE INDEX idx_mfi_user_activity_logs_event_time ON mfi_user_activity_logs(event_time);
CREATE INDEX idx_mfi_user_activity_logs_created_on ON mfi_user_activity_logs(created_on);

-- ============================================================================
-- SEED DATA (Reference Tables)
-- ============================================================================

-- ----------------------------------------------------------------------------
-- Activity Types
-- ----------------------------------------------------------------------------
INSERT INTO activity_type (name) VALUES
    ('CREATE MFI'),
    ('ASSIGN GROUP'),
    ('CREATE USER'),
    ('UPDATE USER'),
    ('DELETE USER'),
    ('LOGIN'),
    ('LOGOUT'),
    ('ASSIGN PLATFORM'),
    ('UPDATE PROFILE'),
    ('CHANGE PASSWORD')
ON CONFLICT (name) DO NOTHING;

-- ----------------------------------------------------------------------------
-- Countries
-- ----------------------------------------------------------------------------
INSERT INTO mfi_country (name) VALUES
    ('Rwanda'),
    ('Malawi'),
    ('Kenya'),
    ('Uganda'),
    ('Tanzania'),
    ('Zambia'),
    ('Zimbabwe'),
    ('Botswana'),
    ('Namibia'),
    ('South Africa')
ON CONFLICT (name) DO NOTHING;

-- ----------------------------------------------------------------------------
-- MFI Types
-- ----------------------------------------------------------------------------
INSERT INTO mfi_type (name) VALUES
    ('Savings & Deposits Only'),
    ('Microfinance Institution'),
    ('Non-Deposit Financial Institution'),
    ('Credit Only Institution'),
    ('Cooperative Society')
ON CONFLICT (name) DO NOTHING;

-- ----------------------------------------------------------------------------
-- Platform Types
-- ----------------------------------------------------------------------------
INSERT INTO platform_type (name) VALUES
    ('Mobile App'),
    ('Web App'),
    ('USSD Services'),
    ('API Services'),
    ('SMS Banking'),
    ('Agent Banking')
ON CONFLICT (name) DO NOTHING;

-- ============================================================================
-- TRIGGERS FOR updated_at TIMESTAMP
-- ============================================================================

CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Apply to tables with updated_at
CREATE TRIGGER update_portals_updated_at
    BEFORE UPDATE ON portals
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_portal_groups_updated_at
    BEFORE UPDATE ON portal_groups
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_portal_users_updated_at
    BEFORE UPDATE ON portal_users
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_mfi_clients_updated_at
    BEFORE UPDATE ON mfi_clients
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_mfi_groups_updated_at
    BEFORE UPDATE ON mfi_groups
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_mfi_users_updated_at
    BEFORE UPDATE ON mfi_users
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_digital_platforms_updated_at
    BEFORE UPDATE ON digital_platforms
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_activity_type_updated_at
    BEFORE UPDATE ON activity_type
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_mfi_country_updated_at
    BEFORE UPDATE ON mfi_country
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_mfi_type_updated_at
    BEFORE UPDATE ON mfi_type
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_platform_type_updated_at
    BEFORE UPDATE ON platform_type
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- ============================================================================
-- VIEWS FOR COMMON QUERIES
-- ============================================================================

-- ----------------------------------------------------------------------------
-- View: Active Portals with User Count
-- ----------------------------------------------------------------------------
CREATE OR REPLACE VIEW v_active_portals AS
SELECT
    p.id,
    p.name,
    p.description,
    p.realm_id,
    p.is_active,
    p.on_prod,
    COUNT(DISTINCT ug.user_id) AS user_count,
    p.created_on,
    p.updated_at
FROM portals p
LEFT JOIN portal_groups pg ON pg.group_path LIKE '%' || p.realm_id || '%'
LEFT JOIN user_groups ug ON ug.group_id = pg.iam_group_id
GROUP BY p.id, p.name, p.description, p.realm_id, p.is_active, p.on_prod, p.created_on, p.updated_at;

-- ----------------------------------------------------------------------------
-- View: MFI Clients with Platform Assignments
-- ----------------------------------------------------------------------------
CREATE OR REPLACE VIEW v_mfi_platforms_summary AS
SELECT 
    mc.id AS mfi_id,
    mc.name AS mfi_name,
    mc.schema,
    mc.is_active AS mfi_active,
    mfi_country.name AS country,
    mfi_type.name AS mfi_type_name,
    dp.name AS platform_name,
    dp.is_active AS platform_active,
    mp.status AS assignment_status,
    mp.assigned_on
FROM mfi_clients mc
LEFT JOIN mfi_country ON mc.id_country = mfi_country.id
LEFT JOIN mfi_type ON mc.id_type = mfi_type.id
LEFT JOIN mfi_platforms mp ON mc.id = mp.mfi_id
LEFT JOIN digital_platforms dp ON mp.platform_id = dp.id;

-- ----------------------------------------------------------------------------
-- View: User Group Assignments
-- ----------------------------------------------------------------------------
CREATE OR REPLACE VIEW v_user_group_assignments AS
SELECT 
    pu.id AS user_id,
    pu.username,
    pu.email,
    pu.fname,
    pu.lname,
    pg.name AS group_name,
    pg.iam_group_id,
    ug.assigned_by,
    ug.assigned_on
FROM portal_users pu
JOIN user_groups ug ON pu.id_iam = ug.user_id
JOIN portal_groups pg ON ug.group_id = pg.iam_group_id;

-- ============================================================================
-- SECURITY & PERMISSIONS (Optional - Adjust as needed)
-- ============================================================================

-- Create application role
-- CREATE ROLE mfi_app_user WITH LOGIN PASSWORD 'your_secure_password';

-- Grant permissions
-- GRANT SELECT, INSERT, UPDATE ON ALL TABLES IN SCHEMA public TO mfi_app_user;
-- GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO mfi_app_user;

-- Read-only role for reporting
-- CREATE ROLE mfi_read_only WITH LOGIN PASSWORD 'your_secure_password';
-- GRANT SELECT ON ALL TABLES IN SCHEMA public TO mfi_read_only;

-- ============================================================================
-- END OF SCHEMA
-- ============================================================================