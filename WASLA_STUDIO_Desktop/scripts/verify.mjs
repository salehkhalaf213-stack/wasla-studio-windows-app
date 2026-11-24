import fs from 'node:fs';
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
  ['Pending account access gate', html.includes("profile?.approval_status==='pending'") ]];
for (const [label, ok] of checks) console.log(`${ok ? 'OK' : 'MISSING'}  ${label}`);
if (checks.some(([, ok]) => !ok)) process.exit(1);
