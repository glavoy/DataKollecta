# Website/Backend Sync Implementation Guide

This document provides complete instructions for implementing the data sync functionality on the Supabase backend to receive data from the DataKollecta mobile app.

## Overview

The mobile app uploads data to the server via a Supabase Edge Function (`app-sync`). The server:
1. Validates the session token
2. Upserts submission data into the `submissions` table
3. Upserts audit log entries into the `formchanges` table
4. Returns success/failure status for each record

---

## 1. Database Schema Changes

### 1.1 Rename `submission_history` to `formchanges`

The existing `submission_history` table should be replaced with a `formchanges` table that stores field-level audit logs.

```sql
-- Drop the old table (backup data first if needed)
DROP TABLE IF EXISTS submission_history;

-- Create the new formchanges table
CREATE TABLE formchanges (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    formchanges_uuid TEXT NOT NULL UNIQUE,
    project_id UUID NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
    record_uuid TEXT NOT NULL,
    tablename TEXT NOT NULL,
    fieldname TEXT NOT NULL,
    oldvalue TEXT,
    newvalue TEXT,
    surveyor_id TEXT,
    changed_at TIMESTAMPTZ,
    synced_at TIMESTAMPTZ DEFAULT NOW(),
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Create indexes for performance
CREATE INDEX idx_formchanges_project ON formchanges(project_id);
CREATE INDEX idx_formchanges_record ON formchanges(record_uuid);
CREATE INDEX idx_formchanges_uuid ON formchanges(formchanges_uuid);
CREATE INDEX idx_formchanges_tablename ON formchanges(tablename);
```

### 1.2 Row Level Security (RLS) for formchanges

```sql
-- Enable RLS
ALTER TABLE formchanges ENABLE ROW LEVEL SECURITY;

-- Users can view formchanges for their projects
CREATE POLICY "Users can view project formchanges" ON formchanges
    FOR SELECT USING (
        EXISTS (
            SELECT 1 FROM project_members pm
            WHERE pm.project_id = formchanges.project_id
            AND pm.user_id = auth.uid()
        )
    );

-- Editors and owners can manage formchanges
CREATE POLICY "Editors can manage formchanges" ON formchanges
    FOR ALL USING (
        EXISTS (
            SELECT 1 FROM project_members pm
            WHERE pm.project_id = formchanges.project_id
            AND pm.user_id = auth.uid()
            AND pm.role IN ('editor', 'owner')
        )
    );
```

### 1.3 Ensure submissions table has unique constraint

The `submissions` table needs a unique constraint for upserts:

```sql
-- Add unique constraint if not exists
ALTER TABLE submissions
ADD CONSTRAINT submissions_unique_local_id
UNIQUE (project_id, table_name, local_unique_id);
```

---

## 2. Edge Function: `app-sync`

Deploy this Edge Function to handle data uploads from the mobile app.

### 2.1 Function Code

```typescript
// supabase/functions/app-sync/index.ts

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

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
        const { token, submissions, formchanges } = await req.json();

        // Validate required fields
        if (!token || (!submissions && !formchanges)) {
            return new Response(
                JSON.stringify({ error: "Missing required fields: token and (submissions or formchanges)" }),
                { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
            );
        }

        // Create Supabase client with service role
        const supabase = createClient(
            Deno.env.get("SUPABASE_URL")!,
            Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
        );

        // Validate session token
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

        // Update session activity timestamp
        await supabase
            .from("app_sessions")
            .update({ last_activity_at: new Date().toISOString() })
            .eq("id", session.id);

        // Initialize results
        const results = {
            synced: [] as string[],
            failed: [] as { id: string; error: string }[],
            formchanges_synced: [] as string[],
            formchanges_failed: [] as { id: string; error: string }[],
        };

        // Process Submissions
        if (submissions && Array.isArray(submissions)) {
            for (const submission of submissions) {
                try {
                    const { error: upsertError } = await supabase
                        .from("submissions")
                        .upsert(
                            {
                                project_id: session.project_id,
                                survey_package_id: submission.survey_package_id,
                                table_name: submission.table_name,
                                local_unique_id: submission.local_uuid,
                                data: submission.data,
                                version: 1,
                                device_id: submission.device_id,
                                surveyor_id: session.app_credentials.username,
                                app_version: submission.swver,
                                collected_at: submission.collected_at,
                                updated_at: new Date().toISOString(),
                            },
                            { onConflict: "project_id,table_name,local_unique_id" }
                        );

                    if (upsertError) {
                        results.failed.push({
                            id: submission.local_uuid,
                            error: upsertError.message,
                        });
                    } else {
                        results.synced.push(submission.local_uuid);
                    }
                } catch (err) {
                    results.failed.push({
                        id: submission.local_uuid,
                        error: String(err),
                    });
                }
            }
        }

        // Process Formchanges
        if (formchanges && Array.isArray(formchanges)) {
            for (const change of formchanges) {
                try {
                    const { error: formchangeError } = await supabase
                        .from("formchanges")
                        .upsert(
                            {
                                formchanges_uuid: change.formchanges_uuid,
                                project_id: session.project_id,
                                record_uuid: change.record_uuid,
                                tablename: change.tablename,
                                fieldname: change.fieldname,
                                oldvalue: change.oldvalue,
                                newvalue: change.newvalue,
                                surveyor_id: change.surveyor_id || session.app_credentials.username,
                                changed_at: change.changed_at,
                                synced_at: new Date().toISOString(),
                            },
                            { onConflict: "formchanges_uuid" }
                        );

                    if (formchangeError) {
                        results.formchanges_failed.push({
                            id: change.formchanges_uuid,
                            error: formchangeError.message,
                        });
                    } else {
                        results.formchanges_synced.push(change.formchanges_uuid);
                    }
                } catch (err) {
                    results.formchanges_failed.push({
                        id: change.formchanges_uuid,
                        error: String(err),
                    });
                }
            }
        }

        // Return results
        return new Response(
            JSON.stringify({
                success: true,
                synced_count: results.synced.length,
                failed_count: results.failed.length,
                synced: results.synced,
                failed: results.failed,
                formchanges_synced: results.formchanges_synced,
                formchanges_failed: results.formchanges_failed,
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

### 2.2 Deploy the Edge Function

```bash
# Navigate to your Supabase project
cd your-supabase-project

# Deploy the function
supabase functions deploy app-sync
```

---

## 3. API Specification

### 3.1 Endpoint

```
POST https://[PROJECT_ID].supabase.co/functions/v1/app-sync
```

### 3.2 Request Headers

| Header | Value | Required |
|--------|-------|----------|
| `Content-Type` | `application/json` | Yes |
| `Authorization` | `Bearer [SUPABASE_ANON_KEY]` | Yes |

### 3.3 Request Body

```typescript
interface SyncRequest {
    token: string;                    // Session token from app-login
    submissions?: Submission[];       // Array of submission records
    formchanges?: FormChange[];       // Array of form changes (optional)
}

interface Submission {
    table_name: string;               // Name of the CRF table (e.g., "enrollee")
    local_uuid: string;               // UUID from the mobile app's record
    data: Record<string, any>;        // All field values (includes survey_id for lookup)
    collected_at: string;             // ISO timestamp when data was collected
    swver: string;                    // App version string
    device_id: string;                // Device identifier
}

interface FormChange {
    formchanges_uuid: string;         // Unique ID for this change record
    record_uuid: string;              // UUID of the parent submission
    tablename: string;                // CRF table name
    fieldname: string;                // Field that was changed
    oldvalue: string | null;          // Previous value
    newvalue: string | null;          // New value
    surveyor_id: string;              // User who made the change
    changed_at: string;               // ISO timestamp of the change
}
```

### 3.4 Response Body

```typescript
interface SyncResponse {
    success: boolean;
    synced_count: number;             // Number of successfully synced submissions
    failed_count: number;             // Number of failed submissions
    synced: string[];                 // UUIDs of synced submissions
    failed: FailedRecord[];           // Details of failed submissions
    formchanges_synced: string[];     // UUIDs of synced formchanges
    formchanges_failed: FailedRecord[]; // Details of failed formchanges
}

interface FailedRecord {
    id: string;                       // UUID that failed
    error: string;                    // Error message
}
```

---

## 4. Data Flow

```
┌─────────────────┐         ┌─────────────────┐         ┌─────────────────┐
│   Mobile App    │         │  Edge Function  │         │    Supabase     │
│  (DataKollecta) │         │   (app-sync)    │         │    Database     │
└────────┬────────┘         └────────┬────────┘         └────────┬────────┘
         │                           │                           │
         │  POST /app-sync           │                           │
         │  {token, submissions,     │                           │
         │   formchanges}            │                           │
         │ ─────────────────────────>│                           │
         │                           │                           │
         │                           │  Validate token           │
         │                           │ ─────────────────────────>│
         │                           │                           │
         │                           │  Token valid              │
         │                           │ <─────────────────────────│
         │                           │                           │
         │                           │  Upsert submissions       │
         │                           │ ─────────────────────────>│
         │                           │                           │
         │                           │  Upsert formchanges       │
         │                           │ ─────────────────────────>│
         │                           │                           │
         │                           │  Results                  │
         │                           │ <─────────────────────────│
         │                           │                           │
         │  {synced: [...],          │                           │
         │   failed: [...],          │                           │
         │   formchanges_synced:[]}  │                           │
         │ <─────────────────────────│                           │
         │                           │                           │
         │  Update local synced_at   │                           │
         │  for successful records   │                           │
         │                           │                           │
```

---

## 5. Website Features to Implement

### 5.1 View Submissions

Display submitted data from the `submissions` table:

```sql
-- Get all submissions for a project
SELECT
    s.id,
    s.table_name,
    s.local_unique_id,
    s.data,
    s.surveyor_id,
    s.collected_at,
    s.updated_at,
    sp.name as survey_name
FROM submissions s
JOIN survey_packages sp ON s.survey_package_id = sp.id
WHERE s.project_id = '[PROJECT_UUID]'
ORDER BY s.collected_at DESC;
```

### 5.2 View Form Changes (Audit Log)

Display the audit trail for a specific record:

```sql
-- Get change history for a record
SELECT
    fc.fieldname,
    fc.oldvalue,
    fc.newvalue,
    fc.surveyor_id,
    fc.changed_at
FROM formchanges fc
WHERE fc.record_uuid = '[RECORD_UUID]'
ORDER BY fc.changed_at ASC;
```

### 5.3 Export Data

Export submissions as CSV or JSON:

```typescript
// Example: Export all enrollee data
const { data, error } = await supabase
    .from('submissions')
    .select('data')
    .eq('project_id', projectId)
    .eq('table_name', 'enrollee');

// Flatten the data object for CSV export
const flatData = data.map(row => row.data);
```

### 5.4 Sync Status Dashboard

Show sync statistics:

```sql
-- Count records by table and sync status
SELECT
    table_name,
    COUNT(*) as total_records,
    MAX(updated_at) as last_sync
FROM submissions
WHERE project_id = '[PROJECT_UUID]'
GROUP BY table_name;
```

---

## 6. Security Considerations

1. **Token Validation**: Always validate the session token before processing data
2. **Project Isolation**: Use RLS policies to ensure users can only access their project's data
3. **Service Role Key**: The Edge Function uses the service role key - keep it secure
4. **Input Validation**: Validate all input data before inserting into the database
5. **Rate Limiting**: Consider implementing rate limiting for the sync endpoint

---

## 7. Troubleshooting

### Common Issues

| Issue | Cause | Solution |
|-------|-------|----------|
| 401 Unauthorized | Token expired | User needs to re-authenticate |
| Duplicate key violation | Record already exists | Handled by upsert (updates existing) |
| Foreign key violation | Invalid survey_package_id | Check manifest has correct ID |
| Missing formchanges_uuid | Old mobile app version | Update mobile app |

### Debugging

Enable logging in the Edge Function:

```typescript
console.log('Received payload:', JSON.stringify({ token: '***', submissions: submissions?.length, formchanges: formchanges?.length }));
```

Check Supabase logs:
```bash
supabase functions logs app-sync
```

---

## 8. Summary of Required Changes

| Component | Action |
|-----------|--------|
| **Database** | Create `formchanges` table (replace `submission_history`) |
| **Database** | Add RLS policies for `formchanges` table |
| **Database** | Ensure unique constraint on `submissions` table |
| **Edge Function** | Deploy updated `app-sync` function |
| **Website** | Add views for submissions and formchanges |
| **Website** | Add export functionality |
| **Website** | Add sync status dashboard |

---

## 9. Testing

### Test the Edge Function

```bash
curl -X POST 'https://[PROJECT_ID].supabase.co/functions/v1/app-sync' \
  -H 'Content-Type: application/json' \
  -H 'Authorization: Bearer [ANON_KEY]' \
  -d '{
    "token": "[VALID_SESSION_TOKEN]",
    "submissions": [{
      "survey_package_id": "[SURVEY_PACKAGE_UUID]",
      "table_name": "enrollee",
      "local_uuid": "test-uuid-123",
      "data": {"name": "Test User", "age": 25},
      "collected_at": "2026-01-12T10:00:00Z",
      "swver": "DataKollecta 1.0.0",
      "device_id": "test-device"
    }]
  }'
```

Expected response:
```json
{
  "success": true,
  "synced_count": 1,
  "failed_count": 0,
  "synced": ["test-uuid-123"],
  "failed": [],
  "formchanges_synced": [],
  "formchanges_failed": []
}
```
