import fs from 'node:fs';
import vm from 'node:vm';
const html = fs.readFileSync(new URL('../src/index.html', import.meta.url), 'utf8');
const checks = [
  ['Supabase project URL', html.includes('https://oqkmesadspiibllyjwmj.supabase.co')],
  ['Supabase publishable key', html.includes('sb_publishable_')],
  ['Employee portal', html.includes('employeePortal')],
  ['Employee performance', html.includes('loadAdminEmployees')],
  ['Notifications', html.includes('pollAdminNotifications')],
  ['Cloud workspace sync', html.includes('loadCloudData')],
  ['Supabase session persistence and token refresh', /persistSession\s*:\s*true/.test(html) && /autoRefreshToken\s*:\s*true/.test(html)],
  ['Active organization membership lookup', html.includes(".from('organization_members').select('organization_id,role,status').eq('user_id',session.user.id).eq('status','active')")],
  ['Fail-closed when no active organization membership exists', html.includes('لا توجد عضوية مؤسسة نشطة لهذا الحساب.') && html.includes('if(membershipError||!membership?.organization_id)')],
  ['Organization-specific local workspace key', html.includes("KEY='wasla_mvp_02:'+currentOrganizationId")],
  ['Cloud workspace reads scoped to current organization', html.includes(".from('workspace_data').select('payload,updated_at').eq('id',1).eq('organization_id',currentOrganizationId)")],
  ['Cloud workspace writes scoped to current organization', html.includes("upsert({id:1,organization_id:currentOrganizationId,payload:data")],
  ['Logout clears Supabase session', html.includes('await sb.auth.signOut()') && /event==='SIGNED_OUT'[\s\S]{0,220}clearTenantState\(\)/.test(html)],
  ['Desktop password recovery redirect with CAPTCHA', /resetPasswordForEmail\s*\(\s*email\s*,\s*\{\s*redirectTo\s*,\s*captchaToken\s*\}\s*\)/.test(html) && /const\s+redirectTo\s*=\s*window\.location\.origin\s*\+\s*window\.location\.pathname/.test(html)],
  ['Cloudflare Turnstile site key and widgets', html.includes('const TURNSTILE_SITE_KEY=') && html.includes('id="loginCaptcha"') && html.includes('id="signupCaptcha"') && html.includes('id="recoveryCaptcha"')],
  ['Supabase Auth CAPTCHA token wiring', html.includes('options:{captchaToken}') && html.includes('captchaToken}') && html.includes('resetPasswordForEmail(email,{redirectTo,captchaToken})')],
  ['New account signup form', html.includes('id="signupForm"') && html.includes("sb.auth.signUp(")],
  ['Tenant-specific client signup form', html.includes('id="signupPhone"') && html.includes('client_registration_token') && html.includes('clientRegistrationToken')],
  ['Admin approval queue', html.includes('pendingSignupTable') && html.includes("sb.rpc('approve_signup'")],
  ['Pending account access gate', html.includes("profile?.approval_status==='pending'")],
  ['Invoice print action', html.includes('onclick="printFinanceInvoice(') && html.includes('function printFinanceInvoice(id)')],
  ['Invoice PDF action', html.includes('onclick="exportFinanceInvoicePdf(') && html.includes('function exportFinanceInvoicePdf(id)')],
  ['Premium invoice PDF layout', html.includes('invoice-sheet') && html.includes('totals-wrap') && html.includes('payments-section') && html.includes('WASLA STUDIO · FINANCE')],
  ['Invoice PDF preserves existing financial values', html.includes('invoice.subtotal_original') && html.includes('invoice.vat_original') && html.includes('invoice.total_original') && html.includes('invoice.paid_original')],
  ['In-app invoice print view (no popup dependency)', html.includes('wasla-invoice-print-root') && html.includes('window.print()') && !html.includes("window.open('','_blank')")]
];
const inlineScripts = [...html.matchAll(/<script\b([^>]*)>([\s\S]*?)<\/script\s*>/gi)]
  .filter(match => !/\bsrc\s*=/.test(match[1]) && match[2].trim());
for (let i = 0; i < inlineScripts.length; i++) {
  try { new vm.Script(inlineScripts[i][2], { filename: 'inline-script-' + (i + 1) + '.js' }); }
  catch (error) { console.error('JavaScript syntax error in inline script ' + (i + 1) + ': ' + error.message); process.exit(1); }
}
console.log('OK  JavaScript syntax (' + inlineScripts.length + ' inline script)');
for (const [label, ok] of checks) console.log((ok ? 'OK' : 'MISSING') + '  ' + label);
if (checks.some(([, ok]) => !ok)) process.exit(1);
