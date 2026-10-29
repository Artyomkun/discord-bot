# C DSP Library

Библиотека цифровой обработки сигналов (DSP) на языке C для аудио эффектов.

## Структура проекта

```text
c_src/
├── cpu/           # CPU реализации эффектов
│   └── src/
├── gpu/           # GPU (CUDA) реализации
│   ├── src/
│   └── include/
├── common/        # Общие компоненты
│   ├── src/
│   └── include/
├── src/           # Основной код (интеграция)
├── include/       # Основные заголовки
├── tests/         # Unit тесты
├── docs/          # Документация
├── examples/      # Примеры использования
├── Makefile       # Скрипт сборки
└── README.md      # Эта документация
```

## Доступные эффекты

### Delay

Простой delay buffer с feedback.

```c
DelayBuffer delay;
delay_init(&delay, 44100, 0.5, 0.3, 0.7); // 1 сек delay, feedback 0.5, wet 0.3, dry 0.7
float output = delay_process(&delay, input);
delay_free(&delay);
```

### Low-Pass Filter

Однополюсный low-pass filter.

```c
LowPassFilter filter;
lpf_init(&filter, 1000.0, 44100.0); // cutoff 1000Hz, sample rate 44100Hz
float output = lpf_process(&filter, input);
```

### Distortion

Soft clipping distortion.

```c
Distortion dist;
distortion_init(&dist, 2.0, 0.8, 0.5); // drive 2.0, threshold 0.8, gain 0.5
float output = distortion_process(&dist, input);
```

### Reverb

Schroeder reverb с 4 comb filters.

```c
Reverb rev;
reverb_init(&rev, 44100.0, 0.5, 0.3, 0.7); // sample rate, decay, wet, dry
float output = reverb_process(&rev, input);
reverb_free(&rev);
```

### Chorus

Chorus эффект с LFO modulation.

```c
Chorus chor;
chorus_init(&chor, 44100.0, 0.5, 10.0, 0.3, 0.7); // sample rate, rate, depth, wet, dry
float output = chorus_process(&chor, input);
chorus_free(&chor);
```

## Сборка

```bash
make all      # Собрать библиотеку
make test     # Запустить тесты
make clean    # Очистить
make install  # Установить в систему
```

## Тестирование

Библиотека включает unit тесты для всех эффектов. Запустите `make test` для выполнения тестов.

## Производительность

- Оптимизирована для real-time обработки
- Минимальное использование памяти
- SIMD-friendly структуры данных

## CUDA поддержка

Библиотека поддерживает ускорение на GPU с помощью CUDA для интенсивных DSP операций.

### Сборка с CUDA

```bash
make CUDA_SUPPORT=1 all
```

Требуется установленный CUDA toolkit.

### GPU функции

- `process_distortion_gpu`: обработка distortion эффекта на GPU для массивов семплов
- `process_lpf_gpu`: обработка low-pass filter на GPU для массивов семплов

GPU функции обрабатывают массивы семплов параллельно, что полезно для batch обработки.

## Лицензия

MIT License
