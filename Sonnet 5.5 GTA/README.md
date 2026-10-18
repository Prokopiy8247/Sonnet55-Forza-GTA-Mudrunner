# Halcyon Bay — GTA-подобная песочница, созданная Claude Sonnet 5.5
# Halcyon Bay — a GTA-style open-world sandbox built by Claude Sonnet 5.5

Оригинальная игра без миссий: свободно ездите, летайте, стреляйте, убегайте от полиции, меняйте время суток и погоду.
An original missionless sandbox: drive, fly, shoot, escape the police, change time and weather.

---

## КАК ЗАПУСТИТЬ (по-русски) — это просто, программы устанавливать не нужно

### Windows
1. Откройте папку **Download** и скачайте **Halcyon-Bay-Windows.zip**.
2. Правой кнопкой по файлу → **Извлечь всё** (или откройте архив двойным щелчком).
3. Дважды щёлкните по **HalcyonBay.exe** — игра запустится.
   - Если Windows пишет «Система Windows защитила ваш компьютер»: нажмите **Подробнее** → **Выполнить в любом случае**. Это нормально: файл не подписан платным сертификатом.

### Mac
1. Скачайте **Halcyon-Bay-Mac.zip** из папки **Download** и дважды щёлкните по нему — появится **Sonnet5.5GTA**.
2. Первый раз: **правой кнопкой** по Sonnet5.5GTA → **Открыть** → в окне ещё раз **Открыть**. (Двойной щелчок в первый раз может не сработать — Mac не знает разработчика.)
3. Если пишет «приложение повреждено»: откройте программу **Терминал**, вставьте строку ниже (путь можно перетащить в окно мышью) и нажмите Enter, потом откройте игру снова:

   `xattr -cr ~/Downloads/Sonnet5.5GTA.app`
   (измените путь, если распаковали в другое место)

Нужен относительно современный компьютер с видеокартой (Windows 10/11 или macOS 11+; на Mac работает на Intel и на Apple Silicon). Первый запуск может занять до минуты.

## УПРАВЛЕНИЕ
| Клавиша | Действие |
|---|---|
| W A S D | ходьба / руль машины |
| Мышь | камера / прицел |
| Shift | бег |
| Пробел | прыжок / ручник |
| F | сесть в машину / выйти |
| E | взаимодействие (магазины, двери) |
| ЛКМ / ПКМ | стрельба / прицеливание |
| R | перезарядка |
| Tab | колесо оружия |
| 1–9 | выбор оружия |
| C | присесть / скрытность |
| Q | укрытие |
| V | переключить вид камеры |
| M | карта |
| P | телефон (такси, сохранение, фото) |
| H, L, N | гудок, фары, сирена |
| F1 | **меню разработчика**: телепорт, любая машина/вертолёт/самолёт/лодка, оружие, деньги, розыск 0–5, время, погода |
| F5 / F9 | быстрое сохранение / загрузка |
| Esc | пауза и настройки |

**Хотите быстро всё посмотреть?** Нажмите **F1** → вкладки: телепорт в любой район, создать вертолёт или самолёт, выдать оружие, поставить розыск 5 звёзд, сменить погоду.

## Если игра не запускается
- Обновите драйвер видеокарты и запустите ещё раз.
- Распакуйте архив полностью (нельзя запускать файл прямо из окна архива).
- Антивирус может ругаться на неподписанный файл — это ложное срабатывание; исходники проекта лежат рядом, можно собрать самому.

---

## HOW TO RUN (English) — no installation needed

**Windows:** download `Download/Halcyon-Bay-Windows.zip` → right-click → *Extract All* → double-click **HalcyonBay.exe**. If SmartScreen appears: *More info → Run anyway* (the file is unsigned).

**Mac:** download `Download/Halcyon-Bay-Mac.zip` → double-click to unzip → **right-click `Sonnet5.5GTA` → Open → Open** (first launch only). If macOS says the app is damaged, run in Terminal: `xattr -cr ~/Downloads/Sonnet5.5GTA.app` and open it again. Works on Intel and Apple Silicon (macOS 11+).

Controls are the same as in the table above. Press **F1** for the benchmark/debug menu.

---

## Исходный код / Source
Открывается в **Godot 4.7.2** (папка проекта содержит `project.godot`, запуск — F5). 3D-модели созданы в Blender 5.2 через MCP (файл `GodotSonnet5.5GTA.blend`), всё остальное — GDScript.
Open the project folder with **Godot 4.7.2** and press F5. All 3D assets were generated in Blender 5.2 via MCP (`GodotSonnet5.5GTA.blend`); everything else is GDScript.

Подробности / details: `SONNET_5.5_FINAL_REPORT.md`, `FEATURE_MATRIX.md`, `DEVELOPMENT.md`, `docs/ARCHITECTURE.md`.
Все звуки и текстуры сгенерированы кодом, внешние ассеты не использовались / all audio and textures are procedural, no third-party assets.