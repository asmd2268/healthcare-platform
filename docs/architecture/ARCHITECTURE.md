# Architecture

## Status

لا يزال التنفيذ غير معتمد، لكن المعمارية المفضلة موثقة في `PROJECT_BIBLE.md` و`docs/ARCHITECTURE.md`: Modular Monolith باستخدام Next.js وTypeScript وPostgreSQL/Supabase، بحدود وحدات قابلة للاستخراج لاحقًا.

## Decisions required

- تفاصيل نموذج العزل بين المستأجرين وخيار النشر لكل عميل.
- حدود كل وحدة وعقود التكامل الفعلية، من دون مخالفة مبدأ Modular Monolith.
- مزود الهوية، التخزين، المراقبة، وسياسات الاستعادة ضمن المتطلبات المعتمدة.

## Decision records

Add a dated decision record in this directory for each material architectural choice once approved.
