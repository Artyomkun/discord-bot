#!/bin/bash

# Получаем абсолютные пути к корню проекта (если переменные окружения не переданы)
if [ -z "$PROJECT_ROOT" ]; then
    PROJECT_ROOT="$(realpath ../../../../../../..)"
fi

# Пути к компонентам (используем PROJECT_ROOT)
ELIXIR_DIR="${ELIXIR_DIR:-$PROJECT_ROOT/music_core}"
GO_PROCESSOR_DIR="${GO_PROCESSOR_DIR:-$PROJECT_ROOT/go_processor}"
JAVA_GATEWAY_DIR="${JAVA_GATEWAY_DIR:-$PROJECT_ROOT/go_processor/java_gateway}"
PYTHON_DIR="${PYTHON_DIR:-.}"

# Если передан аргумент "python" — запускаем только Python бота
if [ "$1" = "python" ]; then
    echo "Запуск только Python бота..."
    cd "$PYTHON_DIR"
    source "$PROJECT_ROOT/grpc/Python/venv/bin/activate"
    PYTHONPATH="$PROJECT_ROOT/grpc:$PROJECT_ROOT/grpc/Python:$PROJECT_ROOT/grpc/Python/generated:$PROJECT_ROOT/grpc/Python/generated/v1:$PYTHONPATH" python3 bot.py
    exit 0
fi

# Иначе — запускаем все компоненты в tmux
SESSION="music_bot"
if tmux has-session -t $SESSION 2>/dev/null; then
    echo "Сессия $SESSION уже существует. Остановите её: tmux kill-session -t $SESSION"
    exit 1
fi

tmux new-session -d -s $SESSION
tmux send-keys -t $SESSION "cd $ELIXIR_DIR && make run" C-m
tmux split-window -t $SESSION -h
tmux send-keys -t $SESSION "sleep 3 && cd $GO_PROCESSOR_DIR && make run" C-m
tmux split-window -t $SESSION -v
tmux send-keys -t $SESSION "sleep 6 && cd $JAVA_GATEWAY_DIR && make run" C-m
tmux split-window -t $SESSION -v
tmux send-keys -t $SESSION "sleep 9 && cd $PYTHON_DIR && make run" C-m
tmux select-layout -t $SESSION tiled
tmux attach -t $SESSION