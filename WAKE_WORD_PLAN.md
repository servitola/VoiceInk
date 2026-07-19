# План реализации Wake Word Detection для VoiceInk

## Обзор

Добавление функции постоянного прослушивания микрофона и активации записи по ключевому слову (например, "лошадка").

## Выбранный подход: Apple Speech Recognition

**Преимущества:**
- Встроенный в macOS, не требует дополнительных зависимостей
- Хорошая точность распознавания русского языка
- Работает оффлайн на современных macOS
- Работает в фоне с низким приоритетом

---

## Этап 1: Создание основного сервиса

**Файл:** `VoiceInk/Services/WakeWordListeningService.swift` (новый)

**Что делает:**
- Использует `SFSpeechRecognizer` для непрерывного распознавания речи
- Буферизует аудио через `AVAudioEngine`
- Анализирует распознанный текст в реальном времени на наличие wake word
- При детекте wake word → вызывает callback для старта записи
- Управляет состояниями: `.idle`, `.listening`, `.detected`

**Ключевые методы:**
```swift
- startListening() // запуск прослушивания
- stopListening() // остановка
- configureWakeWord(_ word: String) // настройка слова
```

---

## Этап 2: Интеграция с WhisperState

**Файл:** `VoiceInk/Whisper/WhisperState.swift` (модификация)

**Изменения:**
- Добавить свойство `private var wakeWordService: WakeWordListeningService?`
- Добавить флаг `@Published var isWakeWordListening = false`
- Добавить методы:
  - `startWakeWordListening()` - запускает фоновое прослушивание
  - `stopWakeWordListening()` - останавливает
  - `handleWakeWordDetected()` - callback при детекте, вызывает `toggleRecord()`

---

## Этап 3: Настройки UI

**Файл:** `VoiceInk/Views/Settings/WakeWordSettingsView.swift` (новый)

**Компоненты:**
- Toggle "Enable Wake Word Mode"
- TextField для ввода wake word (default: "лошадка")
- Picker для выбора языка распознавания (русский/английский)
- Toggle "Remove wake word from transcription"
- Индикатор статуса (слушает/не слушает) с анимацией

**Интеграция:**
- Добавить секцию в `SettingsView.swift`

---

## Этап 4: Обработка wake word в транскрипции

**Файл:** `VoiceInk/Services/TranscriptionOutputFilter.swift` (модификация)

**Добавить:**
- Метод для удаления wake word из начала транскрипции
- Проверка настройки "Remove wake word from transcription"

---

## Этап 5: Разрешения и UI индикаторы

**Файлы:**
- `VoiceInk/Views/Onboarding/OnboardingPermissionsView.swift` (добавить речевые разрешения)
- `VoiceInk/Views/Recorder/MiniRecorderView.swift` (добавить индикатор wake word listening)

**Индикатор в menu bar:**
- Маленькая иконка/точка, показывающая что слушает wake word

---

## Этап 6: UserDefaults ключи

**Добавить настройки:**
```swift
- "isWakeWordEnabled" -> Bool
- "wakeWord" -> String (default: "лошадка")
- "wakeWordLanguage" -> String (default: "ru-RU")
- "removeWakeWordFromTranscription" -> Bool (default: true)
```

---

## Структура работы

```
1. Пользователь включает Wake Word Mode в настройках
   ↓
2. При запуске приложения автоматически стартует WakeWordListeningService
   ↓
3. Сервис непрерывно слушает микрофон с низким приоритетом
   ↓
4. Пользователь говорит: "лошадка, сделай вот это"
   ↓
5. Детект "лошадка" → handleWakeWordDetected() → toggleRecord()
   ↓
6. Начинается обычная запись (как по горячей клавише)
   ↓
7. После стопа - транскрибируется: "сделай вот это" (без "лошадка")
   ↓
8. Текст вставляется в поле ввода
   ↓
9. WakeWordService снова начинает слушать
```

---

## Важные детали

1. **Приоритет аудио:** Wake word listening использует низкий приоритет, основная запись - высокий
2. **Конфликт микрофона:** При детекте wake word останавливаем listening, запускаем запись
3. **Энергопотребление:** SFSpeechRecognizer оптимизирован Apple для фонового использования
4. **Фильтрация ложных срабатываний:** Можно добавить confidence threshold
5. **Разрешения:** Требуется Speech Recognition permission (добавить в Info.plist)

---

## Альтернативные варианты (не выбраны)

### Вариант 2: Porcupine Wake Word Engine
- Специализирован для wake word detection
- Очень низкое потребление ресурсов
- Требует добавления SPM зависимости
- Нужна тренировка для кастомного слова "лошадка"

### Вариант 3: Гибридный (VAD + локальное распознавание)
- Использовать существующий `VADModelManager` для детекции голоса
- Простое сравнение с шаблоном
