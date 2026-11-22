import fs from 'node:fs';
import vm from 'node:vm';
const html = fs.readFileSync(new URL('../src/index.html', import.meta.url), 'utf8');
const vendorMigration = fs.readFileSync(new URL('../../supabase/migrations/20261121043705_finance_vendors_and_expenses.sql', import.meta.url), 'utf8');
const vatMigration = fs.readFileSync(new URL('../../supabase/migrations/20261122010000_finance_customer_and_vendor_vat.sql', import.meta.url), 'utf8');
const vendorBillUpdates = vatMigration.split('update public.finance_vendor_bills set').slice(1);
const vendorBillUpdatesAreScoped = vendorBillUpdates.length === 1 && vendorBillUpdates[0].includes('where organization_id=v_org and id=p_bill_id;');
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
  ['Invoice PDF clarifies missing payment references', html.includes("p.reference||'غير مسجل'")],
  ['Invoice PDF footer aligned to page bottom', html.includes('min-height:270mm') && html.includes('margin-top:auto;padding-top:13px')],
  ['Invoice PDF preserves existing financial values', html.includes('invoice.subtotal_original') && html.includes('invoice.vat_original') && html.includes('invoice.total_original') && html.includes('invoice.paid_original')],
  ['Vendor directory and bill workflow UI', html.includes('financeVendorName') && html.includes('financeVendorBillsTable') && html.includes('createFinanceVendorBillDraft()')],
  ['Vendor payable defaults to accounts payable rather than output VAT', html.includes("a.account_code==='2000'") && html.includes('preferredPayable')],
  ['Vendor payable selector only offers approved accounts payable and rejects output VAT account 2200', html.includes('function financeVendorIsPayableAccount(account)') && html.includes('financeAccounts.filter(financeVendorIsPayableAccount)') && html.includes('!financeVendorIsPayableAccount(selectedPayable)')],
  ['Vendor bill posting is blocked when an existing draft has an invalid payable account', html.includes('status,payable_account_id') && html.includes('!financeVendorIsPayableAccount(payableAccount)') && html.includes('تم إيقاف اعتماد هذه المسودة')],
  ['Vendor expense defaults to operating expenses account 5000 while preserving manual selection', html.includes("String(a.account_code||'').trim()==='5000'") && html.includes('preferredExpense') && html.includes('!expenseSelect.value&&preferredExpense')],
  ['Vendor input VAT defaults to active recoverable VAT asset account 1300 while preserving manual selection', html.includes("String(a.account_code||'').trim()==='1300'") && html.includes('preferredInputVat') && html.includes('!vatSelect.value&&preferredInputVat')],
  ['Vendor edit form and action available with address and active status', html.includes('openFinanceVendorEditModal') && html.includes('financeVendorEditAddress') && html.includes('financeVendorEditStatus')],
  ['Vendor edit action safely passes the vendor ID and resolves string IDs', html.includes('openFinanceVendorEditModal(&quot;') && html.includes('String(v.id)===String(id)')],
  ['Vendor updates are tenant-scoped and preserve bill/payment history', html.includes(".from('finance_vendors').update(payload).eq('organization_id',currentOrganizationId).eq('id',id)") && html.includes('لم يتم تغيير الفواتير أو الدفعات السابقة')],
  ['Vendor draft bill edit button only appears for drafts and managers', html.includes("b.status==='draft'&&financeCanManage()") && html.includes('openFinanceVendorBillEditModal') && html.includes("'+details+' '+edit+' '+action")],
  ['Vendor bill draft edit is limited to approved payable account and tenant-scoped draft-only update', html.includes('financeVendorBillEditPayable') && html.includes('financeAccounts.filter(financeVendorIsPayableAccount)') && html.includes(".update({payable_account_id:accountId}).eq('organization_id',currentOrganizationId).eq('id',id).eq('status','draft')")],
  ['Vendor bill edit preserves totals, VAT, lines and payments without posting', html.includes('لم تتغير قيمة الفاتورة أو الضريبة أو الدفعات') && html.includes('لم يُنشأ قيد ولم يتم ترحيلها')],
  ['Read-only vendor bill details action available for every bill status', html.includes("openFinanceVendorBillDetails(\\'") && html.includes('التفاصيل') && html.includes('closeFinanceVendorBillDetails()')],
  ['Vendor bill details load tenant-scoped bill lines and payments', html.includes(".from('finance_vendor_bill_lines').select(") && html.includes(".from('finance_vendor_bill_payments').select(") && html.includes(".eq('organization_id',currentOrganizationId).eq('bill_id',id)")],
  ['Vendor bill details show linked expense/payable and payment journals', html.includes(".from('finance_journals').select(") && html.includes(".from('finance_journal_lines').select(") && html.includes('issued_journal_id')],
  ['Vendor bill details show explicit VAT instead of treating the total difference as tax', html.includes('ضريبة القيمة المضافة (') && html.includes('الإجمالي شامل الضريبة') && html.includes('vat_original')],
  ['Vendor bill VAT rate and recoverable input VAT account fields', html.includes('id="financeVendorVatRate"') && html.includes('id="financeVendorVatAccount"')],
  ['Vendor bill draft RPC sends VAT rate and input VAT account', html.includes('p_vat_rate:vatRate') && html.includes('p_vat_account_id:vatAccount')],
  ['Vendor bill details show stored subtotal, VAT and VAT account', html.includes('subtotal_original,subtotal_base,vat_rate,vat_original,vat_base,vat_account_id') && html.includes('حساب ضريبة المدخلات') && html.includes('الإجمالي شامل الضريبة')],
  ['VAT migration adds supplier input VAT fields without bulk-rewriting old bill values', vatMigration.includes('add column if not exists subtotal_original') && vatMigration.includes('add column if not exists vat_account_id') && vendorBillUpdatesAreScoped],
  ['Supplier input VAT requires an active asset account', vatMigration.includes("account_type='asset'") && vatMigration.includes('recoverable input VAT asset account')],
  ['Supplier posting debits recoverable input VAT and credits payable including VAT', vatMigration.includes("v_bill.vat_account_id,'ضريبة قيمة مضافة مدخلات قابلة للاسترداد") && vatMigration.includes('v_vat,0,v_vat_base,0') && vatMigration.includes('v_bill.payable_account_id') && vatMigration.includes('0,v_total,0,v_total_base')],
  ['Customer output VAT draft and posting functions remain available', vatMigration.includes('p_vat_rate numeric,p_vat_account_id uuid') && vatMigration.includes('ضريبة قيمة مضافة مستحقة')],
  ['Vendor bill draft creation RPC', html.includes("sb.rpc('create_finance_vendor_bill_draft'")],
  ['Vendor bill posting and payable journal RPC', html.includes("sb.rpc('issue_finance_vendor_bill'") && html.includes('ترحيل قيد المصروف والمستحقات')],
  ['Vendor bill payment and cash journal RPC', html.includes("sb.rpc('record_finance_vendor_bill_payment'")],
  ['Vendor statement is read-only and date-scoped', html.includes('كشف حساب المورد') && html.includes('.eq(\'vendor_id\',vendorId)') && html.includes('startDate>endDate')],
  ['Vendor bill tables enforce tenant RLS', vendorMigration.includes('finance_vendor_bills_tenant_scope') && vendorMigration.includes('finance_vendors_tenant_scope') && vendorMigration.includes('finance_vendor_bill_payments_tenant_scope')],
  ['Posted vendor bills and payments are immutable', vendorMigration.includes('Issued and paid vendor bills are immutable') && vendorMigration.includes('Vendor payment records are immutable')],
  ['Vendor bill draft validates liability and expense accounts', vendorMigration.includes("account_type='liability'") && vendorMigration.includes("account_type='expense'")],
  ['Vendor bill posting creates balanced expense and payable journal', vendorMigration.includes('إثبات فاتورة مورد') && vendorMigration.includes('finance_journal_lines') && vendorMigration.includes('status=\'posted\'')],
  ['Vendor payments validate cash/bank account and outstanding balance', vendorMigration.includes('p_amount>v_remaining') && vendorMigration.includes('Select an active cash or bank account')],
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
