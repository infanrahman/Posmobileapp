import 'package:flutter/material.dart';

String tr(BuildContext context, String text) =>
    translateUi(text, Localizations.localeOf(context).languageCode);

String translateUi(String text, String language) {
  if (language != 'ar') return text;
  final exact = arabic[text];
  if (exact != null) return exact;
  for (final entry in _templates) {
    final match = entry.pattern.firstMatch(text);
    if (match == null) continue;
    var result = entry.translation;
    for (var i = 0; i < entry.keys.length; i++) {
      var value = match.group(i + 1)!;
      if (entry.keys[i] == 'location') value = arabic[value] ?? value;
      result = result.replaceAll('{${entry.keys[i]}}', value);
    }
    return result;
  }
  return text;
}

final _templates = arabic.entries.where((e) => e.key.contains('{')).map((e) {
  final keys = <String>[];
  final token = RegExp(r'\{(\w+)\}');
  var start = 0;
  var expression = '^';
  for (final match in token.allMatches(e.key)) {
    expression += RegExp.escape(e.key.substring(start, match.start));
    expression += '(.+?)';
    keys.add(match.group(1)!);
    start = match.end;
  }
  expression += '${RegExp.escape(e.key.substring(start))}\$';
  return (
    pattern: RegExp(expression, dotAll: true),
    keys: keys,
    translation: e.value,
  );
}).toList();

/// Translates interface labels at build time; business names and item names use
/// ordinary Text widgets so user-entered content is never translated.
class UiText extends StatelessWidget {
  final String data;
  final TextStyle? style;
  final TextAlign? textAlign;
  final TextOverflow? overflow;
  final int? maxLines;
  const UiText(
    this.data, {
    super.key,
    this.style,
    this.textAlign,
    this.overflow,
    this.maxLines,
  });
  @override
  Widget build(BuildContext context) => Text(
    tr(context, data),
    style: style,
    textAlign: textAlign,
    overflow: overflow,
    maxLines: maxLines,
  );
}

const arabic = <String, String>{
  'Stock adjustment': 'تعديل المخزون',
  'Adjustment history': 'سجل تعديلات المخزون',
  'No adjustments yet': 'لا توجد تعديلات بعد',
  'Reason for stock reduction': 'سبب تخفيض المخزون',
  'Damaged': 'تالف',
  'Expired': 'منتهي الصلاحية',
  'Missing': 'مفقود',
  'Damaged: {details}': 'تالف: {details}',
  'Expired: {details}': 'منتهي الصلاحية: {details}',
  'Missing: {details}': 'مفقود: {details}',
  'Quantity to remove': 'الكمية المراد إزالتها',
  'Reason / details': 'السبب / التفاصيل',
  'Shop and van': 'المحل والسيارة',
  'All dates': 'كل التواريخ',
  'Export CSV': 'تصدير CSV',
  'Report exported': 'تم تصدير التقرير',
  'Could not export report. Please try again.':
      'تعذر تصدير التقرير. حاول مرة أخرى.',
  'Current stock value at cost': 'قيمة المخزون الحالية بالتكلفة',
  'Dates': 'التواريخ',
  'Location': 'الموقع',
  'Report': 'التقرير',
  'Invoices are selected by original date, including all recorded returns and payments. Expenses use their recorded date. Stock value is current for the selected location, independent of dates.':
      'تُحدد الفواتير بتاريخها الأصلي وتشمل جميع المرتجعات والمدفوعات المسجلة. تُحدد المصروفات بتاريخ تسجيلها. قيمة المخزون حالية للموقع المحدد بصرف النظر عن التواريخ.',
  'Overview': 'الرئيسية',
  'Sales': 'المبيعات',
  'Stock': 'المخزون',
  'Customers': 'العملاء',
  'More': 'المزيد',
  'Shop': 'المحل',
  'Van': 'السيارة',
  'shop': 'المحل',
  'van': 'السيارة',
  'On-device': 'على الجهاز',
  'Language': 'اللغة',
  'English': 'English',
  'Arabic': 'العربية',
  'My business': 'نشاطي التجاري',
  'Your business, at a glance.': 'نظرة على نشاطك التجاري.',
  'Ready for the road.': 'جاهز للانطلاق.',
  "TODAY'S SALES": 'مبيعات اليوم',
  'To collect': 'مبالغ للتحصيل',
  'Low stock': 'مخزون منخفض',
  'Quick actions': 'إجراءات سريعة',
  'Make a sale': 'بيع جديد',
  'Move stock': 'نقل مخزون',
  'Customer': 'العميل',
  'Last 7 days': 'آخر ٧ أيام',
  'Recent sales': 'أحدث المبيعات',
  'View all': 'عرض الكل',
  'Shop counter': 'نقطة بيع المحل',
  'Van inventory': 'مخزون السيارة',
  'Shop inventory': 'مخزون المحل',
  'Shop stock': 'مخزون المحل',
  'Van stock': 'مخزون السيارة',
  'Your first sale starts here': 'ابدأ أول عملية بيع',
  'Add your products, then create a sale. Every record stays on this device.':
      'أضف المنتجات ثم أنشئ عملية بيع. تُحفظ جميع السجلات على هذا الجهاز.',
  'Works without internet. Shop and van data on this device are separate stock locations.':
      'يعمل دون إنترنت. مخزون المحل والسيارة منفصلان على هذا الجهاز.',
  'Sales ledger': 'سجل المبيعات',
  'Every sale. Every payment. Saved locally.':
      'كل عملية بيع وكل دفعة محفوظة محلياً.',
  'Search invoice or customer': 'ابحث عن فاتورة أو عميل',
  'No sales found': 'لا توجد مبيعات',
  'Create a sale using the button below.':
      'أنشئ عملية بيع باستخدام الزر أدناه.',
  'New sale': 'بيع جديد',
  'Paid': 'مدفوع',
  'Partial': 'جزئي',
  'Credit': 'آجل',
  'Receive stock or transfer between shop and van.':
      'استلم المخزون أو انقله بين المحل والسيارة.',
  'Search item name or SKU': 'ابحث عن اسم الصنف أو رمزه',
  'No items found': 'لا توجد أصناف',
  'Add an item with its selling price and opening stock.':
      'أضف صنفاً مع سعر البيع والمخزون الافتتاحي.',
  'Add item': 'إضافة صنف',
  'In stock': 'متوفر',
  'Your customers': 'عملاؤك',
  'Shop and van customers • credit balances combined':
      'عملاء المحل والسيارة • إجمالي الأرصدة الآجلة',
  'Search name, phone or area': 'ابحث بالاسم أو الهاتف أو المنطقة',
  'Build your customer book': 'أنشئ دليل العملاء',
  'Save customer details to track credit sales and collections.':
      'احفظ بيانات العملاء لمتابعة المبيعات الآجلة والتحصيلات.',
  'Add customer': 'إضافة عميل',
  'Business tools': 'أدوات النشاط',
  'Purchases, expenses, suppliers and reports.':
      'المشتريات والمصروفات والموردون والتقارير.',
  'Purchases': 'المشتريات',
  'Receive stock and track supplier credit':
      'استلام المخزون ومتابعة مستحقات الموردين',
  'Suppliers': 'الموردون',
  'Contacts and payable balances': 'بيانات التواصل والأرصدة المستحقة',
  'Expenses': 'المصروفات',
  'Record daily business costs': 'تسجيل مصروفات النشاط اليومية',
  'Reports': 'التقارير',
  'Sales, profit, stock and balances': 'المبيعات والأرباح والمخزون والأرصدة',
  'Business profile': 'بيانات النشاط',
  'Business name': 'اسم النشاط',
  'Sales tax': 'ضريبة المبيعات',
  'Tax rate (%)': 'نسبة الضريبة (%)',
  'Built to work offline': 'مصمم للعمل دون إنترنت',
  'Sales, stock and customers are stored in SQLite on this phone. No account or internet is needed for daily use.':
      'تُحفظ المبيعات والمخزون والعملاء على هذا الهاتف. لا يلزم حساب أو إنترنت للاستخدام اليومي.',
  'Save regular backups. Devices do not sync automatically. Saudi e-invoicing and thermal printer support are not configured. Use sample business data while testing.':
      'احفظ نسخاً احتياطية بانتظام. لا تتم مزامنة الأجهزة تلقائياً. الفوترة الإلكترونية السعودية والطابعات الحرارية غير مهيأة. استخدم بيانات تجريبية أثناء الاختبار.',
  'Add inventory item': 'إضافة صنف للمخزون',
  'Item name': 'اسم الصنف',
  'SKU / barcode': 'رمز الصنف / الباركود',
  'Selling price (SAR)': 'سعر البيع (ر.س)',
  'Purchase cost (SAR)': 'تكلفة الشراء (ر.س)',
  'Opening quantity': 'الكمية الافتتاحية',
  'Customer / shop name': 'اسم العميل / المحل',
  'Phone number': 'رقم الهاتف',
  'Area / route': 'المنطقة / المسار',
  'Edit item details': 'تعديل بيانات الصنف',
  'Edit inventory item': 'تعديل صنف المخزون',
  'Receive stock': 'استلام مخزون',
  'Transfer stock': 'نقل مخزون',
  'Quantity': 'الكمية',
  'No sales for this customer yet.': 'لا توجد مبيعات لهذا العميل بعد.',
  'Sales record • saved on this device': 'سجل بيع • محفوظ على هذا الجهاز',
  'Subtotal': 'المجموع الفرعي',
  'Total': 'الإجمالي',
  'Returns': 'المرتجعات',
  'Refunded': 'المبلغ المسترد',
  'Balance due': 'الرصيد المستحق',
  'Balance': 'الرصيد',
  'Record payment': 'تسجيل دفعة',
  'Record customer payment': 'تسجيل تحصيل من العميل',
  'Return items': 'إرجاع أصناف',
  'Return sale items': 'إرجاع أصناف البيع',
  'Returned quantities go back to the original stock location.':
      'تُعاد الكميات المرتجعة إلى موقع المخزون الأصلي.',
  'Confirm return': 'تأكيد الإرجاع',
  'Return saved and stock restored.': 'تم حفظ المرتجع وإعادة المخزون.',
  'Sales record for testing. Saudi e-invoicing is not configured.':
      'سجل بيع للاختبار. الفوترة الإلكترونية السعودية غير مهيأة.',
  'Total sales including configured tax':
      'إجمالي المبيعات شاملاً الضريبة المحددة',
  'Save': 'حفظ',
  'Saving…': 'جارٍ الحفظ…',
  'Cancel': 'إلغاء',
  'Try again': 'إعادة المحاولة',
  'Supplier accounts': 'حسابات الموردين',
  'Contacts and purchase balances saved offline.':
      'بيانات التواصل وأرصدة المشتريات محفوظة دون إنترنت.',
  'Add supplier': 'إضافة مورد',
  'Supplier name': 'اسم المورد',
  'VAT / tax number': 'الرقم الضريبي',
  'Address': 'العنوان',
  'No suppliers yet': 'لا يوجد موردون بعد',
  'Add a supplier before recording a credit purchase.':
      'أضف مورداً قبل تسجيل شراء آجل.',
  'payable': 'مستحق الدفع',
  'Purchase ledger': 'سجل المشتريات',
  'New purchase': 'شراء جديد',
  'No purchases yet': 'لا توجد مشتريات بعد',
  'Record stock bought from a supplier.': 'سجّل المخزون المشترى من المورد.',
  'Pay supplier': 'دفع للمورد',
  'Record supplier payment': 'تسجيل دفعة للمورد',
  'Amount (SAR)': 'المبلغ (ر.س)',
  'Unit cost (SAR)': 'تكلفة الوحدة (ر.س)',
  'Supplier': 'المورد',
  'Cash supplier': 'شراء نقدي دون مورد',
  'Search products': 'البحث عن المنتجات',
  'No products available': 'لا توجد منتجات',
  'Add products from the Stock tab first.':
      'أضف منتجات من تبويب المخزون أولاً.',
  'Purchase total': 'إجمالي الشراء',
  'Amount paid (SAR)': 'المبلغ المدفوع (ر.س)',
  'Expense book': 'سجل المصروفات',
  'Fuel, meals, rent and other operating costs.':
      'الوقود والوجبات والإيجار والمصروفات التشغيلية الأخرى.',
  'Add expense': 'إضافة مصروف',
  'Category': 'الفئة',
  'Description': 'الوصف',
  'No expenses yet': 'لا توجد مصروفات بعد',
  'Record business costs to improve your profit report.':
      'سجّل مصروفات النشاط لتحسين دقة تقرير الأرباح.',
  'Business reports': 'تقارير النشاط',
  'All recorded activity • shop and van combined':
      'جميع العمليات المسجلة • المحل والسيارة معاً',
  'Net sales': 'صافي المبيعات',
  'Gross profit': 'مجمل الربح',
  'Receivable': 'مستحقات العملاء',
  'Payable': 'مستحقات الموردين',
  'Stock value at cost': 'قيمة المخزون بالتكلفة',
  'Net sales tax': 'صافي ضريبة المبيعات',
  'Profit after expenses': 'الربح بعد المصروفات',
  'Gross profit uses the item cost saved at the time of sale. It is an operational estimate, not a filed tax statement.':
      'يُحسب مجمل الربح حسب تكلفة الصنف وقت البيع. هذا تقدير تشغيلي وليس إقراراً ضريبياً.',
  'No more stock available at this location.':
      'لا توجد كمية إضافية في هذا الموقع.',
  'Discard this sale?': 'تجاهل عملية البيع؟',
  'This unsaved cart will be cleared. Your inventory has not changed.':
      'ستُمسح السلة غير المحفوظة. لم يتغير المخزون.',
  'Keep editing': 'متابعة التعديل',
  'Discard': 'تجاهل',
  'Walk-in customer': 'عميل نقدي',
  'Add items': 'إضافة أصناف',
  'Search item or SKU': 'ابحث عن صنف أو رمز',
  'Add items from the Stock tab before making a sale.':
      'أضف أصنافاً من تبويب المخزون قبل البيع.',
  'No matching items.': 'لا توجد أصناف مطابقة.',
  'Sale summary': 'ملخص البيع',
  'Payment': 'الدفع',
  'Amount received (SAR)': 'المبلغ المستلم (ر.س)',
  'Select a named customer to keep an unpaid balance.':
      'اختر عميلاً مسجلاً للاحتفاظ برصيد غير مدفوع.',
  'Saving locally…': 'جارٍ الحفظ على الجهاز…',
  'Saved on this device. No internet required.':
      'محفوظ على هذا الجهاز. لا حاجة للإنترنت.',
  'Backup and restore': 'النسخ الاحتياطي والاستعادة',
  'Save your records or recover from a backup':
      'حفظ السجلات أو استعادتها من نسخة احتياطية',
  'Keep a copy of your business': 'احتفظ بنسخة من سجلات نشاطك',
  'Backups include products, shop and van stock, customers, suppliers, sales, purchases, payments, returns, expenses and settings.':
      'تشمل النسخة المنتجات ومخزون المحل والسيارة والعملاء والموردين والمبيعات والمشتريات والمدفوعات والمرتجعات والمصروفات والإعدادات.',
  'Save to Files or a folder you choose. A local backup works without internet.':
      'احفظ في تطبيق الملفات أو مجلد تختاره. النسخ المحلي يعمل دون إنترنت.',
  'Save backup': 'حفظ نسخة احتياطية',
  'Restore from file': 'استعادة من ملف',
  'Save Rihla backup': 'حفظ نسخة رحلة',
  'Choose a Rihla backup': 'اختر نسخة احتياطية لرحلة',
  'Restore this backup?': 'استعادة هذه النسخة؟',
  'Replace records': 'استبدال السجلات',
  'This replaces all records on this phone, including payments, returns, stock and settings. Records are not merged. Save a backup of your current data first if you want to keep it.':
      'سيتم استبدال جميع السجلات على هذا الهاتف، بما فيها المدفوعات والمرتجعات والمخزون والإعدادات. لن تُدمج السجلات. احفظ نسخة من بياناتك الحالية أولاً إذا أردت الاحتفاظ بها.',
  'Backup saved. Keep a copy outside this app.':
      'تم حفظ النسخة الاحتياطية. احتفظ بنسخة خارج هذا التطبيق.',
  'Backup cancelled. No file was saved to your selected location.':
      'أُلغي النسخ الاحتياطي. لم يُحفظ ملف في الموقع المحدد.',
  'Restore cancelled. Your records are unchanged.':
      'أُلغيت الاستعادة. لم تتغير سجلاتك.',
  'Backup files are not encrypted and contain business and customer details. Keep them in a private location outside the app. Cloud file providers may need internet. Backups do not sync devices.':
      'ملفات النسخ الاحتياطي غير مشفرة وتحتوي على بيانات النشاط والعملاء. احتفظ بها في مكان خاص خارج التطبيق. قد تحتاج خدمات الملفات السحابية إلى الإنترنت. النسخ الاحتياطية لا تزامن الأجهزة.',
  'Could not complete this operation. Your records have not been replaced.':
      'تعذر إكمال العملية. لم تُستبدل سجلاتك.',
  'Could not open your local data': 'تعذر فتح بياناتك المحلية',
  'Could not load inventory. Reopen this sale to retry.':
      'تعذر تحميل المخزون. أعد فتح البيع للمحاولة.',
  'Could not save the sale. Please try again.':
      'تعذر حفظ البيع. حاول مرة أخرى.',
  'Could not save this purchase.': 'تعذر حفظ عملية الشراء.',
  'Could not save the return.': 'تعذر حفظ المرتجع.',
  'Could not save. Your changes were not applied. Please try again.':
      'تعذر الحفظ. لم تُطبق التغييرات. حاول مرة أخرى.',
  'This SKU already exists. Use a different SKU.':
      'رمز الصنف موجود بالفعل. استخدم رمزاً آخر.',
  'Enter an opening quantity from 0 to 1,000,000.':
      'أدخل كمية افتتاحية من ٠ إلى ١٬٠٠٠٬٠٠٠.',
  'Share PDF': 'مشاركة PDF',
  'Save PDF': 'حفظ PDF',
  'Invoice PDF': 'فاتورة PDF',
  'PDF saved.': 'تم حفظ ملف PDF.',
  'PDF save cancelled.': 'أُلغي حفظ PDF.',
  'Could not create the PDF. Please try again.':
      'تعذر إنشاء ملف PDF. حاول مرة أخرى.',
  'Choose PDF action': 'اختر إجراء PDF',
  'Rihla POS • Version {version}': 'رحلة POS • الإصدار {version}',
  '{count} sales recorded  •  {location}':
      'عمليات البيع المسجلة: {count} • {location}',
  '{count} items': 'عدد الأصناف: {count}',
  '{count} units': 'الوحدات: {count}',
  '{amount} due': 'المستحق: {amount}',
  'Outstanding: {amount}': 'الرصيد المستحق: {amount}',
  'Shop: {shop} • Van: {van}': 'المحل: {shop} • السيارة: {van}',
  'Receive stock into {location}': 'استلام مخزون في {location}',
  'Transfer from {location}': 'نقل من {location}',
  'Stock received into {location}.': 'استلام المخزون في {location}.',
  'Purchase #{id}': 'شراء رقم {id}',
  'Purchase {name}': 'شراء {name}',
  'Current cost {amount}': 'التكلفة الحالية {amount}',
  'Save purchase • {amount}': 'حفظ الشراء • {amount}',
  'Tax ({rate}%)': 'الضريبة ({rate}%)',
  '{rate}% • prices exclude tax': '{rate}% • الأسعار لا تشمل الضريبة',
  '{count} available to return': 'الكمية المتاحة للإرجاع: {count}',
  'Return saved. Refund {amount} to the customer.':
      'حُفظ المرتجع. أعد {amount} إلى العميل.',
  'Complete sale • {amount}': 'إتمام البيع • {amount}',
  'Remove one {name}': 'إزالة وحدة من {name}',
  'Add one {name}': 'إضافة وحدة من {name}',
  '{invoice} saved. Stock and balances updated.':
      'تم حفظ {invoice}. حُدّث المخزون والأرصدة.',
  'Saved {date}': 'تاريخ الحفظ: {date}',
  '{count} products': 'المنتجات: {count}',
  '{count} customers': 'العملاء: {count}',
  '{count} suppliers': 'الموردون: {count}',
  '{count} sales': 'المبيعات: {count}',
  '{count} purchases': 'المشتريات: {count}',
  '{count} expenses': 'المصروفات: {count}',
  'Backup restored for {business}. Your records are ready.':
      'استُعيدت نسخة {business}. سجلاتك جاهزة.',
  'Enter an amount with up to two decimal places.':
      'أدخل مبلغاً بمنزلتين عشريتين كحد أقصى.',
  'Enter a whole quantity between 1 and 1,000,000.':
      'أدخل كمية صحيحة بين ١ و١٬٠٠٠٬٠٠٠.',
  'Enter a business name and a tax rate from 0 to 100.':
      'أدخل اسم النشاط ونسبة ضريبة من ٠ إلى ١٠٠.',
  'Unsupported language.': 'اللغة غير مدعومة.',
  'Name, unique SKU, price and stock are required.':
      'الاسم ورمز صنف فريد والسعر والمخزون مطلوبة.',
  'Name, unique SKU, cost and price are required.':
      'الاسم ورمز صنف فريد والتكلفة والسعر مطلوبة.',
  'Product no longer exists.': 'الصنف لم يعد موجوداً.',
  'Customer name is required.': 'اسم العميل مطلوب.',
  'Quantity must be positive.': 'يجب أن تكون الكمية أكبر من صفر.',
  'Not enough stock to transfer.': 'المخزون غير كافٍ للنقل.',
  'Add an item to the sale.': 'أضف صنفاً إلى البيع.',
  'Invalid tax rate.': 'نسبة الضريبة غير صالحة.',
  'Customer no longer exists.': 'العميل لم يعد موجوداً.',
  'Invalid quantity.': 'الكمية غير صالحة.',
  'Not enough {name} stock in {location}.':
      'مخزون {name} غير كافٍ في {location}.',
  'Payment must be between zero and the sale total.':
      'يجب أن يكون المبلغ المدفوع بين صفر وإجمالي البيع.',
  'Select a customer for a credit sale.': 'اختر عميلاً للبيع الآجل.',
  'Payment must be greater than zero.':
      'يجب أن يكون المبلغ المدفوع أكبر من صفر.',
  'Payment exceeds the outstanding balance.': 'المبلغ يتجاوز الرصيد المستحق.',
  'Supplier name is required.': 'اسم المورد مطلوب.',
  'Add an item to the purchase.': 'أضف صنفاً إلى الشراء.',
  'Supplier no longer exists.': 'المورد لم يعد موجوداً.',
  'Purchase quantities and costs are invalid.':
      'كميات الشراء وتكاليفه غير صالحة.',
  'Payment must be between zero and the purchase total.':
      'يجب أن يكون المبلغ المدفوع بين صفر وإجمالي الشراء.',
  'Select a supplier for a credit purchase.': 'اختر مورداً للشراء الآجل.',
  'Payment exceeds the purchase balance.': 'المبلغ يتجاوز رصيد الشراء.',
  'Expense category and amount are required.': 'فئة المصروف والمبلغ مطلوبان.',
  'Choose at least one item to return.': 'اختر صنفاً واحداً على الأقل للإرجاع.',
  'Sale no longer exists.': 'عملية البيع لم تعد موجودة.',
  'Return quantity must be positive.': 'يجب أن تكون كمية الإرجاع أكبر من صفر.',
  'Sale item no longer exists.': 'صنف البيع لم يعد موجوداً.',
  'Only {count} {name} can be returned.': 'يمكن إرجاع {count} فقط من {name}.',
  'Choose a Rihla backup smaller than 25 MB.':
      'اختر نسخة احتياطية لرحلة بحجم أقل من ٢٥ ميغابايت.',
  'This backup format is not supported.': 'تنسيق النسخة الاحتياطية غير مدعوم.',
  'The backup is damaged or incomplete.':
      'النسخة الاحتياطية تالفة أو غير مكتملة.',
  'The backup is missing required records.':
      'تفتقد النسخة الاحتياطية سجلات مطلوبة.',
  'Invalid backup records.': 'سجلات النسخة الاحتياطية غير صالحة.',
  'Invalid backup record.': 'سجل النسخة الاحتياطية غير صالح.',
  'The backup business settings are invalid.':
      'إعدادات النشاط في النسخة الاحتياطية غير صالحة.',
  'The backup tax setting is invalid.':
      'إعداد الضريبة في النسخة الاحتياطية غير صالح.',
  'The backup language setting is invalid.':
      'إعداد اللغة في النسخة الاحتياطية غير صالح.',
  'This file is not a valid Rihla backup.':
      'هذا الملف ليس نسخة احتياطية صالحة لرحلة.',
  'This backup exceeds the 25 MB limit.':
      'النسخة الاحتياطية تتجاوز حد ٢٥ ميغابايت.',
  'Backup record fields do not match this app.':
      'حقول سجلات النسخة لا تتطابق مع هذا التطبيق.',
  'Backup record values are invalid.': 'قيم سجلات النسخة الاحتياطية غير صالحة.',
  'Backup record identifiers are invalid.':
      'معرّفات سجلات النسخة الاحتياطية غير صالحة.',
  'Backup stock location is invalid.':
      'موقع المخزون في النسخة الاحتياطية غير صالح.',
  'The backup contains broken record links.':
      'تحتوي النسخة الاحتياطية على روابط سجلات غير صالحة.',
  'The backup contains invalid records. Your existing data was not changed.':
      'تحتوي النسخة على سجلات غير صالحة. لم تتغير بياناتك الحالية.',
  'Backup balances do not match its records. Your existing data was not changed.':
      'أرصدة النسخة لا تتطابق مع سجلاتها. لم تتغير بياناتك الحالية.',
  'Edit customer': 'تعديل العميل',
  'Edit supplier': 'تعديل المورد',
  'Items total': 'إجمالي الأصناف',
  'Discount': 'الخصم',
  'Discount (SAR)': 'الخصم (ر.س)',
  'Discount is applied before tax.': 'يُطبق الخصم قبل الضريبة.',
  'Discount exceeds the items total.': 'الخصم يتجاوز إجمالي الأصناف.',
  'Discount must be between zero and the items total.':
      'يجب أن يكون الخصم بين صفر وإجمالي الأصناف.',
  'Supplier refunds received': 'مبالغ مستردة من المورد',
  'Supplier refund received': 'مبلغ مسترد من المورد',
  'Return purchase items': 'إرجاع أصناف الشراء',
  'Return value': 'قيمة المرتجع',
  'Purchase returns remove stock from the original location and reduce the supplier balance.':
      'تُخصم مرتجعات الشراء من المخزون في الموقع الأصلي وتُخفض رصيد المورد.',
  'Confirm only after receiving the supplier refund shown above.':
      'أكد فقط بعد استلام المبلغ المسترد من المورد الموضح أعلاه.',
  'Purchase return saved. Supplier refund received: {amount}':
      'حُفظ مرتجع الشراء. المبلغ المسترد من المورد: {amount}',
  'Purchase no longer exists.': 'عملية الشراء لم تعد موجودة.',
  'Purchase item no longer exists.': 'صنف الشراء لم يعد موجوداً.',
  'Not enough stock at the original purchase location.':
      'المخزون غير كافٍ في موقع الشراء الأصلي.',
  '{quantity} × {price} • {returned} returned':
      '{quantity} × {price} • المرتجع: {returned}',
  'Scan barcode': 'مسح الباركود',
  'Barcode (optional)': 'الباركود (اختياري)',
  'Barcode / SKU': 'الباركود / رمز الصنف',
  'Enter code manually': 'إدخال الرمز يدوياً',
  'Use code': 'استخدام الرمز',
  'Use camera': 'استخدام الكاميرا',
  'Show one barcode at a time.': 'اعرض باركوداً واحداً في كل مرة.',
  'Enter or scan a barcode.': 'أدخل الباركود أو امسحه.',
  'Enter a barcode with up to 128 characters on one line.':
      'أدخل باركوداً حتى ١٢٨ حرفاً في سطر واحد.',
  'No product matches this code. Add its barcode in Stock first.':
      'لا يوجد صنف مطابق. أضف باركوده في المخزون أولاً.',
  'This code matches multiple products. Check their barcodes and SKUs in Stock.':
      'يطابق الرمز عدة أصناف. راجع الباركود ورموز الأصناف في المخزون.',
  'This barcode already belongs to another product.':
      'هذا الباركود مرتبط بصنف آخر.',
  'Backup barcodes are invalid.': 'باركودات النسخة الاحتياطية غير صالحة.',
  'Added {name} to the sale.': 'أُضيف {name} إلى البيع.',
  'Camera unavailable. Allow camera access in your phone settings, or enter the code manually.':
      'الكاميرا غير متاحة. اسمح بالوصول إليها في إعدادات الهاتف أو أدخل الرمز يدوياً.',
  'Point the camera at one product barcode. Scanning works offline.':
      'وجّه الكاميرا إلى باركود صنف واحد. يعمل المسح دون إنترنت.',
};
