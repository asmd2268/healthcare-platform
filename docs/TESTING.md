# الاختبارات والجودة

الأوامر المعتمدة: `npm run lint` و`npm run typecheck` و`npm run test` و`npm run build` و`npm run check`. تشمل البداية اختبار تطابق مفاتيح الترجمة، ومنفعة الصلاحيات، وحدود البيئة. يضيف كل طور لاحقًا unit وintegration وpermission وlocalization وRTL/LTR وimport/export وmigration وsecurity وacceptance وregression وفق `PROJECT_BIBLE.md`.

CI في `.github/workflows/ci.yml` يعمل على Pull Requests وفروع `main` و`feature/**` ويشغل install ثم lint وtypecheck وtests وbuild، بلا أسرار إنتاج.

تضيف وحدة التفتيش اختبارات scoring، الأسئلة المطلوبة، الاستثناء N/A، الفشل الحرج، إنشاء Draft version، وإيجاد المخالفات، إضافة إلى اختبار تطابق ترجمات العربية والإنجليزية الموجود.

يضيف أساس Supabase اختبارات fail-closed للمصادقة، محتوى migration وRLS غير المتساهل، حماية الإصدارات المنشورة، وضمانات طلب الحذف. لا يمكن اعتبار اختبار migration أو RLS التشغيلي ناجحًا إلا عند توفر Supabase CLI وDocker وتشغيل قاعدة محلية Disposable؛ لم يُنفذ ذلك في هذه البيئة عند غياب الأداتين.
