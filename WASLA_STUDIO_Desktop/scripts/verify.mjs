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
  ['Desktop password recovery redirect', /resetPasswordForEmail\s*\(\s*email\s*,\s*\{\s*redirectTo\s*\}\s*\)/.test(html) && /const\s+redirectTo\s*=\s*window\.location\.origin\s*\+\s*window\.location\.pathname/.test(html)],
  ['Client portal shell', html.includes('id="clientShell"')],
  ['Client role routing', html.includes("['owner','admin','employee','user']")],
  ['Client project mapping', html.includes(".from('client_accounts').select('legacy_client_id')")],
  ['Client milestones', html.includes(".from('client_project_milestones')")],
  ['Client-visible designs only', html.includes(".eq('visible_to_client',true)")],
  ['Client comments', html.includes('sendClientComment')],
  ['Design approval and revision requests', html.includes('submitClientDesignReview') && html.includes('revision_requested')],
  ['Private design files use signed URLs', html.includes("createSignedUrl(design.storage_path,3600)")],
  ['No service-role key in frontend', !html.includes('service_role')]
];

const inlineScripts = [...html.matchAll(/<script(?:\s[^>]*)?>([\s\S]*?)<\/script>/gi)]
  .map(match => match[1])
  .filter(script => script.trim());
try {
  if (inlineScripts.length !== 1) throw new Error('Expected one inline application script, found ' + inlineScripts.length);
  new vm.Script(inlineScripts[0], { filename: 'WASLA_STUDIO/src/index.html' });
  checks.push(['Inline JavaScript syntax', true]);
} catch (error) {
  checks.push(['Inline JavaScript syntax', false]);
  console.error(error.message);
}

for (const [label, ok] of checks) console.log((ok ? 'OK' : 'MISSING') + '  ' + label);
if (checks.some(([, ok]) => !ok)) process.exit(1);
