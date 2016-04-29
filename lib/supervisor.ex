defmodule PGPool.Supervisor do
  use Supervisor

  def start_link do
    Supervisor.start_link(__MODULE__, [])
  end

  def init([]) do
    {:ok, databases} = :application.get_env(:pgpool, :database)

    children = databases
    |> Enum.map(fn ({name, size_args, worker_args}, acc) ->
      pool_args = [{:name, {:local, name}},
                   {:worker_module, PGPool.Worker}] ++ size_args
      [:poolboy.child_spec(name, pool_args, worker_args) | acc]
    end)

    supervise(children, strategy: :one_for_one)
  end
end
