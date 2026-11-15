import fs from 'node:fs';
const html = fs.readFileSync(new URL('../src/index.html', import.meta.url), 'utf8');
const checks = [
  ['Supabase project URL', html.includes('https://oqkmesadspiibllyjwmj.supabase.co')],
  ['Supabase publishable key', html.includes('sb_publishable_')],
  ['Employee portal', html.includes('employeePortal')],
  ['Employee performance', html.includes('loadAdminEmployees')],
  ['Notifications', html.includes('pollAdminNotifications')],
  ['Cloud workspace sync', html.includes('loadCloudData')],
  ['Desktop password recovery redirect', /resetPasswordForEmail\s*\(\s*email\s*,\s*\{\s*redirectTo\s*\}\s*\)/.test(html) && /const\s+redirectTo\s*=\s*window\.location\.origin\s*\+\s*window\.location\.pathname/.test(html)],
  ['New account signup form', html.includes('id="signupForm"') && html.includes("sb.auth.signUp(")],
  ['Client and employee account selection', html.includes('value="user">عميل') && html.includes('value="employee">موظف')],
  ['Admin approval queue', html.includes('pendingSignupTable') && html.includes("sb.rpc('approve_signup'")],
  ['Pending account access gate', html.includes("profile?.approval_status==='pending'") ]];
for (const [label, ok] of checks) console.log(`${ok ? 'OK' : 'MISSING'}  ${label}`);
if (checks.some(([, ok]) => !ok)) process.exit(1);
