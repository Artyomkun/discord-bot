defmodule MusicCore.AudioStreaming.Processor.TaskSupervisor do
  use DynamicSupervisor

  def start_link(opts) do
    DynamicSupervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(_opts) do
    DynamicSupervisor.init(strategy: :one_for_one, max_seconds: 30)
  end

  def start_audio_task(module, function, args) do
    spec = %{
      id: make_ref(),
      start: {Task, :start_link, [module, function, args]},
      restart: :transient,
      shutdown: 5000
    }

    DynamicSupervisor.start_child(__MODULE__, spec)
  end

  def start_hot_standby do
    spec = %{
      id: :hot_standby,
      start: {Task, :start_link, [fn -> hot_standby_loop() end]},
      restart: :permanent
    }

    DynamicSupervisor.start_child(__MODULE__, spec)
  end

  defp hot_standby_loop do
    receive do
      :shutdown -> :ok
    after
      :infinity -> :ok
    end
  end

  def count_children do
    DynamicSupervisor.count_children(__MODULE__)
  end

  def terminate_child(pid) do
    DynamicSupervisor.terminate_child(__MODULE__, pid)
  end
end
