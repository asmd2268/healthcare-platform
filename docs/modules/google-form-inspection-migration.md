# نقل Google Forms للتفتيش

لا يتم scraping أو تخمين أسئلة النموذج المرتبط. عند توفر export مصرح به، تُطابق مجموعات الأسئلة إلى Sections، والأسئلة إلى `InspectionQuestion`، والاختيارات إلى `InspectionAnswerOption`، وتُراجع required/score/finding rules يدويًا. تستورد الردود التاريخية إلى Sessions/Responses فقط بعد mapping معرفات ومراجعة الخصوصية.

```json
{"template":{"name":{"ar":"","en":""},"inspectionType":"","passingScore":80},"sections":[{"title":{"ar":"","en":""},"weight":1,"questions":[{"text":{"ar":"","en":""},"type":"compliance","required":true,"weight":1,"maxScore":100,"options":[]}]}]}
```
