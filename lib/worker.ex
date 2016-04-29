defmodule PGPool.Worker do
  use GenServer
  @behaviour :poolboy_worker

  @reconnect_timeout_ms 5000
  @retry_sleep_ms 1000

  def start_link(args) do
    GenServer.start_link(__MODULE__, args, [])
  end

  def squery(database, stmt, retry_timeout \\ 0) do
    :poolboy.transaction(database, fn worker ->
      case GenServer.call worker, {:squery, stmt}, :infinity do
        {:error, :no_connection} when retry_timeout == :infinity ->
          :timer.sleep(@retry_sleep_ms)
          squery(database, stmt, :infinity)
        {:error, :no_connection} when retry_timeout > 0 ->
          :timer.sleep(@retry_sleep_ms)
          squery(database, stmt, retry_timeout - @retry_sleep_ms)
        result -> result
      end
    end)
  end

  def equery(database, stmt, params, retry_timeout \\ 0) do
    :poolboy.transaction(database, fn worker ->
      case GenServer.call worker, {:equery, stmt, params}, :infinity do
        {:error, :no_connection} when retry_timeout == :infinity ->
          :timer.sleep(@retry_sleep_ms)
          squery(database, stmt, :infinity)
        {:error, :no_connection} when retry_timeout > 0 ->
          :timer.sleep(@retry_sleep_ms)
          squery(database, stmt, retry_timeout - @retry_sleep_ms)
        result -> result
      end
    end)
  end

  def init(args) do
    :erlang.process_flag(:trap_exit, true)

    hostname = args[:hostname]
    database = args[:database]
    username = args[:username]
    password = args[:password]

    state = connect(%{hostname: hostname, database: database, username: username, password: password})
    {:ok, state}
  end

  def handle_call({:equery, stmt, params}, _from, %{conn: conn} = state) do
    {:reply, :epgsql.equery(conn, stmt, params), state}
  end

  def handle_call({:squery, stmt}, _from, %{conn: conn} = state) do
    {:reply, :epgsql.squery(conn, stmt), state}
  end

  def handle_call(_any, _from, %{conn: :undefined} = state) do
    {:reply, {:error, :no_connection}, state}
  end

  def handle_call(_request, _from, state) do
    {:reply, :ok, state}
  end

  def handle_info(:connect, state) do
    {:noreply, connect(state)}
  end

  def handle_info({'EXIT', _from, _reason}, state) do
    {:noreply, timeout(state)}
  end

  def terminate(_reason, %{conn: conn}) do
    case conn do
      :undefined -> :ok
      _ -> :epgsql.close(conn)
    end
    :terminated
  end

  defp connect(%{hostname: hostname, database: database, username: username, password: password} = state) do
    case :epgsql.connect(hostname, username, password, [{:database, database}]) do
      {:ok, conn} -> Map.put(state, :conn, conn)
      _error -> Map.put(state, :conn, :undefined)
    end
  end

  defp timeout(state) do
    case Map.fetch(state, :timer) do
      {:ok, timer} -> :erlang.cancel_timer(timer)
      :error -> :ignore
    end
    timer1 = :erlang.send_after(@reconnect_timeout_ms, Node.self, :connect)
    Map.put(state, :timer, timer1)
  end
end
