# GiSTKollect Implementation Plan

## Complete Step-by-Step Guide

This document provides a detailed implementation plan for building the GiSTKollect platform. Follow each phase in order, completing all steps before moving to the next phase.

---

## Table of Contents

1. [Phase 1: Domain & Accounts Setup](#phase-1-domain--accounts-setup)
2. [Phase 2: Supabase Database Setup](#phase-2-supabase-database-setup)
3. [Phase 3: Supabase Storage Setup](#phase-3-supabase-storage-setup)
4. [Phase 4: Supabase Edge Functions](#phase-4-supabase-edge-functions)
5. [Phase 5: Flutter Web Project Setup](#phase-5-flutter-web-project-setup)
6. [Phase 6: Web App - Authentication](#phase-6-web-app---authentication)
7. [Phase 7: Web App - Projects Management](#phase-7-web-app---projects-management)
8. [Phase 8: Web App - Survey Management](#phase-8-web-app---survey-management)
9. [Phase 9: Web App - Team & Credentials](#phase-9-web-app---team--credentials)
10. [Phase 10: Web App - Data Viewing](#phase-10-web-app---data-viewing)
11. [Phase 11: Mobile App - Rename & Rebrand](#phase-11-mobile-app---rename--rebrand)
12. [Phase 12: Mobile App - Authentication](#phase-12-mobile-app---authentication)
13. [Phase 13: Mobile App - Survey Download](#phase-13-mobile-app---survey-download)
14. [Phase 14: Mobile App - Data Sync](#phase-14-mobile-app---data-sync)
15. [Phase 15: Testing & Deployment](#phase-15-testing--deployment)

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                     gistkollect.org                              │
│                     (Flutter Web)                                │
│  ┌──────────────┐ ┌──────────────┐ ┌──────────────┐             │
│  │   Projects   │ │   Surveys    │ │     Data     │             │
│  │  Management  │ │  Management  │ │   Viewing    │             │
│  └──────────────┘ └──────────────┘ └──────────────┘             │
└──────────────────────────┬──────────────────────────────────────┘
                           │
                           ▼
              ┌────────────────────────┐
              │       Supabase         │
              │  ┌──────────────────┐  │
              │  │   PostgreSQL     │  │
              │  │   (Database)     │  │
              │  └──────────────────┘  │
              │  ┌──────────────────┐  │
              │  │     Storage      │  │
              │  │  (ZIP files)     │  │
              │  └──────────────────┘  │
              │  ┌──────────────────┐  │
              │  │      Auth        │  │
              │  │  (Web users)     │  │
              │  └──────────────────┘  │
              │  ┌──────────────────┐  │
              │  │ Edge Functions   │  │
              │  │ (App login API)  │  │
              │  └──────────────────┘  │
              └────────────┬───────────┘
                           │
         ┌─────────────────┼─────────────────┐
         │                 │                 │
    ┌────┴────┐      ┌────┴────┐      ┌────┴────┐
    │ Android │      │ Windows │      │   iOS   │
    │   App   │      │   App   │      │   App   │
    └─────────┘      └─────────┘      └─────────┘
```

---

## Phase 1: Domain & Accounts Setup

**Estimated time: 1-2 hours**

### Step 1.1: Register Domain

1. Go to a domain registrar:
   - Namecheap (https://namecheap.com)
   - Google Domains (https://domains.google)
   - Cloudflare (https://cloudflare.com)

2. Search for and register:
   - Primary: `gistkollect.org`
   - Optional backup: `gistkollect.com`

3. Note your domain registrar login credentials

### Step 1.2: Create Supabase Account

1. Go to https://supabase.com
2. Click "Start your project"
3. Sign up with GitHub or email
4. Verify your email if required

### Step 1.3: Create Supabase Project

1. Click "New Project"
2. Fill in details:
   - **Name:** `gistkollect`
   - **Database Password:** Generate a strong password and SAVE IT SECURELY
   - **Region:** Choose closest to your users (e.g., EU West for Africa)
   - **Plan:** Free tier (can upgrade later)

3. Wait for project to initialize (2-3 minutes)

4. Once ready, note down these values (Settings > API):
   - **Project URL:** `https://xxxxx.supabase.co`
   - **Anon/Public Key:** `eyJhbGciOiJI...`
   - **Service Role Key:** `eyJhbGciOiJI...` (keep this SECRET)

### Step 1.4: Save Credentials Securely

Create a secure document (password manager or encrypted file) with:

```
DOMAIN REGISTRAR
================
Provider: [e.g., Namecheap]
Username: [your username]
Password: [your password]

SUPABASE
========
Project URL: https://xxxxx.supabase.co
Anon Key: eyJhbGciOiJI...
Service Role Key: eyJhbGciOiJI... (SECRET - never expose)
Database Password: [your db password]
```

### Step 1.5: Checklist

- [x] Domain registered (gistkollect.org)
- [x] Supabase account created
- [x] Supabase project created
- [x] All credentials saved securely

---

## Phase 2: Supabase Database Setup

**Estimated time: 1-2 hours**

### Step 2.1: Open SQL Editor

1. In Supabase dashboard, click "SQL Editor" in left sidebar
2. Click "New query"

### Step 2.2: Run Schema Creation Script

Copy and run the following SQL script. Run it in ONE execution:

```sql
-- ============================================================================
-- GISTKOLLECT DATABASE SCHEMA
-- Version: 1.0.0
-- Run this entire script in Supabase SQL Editor
-- ============================================================================

-- Enable UUID extension
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- ============================================================================
-- SECTION 1: USER PROFILES
-- Extends Supabase auth.users with additional profile information
-- ============================================================================

CREATE TABLE public.profiles (
    id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    email TEXT NOT NULL,
    full_name TEXT,
    organization TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Trigger to auto-create profile when user signs up
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO public.profiles (id, email, full_name)
    VALUES (NEW.id, NEW.email, NEW.raw_user_meta_data->>'full_name');
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER on_auth_user_created
    AFTER INSERT ON auth.users
    FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- ============================================================================
-- SECTION 2: PROJECTS
-- Research projects/studies
-- ============================================================================

CREATE TABLE public.projects (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name TEXT NOT NULL,
    description TEXT,
    slug TEXT UNIQUE NOT NULL,  -- URL-friendly identifier (e.g., 'r21-vaccine')
    created_by UUID REFERENCES public.profiles(id),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    is_active BOOLEAN DEFAULT TRUE
);

-- Index for faster slug lookups
CREATE INDEX idx_projects_slug ON public.projects(slug);

-- ============================================================================
-- SECTION 3: PROJECT MEMBERSHIPS
-- Links users to projects with specific roles
-- ============================================================================

CREATE TYPE public.project_role AS ENUM (
    'viewer',        -- View surveys and data (read-only)
    'data_analyst',  -- View data, export, run reports
    'editor',        -- Upload surveys, view data
    'admin',         -- Manage team, credentials
    'owner'          -- Full control including delete
);

CREATE TABLE public.project_members (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    project_id UUID REFERENCES public.projects(id) ON DELETE CASCADE,
    user_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE,
    role public.project_role NOT NULL DEFAULT 'viewer',
    invited_by UUID REFERENCES public.profiles(id),
    invited_at TIMESTAMPTZ DEFAULT NOW(),
    accepted_at TIMESTAMPTZ,
    UNIQUE(project_id, user_id)
);

-- Indexes for faster lookups
CREATE INDEX idx_project_members_user ON public.project_members(user_id);
CREATE INDEX idx_project_members_project ON public.project_members(project_id);

-- ============================================================================
-- SECTION 4: SURVEY PACKAGES
-- Survey configurations (ZIP files containing XML + CSV)
-- ============================================================================

CREATE TYPE public.survey_status AS ENUM (
    'draft',      -- Not yet published
    'processing', -- Being generated
    'ready',      -- Available for download
    'archived',   -- No longer active
    'error'       -- Generation failed
);

CREATE TABLE public.survey_packages (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    project_id UUID REFERENCES public.projects(id) ON DELETE CASCADE,

    -- Survey identification
    name TEXT NOT NULL,
    version TEXT,
    description TEXT,

    -- File storage (Supabase Storage paths)
    excel_file_path TEXT,
    zip_file_path TEXT,

    -- Parsed manifest content (from survey_manifest.gistx)
    manifest JSONB,

    -- Status tracking
    status public.survey_status DEFAULT 'draft',
    error_message TEXT,

    -- Metadata
    created_by UUID REFERENCES public.profiles(id),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    published_at TIMESTAMPTZ
);

CREATE INDEX idx_survey_packages_project ON public.survey_packages(project_id);
CREATE INDEX idx_survey_packages_status ON public.survey_packages(status);

-- ============================================================================
-- SECTION 5: CRF DEFINITIONS
-- Case Report Form definitions (parsed from manifest)
-- ============================================================================

CREATE TABLE public.crfs (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    survey_package_id UUID REFERENCES public.survey_packages(id) ON DELETE CASCADE,
    project_id UUID REFERENCES public.projects(id) ON DELETE CASCADE,

    -- CRF identification
    table_name TEXT NOT NULL,
    display_name TEXT NOT NULL,
    display_order INTEGER DEFAULT 0,

    -- Configuration
    is_base BOOLEAN DEFAULT FALSE,
    primary_key TEXT,
    linking_field TEXT,
    parent_table TEXT,

    -- Field definitions (from XML parsing)
    fields JSONB,  -- Array of field definitions

    -- ID generation config
    id_config JSONB,

    -- Display configuration
    display_fields TEXT,

    created_at TIMESTAMPTZ DEFAULT NOW(),

    UNIQUE(survey_package_id, table_name)
);

CREATE INDEX idx_crfs_survey_package ON public.crfs(survey_package_id);
CREATE INDEX idx_crfs_project ON public.crfs(project_id);

-- ============================================================================
-- SECTION 6: SUBMISSIONS
-- All survey data collected from the app
-- ============================================================================

CREATE TABLE public.submissions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    project_id UUID REFERENCES public.projects(id) ON DELETE CASCADE,
    survey_package_id UUID REFERENCES public.survey_packages(id),
    crf_id UUID REFERENCES public.crfs(id),

    -- Record identification
    table_name TEXT NOT NULL,
    record_id TEXT,
    local_unique_id TEXT NOT NULL,

    -- THE ACTUAL DATA (all survey fields as JSON)
    data JSONB NOT NULL,

    -- Version tracking
    version INTEGER DEFAULT 1,

    -- Parent-child linking
    parent_table TEXT,
    parent_record_id TEXT,

    -- Device/surveyor info
    device_id TEXT,
    surveyor_id TEXT,
    app_version TEXT,

    -- Timestamps
    collected_at TIMESTAMPTZ,
    submitted_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Prevent duplicate submissions
CREATE UNIQUE INDEX idx_submissions_unique
    ON public.submissions(project_id, table_name, local_unique_id);

-- Fast lookups
CREATE INDEX idx_submissions_project_table
    ON public.submissions(project_id, table_name);
CREATE INDEX idx_submissions_record
    ON public.submissions(project_id, table_name, record_id);
CREATE INDEX idx_submissions_collected
    ON public.submissions(project_id, collected_at);
CREATE INDEX idx_submissions_surveyor
    ON public.submissions(project_id, surveyor_id);

-- JSON search index
CREATE INDEX idx_submissions_data
    ON public.submissions USING GIN (data);

-- ============================================================================
-- SECTION 7: SUBMISSION HISTORY (AUDIT LOG)
-- Tracks all changes to submissions
-- ============================================================================

CREATE TABLE public.submission_history (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    submission_id UUID REFERENCES public.submissions(id) ON DELETE CASCADE,

    -- Snapshot of data at this version
    data JSONB NOT NULL,
    version INTEGER NOT NULL,

    -- Change details
    change_type TEXT NOT NULL,  -- 'created', 'modified', 'deleted'
    changed_fields JSONB,       -- Array of field names that changed

    -- Who/when/where
    changed_by TEXT,            -- Surveyor ID
    changed_on_device TEXT,     -- Device ID
    changed_at TIMESTAMPTZ DEFAULT NOW(),
    synced_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_submission_history_submission
    ON public.submission_history(submission_id);
CREATE INDEX idx_submission_history_changed_at
    ON public.submission_history(changed_at);

-- Trigger to automatically log changes
CREATE OR REPLACE FUNCTION log_submission_change()
RETURNS TRIGGER AS $$
DECLARE
    v_changed_fields JSONB;
BEGIN
    -- Calculate which fields changed (for updates)
    IF TG_OP = 'UPDATE' THEN
        SELECT jsonb_agg(key)
        INTO v_changed_fields
        FROM jsonb_each(NEW.data)
        WHERE NOT (OLD.data ? key AND OLD.data->key = NEW.data->key);
    END IF;

    INSERT INTO public.submission_history (
        submission_id,
        data,
        version,
        change_type,
        changed_fields,
        changed_by,
        changed_on_device,
        synced_at
    ) VALUES (
        NEW.id,
        NEW.data,
        NEW.version,
        CASE
            WHEN TG_OP = 'INSERT' THEN 'created'
            WHEN TG_OP = 'UPDATE' THEN 'modified'
        END,
        v_changed_fields,
        NEW.surveyor_id,
        NEW.device_id,
        NOW()
    );

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER submission_audit_trigger
    AFTER INSERT OR UPDATE ON public.submissions
    FOR EACH ROW
    EXECUTE FUNCTION log_submission_change();

-- ============================================================================
-- SECTION 8: APP CREDENTIALS
-- Credentials for mobile app login (shared per field team)
-- ============================================================================

CREATE TABLE public.app_credentials (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    project_id UUID REFERENCES public.projects(id) ON DELETE CASCADE,

    -- Login credentials
    username TEXT NOT NULL,
    password_hash TEXT NOT NULL,

    -- Metadata
    description TEXT,
    is_active BOOLEAN DEFAULT TRUE,

    -- Tracking
    created_by UUID REFERENCES public.profiles(id),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    last_used_at TIMESTAMPTZ,

    UNIQUE(project_id, username)
);

CREATE INDEX idx_app_credentials_project ON public.app_credentials(project_id);
CREATE INDEX idx_app_credentials_lookup ON public.app_credentials(project_id, username, is_active);

-- ============================================================================
-- SECTION 9: APP SESSIONS
-- Track active app sessions (optional, for token validation)
-- ============================================================================

CREATE TABLE public.app_sessions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    credential_id UUID REFERENCES public.app_credentials(id) ON DELETE CASCADE,
    project_id UUID REFERENCES public.projects(id) ON DELETE CASCADE,

    token TEXT UNIQUE NOT NULL,
    device_id TEXT,
    device_info JSONB,

    created_at TIMESTAMPTZ DEFAULT NOW(),
    expires_at TIMESTAMPTZ NOT NULL,
    last_activity_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_app_sessions_token ON public.app_sessions(token);
CREATE INDEX idx_app_sessions_credential ON public.app_sessions(credential_id);

-- ============================================================================
-- SECTION 10: ROW LEVEL SECURITY (RLS)
-- Controls who can access what data
-- ============================================================================

-- Enable RLS on all tables
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.projects ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.project_members ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.survey_packages ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.crfs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.submissions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.submission_history ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.app_credentials ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.app_sessions ENABLE ROW LEVEL SECURITY;

-- PROFILES: Users can read/update their own profile
CREATE POLICY "Users can view own profile"
    ON public.profiles FOR SELECT
    USING (auth.uid() = id);

CREATE POLICY "Users can update own profile"
    ON public.profiles FOR UPDATE
    USING (auth.uid() = id);

-- PROJECTS: Users can see projects they're members of
CREATE POLICY "Users can view member projects"
    ON public.projects FOR SELECT
    USING (
        id IN (
            SELECT project_id FROM public.project_members
            WHERE user_id = auth.uid()
        )
    );

CREATE POLICY "Users can create projects"
    ON public.projects FOR INSERT
    WITH CHECK (auth.uid() IS NOT NULL);

CREATE POLICY "Owners can update projects"
    ON public.projects FOR UPDATE
    USING (
        id IN (
            SELECT project_id FROM public.project_members
            WHERE user_id = auth.uid() AND role = 'owner'
        )
    );

CREATE POLICY "Owners can delete projects"
    ON public.projects FOR DELETE
    USING (
        id IN (
            SELECT project_id FROM public.project_members
            WHERE user_id = auth.uid() AND role = 'owner'
        )
    );

-- PROJECT_MEMBERS: Users can see memberships for their projects
CREATE POLICY "Users can view project memberships"
    ON public.project_members FOR SELECT
    USING (
        project_id IN (
            SELECT project_id FROM public.project_members
            WHERE user_id = auth.uid()
        )
    );

CREATE POLICY "Admins can manage memberships"
    ON public.project_members FOR ALL
    USING (
        project_id IN (
            SELECT project_id FROM public.project_members
            WHERE user_id = auth.uid() AND role IN ('admin', 'owner')
        )
    );

-- SURVEY_PACKAGES: Users can see surveys for their projects
CREATE POLICY "Users can view project surveys"
    ON public.survey_packages FOR SELECT
    USING (
        project_id IN (
            SELECT project_id FROM public.project_members
            WHERE user_id = auth.uid()
        )
    );

CREATE POLICY "Editors can manage surveys"
    ON public.survey_packages FOR ALL
    USING (
        project_id IN (
            SELECT project_id FROM public.project_members
            WHERE user_id = auth.uid() AND role IN ('editor', 'admin', 'owner')
        )
    );

-- CRFS: Users can see CRFs for their projects
CREATE POLICY "Users can view project crfs"
    ON public.crfs FOR SELECT
    USING (
        project_id IN (
            SELECT project_id FROM public.project_members
            WHERE user_id = auth.uid()
        )
    );

CREATE POLICY "Editors can manage crfs"
    ON public.crfs FOR ALL
    USING (
        project_id IN (
            SELECT project_id FROM public.project_members
            WHERE user_id = auth.uid() AND role IN ('editor', 'admin', 'owner')
        )
    );

-- SUBMISSIONS: Users can see submissions for their projects
CREATE POLICY "Users can view project submissions"
    ON public.submissions FOR SELECT
    USING (
        project_id IN (
            SELECT project_id FROM public.project_members
            WHERE user_id = auth.uid()
        )
    );

CREATE POLICY "Editors can manage submissions"
    ON public.submissions FOR ALL
    USING (
        project_id IN (
            SELECT project_id FROM public.project_members
            WHERE user_id = auth.uid() AND role IN ('editor', 'admin', 'owner')
        )
    );

-- SUBMISSION_HISTORY: Users can view history for their projects
CREATE POLICY "Users can view submission history"
    ON public.submission_history FOR SELECT
    USING (
        submission_id IN (
            SELECT s.id FROM public.submissions s
            WHERE s.project_id IN (
                SELECT project_id FROM public.project_members
                WHERE user_id = auth.uid()
            )
        )
    );

-- APP_CREDENTIALS: Admins can manage credentials
CREATE POLICY "Admins can view credentials"
    ON public.app_credentials FOR SELECT
    USING (
        project_id IN (
            SELECT project_id FROM public.project_members
            WHERE user_id = auth.uid() AND role IN ('admin', 'owner')
        )
    );

CREATE POLICY "Admins can manage credentials"
    ON public.app_credentials FOR ALL
    USING (
        project_id IN (
            SELECT project_id FROM public.project_members
            WHERE user_id = auth.uid() AND role IN ('admin', 'owner')
        )
    );

-- APP_SESSIONS: Admins can view sessions
CREATE POLICY "Admins can view sessions"
    ON public.app_sessions FOR SELECT
    USING (
        project_id IN (
            SELECT project_id FROM public.project_members
            WHERE user_id = auth.uid() AND role IN ('admin', 'owner')
        )
    );

-- ============================================================================
-- SECTION 11: HELPER FUNCTIONS
-- Useful functions for common operations
-- ============================================================================

-- Function to check if user has a specific role or higher
CREATE OR REPLACE FUNCTION public.user_has_project_role(
    p_project_id UUID,
    p_min_role public.project_role
)
RETURNS BOOLEAN AS $$
DECLARE
    v_user_role public.project_role;
    v_role_order INTEGER;
    v_min_role_order INTEGER;
BEGIN
    -- Get user's role
    SELECT role INTO v_user_role
    FROM public.project_members
    WHERE project_id = p_project_id AND user_id = auth.uid();

    IF v_user_role IS NULL THEN
        RETURN FALSE;
    END IF;

    -- Define role hierarchy (higher number = more permissions)
    v_role_order := CASE v_user_role
        WHEN 'viewer' THEN 1
        WHEN 'data_analyst' THEN 2
        WHEN 'editor' THEN 3
        WHEN 'admin' THEN 4
        WHEN 'owner' THEN 5
    END;

    v_min_role_order := CASE p_min_role
        WHEN 'viewer' THEN 1
        WHEN 'data_analyst' THEN 2
        WHEN 'editor' THEN 3
        WHEN 'admin' THEN 4
        WHEN 'owner' THEN 5
    END;

    RETURN v_role_order >= v_min_role_order;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function to get submission counts by table
CREATE OR REPLACE FUNCTION public.get_submission_counts(p_project_id UUID)
RETURNS TABLE (
    table_name TEXT,
    total_count BIGINT,
    today_count BIGINT
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        s.table_name,
        COUNT(*) as total_count,
        COUNT(*) FILTER (WHERE DATE(s.collected_at) = CURRENT_DATE) as today_count
    FROM public.submissions s
    WHERE s.project_id = p_project_id
    GROUP BY s.table_name
    ORDER BY s.table_name;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================================
-- SETUP COMPLETE
-- ============================================================================

-- Verify tables were created
SELECT table_name
FROM information_schema.tables
WHERE table_schema = 'public'
ORDER BY table_name;
```

### Step 2.3: Verify Schema Creation

After running the script, you should see these tables listed:
- app_credentials
- app_sessions
- crfs
- profiles
- project_members
- projects
- submission_history
- submissions
- survey_packages

### Step 2.4: Checklist

- [x] SQL script executed without errors
- [x] All 9 tables created
- [ ] Triggers created (on_auth_user_created, submission_audit_trigger)
- [ ] RLS policies created

---

## Phase 3: Supabase Storage Setup

**Estimated time: 30 minutes**

### Step 3.1: Create Storage Buckets

1. In Supabase dashboard, click "Storage" in left sidebar
2. Click "New bucket"

**Bucket 1: uploads**
- Name: `uploads`
- Public: OFF (unchecked)
- Click "Create bucket"

**Bucket 2: surveys**
- Name: `surveys`
- Public: OFF (unchecked)
- Click "Create bucket"

### Step 3.2: Set Storage Policies

Click on each bucket and go to "Policies" tab.

**For `uploads` bucket:**

Click "New policy" > "Create a policy from scratch"

Policy 1 - Allow authenticated uploads:
```sql
-- Policy name: Allow authenticated uploads
-- Allowed operation: INSERT
-- Policy definition:
((bucket_id = 'uploads'::text) AND (auth.role() = 'authenticated'::text))
```

Policy 2 - Allow users to read their project files:
```sql
-- Policy name: Allow project member reads
-- Allowed operation: SELECT
-- Policy definition:
((bucket_id = 'uploads'::text) AND (auth.role() = 'authenticated'::text))
```

**For `surveys` bucket:**

Policy 1 - Allow authenticated uploads:
```sql
-- Policy name: Allow authenticated uploads
-- Allowed operation: INSERT
((bucket_id = 'surveys'::text) AND (auth.role() = 'authenticated'::text))
```

Policy 2 - Allow reads:
```sql
-- Policy name: Allow authenticated reads
-- Allowed operation: SELECT
((bucket_id = 'surveys'::text) AND (auth.role() = 'authenticated'::text))
```

### Step 3.3: Checklist

- [x] `uploads` bucket created
- [x] `surveys` bucket created
- [x] Storage policies configured

---

## Phase 4: Supabase Edge Functions

**Estimated time: 1-2 hours**

Edge Functions handle the mobile app authentication.

### Step 4.1: Install Supabase CLI

**Windows (PowerShell as Administrator):**
```powershell
# Using Scoop
scoop bucket add supabase https://github.com/supabase/scoop-bucket.git
scoop install supabase

# OR using npm
npm install -g supabase
```

**Verify installation:**
```powershell
supabase --version
```

### Step 4.2: Initialize Supabase Project Locally

```powershell
# Navigate to your project folder
cd C:\GeoffOffline\GiSTX

# Create supabase folder for edge functions
mkdir supabase
cd supabase

# Initialize (this creates the folder structure)
supabase init
```

### Step 4.3: Login to Supabase

```powershell
supabase login
```

This opens a browser window. Authorize the CLI.

### Step 4.4: Link to Your Project

```powershell
# Get your project ref from Supabase dashboard URL
# URL looks like: https://app.supabase.com/project/abcdefghijklmnop
# The ref is: abcdefghijklmnop

supabase link --project-ref YOUR_PROJECT_REF
```

### Step 4.5: Create App Login Function

```powershell
supabase functions new app-login
```

This creates: `supabase/functions/app-login/index.ts`

### Step 4.6: Edit the Function

Open `supabase/functions/app-login/index.ts` and replace contents with:

```typescript
// supabase/functions/app-login/index.ts

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import * as bcrypt from "https://deno.land/x/bcrypt@v0.4.1/mod.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

serve(async (req) => {
  // Handle CORS preflight
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const { project_code, username, password } = await req.json();

    // Validate input
    if (!project_code || !username || !password) {
      return new Response(
        JSON.stringify({ error: "Missing required fields" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // Create Supabase client with service role (bypasses RLS)
    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
    );

    // 1. Find project by slug
    const { data: project, error: projectError } = await supabase
      .from("projects")
      .select("id, name, slug")
      .eq("slug", project_code.toLowerCase().trim())
      .eq("is_active", true)
      .single();

    if (projectError || !project) {
      return new Response(
        JSON.stringify({ error: "Project not found" }),
        { status: 404, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // 2. Find credentials
    const { data: credential, error: credError } = await supabase
      .from("app_credentials")
      .select("*")
      .eq("project_id", project.id)
      .eq("username", username.trim())
      .eq("is_active", true)
      .single();

    if (credError || !credential) {
      return new Response(
        JSON.stringify({ error: "Invalid username or password" }),
        { status: 401, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // 3. Verify password
    const passwordValid = await bcrypt.compare(password, credential.password_hash);
    if (!passwordValid) {
      return new Response(
        JSON.stringify({ error: "Invalid username or password" }),
        { status: 401, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // 4. Update last used timestamp
    await supabase
      .from("app_credentials")
      .update({ last_used_at: new Date().toISOString() })
      .eq("id", credential.id);

    // 5. Get available surveys
    const { data: surveys } = await supabase
      .from("survey_packages")
      .select("id, name, version, zip_file_path, manifest, updated_at")
      .eq("project_id", project.id)
      .eq("status", "ready")
      .order("updated_at", { ascending: false });

    // 6. Generate signed URLs for survey downloads (valid 24 hours)
    const surveysWithUrls = await Promise.all(
      (surveys || []).map(async (survey) => {
        let downloadUrl = null;
        if (survey.zip_file_path) {
          const { data } = await supabase.storage
            .from("surveys")
            .createSignedUrl(survey.zip_file_path, 86400);
          downloadUrl = data?.signedUrl;
        }

        return {
          id: survey.id,
          name: survey.name,
          version: survey.version,
          manifest: survey.manifest,
          updated_at: survey.updated_at,
          download_url: downloadUrl,
        };
      })
    );

    // 7. Generate session token
    const token = crypto.randomUUID();
    const expiresAt = new Date(Date.now() + 30 * 24 * 60 * 60 * 1000); // 30 days

    await supabase.from("app_sessions").insert({
      credential_id: credential.id,
      project_id: project.id,
      token: token,
      expires_at: expiresAt.toISOString(),
    });

    // 8. Return success response
    return new Response(
      JSON.stringify({
        success: true,
        project: {
          id: project.id,
          name: project.name,
          code: project.slug,
        },
        credential: {
          id: credential.id,
          username: credential.username,
          description: credential.description,
        },
        surveys: surveysWithUrls,
        token: token,
        expires_at: expiresAt.toISOString(),
      }),
      { headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );

  } catch (error) {
    console.error("Error:", error);
    return new Response(
      JSON.stringify({ error: "Internal server error" }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }
});
```

### Step 4.7: Create App Sync Function

```powershell
supabase functions new app-sync
```

Open `supabase/functions/app-sync/index.ts` and replace contents with:

```typescript
// supabase/functions/app-sync/index.ts

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const { token, submissions } = await req.json();

    if (!token || !submissions || !Array.isArray(submissions)) {
      return new Response(
        JSON.stringify({ error: "Missing required fields" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
    );

    // Validate token
    const { data: session, error: sessionError } = await supabase
      .from("app_sessions")
      .select("*, app_credentials(*)")
      .eq("token", token)
      .gt("expires_at", new Date().toISOString())
      .single();

    if (sessionError || !session) {
      return new Response(
        JSON.stringify({ error: "Invalid or expired token" }),
        { status: 401, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // Update session activity
    await supabase
      .from("app_sessions")
      .update({ last_activity_at: new Date().toISOString() })
      .eq("id", session.id);

    // Process submissions
    const results = {
      synced: [] as string[],
      failed: [] as { id: string; error: string }[],
    };

    for (const submission of submissions) {
      try {
        // Upsert submission
        const { error: upsertError } = await supabase
          .from("submissions")
          .upsert(
            {
              project_id: session.project_id,
              survey_package_id: submission.survey_package_id,
              table_name: submission.table_name,
              record_id: submission.record_id,
              local_unique_id: submission.local_unique_id,
              data: submission.data,
              version: submission.version || 1,
              parent_table: submission.parent_table,
              parent_record_id: submission.parent_record_id,
              device_id: submission.device_id,
              surveyor_id: session.app_credentials.username,
              app_version: submission.app_version,
              collected_at: submission.collected_at,
              updated_at: new Date().toISOString(),
            },
            { onConflict: "project_id,table_name,local_unique_id" }
          );

        if (upsertError) {
          results.failed.push({
            id: submission.local_unique_id,
            error: upsertError.message,
          });
        } else {
          results.synced.push(submission.local_unique_id);
        }
      } catch (err) {
        results.failed.push({
          id: submission.local_unique_id,
          error: String(err),
        });
      }
    }

    return new Response(
      JSON.stringify({
        success: true,
        synced_count: results.synced.length,
        failed_count: results.failed.length,
        synced: results.synced,
        failed: results.failed,
      }),
      { headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );

  } catch (error) {
    console.error("Error:", error);
    return new Response(
      JSON.stringify({ error: "Internal server error" }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }
});
```

### Step 4.8: Deploy Edge Functions

```powershell
# Deploy both functions
supabase functions deploy app-login
supabase functions deploy app-sync
```

### Step 4.9: Test Edge Function

You can test in the Supabase dashboard:
1. Go to "Edge Functions"
2. Click on `app-login`
3. Click "Test function"
4. Enter test payload (will fail since no credentials exist yet, but should return proper error)

### Step 4.10: Checklist

- [x] Supabase CLI installed
- [x] CLI logged in and linked to project
- [x] app-login function created and deployed
- [x] app-sync function created and deployed
- [x] Functions appear in Supabase dashboard

---

## Phase 5: Flutter Web Project Setup

**Estimated time: 2-3 hours**

### Step 5.1: Create New Flutter Project

```powershell
# Navigate to your development folder
cd C:\GeoffOffline

# Create new Flutter project
flutter create gistkollect_web

# Enter project folder
cd gistkollect_web
```

### Step 5.2: Add Dependencies

Edit `pubspec.yaml`:

```yaml
name: gistkollect_web
description: GiSTKollect Survey Management Platform
publish_to: 'none'

version: 1.0.0+1

environment:
  sdk: '>=3.2.0 <4.0.0'

dependencies:
  flutter:
    sdk: flutter

  # Supabase
  supabase_flutter: ^2.3.0

  # Navigation
  go_router: ^13.0.0

  # State management
  flutter_riverpod: ^2.4.9

  # File handling
  file_picker: ^6.1.1

  # Excel parsing (for survey generation)
  excel: ^4.0.3

  # XML generation
  xml: ^6.5.0

  # ZIP creation
  archive: ^3.6.1

  # Utilities
  uuid: ^4.2.1
  intl: ^0.18.1
  url_launcher: ^6.2.2
  shared_preferences: ^2.2.2
  crypto: ^3.0.3

dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: ^3.0.0

flutter:
  uses-material-design: true
```

### Step 5.3: Get Dependencies

```powershell
flutter pub get
```

### Step 5.4: Create Folder Structure

Create the following folder structure in `lib/`:

```
lib/
├── main.dart
├── config/
│   ├── supabase_config.dart
│   ├── router.dart
│   └── theme.dart
├── models/
│   ├── user.dart
│   ├── project.dart
│   ├── survey_package.dart
│   ├── crf.dart
│   ├── submission.dart
│   ├── app_credential.dart
│   └── project_member.dart
├── providers/
│   ├── auth_provider.dart
│   ├── project_provider.dart
│   ├── survey_provider.dart
│   └── submission_provider.dart
├── services/
│   ├── auth_service.dart
│   ├── project_service.dart
│   ├── survey_service.dart
│   ├── submission_service.dart
│   ├── storage_service.dart
│   └── xml_generator_service.dart
├── screens/
│   ├── auth/
│   │   ├── login_screen.dart
│   │   ├── register_screen.dart
│   │   └── forgot_password_screen.dart
│   ├── home/
│   │   └── home_screen.dart
│   ├── projects/
│   │   ├── projects_list_screen.dart
│   │   └── create_project_screen.dart
│   ├── dashboard/
│   │   ├── project_dashboard_screen.dart
│   │   ├── surveys_tab.dart
│   │   ├── data_tab.dart
│   │   ├── reports_tab.dart
│   │   └── team_tab.dart
│   └── survey/
│       ├── upload_survey_screen.dart
│       └── survey_detail_screen.dart
└── widgets/
    ├── common/
    │   ├── loading_indicator.dart
    │   ├── error_message.dart
    │   └── empty_state.dart
    ├── layout/
    │   ├── app_scaffold.dart
    │   └── responsive_layout.dart
    └── forms/
        ├── text_input.dart
        └── dropdown_input.dart
```

### Step 5.5: Create Configuration Files

**lib/config/supabase_config.dart:**

```dart
class SupabaseConfig {
  static const String url = 'YOUR_SUPABASE_URL';  // Replace with your URL
  static const String anonKey = 'YOUR_ANON_KEY';  // Replace with your anon key
}
```

**lib/main.dart:**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'config/supabase_config.dart';
import 'config/router.dart';
import 'config/theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: SupabaseConfig.url,
    anonKey: SupabaseConfig.anonKey,
  );

  runApp(
    const ProviderScope(
      child: GiSTKollectApp(),
    ),
  );
}

class GiSTKollectApp extends StatelessWidget {
  const GiSTKollectApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'GiSTKollect',
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.system,
      routerConfig: router,
      debugShowCheckedModeBanner: false,
    );
  }
}
```

**lib/config/theme.dart:**

```dart
import 'package:flutter/material.dart';

class AppTheme {
  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF2563EB),  // Blue
        brightness: Brightness.light,
      ),
      appBarTheme: const AppBarTheme(
        centerTitle: false,
        elevation: 0,
      ),
      cardTheme: CardTheme(
        elevation: 1,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        filled: true,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      ),
    );
  }

  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF2563EB),
        brightness: Brightness.dark,
      ),
      appBarTheme: const AppBarTheme(
        centerTitle: false,
        elevation: 0,
      ),
      cardTheme: CardTheme(
        elevation: 1,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        filled: true,
      ),
    );
  }
}
```

**lib/config/router.dart:**

```dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../screens/auth/login_screen.dart';
import '../screens/auth/register_screen.dart';
import '../screens/home/home_screen.dart';
import '../screens/projects/projects_list_screen.dart';
import '../screens/projects/create_project_screen.dart';
import '../screens/dashboard/project_dashboard_screen.dart';

final router = GoRouter(
  initialLocation: '/',
  redirect: (context, state) {
    final session = Supabase.instance.client.auth.currentSession;
    final isLoggedIn = session != null;
    final isAuthRoute = state.matchedLocation == '/login' ||
                        state.matchedLocation == '/register';

    if (!isLoggedIn && !isAuthRoute) {
      return '/login';
    }
    if (isLoggedIn && isAuthRoute) {
      return '/';
    }
    return null;
  },
  routes: [
    GoRoute(
      path: '/',
      builder: (context, state) => const HomeScreen(),
    ),
    GoRoute(
      path: '/login',
      builder: (context, state) => const LoginScreen(),
    ),
    GoRoute(
      path: '/register',
      builder: (context, state) => const RegisterScreen(),
    ),
    GoRoute(
      path: '/projects',
      builder: (context, state) => const ProjectsListScreen(),
    ),
    GoRoute(
      path: '/projects/new',
      builder: (context, state) => const CreateProjectScreen(),
    ),
    GoRoute(
      path: '/projects/:id',
      builder: (context, state) {
        final projectId = state.pathParameters['id']!;
        return ProjectDashboardScreen(projectId: projectId);
      },
    ),
  ],
);
```

### Step 5.6: Test the Project

```powershell
# Run in Chrome for web testing
flutter run -d chrome
```

You should see a blank login screen (we'll build it in the next phase).

### Step 5.7: Checklist

- [ ] Flutter project created
- [ ] Dependencies added and fetched
- [ ] Folder structure created
- [ ] Configuration files created
- [ ] Project runs without errors

---

## Phase 6: Web App - Authentication

**Estimated time: 3-4 hours**

### Step 6.1: Create Auth Service

**lib/services/auth_service.dart:**

```dart
import 'package:supabase_flutter/supabase_flutter.dart';

class AuthService {
  final SupabaseClient _supabase = Supabase.instance.client;

  User? get currentUser => _supabase.auth.currentUser;

  Stream<AuthState> get authStateChanges => _supabase.auth.onAuthStateChange;

  Future<AuthResponse> signUp({
    required String email,
    required String password,
    String? fullName,
  }) async {
    return await _supabase.auth.signUp(
      email: email,
      password: password,
      data: {'full_name': fullName},
    );
  }

  Future<AuthResponse> signIn({
    required String email,
    required String password,
  }) async {
    return await _supabase.auth.signInWithPassword(
      email: email,
      password: password,
    );
  }

  Future<void> signOut() async {
    await _supabase.auth.signOut();
  }

  Future<void> resetPassword(String email) async {
    await _supabase.auth.resetPasswordForEmail(email);
  }

  Future<UserResponse> updateProfile({
    String? fullName,
    String? organization,
  }) async {
    // Update auth metadata
    final response = await _supabase.auth.updateUser(
      UserAttributes(data: {'full_name': fullName}),
    );

    // Update profile table
    if (currentUser != null) {
      await _supabase.from('profiles').update({
        'full_name': fullName,
        'organization': organization,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', currentUser!.id);
    }

    return response;
  }

  Future<Map<String, dynamic>?> getProfile() async {
    if (currentUser == null) return null;

    final response = await _supabase
        .from('profiles')
        .select()
        .eq('id', currentUser!.id)
        .single();

    return response;
  }
}
```

### Step 6.2: Create Auth Provider

**lib/providers/auth_provider.dart:**

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/auth_service.dart';

final authServiceProvider = Provider<AuthService>((ref) => AuthService());

final currentUserProvider = StreamProvider<User?>((ref) {
  final authService = ref.watch(authServiceProvider);
  return authService.authStateChanges.map((state) => state.session?.user);
});

final userProfileProvider = FutureProvider<Map<String, dynamic>?>((ref) async {
  final authService = ref.watch(authServiceProvider);
  return await authService.getProfile();
});
```

### Step 6.3: Create Login Screen

**lib/screens/auth/login_screen.dart:**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../providers/auth_provider.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _isLoading = false;
  bool _obscurePassword = true;
  String? _errorMessage;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final authService = ref.read(authServiceProvider);
      await authService.signIn(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );

      if (mounted) {
        context.go('/');
      }
    } catch (e) {
      setState(() {
        _errorMessage = e.toString().contains('Invalid login')
            ? 'Invalid email or password'
            : 'An error occurred. Please try again.';
      });
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Logo
                  Icon(
                    Icons.assignment,
                    size: 80,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'GiSTKollect',
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Survey Management Platform',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Colors.grey,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 48),

                  // Email field
                  TextFormField(
                    controller: _emailController,
                    decoration: const InputDecoration(
                      labelText: 'Email',
                      prefixIcon: Icon(Icons.email_outlined),
                    ),
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Please enter your email';
                      }
                      if (!value.contains('@')) {
                        return 'Please enter a valid email';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),

                  // Password field
                  TextFormField(
                    controller: _passwordController,
                    decoration: InputDecoration(
                      labelText: 'Password',
                      prefixIcon: const Icon(Icons.lock_outlined),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscurePassword
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                        ),
                        onPressed: () {
                          setState(() => _obscurePassword = !_obscurePassword);
                        },
                      ),
                    ),
                    obscureText: _obscurePassword,
                    textInputAction: TextInputAction.done,
                    onFieldSubmitted: (_) => _login(),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Please enter your password';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 8),

                  // Forgot password link
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () {
                        // TODO: Implement forgot password
                      },
                      child: const Text('Forgot password?'),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Error message
                  if (_errorMessage != null)
                    Container(
                      padding: const EdgeInsets.all(12),
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.red.shade200),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.error_outline, color: Colors.red.shade700),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _errorMessage!,
                              style: TextStyle(color: Colors.red.shade700),
                            ),
                          ),
                        ],
                      ),
                    ),

                  // Login button
                  ElevatedButton(
                    onPressed: _isLoading ? null : _login,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Sign In'),
                  ),
                  const SizedBox(height: 24),

                  // Register link
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text("Don't have an account?"),
                      TextButton(
                        onPressed: () => context.go('/register'),
                        child: const Text('Sign Up'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
```

### Step 6.4: Create Register Screen

**lib/screens/auth/register_screen.dart:**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../providers/auth_provider.dart';

class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _isLoading = false;
  bool _obscurePassword = true;
  String? _errorMessage;
  bool _registrationSuccess = false;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _register() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final authService = ref.read(authServiceProvider);
      await authService.signUp(
        email: _emailController.text.trim(),
        password: _passwordController.text,
        fullName: _nameController.text.trim(),
      );

      setState(() => _registrationSuccess = true);
    } catch (e) {
      setState(() {
        _errorMessage = e.toString().contains('already registered')
            ? 'This email is already registered'
            : 'Registration failed. Please try again.';
      });
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_registrationSuccess) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.mark_email_read_outlined,
                  size: 80,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(height: 24),
                Text(
                  'Check your email',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                Text(
                  'We sent a confirmation link to ${_emailController.text}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.grey),
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: () => context.go('/login'),
                  child: const Text('Back to Login'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Logo
                  Icon(
                    Icons.assignment,
                    size: 80,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Create Account',
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 48),

                  // Name field
                  TextFormField(
                    controller: _nameController,
                    decoration: const InputDecoration(
                      labelText: 'Full Name',
                      prefixIcon: Icon(Icons.person_outlined),
                    ),
                    textInputAction: TextInputAction.next,
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Please enter your name';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),

                  // Email field
                  TextFormField(
                    controller: _emailController,
                    decoration: const InputDecoration(
                      labelText: 'Email',
                      prefixIcon: Icon(Icons.email_outlined),
                    ),
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Please enter your email';
                      }
                      if (!value.contains('@')) {
                        return 'Please enter a valid email';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),

                  // Password field
                  TextFormField(
                    controller: _passwordController,
                    decoration: InputDecoration(
                      labelText: 'Password',
                      prefixIcon: const Icon(Icons.lock_outlined),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscurePassword
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                        ),
                        onPressed: () {
                          setState(() => _obscurePassword = !_obscurePassword);
                        },
                      ),
                    ),
                    obscureText: _obscurePassword,
                    textInputAction: TextInputAction.next,
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Please enter a password';
                      }
                      if (value.length < 6) {
                        return 'Password must be at least 6 characters';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),

                  // Confirm password field
                  TextFormField(
                    controller: _confirmPasswordController,
                    decoration: const InputDecoration(
                      labelText: 'Confirm Password',
                      prefixIcon: Icon(Icons.lock_outlined),
                    ),
                    obscureText: _obscurePassword,
                    textInputAction: TextInputAction.done,
                    onFieldSubmitted: (_) => _register(),
                    validator: (value) {
                      if (value != _passwordController.text) {
                        return 'Passwords do not match';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 24),

                  // Error message
                  if (_errorMessage != null)
                    Container(
                      padding: const EdgeInsets.all(12),
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.red.shade200),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.error_outline, color: Colors.red.shade700),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _errorMessage!,
                              style: TextStyle(color: Colors.red.shade700),
                            ),
                          ),
                        ],
                      ),
                    ),

                  // Register button
                  ElevatedButton(
                    onPressed: _isLoading ? null : _register,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Create Account'),
                  ),
                  const SizedBox(height: 24),

                  // Login link
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text('Already have an account?'),
                      TextButton(
                        onPressed: () => context.go('/login'),
                        child: const Text('Sign In'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
```

### Step 6.5: Create Home Screen (Temporary)

**lib/screens/home/home_screen.dart:**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../providers/auth_provider.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userAsync = ref.watch(currentUserProvider);
    final authService = ref.read(authServiceProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('GiSTKollect'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await authService.signOut();
              if (context.mounted) {
                context.go('/login');
              }
            },
          ),
        ],
      ),
      body: Center(
        child: userAsync.when(
          data: (user) => Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('Welcome, ${user?.email ?? "User"}!'),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () => context.go('/projects'),
                child: const Text('View Projects'),
              ),
            ],
          ),
          loading: () => const CircularProgressIndicator(),
          error: (e, _) => Text('Error: $e'),
        ),
      ),
    );
  }
}
```

### Step 6.6: Test Authentication

```powershell
flutter run -d chrome
```

1. Test registration - create a new account
2. Check email for confirmation link
3. Test login with the new account
4. Test logout

### Step 6.7: Checklist

- [ ] Auth service created
- [ ] Auth provider created
- [ ] Login screen created and working
- [ ] Register screen created and working
- [ ] Home screen shows logged-in user
- [ ] Logout works correctly

---

## Phase 7-15: Remaining Implementation

The implementation continues in the same detailed fashion. Due to length constraints, I'll summarize the remaining phases. Each phase should be implemented fully before moving to the next.

---

## Phase 7: Web App - Projects Management

**Key files to create:**
- `lib/services/project_service.dart` - CRUD operations for projects
- `lib/providers/project_provider.dart` - State management
- `lib/models/project.dart` - Project data model
- `lib/screens/projects/projects_list_screen.dart` - List all user's projects
- `lib/screens/projects/create_project_screen.dart` - Create new project

**Key features:**
- List all projects user is a member of
- Create new project (auto-creates owner membership)
- Edit project details
- Navigate to project dashboard

---

## Phase 8: Web App - Survey Management

**Key files to create:**
- `lib/services/survey_service.dart` - Survey CRUD and file handling
- `lib/services/xml_generator_service.dart` - Port XML generation from GiSTConfigX
- `lib/screens/dashboard/surveys_tab.dart` - List surveys
- `lib/screens/survey/upload_survey_screen.dart` - Upload Excel/CSV, generate ZIP

**Key features:**
- List all surveys for a project
- Upload Excel file + CSV files
- Parse Excel and generate XML + manifest
- Create ZIP and upload to Supabase Storage
- Download survey ZIP files

---

## Phase 9: Web App - Team & Credentials

**Key files to create:**
- `lib/services/team_service.dart` - Member management
- `lib/services/credential_service.dart` - App credential management
- `lib/screens/dashboard/team_tab.dart` - Manage members and credentials

**Key features:**
- List project members with roles
- Invite new members (by email)
- Change member roles
- Remove members
- Create app credentials (username/password)
- View/deactivate app credentials

---

## Phase 10: Web App - Data Viewing

**Key files to create:**
- `lib/services/submission_service.dart` - Query submissions
- `lib/screens/dashboard/data_tab.dart` - View and export data
- `lib/screens/dashboard/reports_tab.dart` - Basic reports/charts

**Key features:**
- Select CRF/form to view
- Display submissions in data table
- Search and filter data
- Export to CSV
- View submission history/audit log
- Basic statistics (counts by surveyor, by date)

---

## Phase 11: Mobile App - Rename & Rebrand

**Changes to GiSTX:**
- Rename app to GiSTKollect
- Update `pubspec.yaml` name
- Update Android `app/build.gradle` applicationId
- Update iOS bundle identifier
- Update Windows installer
- Update app icons and splash screen
- Update all user-facing text

---

## Phase 12: Mobile App - Authentication

**New/modified files:**
- `lib/screens/app_login_screen.dart` - New login screen
- `lib/services/app_auth_service.dart` - Handle app authentication
- `lib/config/supabase_config.dart` - Supabase configuration

**Key features:**
- Project code + username + password login
- Call app-login Edge Function
- Store credentials locally
- Remember project code and username
- Offline capability after initial login

---

## Phase 13: Mobile App - Survey Download

**New/modified files:**
- `lib/services/survey_download_service.dart` - Download from Supabase
- `lib/screens/survey_selector_screen.dart` - List available surveys

**Key features:**
- Show available surveys from login response
- Download survey ZIP from signed URL
- Extract and install survey locally
- Check for survey updates

---

## Phase 14: Mobile App - Data Sync

**New/modified files:**
- `lib/services/supabase_sync_service.dart` - Sync to Supabase
- Modify `lib/services/db_service.dart` - Add sync_status column
- `lib/screens/sync_screen.dart` - Update sync UI

**Key features:**
- Track sync_status per record (pending, synced, modified, error)
- Batch sync with progress indication
- Retry failed records
- Mark as modified when record edited
- Call app-sync Edge Function

---

## Phase 15: Testing & Deployment

### Web Deployment

**Option A: Vercel**
```powershell
# Build web app
flutter build web

# Install Vercel CLI
npm install -g vercel

# Deploy
cd build/web
vercel
```

**Option B: Firebase Hosting**
```powershell
# Install Firebase CLI
npm install -g firebase-tools

# Login and init
firebase login
firebase init hosting

# Build and deploy
flutter build web
firebase deploy
```

### Mobile App Deployment

**Android:**
```powershell
flutter build apk --release
flutter build appbundle --release
```

**Windows:**
```powershell
flutter build windows --release
# Run Inno Setup to create installer
```

### Domain Configuration

1. Point domain to hosting provider
2. Configure SSL certificate
3. Update Supabase allowed domains

---

## Quick Reference: Important URLs and Keys

After setup, you'll need these values in multiple places:

```
SUPABASE
========
Project URL: https://xxxxx.supabase.co
Anon Key: eyJhbGciOiJI... (public, OK to expose)
Service Role Key: eyJhbGciOiJI... (SECRET, server-side only)

EDGE FUNCTIONS
==============
App Login: https://xxxxx.supabase.co/functions/v1/app-login
App Sync: https://xxxxx.supabase.co/functions/v1/app-sync

WEB APP
=======
URL: https://gistkollect.org (after deployment)

STORAGE BUCKETS
===============
Uploads: uploads
Surveys: surveys
```

---

## Troubleshooting Common Issues

### Supabase

**RLS blocking queries:**
- Check that user is authenticated
- Verify RLS policies are correct
- Use Supabase dashboard to test queries

**Edge Function errors:**
- Check function logs in Supabase dashboard
- Verify environment variables are set
- Test with curl or Postman

### Flutter Web

**CORS errors:**
- Supabase handles CORS automatically
- Check that URLs are correct

**Build errors:**
- Run `flutter clean` then `flutter pub get`
- Check Dart SDK version compatibility

### Mobile App

**Sync failures:**
- Check network connectivity
- Verify token hasn't expired
- Check Supabase logs for errors

---

## Summary Checklist

### Phase 1: Domain & Accounts
- [ ] Domain registered
- [ ] Supabase account created
- [ ] Supabase project created
- [ ] Credentials saved securely

### Phase 2: Database Setup
- [ ] Schema SQL executed
- [ ] All tables created
- [ ] Triggers working
- [ ] RLS policies active

### Phase 3: Storage Setup
- [ ] Buckets created
- [ ] Storage policies configured

### Phase 4: Edge Functions
- [ ] CLI installed and linked
- [ ] app-login deployed
- [ ] app-sync deployed

### Phase 5: Flutter Web Setup
- [ ] Project created
- [ ] Dependencies added
- [ ] Folder structure created
- [ ] Basic config files created

### Phase 6: Authentication
- [ ] Auth service created
- [ ] Login screen working
- [ ] Register screen working
- [ ] Email confirmation working

### Phase 7: Projects
- [ ] Project list screen
- [ ] Create project screen
- [ ] Project CRUD working

### Phase 8: Surveys
- [ ] Survey list screen
- [ ] Upload screen
- [ ] XML generation working
- [ ] ZIP creation working

### Phase 9: Team
- [ ] Member management working
- [ ] App credentials working

### Phase 10: Data
- [ ] Data viewing screen
- [ ] Export working
- [ ] Reports screen

### Phase 11: Mobile Rebrand
- [ ] App renamed
- [ ] Icons updated
- [ ] All text updated

### Phase 12: Mobile Auth
- [ ] Login screen added
- [ ] Auth service working
- [ ] Credentials remembered

### Phase 13: Survey Download
- [ ] Download from Supabase working
- [ ] Survey installation working

### Phase 14: Data Sync
- [ ] Sync status tracking
- [ ] Sync to Supabase working
- [ ] Sync UI updated

### Phase 15: Deployment
- [ ] Web app deployed
- [ ] Domain configured
- [ ] Mobile apps built
- [ ] End-to-end testing complete

---

## Next Steps After Completion

1. **User testing** - Have your team test the full workflow
2. **Bug fixes** - Address any issues found
3. **Documentation** - Create user guides
4. **Monitoring** - Set up error tracking (Sentry)
5. **Backups** - Configure database backups
6. **Future features:**
   - QR code login
   - Visual survey builder
   - Advanced reports
   - API for external integrations

---

*Document created: 2024*
*GiSTKollect Implementation Plan v1.0*
