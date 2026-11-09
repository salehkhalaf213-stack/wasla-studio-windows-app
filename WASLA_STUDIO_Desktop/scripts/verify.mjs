import fs from 'node:fs';
const html = fs.readFileSync(new URL('../src/index.html', import.meta.url), 'utf8');
const checks = [
  ['Supabase project URL', html.includes('https://oqkmesadspiibllyjwmj.supabase.co')],
  ['Supabase publishable key', html.includes('sb_publishable_')],
  ['Employee portal', html.includes('employeePortal')],
  ['Employee performance', html.includes('loadAdminEmployees')],
  ['Notifications', html.includes('pollAdminNotifications')],
  ['Cloud workspace sync', html.includes('loadCloudData')],
  ['Desktop password recovery redirect', html.includes('https://elaborate-chimera-2d1aaa.netlify.app/')]
];
for (const [label, ok] of checks) console.log(`${ok ? 'OK' : 'MISSING'}  ${label}`);
if (checks.some(([, ok]) => !ok)) process.exit(1);
