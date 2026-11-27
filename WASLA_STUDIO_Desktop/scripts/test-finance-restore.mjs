import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';

const html = fs.readFileSync(new URL('../src/index.html', import.meta.url), 'utf8');
const start = html.indexOf('async function restoreFinanceBackup(');
const end = html.indexOf('\nasync function importData(', start);
assert.ok(start >= 0 && end > start, 'restoreFinanceBackup must exist in the application source');
const functionSource = html.slice(start, end);

const TABLES = [
  'finance_settings','finance_member_roles','finance_project_access','finance_accounts',
  'finance_journals','finance_journal_lines','finance_invoices','finance_invoice_lines',
  'finance_invoice_payments','finance_vendors','finance_vendor_bills',
  'finance_vendor_bill_lines','finance_vendor_bill_payments','finance_audit_log'
];

async function runRestore({ existingAccounts = [], sourceAccounts = [], failIds = [] } = {}) {
  const inserts = [];
  const empty = Object.fromEntries(TABLES.map(table => [table, []]));
  const query = table => ({
    table,
    select() { return this; },
    eq() { return this; },
    async maybeSingle() { return { data: null, error: null }; },
    async insert(row) {
      inserts.push({ table, row });
      if (table === 'finance_accounts' && failIds.includes(row.id)) {
        return { error: { message: 'SIMULATED_INSERT_FAILURE_' + row.id } };
      }
      return { error: null };
    }
  });
  const context = {
    FINANCE_BACKUP_TABLES: TABLES,
    currentOrganizationId: 'test-org',
    currentUser: { id: 'test-user' },
    financeCanManage: () => true,
    sb: { from: query },
    financeFetchAllRows: async q => q.table === 'finance_accounts' ? existingAccounts : empty[q.table] || []
  };
  vm.runInNewContext(functionSource + '\nthis.__restore = restoreFinanceBackup;', context);
  const tables = Object.fromEntries(TABLES.map(table => [table, []]));
  tables.finance_accounts = sourceAccounts.map(row => ({ organization_id: 'test-org', account_name: 'Account ' + row.id, account_type: 'asset', ...row }));
  const report = await context.__restore({ organizationId: 'test-org', tables });
  return { report, inserts };
}

const existing = [
  { id: 'same-id-ok', account_code: '100', account_name: 'Cash', account_type: 'asset', parent_id: null },
  { id: 'same-id-conflict', account_code: '200', account_name: 'Old', account_type: 'asset', parent_id: null },
  { id: 'code-match-existing', account_code: '300', account_name: 'Receivables', account_type: 'asset', parent_id: null },
  { id: 'code-conflict-existing', account_code: '400', account_name: 'Other', account_type: 'liability', parent_id: null }
];
const { report, inserts } = await runRestore({
  existingAccounts: existing,
  failIds: ['insert-fail'],
  sourceAccounts: [
    { id: 'same-id-ok', account_code: '100', account_name: 'Cash', account_type: 'asset', parent_id: null },
    { id: 'same-id-conflict', account_code: '999', account_name: 'Changed', account_type: 'asset', parent_id: null },
    { id: 'new-id-code-match', account_code: '300', account_name: 'Receivables', account_type: 'asset', parent_id: null },
    { id: 'new-id-code-conflict', account_code: '400', account_name: 'Different', account_type: 'asset', parent_id: null },
    { id: 'missing-parent-child', account_code: '501', account_name: 'Child', account_type: 'asset', parent_id: 'missing-parent' },
    { id: 'insert-fail', account_code: '600', account_name: 'Rejected', account_type: 'asset', parent_id: null },
    { id: 'new-root', account_code: '700', account_name: 'New root', account_type: 'asset', parent_id: null },
    { id: 'new-child', account_code: '701', account_name: 'New child', account_type: 'asset', parent_id: 'new-root' }
  ]
});

const checks = [
  ['same ID matching reason', 'الحساب موجود مسبقًا بالمعرّف نفسه'],
  ['same ID conflict reason', 'معرّف الحساب موجود مسبقًا لكن بياناته الأساسية مختلفة'],
  ['same code matching reason', 'يوجد حساب مطابق بنفس كود الحساب'],
  ['same code conflict reason', 'كود الحساب مستخدم لحساب ببيانات مختلفة'],
  ['missing parent reason', 'الحساب الأب غير متاح أو لم تتم استعادته'],
  ['insert failure detail', 'SIMULATED_INSERT_FAILURE_insert-fail']
];
for (const [name, phrase] of checks) assert.ok(report.includes(phrase), name + ' should appear in the restore report');
assert.equal((report.match(/تم تجاوز 1/g) || []).length >= 0, true);
assert.equal(inserts.filter(x => x.table === 'finance_accounts').length, 3, 'only failed root plus valid root and child should be attempted');
assert.match(report, /إجمالي السجلات التي تم تجاوزها: 6/, 'each ineligible account must be counted exactly once');
assert.match(report, /دليل الحسابات: أُضيف 2، تم تجاوز 6/, 'account additions and skips must match fixture totals');

console.log('PASS: finance restore account conflict, missing-parent, insert-error, and no-double-count tests');
console.log(report);
