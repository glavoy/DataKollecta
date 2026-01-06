
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
