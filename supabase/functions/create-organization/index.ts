import { createClient } from "npm:@supabase/supabase-js@2";
const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), {
  status, headers: { ...corsHeaders, "Content-Type": "application/json" },
});
Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);
  const url = Deno.env.get("SUPABASE_URL") ?? "";
  const anon = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
  const secret = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? Deno.env.get("SUPABASE_SECRET_KEY") ?? "";
  const authHeader = req.headers.get("Authorization") ?? "";
  const token = authHeader.startsWith("Bearer ") ? authHeader.slice(7) : "";
  if (!url || !anon || !secret || !token) return json({ error: "Missing server configuration or authenticated session" }, 401);

  const caller = createClient(url, anon, {
    auth: { persistSession: false, autoRefreshToken: false },
    global: { headers: { Authorization: authHeader } },
  });
  const { data: authData, error: authError } = await caller.auth.getUser(token);
  if (authError || !authData.user) return json({ error: "Unauthenticated" }, 401);
  const { data: allowed, error: permissionError } = await caller.from("platform_admins")
    .select("user_id").eq("user_id", authData.user.id).eq("status", "active").maybeSingle();
  if (permissionError || !allowed) return json({ error: "Platform owner permission required" }, 403);

  let body: Record<string, unknown>;
  try { body = await req.json(); } catch { return json({ error: "Invalid JSON body" }, 400); }
  const name = String(body.name ?? "").trim();
  const email = String(body.admin_email ?? "").trim().toLowerCase();
  const adminName = String(body.admin_name ?? "").trim();
  const slug = String(body.slug ?? "").trim().toLowerCase().normalize("NFKD")
    .replace(/[\u0300-\u036f]/g, "").replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "").slice(0, 48);
  if (name.length < 2 || name.length > 120) return json({ error: "اسم المؤسسة يجب أن يكون بين حرفين و120 حرفاً" }, 400);
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) return json({ error: "بريد مدير المؤسسة غير صالح" }, 400);
  if (adminName.length < 2 || adminName.length > 100) return json({ error: "أدخل اسم مدير المؤسسة" }, 400);
  if (!slug || !/^[a-z0-9]+(?:-[a-z0-9]+)*$/.test(slug)) return json({ error: "معرّف المؤسسة غير صالح؛ استخدم أحرفاً وأرقاماً إنجليزية" }, 400);

  const service = createClient(url, secret, { auth: { persistSession: false, autoRefreshToken: false } });
  const { data: existing } = await service.from("organizations").select("id").eq("slug", slug).maybeSingle();
  if (existing) return json({ error: "معرّف المؤسسة مستخدم بالفعل" }, 409);

  const { data: invitation, error: inviteError } = await service.auth.admin.inviteUserByEmail(email, {
    data: { full_name: adminName, requested_role: "admin" },
  });
  if (inviteError || !invitation.user) {
    return json({ error: inviteError?.message ?? "تعذر إرسال دعوة المدير. قد يكون البريد مسجلاً مسبقاً." }, 400);
  }

  const invitedUserId = invitation.user.id;
  let organizationId: string | null = null;
  try {
    const { data: organization, error: orgError } = await service.from("organizations")
      .insert({ name, slug, created_by: authData.user.id, status: "active" })
      .select("id,name,slug,status,created_at").single();
    if (orgError || !organization) throw orgError ?? new Error("Organization creation failed");
    organizationId = organization.id;

    const { error: memberError } = await service.from("organization_members").insert({
      organization_id: organization.id, user_id: invitedUserId, role: "admin", status: "active",
    });
    if (memberError) throw memberError;

    const { error: profileError } = await service.from("profiles").update({
      full_name: adminName, role: "admin", requested_role: null,
      approval_status: "approved", organization_id: organization.id,
    }).eq("id", invitedUserId);
    if (profileError) throw profileError;

    return json({ success: true, organization,
      manager: { user_id: invitedUserId, email, full_name: adminName, invitation_sent: true } }, 201);
  } catch (error) {
    await service.auth.admin.deleteUser(invitedUserId);
    if (organizationId) {
      await service.from("organization_members").delete().eq("organization_id", organizationId);
      await service.from("organizations").delete().eq("id", organizationId);
    }
    return json({ error: error instanceof Error ? error.message : "تعذر إكمال إنشاء المؤسسة" }, 500);
  }
});
