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
  ['Desktop password recovery and signup redirect with CAPTCHA', html.includes("const DESKTOP_WEB_URL='https://wasla-workspace.pages.dev/';") && html.includes('resetPasswordForEmail(email,{redirectTo,captchaToken})') && html.includes('emailRedirectTo:DESKTOP_WEB_URL,captchaToken') && html.includes('const redirectTo=DESKTOP_WEB_URL;')],
  ['Cloudflare Turnstile site key and widgets', html.includes('const TURNSTILE_SITE_KEY=') && html.includes('id="loginCaptcha"') && html.includes('id="signupCaptcha"') && html.includes('id="recoveryCaptcha"')],
  ['Supabase Auth CAPTCHA token wiring', html.includes('options:{captchaToken}') && html.includes('captchaToken}') && html.includes('resetPasswordForEmail(email,{redirectTo,captchaToken})')],
  ['New account signup form', html.includes('id="signupForm"') && html.includes("sb.auth.signUp(")],
  ['Tenant-specific client signup form', html.includes('id="signupPhone"') && html.includes('client_registration_token') && html.includes('clientRegistrationToken')],
  ['Client registration links use the public QENTRIVO web URL', html.includes('new URL(DESKTOP_WEB_URL)')],
  ['QENTRIVO desktop login interface', html.includes('تسجيل الدخول إلى QENTRIVO') && html.includes('auth-login-field') && html.includes('Sign in to QENTRIVO')],
  ['Admin approval queue', html.includes('pendingSignupTable') && html.includes("sb.rpc('approve_signup'")],
  ['Pending account access gate', html.includes("profile?.approval_status==='pending'") ]
];

let failed = false;
for (const [label, ok] of checks) {
  console.log(`${ok ? 'OK' : 'MISSING'}  ${label}`);
  if (!ok) failed = true;
}

if (!/<html\\b/i.test(html) || !/<\\/html\\s*>/i.test(html)) {
  console.error('FAIL  HTML document boundaries');
  failed = true;
}

const jsonLdBlocks = [...html.matchAll(/<script\\b([^>]*)>([\\s\\S]*?)<\\/script\\s*>/gi)]
  .filter(([, attrs]) => /type=["']application\\/ld\\+json["']/i.test(attrs));

for (let i = 0; i < jsonLdBlocks.length; i++) {
  try {
    JSON.parse(jsonLdBlocks[i][2]);
    console.log(`OK  Structured data JSON-LD #${i + 1}`);
  } catch (error) {
    console.error(`FAIL  Structured data JSON-LD #${i + 1}: ${error.message}`);
    failed = true;
  }
}

const executableScripts = [...html.matchAll(/<script\\b([^>]*)>([\\s\\S]*?)<\\/script\\s*>/gi)]
  .filter(([, attrs]) => !/\\bsrc\\s*=/.test(attrs))
  .filter(([, attrs]) => !/type=["']application\\/ld\\+json["']/i.test(attrs));

if (executableScripts.length === 0) {
  console.error('FAIL  No inline application script found');
  failed = true;
}

for (let i = 0; i < executableScripts.length; i++) {
  const [, attrs, source] = executableScripts[i];
  try {
    new vm.Script(source, { filename: `src/index.html:inline-script-${i + 1}` });
    console.log(`OK  JavaScript syntax #${i + 1}${attrs ? ` (${attrs.trim()})` : ''}`);
  } catch (error) {
    console.error(`FAIL  JavaScript syntax #${i + 1}: ${error.message}`);
    failed = true;
  }
}

if (failed) process.exit(1);
console.log('PASS  QENTRIVO desktop source verification');
