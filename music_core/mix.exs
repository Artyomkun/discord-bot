defmodule MusicCore.MixProject do
  @moduledoc false
  use Mix.Project

  def project do
    [
      app: :music_core,
      version: "0.1.0",
      elixir: "~> 1.17",
      start_permanent: Mix.env() == :prod,
      compilers: Mix.compilers(),
      deps: deps(),

      # Указываем где искать Elixir модули
      elixirc_paths: [
        "./GRPC/Elixir/**/**/**",
        "audio_streaming/**/**",
        "audio_effects/**/**",
        "external_apis/",
        "go_processor/",
        "audio_stream/",
        "java_gateway/",
        "HealthCheck/",
        "Application/",
        "web_socket/",
        "Telemetry/",
        "services/",
        "workers/",
        "config/",
        "test/",
        ".",
      ],

      # Конфигурация сборки
      build_path: "_build",
      config_path: "config/config.exs",
      deps_path: "deps",
      lib_path: "lib",
      lockfile: "mix.lock",

      # Документация
      name: "Music Core",
      description: "Аудио-обработка для Discord бота",
      source_url: "https://github.com/Artyomkun/Kodland/elixir_music_bot",
      docs: [main: "MusicCore"],

      # Пакеты для релиза
      package: [
        maintainers: ["Artyomkun"],
        licenses: ["MIT"],
        links: %{"GitHub" => "https://github.com/Artyomkun/Kodland/elixir_music_bot"}
      ],

      # Алиасы для удобства
      aliases: aliases()
    ]
  end

  def application do
    [
      extra_applications: [:logger, :runtime_tools, :ssl, :inets],
      mod: {MusicCore.Application.Application, []}
    ]
  end

  defp deps do
    [
      # ФОРКНУТЫЕ БИБЛИОТЕКИ
      {:cowboy_telemetry, path: "lib/cowboy_telemetry", override: true},
      {:nimble_ownership, path: "lib/nimble_ownership", override: true},
      {:nimble_options, path: "lib/nimble_options", override: true},
      {:nimble_parsec, path: "lib/nimble_parsec", override: true},
      {:makeup_elixir, path: "lib/makeup_elixir", override: true},
      {:makeup_erlang, path: "lib/makeup_erlang", override: true},
      {:nimble_pool, path: "lib/nimble_pool", override: true},
      {:polaris, path: "lib/polaris", override: true},
      {:rustler, path: "lib/rustler", override: true},
      {:makeup, path: "lib/makeup", override: true},
      {:cowboy, path: "lib/cowboy", override: true},
      {:req, path: "lib/req", override: true},

      # НЕ форкнутые (обычные версии)
      {:redix, "~> 1.2"},
      {:ed25519, "~> 1.4"},
      {:protobuf, "~> 0.12"},
      {:grpc_statsd, "~> 0.1"},
      {:plug_cowboy, "~> 2.7"},
      {:dotenv_parser, "~> 2.0"},
      {:prometheus_ex, "~> 3.0"},
      {:grpc_prometheus, "~> 0.1"},
      {:prometheus_ecto, "~> 1.4"},
      {:prometheus_plugs, "~> 1.1"},
      {:telemetry_poller, "~> 1.1"},
      {:mox, "~> 1.2", only: :test},
      {:benchee, "~> 1.3", only: :dev},
      {:mime, "~> 2.0", override: true},
      {:ranch, "~> 2.2", override: true},
      {:ratio, "~> 4.0", override: true},
      {:statix, "~> 1.4", optional: true},
      {:decimal, "~> 3.0", override: true},
      {:cowlib, "~> 2.16", override: true},
      {:mockery, "~> 2.5", override: true},
      {:stream_data, "~> 1.1", only: :test},
      {:elixir_make, "~> 0.7", override: true},
      {:db_connection, "~> 2.6", override: true},
      {:oban, github: "sorentwo/oban", override: true},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false},
      {:ecto, github: "elixir-ecto/ecto", override: true},
      {:hpax, github: "elixir-mint/hpax", override: true},
      {:dialyxir, "~> 1.4", only: [:dev], runtime: false},
      {:mix_test_watch, "1.4.0", only: :dev, runtime: false},
      {:jason, github: "michalmuskala/jason", override: true},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:coerce, github: "Qqwy/elixir-coerce", override: true},
      {:con_cache, github: "sasa1977/con_cache", override: true},
      {:qex, github: "princemaple/elixir-queue", override: true},
      {:elixir_uuid, github: "zyro/elixir-uuid", override: true},
      {:ecto_sql, github: "elixir-ecto/ecto_sql", override: true},
      {:postgrex, github: "elixir-ecto/postgrex", override: true},
      {:telemetry, github: "beam-telemetry/telemetry", override: true},
      {:grpc, github: "wingyplus/grpc", branch: "main", override: true},
      {:telemetry_metrics, github: "beam-telemetry/telemetry_metrics", override: true},
      {:plug_crypto, github: "elixir-plug/plug_crypto", tag: "v2.1.1", override: true},
    ]
  end

  defp aliases do
    [
      # Запуск
      start: ["run --no-halt"],

      # Тестирование
      test: ["test --trace"],
      "test.watch": ["test.watch --trace"],

      # Линтинг
      lint: ["credo --strict"],
      "lint.fix": ["credo --strict --fix"],
      dialyzer: ["dialyzer"],

      # База данных
      "ecto.setup": ["ecto.create", "ecto.migrate"],
      "ecto.reset": ["ecto.drop", "ecto.setup"],

      # Бенчмарки
      bench: ["run bench/run.exs"],

      # Документация
      docs: ["docs", "cmd open docs/index.html"],

      # Форматирование
      format: [
        "format mix.exs \"config/**/*.{ex,exs}\" " <>
        "\"audio_effects/**/*.{ex,exs}\" \"audio_streaming/**/*.{ex,exs}\" " <>
        "\"test/**/*.{ex,exs}\""
      ],

      # Полная проверка проекта
      check: [
        "compile --warnings-as-errors",
        "format --check-formatted",
        "credo --strict",
        "test",
        "dialyzer"
      ],

      # Docker сборка
      "docker.build": ["cmd docker build -t music-core ."],
      "docker.run": ["cmd docker run -p 4000:4000 music-core"],

      # Анализ зависимостей
      "deps.audit": ["hex.audit"],
      "deps.outdated": ["hex.outdated"],

      # Профилирование
      profile: ["run --eval 'require IEx; IEx.pry()'"]
    ]
  end

  def releases do
    [
      music_core: [
        include_executables_for: [:unix],
        applications: [runtime_tools: :permanent],
        steps: [:assemble, :tar],
        cookie: "music_core_cookie_#{Mix.env()}"
      ]
    ]
  end
end
