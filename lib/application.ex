defmodule PGPool.Application do
  use Application

  def start(_type, _args) do
    PGPool.Supervisor.start_link
  end

  def stop(_state) do
    :ok
  end
end
