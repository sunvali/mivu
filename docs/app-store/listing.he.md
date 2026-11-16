# App Store listing in Hebrew (draft)

The Hebrew localization of [listing.md](listing.md). Nothing here has been entered in App Store Connect; the owner uploads it.
Wording follows [the Hebrew glossary](../languages/he.md): gender-neutral, "Mivu" in Latin letters, Pip is "פיפ".
Counts are characters as Python's `len` measures them; recount after edits.

## Name (30)

Mivu – יומן אוכל ומאמן

## Subtitle (30)

רישום ארוחות בתמונה או בקול

## Promotional text (170)

אפשר לצלם ארוחה, לספר מה אכלת או להקליד. פיפ הופך את זה לקלוריות, חלבון, פחמימות ושומן שאפשר לבדוק, והיומן נשאר באייפון שלך.

## Keywords (100, comma-separated, no spaces)

קלוריות,ספירת קלוריות,יומן אוכל,דיאטה,חלבון,תזונה,משקל,מאקרו,ירידה במשקל,פחמימות,ארוחות,AI

## Description (4000)

Mivu הוא יומן אוכל פרטי עם מאמן ידידותי. אפשר לספר מה אכלת במילים שלך, לצלם או לדבר, ו-Mivu רושם את הארוחה עם הערכה של קלוריות, חלבון, פחמימות ושומן. כל הערכה פתוחה לבדיקה ולתיקון.

רישום כמו בשיחה
• לתאר ארוחה בשפה פשוטה: "שתי ביצים, טוסט וקפה עם חלב".
• להוסיף תמונות של הצלחת, או לדבר ולבדוק את הטקסט לפני השליחה.
• לרשום משקל בוקר ואימונים באותה שיחה.
• לבקש מפיפ לתקן כמות או מאכל, והיומן מתעדכן.

כל היום במבט אחד
• מסך היום מציג קלוריות ורכיבים תזונתיים מול יעדים שמתאימים לך.
• היומן שומר כל יום, עם פרטי ארוחה ותמונות.
• מסך ההתקדמות מציג את המשקל ואת הצריכה לאורך זמן.
• הקלוריות שנותרו מופיעות בווידג׳ט, במסך הנעילה וב-Dynamic Island.
• רישום ארוחה במרחק הקשה אחת ממסך הבית, ממרכז הבקרה ומסמל האפליקציה.

להכיר את פיפ
פיפ, השועל של Mivu, קובע איתך יעדים יומיים תוך דקה בערך ומגיב לכל רישום. הוא גם מתחשב בהגדרת “הפחתת תנועה” של המכשיר.

פרטיות מהיסוד
• בלי חשבון Mivu. היומן והתמונות נשמרים באייפון שלך.
• בלי פרסומות ובלי מעקב.
• גיבוי לתיקייה שבחרת, או ייצוא של היומן והתמונות בכל רגע.

AI שמשתמש בתוכנית שלך
אפשר לחבר את חשבון ChatGPT כדי להעריך ערכים תזונתיים ולשוחח עם פיפ. הבקשות משתמשות בתוכנית ChatGPT שלך, ואפשר לנהל את השימוש או להתנתק בהגדרות. Mivu שואל לפני שמשהו משותף עם OpenAI. באייפונים נתמכים, Apple Intelligence יכול לרשום ארוחות במכשיר עצמו, בלי חשבון.

הערכים התזונתיים הם הערכות ולא ייעוץ רפואי. לפני החלטות רפואיות או תזונתיות כדאי להתייעץ עם איש מקצוע בתחום הבריאות.

## What's New

עכשיו גם בעברית: כל המסכים, הווידג׳טים, Siri וההתראות. פיפ עונה בשפה שבה כתבת.

## Screenshots (6.9-inch iPhone, 1320 × 2868, in order)

Captured on an iPhone 17 Pro Max simulator in Hebrew with a real ChatGPT connection: the meals, targets and weights were entered through Pip and setup, in invented Hebrew. Framed with `swift scripts/app-store/frame.swift <capture> <out> "<caption>"`.


1. `screenshots/he/01-coach.png` — לרשום ארוחה במילים שלך
2. `screenshots/he/02-today.png` — כל היום במבט אחד
3. `screenshots/he/03-progress.png` — לראות כמה קרוב הגעת
4. `screenshots/he/04-targets.png` — יעדים שמתאימים לך
5. `screenshots/he/05-diary.png` — היומן נשאר באייפון שלך
