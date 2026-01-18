# Mobile Data Upload Implementation Instructions

**Objective**: Implement a robust sync process to upload collected data (`submissions`) and audit logs (`formchanges`) to the Supabase backend.

## 1. Upload Logic & Protocol

### A. Batching Strategy
*   **Batch Size**: Upload **10 records** per request.
*   **Frequency**: Manually triggered by the user when they click the 'Upload Data' button from the Sync Center.
*   **Order**: Upload submissions from each CRF table sequentially. Include formchanges with the first batch only.

### B. Selecting Data to Upload
Select records where `synced_at` is `NULL`.

```sql
-- For CRF tables (e.g., enrollee, household, etc.)
SELECT * FROM enrollee WHERE synced_at IS NULL LIMIT 10;

-- For formchanges
SELECT * FROM formchanges WHERE synced_at IS NULL LIMIT 100;
```

### C. JSON Payload Structure
Send a **POST** request to: `https://qetzeqyuuiposzseqwvb.supabase.co/functions/v1/app-sync`

**Headers**:
*   `Authorization`: `Bearer [SUPABASE_ANON_KEY]`
*   `Content-Type`: `application/json`

**Body**:
```json
{
  "token": "[USER_SESSION_TOKEN]",
  "submissions": [
    {
      "table_name": "enrollee",
      "local_uuid": "e391d84f-be8d-7b90-8d7a-617226a0f28b",
      "data": {
        "uuid": "e391d84f-be8d-7b90-8d7a-617226a0f28b",
        "hhid": "096-001-01",
        "subjid": "096-001-01-0001",
        "name": "John Doe",
        "age": 45,
        "starttime": "2026-01-12T08:30:00",
        "startdate": "2026-01-12",
        "stoptime": "2026-01-12T08:45:00",
        "lastmod": "2026-01-12T08:45:00",
        "swver": "DataKollecta 1.0.2",
        "survey_id": "r21_test_negative_2025-12-30"
      },
      "collected_at": "2026-01-12T08:45:00",
      "swver": "DataKollecta 1.0.2",
      "device_id": "device-uuid-string"
    }
  ],
  "formchanges": [
    {
      "formchanges_uuid": "fc-uuid-1234-5678",
      "record_uuid": "e391d84f-be8d-7b90-8d7a-617226a0f28b",
      "tablename": "enrollee",
      "fieldname": "age",
      "oldvalue": "44",
      "newvalue": "45",
      "surveyor_id": "user123",
      "changed_at": "2026-01-12T10:30:00.000Z"
    }
  ]
}
```

**Notes**:
- The `formchanges` array is **optional**. Only include it when there are unsynced formchanges.
- The `data` object in submissions contains ALL fields from the local record (except `synced_at`).
- The `local_uuid` is the `uuid` field from the local CRF table.

## 2. Handling the Response

The server returns a JSON object indicating which records were successfully synced.

**Success Response (HTTP 200)**:
```json
{
  "success": true,
  "synced_count": 10,
  "failed_count": 0,
  "synced": ["uuid-1", "uuid-2", "uuid-3", ...],
  "failed": [],
  "formchanges_synced": ["fc-uuid-1", "fc-uuid-2"],
  "formchanges_failed": []
}
```

**Partial Failure Response (HTTP 200)**:
```json
{
  "success": true,
  "synced_count": 8,
  "failed_count": 2,
  "synced": ["uuid-1", "uuid-2", ...],
  "failed": [
    { "id": "uuid-9", "error": "Duplicate key violation" },
    { "id": "uuid-10", "error": "Invalid data format" }
  ],
  "formchanges_synced": ["fc-uuid-1"],
  "formchanges_failed": [
    { "id": "fc-uuid-2", "error": "Parent record not found" }
  ]
}
```

**Error Responses**:
- **401 Unauthorized**: Token expired or invalid. Prompt user to reconnect.
- **400 Bad Request**: Missing required fields in payload.
- **500 Internal Server Error**: Server-side issue. Retry later.

## 3. Updating Local State (CRITICAL)

After receiving a successful response:

1. **Parse** the `synced` array (contains UUIDs of successfully synced submissions).
2. **Update** the CRF table to mark those records as synced:
   ```sql
   UPDATE enrollee SET synced_at = '2026-01-12T18:23:41.064352' WHERE uuid IN ('uuid-1', 'uuid-2', ...);
   ```

3. **Parse** the `formchanges_synced` array (contains formchanges_uuid values).
4. **Update** the formchanges table:
   ```sql
   UPDATE formchanges SET synced_at = '2026-01-12T18:23:41.064352' WHERE formchanges_uuid IN ('fc-uuid-1', 'fc-uuid-2', ...);
   ```

5. **Do NOT** update records listed in `failed` arrays. They will be retried on the next upload attempt.

## 4. Error Handling

| Error | Action |
|-------|--------|
| **401 Unauthorized** | Session expired. Prompt user to reconnect to server from Sync Center. |
| **400 Bad Request** | Log error for debugging. Check payload format. |
| **500/Network Error** | Show error to user. Record will be retried on next upload. |
| **Partial Failures** | Only mark successful records as synced. Failed records stay in queue. |

## 5. sync_at Field Behavior

The `synced_at` field tracks the sync state of each record:

| State | `synced_at` Value | Meaning |
|-------|------------------|---------|
| New record | `NULL` | Never synced, needs upload |
| Synced | `2026-01-12T18:23:41` | Successfully uploaded |
| Modified after sync | `NULL` (cleared) | Needs re-upload |

**Important**: When a user modifies a previously-synced record, the app automatically sets `synced_at = NULL` to mark it for re-sync.

## 6. Survey Package ID

The `survey_package_id` is looked up automatically by the server based on the `survey_id` field in your data.

**How it works**:
- The mobile app includes `survey_id` (e.g., "r21_test_negative_2025-12-30") in the `data` object
- The server looks up the corresponding `survey_package_id` UUID from the `survey_packages` table
- No need to store or pass the UUID from the mobile app

## 7. Implementation Checklist

- [x] Get auth token from settings
- [x] Get device ID from device_info_plus
- [x] Query unsynced records (synced_at IS NULL)
- [x] Build payload with submissions and formchanges
- [x] POST to app-sync endpoint
- [x] Parse response and update local synced_at
- [x] Handle errors gracefully
- [x] Show progress and results to user

**Note**: All mobile app implementation is complete. Server side requires the updated edge function.
