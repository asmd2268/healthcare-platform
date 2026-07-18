# الاختبارات والجودة

الأوامر المعتمدة: `npm run lint` و`npm run typecheck` و`npm run test` و`npm run build` و`npm run check`. تشمل البداية اختبار تطابق مفاتيح الترجمة، ومنفعة الصلاحيات، وحدود البيئة. يضيف كل طور لاحقًا unit وintegration وpermission وlocalization وRTL/LTR وimport/export وmigration وsecurity وacceptance وregression وفق `PROJECT_BIBLE.md`.

CI في `.github/workflows/ci.yml` يعمل على Pull Requests وفروع `main` و`feature/**` ويشغل install ثم lint وtypecheck وtests وbuild، بلا أسرار إنتاج.

## فحوصات Pull Request

- يجب أن ينجح فحص `quality` في كل Pull Request.
- يظهر فحص `inventory-database-concurrency` المطلوب في كل Pull Request، حتى عندما لا توجد تغييرات قاعدة بيانات.
- عند تغيير ملفات `supabase/**` أو `scripts/**` أو workflows أو ملفات package manifests، تُشغَّل اختبارات قاعدة بيانات inventory الكاملة، بما فيها مصفوفة concurrency.
- تغييرات التطبيق أو الوثائق غير المطابقة لهذه المسارات تتجاوز job الاختبارات الثقيلة، لكن فحص `inventory-database-concurrency` المطلوب يكتمل بنجاح عبر بوابة التوجيه.
- لا تتجاوز الفحوصات المطلوبة ولا تدفع مباشرة إلى `main`.

تضيف وحدة التفتيش اختبارات scoring، الأسئلة المطلوبة، الاستثناء N/A، الفشل الحرج، إنشاء Draft version، وإيجاد المخالفات، إضافة إلى اختبار تطابق ترجمات العربية والإنجليزية الموجود.

يضيف أساس Supabase اختبارات fail-closed للمصادقة، محتوى migration وRLS غير المتساهل، حماية الإصدارات المنشورة، وضمانات طلب الحذف. يضيف `supabase/tests/202607130002_hardening.sql` سيناريوهات bootstrap المتكرر، ورفض cross-tenant hierarchy، ورفض trusted-audit للمستخدمين غير المصرح لهم، وعزل organization/facility، وعرض المنشور فقط. لا يمكن اعتبار اختبار migration أو RLS التشغيلي ناجحًا إلا عند توفر Supabase CLI وDocker وتشغيل قاعدة محلية Disposable؛ لم يُنفذ ذلك في هذه البيئة عند غياب الأداتين.

تغطي اختبارات `supabase-target-safety` متغيرات Staging المطلوبة، رفض الأهداف التي تبدو إنتاجية، ورفض reset خارج بيئة local/staging. التحقق التشغيلي من Supabase منفصل يدويًا وفق [STAGING_VALIDATION.md](STAGING_VALIDATION.md).
