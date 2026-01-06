
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import * as bcrypt from "https://deno.land/x/bcrypt@v0.3.0/mod.ts";

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
