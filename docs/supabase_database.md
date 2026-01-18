# System Architecture & Database Schema

## Table Descriptions

Here is the breakdown of what each table does in your system:

### 1. Hierarchy & Access

* **profiles**: Website Users. This is YOU (and your colleagues). It stores your name/email extensions.
* **projects**: The main folder. Everything belongs to a project.
* **project_members**: The Access List. It links a Profile to a Project. If you aren't in this table for Project X, you can't see Project X.

### 2. The Survey Definitions
* **survey_packages**: The Zip File/Bundle. When you upload a survey design, it creates a row here. It represents "Version 1 of the Malaria Survey".
* **crfs**: The Forms. If your survey package has 3 parts (Household, Person, Blood Sample), you will have 3 rows here describing the structure of each form.

### 3. The Field App (Data Collectors)
* **app_credentials**: Field Worker Accounts. These are the simple login codes (e.g., surveyor1) that data collectors type into the Android app. They are distinct from website users.
* **app_sessions**: Active Devices. When a phone logs in, it creates a session here.

### 4. The Data
* **submissions**: The Answers. Every time a form is completed and synced, it lands here. The actual data (answers) is stored in a JSON column.
* **submission_history**: The Audit Trail. If you edit a submission on the website, the old version is saved here so you never lose data.

---


### General flow
- create new login
- create a new project
    - after creating a new project, there are records in two tables: `projects`, `project_members`
- in the new project - upload a 'survey' zip file
    - this creates records in the tables: `survey_packages`, `crfs`
- create a 'team member' - under add credentials ion teh team member tab - this creats a record in the table: `app_credentials`
- team member enters credentials on the phone and checks for surveys - writes record to the `app_sessions` table
- fgg



## Technical Schema

### 1. Database Column Schema

**Query:**
```sql
SELECT table_name, column_name, data_type, is_nullable FROM information_schema.columns WHERE table_schema = 'public' ORDER BY table_name, ordinal_position;
```

| table_name | column_name | data_type | is_nullable |
| :--- | :--- | :--- | :--- |
| app_credentials | id | uuid | NO |
| app_credentials | project_id | uuid | NO |
| app_credentials | username | text | NO |
| app_credentials | password_hash | text | NO |
| app_credentials | description | text | YES |
| app_credentials | is_active | boolean | YES |
| app_credentials | created_by | uuid | YES |
| app_credentials | created_at | timestamp with time zone | YES |
| app_credentials | last_used_at | timestamp with time zone | YES |
| app_sessions | id | uuid | NO |
| app_sessions | credential_id | uuid | YES |
| app_sessions | project_id | uuid | YES |
| app_sessions | token | text | NO |
| app_sessions | device_id | text | YES |
| app_sessions | device_info | jsonb | YES |
| app_sessions | created_at | timestamp with time zone | YES |
| app_sessions | expires_at | timestamp with time zone | NO |
| app_sessions | last_activity_at | timestamp with time zone | YES |
| crfs | id | uuid | NO |
| crfs | survey_package_id | uuid | NO |
| crfs | project_id | uuid | NO |
| crfs | table_name | text | NO |
| crfs | display_name | text | NO |
| crfs | display_order | integer | YES |
| crfs | is_base | boolean | YES |
| crfs | primary_key | text | YES |
| crfs | linking_field | text | YES |
| crfs | parent_table | text | YES |
| crfs | fields | jsonb | YES |
| crfs | id_config | jsonb | YES |
| crfs | display_fields | text | YES |
| crfs | auto_start_repeat | boolean | YES |
| crfs | repeat_enforce_count | integer | YES |
| crfs | created_at | timestamp with time zone | YES |
| profiles | id | uuid | NO |
| profiles | email | text | NO |
| profiles | full_name | text | YES |
| profiles | role | text | YES |
| profiles | created_at | timestamp with time zone | YES |
| profiles | updated_at | timestamp with time zone | YES |
| project_members | id | uuid | NO |
| project_members | project_id | uuid | YES |
| project_members | user_id | uuid | YES |
| project_members | role | USER-DEFINED | NO |
| project_members | invited_by | uuid | YES |
| project_members | invited_at | timestamp with time zone | YES |
| project_members | accepted_at | timestamp with time zone | YES |
| projects | id | uuid | NO |
| projects | name | text | NO |
| projects | description | text | YES |
| projects | slug | text | NO |
| projects | status | text | YES |
| projects | created_by | uuid | YES |
| projects | created_at | timestamp with time zone | YES |
| projects | updated_at | timestamp with time zone | YES |
| projects | is_active | boolean | YES |
| submission_history | id | uuid | NO |
| submission_history | submission_id | uuid | YES |
| submission_history | data | jsonb | NO |
| submission_history | version | integer | NO |
| submission_history | change_type | text | NO |
| submission_history | changed_fields | jsonb | YES |
| submission_history | changed_by | text | YES |
| submission_history | changed_on_device | text | YES |
| submission_history | changed_at | timestamp with time zone | YES |
| submission_history | synced_at | timestamp with time zone | YES |
| submissions | id | uuid | NO |
| submissions | project_id | uuid | NO |
| submissions | survey_package_id | uuid | NO |
| submissions | crf_id | uuid | YES |
| submissions | table_name | text | NO |
| submissions | record_id | text | YES |
| submissions | local_unique_id | text | NO |
| submissions | data | jsonb | NO |
| submissions | version | integer | YES |
| submissions | parent_table | text | YES |
| submissions | parent_record_id | text | YES |
| submissions | device_id | text | YES |
| submissions | surveyor_id | text | YES |
| submissions | app_version | text | YES |
| submissions | collected_at | timestamp with time zone | YES |
| submissions | submitted_at | timestamp with time zone | YES |
| submissions | updated_at | timestamp with time zone | YES |
| survey_packages | id | uuid | NO |
| survey_packages | project_id | uuid | YES |
| survey_packages | name | text | NO |
| survey_packages | display_name | text | NO |
| survey_packages | version_date | date | NO |
| survey_packages | description | text | YES |
| survey_packages | zip_file_path | text | YES |
| survey_packages | manifest | jsonb | YES |
| survey_packages | status | USER-DEFINED | YES |
| survey_packages | created_by | uuid | YES |
| survey_packages | created_at | timestamp with time zone | YES |
| survey_packages | updated_at | timestamp with time zone | YES |
| survey_packages | published_at | timestamp with time zone | YES |

---

### 2. Foreign Key Constraints

**Query:**
```sql
SELECT tc.table_name, kcu.column_name, ccu.table_name AS foreign_table_name, ccu.column_name AS foreign_column_name FROM information_schema.table_constraints AS tc JOIN information_schema.key_column_usage AS kcu ON tc.constraint_name = kcu.constraint_name AND tc.table_schema = kcu.table_schema JOIN information_schema.constraint_column_usage AS ccu ON ccu.constraint_name = tc.constraint_name AND ccu.table_schema = tc.table_schema WHERE tc.constraint_type = 'FOREIGN KEY' AND tc.table_schema = 'public';
```

| table_name | column_name | foreign_table_name | foreign_column_name |
| :--- | :--- | :--- | :--- |
| app_sessions | project_id | projects | id |
| app_sessions | credential_id | app_credentials | id |
| app_credentials | created_by | profiles | id |
| app_credentials | project_id | projects | id |
| submission_history | submission_id | submissions | id |
| submissions | crf_id | crfs | id |
| submissions | survey_package_id | survey_packages | id |
| submissions | project_id | projects | id |
| crfs | project_id | projects | id |
| crfs | survey_package_id | survey_packages | id |
| survey_packages | created_by | profiles | id |
| survey_packages | project_id | projects | id |
| project_members | invited_by | profiles | id |
| project_members | user_id | profiles | id |
| project_members | project_id | projects | id |
| projects | created_by | profiles | id |

---

### 3. Row Level Security (RLS) Policies

**Query:**
```sql
SELECT tablename, policyname, roles, cmd, qual, with_check FROM pg_policies WHERE schemaname = 'public';
```

| tablename | policyname | roles | cmd | qual | with_check |
| :--- | :--- | :--- | :--- | :--- | :--- |
| app_credentials | Owners can view credentials | {authenticated} | SELECT | (EXISTS (SELECT 1 FROM project_members pm WHERE ((pm.project_id = pm.project_id) AND (pm.user_id = auth.uid()) AND (pm.role = 'owner'::project_role)))) | null |
| profiles | Users can view own profile | {public} | SELECT | (auth.uid() = id) | null |
| profiles | Users can update own profile | {public} | UPDATE | (auth.uid() = id) | null |
| projects | Owners can update projects | {authenticated} | UPDATE | (EXISTS (SELECT 1 FROM project_members pm WHERE ((pm.project_id = pm.id) AND (pm.user_id = auth.uid()) AND (pm.role = 'owner'::project_role)))) | null |
| projects | Owners can delete projects | {authenticated} | DELETE | (EXISTS (SELECT 1 FROM project_members pm WHERE ((pm.project_id = pm.id) AND (pm.user_id = auth.uid()) AND (pm.role = 'owner'::project_role)))) | null |
| project_members | Users can view own memberships | {authenticated} | SELECT | (user_id = auth.uid()) | null |
| project_members | Allow member creation | {authenticated} | INSERT | null | (((user_id = auth.uid()) AND (role = 'owner'::project_role)) OR (EXISTS (SELECT 1 FROM project_members pm WHERE ((pm.project_id = project_members.project_id) AND (pm.user_id = auth.uid()) AND (pm.role = 'owner'::project_role))))) |
| project_members | Owners can update memberships | {authenticated} | UPDATE | (EXISTS (SELECT 1 FROM project_members pm WHERE ((pm.project_id = project_members.project_id) AND (pm.user_id = auth.uid()) AND (pm.role = 'owner'::project_role)))) | null |
| project_members | Owners can delete memberships | {authenticated} | DELETE | (EXISTS (SELECT 1 FROM project_members pm WHERE ((pm.project_id = project_members.project_id) AND (pm.user_id = auth.uid()) AND (pm.role = 'owner'::project_role)))) | null |
| survey_packages | Users can view project surveys | {authenticated} | SELECT | (EXISTS (SELECT 1 FROM project_members pm WHERE ((pm.project_id = pm.project_id) AND (pm.user_id = auth.uid())))) | null |
| survey_packages | Editors can manage surveys | {authenticated} | ALL | (EXISTS (SELECT 1 FROM project_members pm WHERE ((pm.project_id = pm.project_id) AND (pm.user_id = auth.uid()) AND (pm.role = ANY (ARRAY['editor'::project_role, 'owner'::project_role]))))) | null |
| crfs | Users can view project crfs | {authenticated} | SELECT | (EXISTS (SELECT 1 FROM project_members pm WHERE ((pm.project_id = pm.project_id) AND (pm.user_id = auth.uid())))) | null |
| crfs | Editors can manage crfs | {authenticated} | ALL | (EXISTS (SELECT 1 FROM project_members pm WHERE ((pm.project_id = pm.project_id) AND (pm.user_id = auth.uid()) AND (pm.role = ANY (ARRAY['editor'::project_role, 'owner'::project_role]))))) | null |
| submissions | Users can view project submissions | {authenticated} | SELECT | (EXISTS (SELECT 1 FROM project_members pm WHERE ((pm.project_id = pm.project_id) AND (pm.user_id = auth.uid())))) | null |
| submissions | Editors can manage submissions | {authenticated} | ALL | (EXISTS (SELECT 1 FROM project_members pm WHERE ((pm.project_id = pm.project_id) AND (pm.user_id = auth.uid()) AND (pm.role = ANY (ARRAY['editor'::project_role, 'owner'::project_role]))))) | null |
| submission_history | Users can view submission history | {authenticated} | SELECT | (EXISTS (SELECT 1 FROM (submissions s JOIN project_members pm ON ((pm.project_id = s.project_id))) WHERE ((s.id = submission_history.submission_id) AND (pm.user_id = auth.uid())))) | null |
| app_credentials | Owners can manage credentials | {authenticated} | ALL | (EXISTS (SELECT 1 FROM project_members pm WHERE ((pm.project_id = pm.project_id) AND (pm.user_id = auth.uid()) AND (pm.role = 'owner'::project_role)))) | null |
| app_sessions | Owners can view sessions | {authenticated} | SELECT | (EXISTS (SELECT 1 FROM project_members pm WHERE ((pm.project_id = pm.project_id) AND (pm.user_id = auth.uid()) AND (pm.role = 'owner'::project_role)))) | null |
| projects | Enable insert for authenticated users only | {public} | INSERT | null | ((SELECT auth.role() AS role) = 'authenticated'::text) |
| projects | Users can view member projects | {public} | SELECT | ((auth.uid() = created_by) OR (EXISTS (SELECT 1 FROM project_members pm WHERE ((pm.project_id = projects.id) AND (pm.user_id = auth.uid()))))) | null |



[Image of database ER diagram]