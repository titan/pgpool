defmodule PGPool.Server do
  use GenServer
  @behaviour :poolboy_worker

  def start_link(args) do
    GenServer.start_link(__MODULE__, args, [])
  end

  def init(args) do
    :erlang.process_flag(:trap_exit, true)

    hostname = args[:hostname]
    database = args[:database]
    username = args[:username]
    password = args[:password]

    {:ok, conn} = :epgsql.connect(hostname, username, password, [
          {:database, database}
        ])
    {:ok, %{:conn => conn}}
  end

  def handle_call({:equery, stmt, params}, _from, %{conn: conn} = state) do
    {:reply, :epgsql.equery(conn, stmt, params), state}
  end

  def handle_call({:squery, stmt}, _from, %{conn: conn} = state) do
    {:reply, :epgsql.squery(conn, stmt), state}
  end

  def handle_call(_request, _from, state) do
    {:reply, :ok, state}
  end

  def terminate(_reason, %{conn: conn}) do
    :epgsql.close(conn)
  end
end
