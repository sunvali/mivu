# App Store listing in Spanish (draft)

The Spanish localization of [listing.md](listing.md). Nothing here has been entered in App Store Connect; the owner uploads it.
Wording follows [the Spanish glossary](../languages/es.md): tú, neutral Latin American Spanish, gender-neutral, "Mivu" and "Pip" unchanged.
Counts are characters as Python's `len` measures them; recount after edits.

## Name (30)

Mivu – Diario de comidas

## Subtitle (30)

Registra comida con foto o voz

## Promotional text (170)

Toma una foto, cuéntale a Pip lo que comiste o escríbelo. Pip y Coach lo convierten en calorías y macros que puedes revisar, y tu diario se queda en tu iPhone.

## Keywords (100, comma-separated, no spaces)

calorías,contador de calorías,conteo de calorías,dieta,macros,proteínas,nutrición,peso,bajar de peso

## Description (4000)

Mivu es un diario de comidas privado con un Coach amigable. Cuéntale lo que comiste con tus propias palabras, toma una foto o usa la voz, y Mivu registra la comida con una estimación de calorías, proteínas, carbohidratos y grasas. Tú revisas y corriges cada estimación.

REGISTRA COMO HABLAS
• Describe una comida con palabras sencillas: “dos huevos, pan tostado y un café con leche”.
• Agrega fotos de tu plato, o dicta y revisa el texto antes de enviarlo.
• Registra tu peso de la mañana y tus entrenamientos en la misma conversación.
• Pídele a Coach que corrija una cantidad o un alimento, y se actualiza tu diario.

TU DÍA DE UN VISTAZO
• Hoy muestra calorías y macros frente a metas diarias que se ajustan a ti.
• El Diario guarda todos los días, con el detalle de cada comida y sus fotos.
• Progreso muestra tu peso y lo que consumes a lo largo del tiempo.
• Las calorías que te quedan aparecen en un widget, en la pantalla de bloqueo y en la Dynamic Island.
• Registrar comida está a un toque desde la pantalla de inicio, el Centro de control y el ícono de la app.

CONOCE A PIP
Pip, el zorro de Mivu, prepara tus metas diarias en alrededor de un minuto y reacciona a medida que registras. Pip respeta la opción Reducir movimiento.

PRIVADO DESDE EL DISEÑO
• Sin cuenta de Mivu. Tu diario y tus fotos se guardan en tu iPhone.
• Sin anuncios ni rastreo.
• Haz respaldos en una carpeta que elijas, o exporta tu diario y tus fotos cuando quieras.

IA QUE USA TU PROPIO PLAN
Conecta tu cuenta de ChatGPT para estimar la nutrición y conversar con Coach. Las solicitudes usan tu plan de ChatGPT, y puedes administrar el uso o desconectarte en Ajustes. Mivu pregunta antes de compartir algo con OpenAI. En los iPhone compatibles, Apple Intelligence puede registrar comidas en el dispositivo, sin cuenta.

Las cifras de nutrición son estimaciones, no consejo médico. Habla con un profesional de la salud antes de tomar decisiones médicas o de alimentación.

## What's New

Ahora también en español: todas las pantallas, los widgets, Siri y las notificaciones. Pip responde en el idioma en que escribes.

## Screenshots (6.9-inch iPhone, 1320 × 2868, in order)

Captured on an iPhone 17 Pro Max simulator in Spanish with a real ChatGPT connection: the meals, targets and weights were entered through Pip and setup, in invented Spanish. Framed with `swift scripts/app-store/frame.swift <capture> <out> "<caption>"`.

1. `screenshots/es/01-coach.png` — Registra una comida con tus palabras
2. `screenshots/es/02-today.png` — Tu día de un vistazo
3. `screenshots/es/03-progress.png` — Mira cuánto te acercas a tu meta
4. `screenshots/es/04-targets.png` — Metas que se ajustan a ti
5. `screenshots/es/05-diary.png` — Tu diario se queda en tu iPhone
