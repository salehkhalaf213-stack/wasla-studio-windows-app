import { createClient } from "npm:@supabase/supabase-js@2";

function isAllowedOrigin(value: string | null) {
  if (!value) return false;
  try {
    const url = new URL(value);
    if (url.protocol !== "https:") return false;
    const host = url.hostname.toLowerCase();
    return host === "wasla-studio-windows-app.pages.dev" ||
      host.endsWith(".wasla-studio-windows-app.pages.dev") ||
      host === "wasla-workspace.pages.dev" ||
      host.endsWith(".wasla-workspace.pages.dev");
  } catch {
    return false;
  }
}
const BUCKET_APPLICATIONS = "organization-applications";
const BUCKET_RECEIPTS = "subscription-receipts";
const MAX_FILE_BYTES = 10 * 1024 * 1024;

function cors(origin: string | null) {
  const allowed = isAllowedOrigin(origin) ? origin! : "";
  return {
    "Access-Control-Allow-Origin": allowed,
    "Access-Control-Allow-Headers": "authorization, apikey, x-client-info, content-type",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Vary": "Origin",
  };
}
function json(body: unknown, status = 200, origin: string | null = null) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...cors(origin), "Content-Type": "application/json", "Cache-Control": "no-store" },
  });
}
function env(name: string) {
  return Deno.env.get(name) ?? "";
}
function adminKey() {
  const legacy = env("SUPABASE_SERVICE_ROLE_KEY");
  if (legacy) return legacy;
  try {
    return JSON.parse(env("SUPABASE_SECRET_KEYS") || "{}").default || "";
  } catch {
    return "";
  }
}
function validEmail(value: string) {
  return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(value);
}
function safeText(value: FormDataEntryValue | null, max: number) {
  return typeof value === "string" ? value.trim().slice(0, max) : "";
}
async function sha256(value: string) {
  const bytes = new TextEncoder().encode(value);
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  return Array.from(new Uint8Array(digest)).map(x => x.toString(16).padStart(2, "0")).join("");
}
function validFileSignature(bytes: Uint8Array, type: string) {
  if (type === "image/jpeg") return bytes[0] === 0xff && bytes[1] === 0xd8 && bytes[2] === 0xff;
  if (type === "image/png") return bytes.slice(0, 8).join(",") === "137,80,78,71,13,10,26,10";
  if (type === "image/webp") return String.fromCharCode(...bytes.slice(0, 4)) === "RIFF" &&
    String.fromCharCode(...bytes.slice(8, 12)) === "WEBP";
  if (type === "application/pdf") return String.fromCharCode(...bytes.slice(0, 5)) === "%PDF-";
  return false;
}
async function verifyTurnstile(token: string, ip: string) {
  const secret = env("TURNSTILE_SECRET_KEY");
  if (!secret) return { ok: false, unavailable: true, hostname: "" };
  const form = new URLSearchParams({ secret, response: token });
  if (ip) form.set("remoteip", ip);
  const response = await fetch("https://challenges.cloudflare.com/turnstile/v0/siteverify", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: form,
  });
  if (!response.ok) return { ok: false, unavailable: false, hostname: "" };
  const result = await response.json();
  return {
    ok: result.success === true && (
      result.hostname === "wasla-studio-windows-app.pages.dev" ||
      result.hostname.endsWith(".wasla-studio-windows-app.pages.dev")
    ),
    unavailable: false,
    hostname: String(result.hostname || ""),
  };
}
const supabaseUrl = env("SUPABASE_URL");
const key = adminKey();
const service = supabaseUrl && key
  ? createClient(supabaseUrl, key, { auth: { persistSession: false, autoRefreshToken: false } })
  : null;

async function submitApplication(req: Request, origin: string | null) {
  if (!service) return json({ error: "الخدمة غير مهيأة بعد." }, 503, origin);
  const form = await req.formData();
  const companyName = safeText(form.get("company_name"), 180);
  const managerName = safeText(form.get("manager_name"), 160);
  const managerEmail = safeText(form.get("manager_email"), 254).toLowerCase();
  const managerPhone = safeText(form.get("manager_phone"), 40);
  const planId = safeText(form.get("plan_id"), 64);
  const transferReference = safeText(form.get("transfer_reference"), 160);
  const token = safeText(form.get("turnstile_token"), 4096);
  const receipt = form.get("receipt");
  if (companyName.length < 2 || managerName.length < 2 || !validEmail(managerEmail) ||
      managerPhone.length < 6 || !planId || !token || !(receipt instanceof File)) {
    return json({ error: "أكمل بيانات الشركة والمدير والباقة وأرفق إيصال التحويل." }, 400, origin);
  }
  if (receipt.size < 1 || receipt.size > MAX_FILE_BYTES) {
    return json({ error: "حجم الإيصال يجب ألا يتجاوز 10 ميجابايت." }, 400, origin);
  }
  const allowedTypes = new Set(["image/jpeg", "image/png", "image/webp", "application/pdf"]);
  if (!allowedTypes.has(receipt.type)) return json({ error: "صيغة الإيصال غير مدعومة." }, 400, origin);

  const ip = req.headers.get("cf-connecting-ip") || req.headers.get("x-real-ip") || (req.headers.get("x-forwarded-for") || "").split(",")[0].trim();
  const challenge = await verifyTurnstile(token, ip);
  if (challenge.unavailable) return json({ error: "لم يتم إعداد مفتاح التحقق في الخادم بعد." }, 503, origin);
  if (!challenge.ok) return json({ error: "فشل التحقق الأمني. أعد التحقق ثم حاول مرة أخرى." }, 403, origin);

  const ipHash = ip ? await sha256(ip) : null;
  const since = new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString();
  if (ipHash) {
    const { count, error } = await service.from("platform_organization_applications")
      .select("id", { count: "exact", head: true })
      .eq("source_ip_hash", ipHash).gte("submitted_at", since);
    if (error) return json({ error: "تعذر التحقق من حد الإرسال. حاول لاحقاً." }, 500, origin);
    if ((count || 0) >= 3) return json({ error: "تم بلوغ الحد اليومي للطلبات من هذا الاتصال." }, 429, origin);
  }
  const { count: emailCount, error: emailError } = await service.from("platform_organization_applications")
    .select("id", { count: "exact", head: true })
    .eq("manager_email", managerEmail).gte("submitted_at", since);
  if (emailError) return json({ error: "تعذر التحقق من البريد. حاول لاحقاً." }, 500, origin);
  if ((emailCount || 0) >= 2) return json({ error: "يوجد عدد كافٍ من الطلبات الحديثة لهذا البريد." }, 429, origin);

  const { data: plan, error: planError } = await service.from("subscription_plans")
    .select("id,name,price_minor,currency,is_active").eq("id", planId).eq("is_active", true).maybeSingle();
  if (planError || !plan || plan.currency !== "EGP" || Number(plan.price_minor) <= 0) {
    return json({ error: "الباقة المختارة غير متاحة حالياً." }, 400, origin);
  }
  const bytes = new Uint8Array(await receipt.arrayBuffer());
  if (!validFileSignature(bytes, receipt.type)) return json({ error: "محتوى الملف لا يطابق صيغته المعلنة." }, 400, origin);

  const extension = receipt.type === "application/pdf" ? "pdf" :
    receipt.type === "image/jpeg" ? "jpg" : receipt.type === "image/png" ? "png" : "webp";
  const path = `${crypto.randomUUID()}.${extension}`;
  const { error: uploadError } = await service.storage.from(BUCKET_APPLICATIONS)
    .upload(path, bytes, { contentType: receipt.type, upsert: false });
  if (uploadError) return json({ error: "تعذر حفظ إيصال التحويل بأمان." }, 500, origin);

  const { data, error } = await service.from("platform_organization_applications").insert({
    company_name: companyName,
    manager_name: managerName,
    manager_email: managerEmail,
    manager_phone: managerPhone,
    plan_id: plan.id,
    amount_minor: plan.price_minor,
    currency: "EGP",
    transfer_reference: transferReference || null,
    receipt_path: path,
    receipt_mime_type: receipt.type,
    receipt_size: receipt.size,
    source_ip_hash: ipHash,
  }).select("id,status,submitted_at").single();
  if (error) {
    await service.storage.from(BUCKET_APPLICATIONS).remove([path]);
    return json({ error: "تعذر تسجيل الطلب. حاول مرة أخرى لاحقاً." }, 500, origin);
  }
  return json({ success: true, application: data, message: "تم استلام طلبك وسيتم مراجعته قبل إنشاء مساحة العمل." }, 201, origin);
}

async function reviewApplication(req: Request, origin: string | null, body: Record<string, unknown>) {
  if (!service) return json({ error: "الخدمة غير مهيأة." }, 503, origin);
  const authHeader = req.headers.get("Authorization") || "";
  const token = authHeader.startsWith("Bearer ") ? authHeader.slice(7) : "";
  if (!token) return json({ error: "يلزم تسجيل الدخول." }, 401, origin);
  let publishable = env("SUPABASE_ANON_KEY");
  if (!publishable) {
    try { publishable = JSON.parse(env("SUPABASE_PUBLISHABLE_KEYS") || "{}").default || ""; } catch { /* missing publishable key */ }
  }
  if (!publishable) return json({ error: "إعداد التحقق من الجلسة غير مكتمل." }, 503, origin);
  const caller = createClient(supabaseUrl, publishable, {
    auth: { persistSession: false, autoRefreshToken: false },
    global: { headers: { Authorization: authHeader } },
  });
  const { data: authData, error: authError } = await caller.auth.getUser(token);
  if (authError || !authData.user) return json({ error: "جلسة غير صالحة." }, 401, origin);
  const { data: admin } = await caller.from("platform_admins").select("user_id")
    .eq("user_id", authData.user.id).eq("status", "active").maybeSingle();
  if (!admin) return json({ error: "هذه العملية لمالك المنصة فقط." }, 403, origin);

  const id = String(body.id || "");
  const decision = String(body.decision || "");
  const note = String(body.note || "").trim().slice(0, 500);
  if (!/^[0-9a-f-]{36}$/i.test(id) || !["approved", "rejected"].includes(decision)) {
    return json({ error: "بيانات المراجعة غير صحيحة." }, 400, origin);
  }
  const { data: application, error: appError } = await service.from("platform_organization_applications")
    .select("*").eq("id", id).eq("status", "pending").maybeSingle();
  if (appError || !application) return json({ error: "الطلب غير موجود أو تمت مراجعته بالفعل." }, 409, origin);
  if (decision === "rejected") {
    const { error } = await service.from("platform_organization_applications").update({
      status: "rejected", reviewed_at: new Date().toISOString(), reviewed_by: authData.user.id,
      review_note: note || null,
    }).eq("id", id).eq("status", "pending");
    if (error) return json({ error: "تعذر حفظ قرار الرفض." }, 500, origin);
    return json({ success: true, status: "rejected" }, 200, origin);
  }

  const { data: plan, error: planError } = await service.from("subscription_plans")
    .select("id,price_minor,currency,is_active").eq("id", application.plan_id).maybeSingle();
  if (planError || !plan || !plan.is_active || plan.currency !== "EGP" ||
      Number(plan.price_minor) !== Number(application.amount_minor)) {
    return json({ error: "تغيرت بيانات الباقة منذ تقديم الطلب؛ راجع الطلب يدوياً قبل الموافقة." }, 409, origin);
  }
  const { data: duplicate } = await service.from("organizations").select("id")
    .ilike("name", application.company_name).limit(1).maybeSingle();
  if (duplicate) return json({ error: "توجد مؤسسة بالاسم نفسه؛ تحقق يدوياً قبل المتابعة." }, 409, origin);

  const { data: invite, error: inviteError } = await service.auth.admin.inviteUserByEmail(application.manager_email, {
    data: { full_name: application.manager_name, requested_role: "admin" },
  });
  if (inviteError || !invite?.user) {
    return json({ error: "تعذر دعوة المدير. قد يكون البريد مسجلاً مسبقاً: " + (inviteError?.message || "") }, 409, origin);
  }
  const userId = invite.user.id;
  let organizationId: string | null = null;
  let paymentId: string | null = null;
  let copiedReceiptPath: string | null = null;
  try {
    const baseSlug = application.company_name.normalize("NFKD").replace(/[\u0300-\u036f]/g, "")
      .toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-+|-+$/g, "").slice(0, 34) || "company";
    const slug = `${baseSlug}-${crypto.randomUUID().slice(0, 8)}`;
    const { data: organization, error: orgError } = await service.from("organizations").insert({
      name: application.company_name, slug, created_by: authData.user.id, status: "active",
    }).select("id").single();
    if (orgError || !organization) throw orgError || new Error("تعذر إنشاء المؤسسة.");
    organizationId = organization.id;

    const { error: memberError } = await service.from("organization_members").insert({
      organization_id: organizationId, user_id: userId, role: "admin", status: "active",
    });
    if (memberError) throw memberError;
    const { error: profileError } = await service.from("profiles").update({
      full_name: application.manager_name, role: "admin", requested_role: null,
      approval_status: "approved", organization_id: organizationId,
      company_name: application.company_name, phone: application.manager_phone,
    }).eq("id", userId);
    if (profileError) throw profileError;

    const { data: sourceFile, error: downloadError } = await service.storage.from(BUCKET_APPLICATIONS)
      .download(application.receipt_path);
    if (downloadError || !sourceFile) throw downloadError || new Error("تعذر قراءة الإيصال.");
    copiedReceiptPath = `${organizationId}/${crypto.randomUUID()}`;
    const { error: copyError } = await service.storage.from(BUCKET_RECEIPTS)
      .upload(copiedReceiptPath, sourceFile, { contentType: application.receipt_mime_type, upsert: false });
    if (copyError) throw copyError;

    const { error: subscriptionError } = await service.from("organization_subscriptions").insert({
      organization_id: organizationId, plan_id: application.plan_id, status: "pending", billing_provider: "manual",
    });
    if (subscriptionError) throw subscriptionError;

    const { data: payment, error: paymentError } = await service.from("subscription_payment_requests").insert({
      organization_id: organizationId, submitted_by: userId, plan_id: application.plan_id,
      amount_minor: application.amount_minor, currency: "EGP",
      transfer_reference: application.transfer_reference, receipt_path: copiedReceiptPath, status: "pending",
    }).select("id").single();
    if (paymentError || !payment) throw paymentError || new Error("تعذر إنشاء طلب الدفع.");
    paymentId = payment.id;

    const { error: updateError } = await service.from("platform_organization_applications").update({
      status: "approved", organization_id: organizationId, payment_request_id: paymentId,
      reviewed_at: new Date().toISOString(), reviewed_by: authData.user.id, review_note: note || null,
    }).eq("id", id).eq("status", "pending");
    if (updateError) throw updateError;

    return json({ success: true, status: "approved", organization_id: organizationId,
      payment_request_id: paymentId, manager_invitation_sent: true }, 200, origin);
  } catch (error) {
    if (paymentId) await service.from("subscription_payment_requests").delete().eq("id", paymentId);
    await service.auth.admin.deleteUser(userId);
    if (organizationId) {
      await service.from("organization_members").delete().eq("organization_id", organizationId);
      await service.from("organization_subscriptions").delete().eq("organization_id", organizationId);
      await service.from("organizations").delete().eq("id", organizationId);
    }
    if (copiedReceiptPath) await service.storage.from(BUCKET_RECEIPTS).remove([copiedReceiptPath]);
    return json({ error: error instanceof Error ? error.message : "تعذر إكمال إنشاء المؤسسة." }, 500, origin);
  }
}

Deno.serve(async (req: Request) => {
  const origin = req.headers.get("Origin");
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors(origin) });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405, origin);
  if (!isAllowedOrigin(origin)) return json({ error: "Origin not allowed" }, 403, origin);
  const action = new URL(req.url).searchParams.get("action") || "submit";
  try {
    if (action === "submit") return await submitApplication(req, origin);
    if (action === "review") {
      let body: Record<string, unknown>;
      try { body = await req.json(); } catch { return json({ error: "Invalid JSON body" }, 400, origin); }
      return await reviewApplication(req, origin, body);
    }
    return json({ error: "Unsupported action" }, 400, origin);
  } catch (_error) {
    return json({ error: "تعذر إكمال الطلب. حاول مرة أخرى لاحقاً." }, 500, origin);
  }
});
