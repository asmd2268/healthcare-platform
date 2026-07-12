# Development guide

## Status

لا يوجد كود تطبيق بعد، إلا أن المكدس المفضل محدد: Next.js وTypeScript وPostgreSQL/Supabase، مع Vercel وGitHub، وPWA مستقبلي. `PROJECT_BIBLE.md` هو المرجع الملزم قبل أي تنفيذ.

## Before the first feature

1. Read `PROJECT_BIBLE.md` كاملًا والوثائق ذات الصلة، وتوثيق المخاطر والوحدات المتأثرة وخطة الاختبار.
2. اعتماد إصدارات runtimes وإدارة الحزم والتنسيق وCI ضمن المكدس المفضل، دون مخالفة المعمارية أو قابلية النقل.
3. Define environment handling and secret-management practices.
4. Establish code review, quality gates, and release practices.
5. وثّق إعداد التطوير، وخطة الترحيل، والتوافق الخلفي، وأوامر التحقق. لا تلمس بيانات إنتاج مباشرة ولا تنفذ Migration مدمرة بلا نسخة احتياطية وخطة تراجع.
