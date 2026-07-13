# محرك التقارير والتحليلات المشترك

يوفر المحرك طبقة قراءة معيارية قابلة لإعادة الاستخدام لجميع الوحدات، ولا يقرأ المتصفح الجداول التشغيلية مباشرة. يتكون من Report Definition وإصدارات versioned immutable عند النشر، Saved Reports، filters وcolumns وcalculations وgrouping وdrill-down contracts، وReport Runs وExport contracts.

تسجل كل وحدة adapter يحدد حقول القراءة والمقاييس المسموحة فقط؛ لا يقبل المحرك SQL أو expressions أو أسماء جداول من العميل. يدعم طبقة العقود count/sum/average/median/min/max/percentage وSLA/open/closed/pending/risk/trend. التنفيذ الفعلي للاستعلامات، caching، وdrill-down المصادق عليه خادميًا ما زال placeholder واضحًا.

تتضمن عقود التصدير PDF وExcel وCSV، مع Arabic/English/Bilingual. ستعالج طبقة إخراج خادمية الهوية والشعار والتنسيق وRTL/LTR ومنع الحقول السرية قبل إنشاء الملف. الجدولة محفوظة كحالة مستقبلية، ولا يتم إرسال بريد أو إنشاء ملفات في هذا الأساس.
