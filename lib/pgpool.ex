defmodule PGPool do

  @moduledoc """

  PGPool 是 PostgresSQL 数据的客户端，采用了连接池设计，在出错时，自动重新连接数
  据库。PGPool 并非完全从头开发，在底层利用 `poolboy` 来做连接池，用 `epgsql` 做
  数据库的驱动。

  ## 设置

  确保 PGPool 能从 Application 中启动。

  1. 自动方式: 把 PGPool 作为 `mix.exs` 文件中的 app 依赖。

  2. 手动方式：执行如下的代码：

  ```elixir
  PGPool.start()
  ```

  ## 数据库

  在使用 PGPool 之前，需要指定数据库。在配置文件中加入如下内容：

  ```elixir
  config :pgpool,
  databases: [
    {:mydbname, # db name in poolboy
     [
       size: 10, # maximun pool size
       max_overflow: 20 # maximum number of workers created if pool is empty
     ],
     [
       hostname: 'localhost',
       database: 'xxx',
       username: 'xxx',
       password: 'xxx'
     ]
    }
  ]

  ```

  可以看出，PGPool 的配置格式与 `poolboy` 的要求保持一致。

  ## 数据库访问

  PGPool 的数据库执行方式和 `epgsql` 保持一致，可以分为两大类型。

  ### 简单命令

  简单命令是不带扩展参数的命令，对应于数据库中的普通 `Statement`。这种类型的数据
  库访问可分为两类：

  #### squery

  squery 执行 SELECT 语句，比如：

  ```elixir
  PGPool.squery(:mydbname, "SELECT * FROM accounts;")
  ```

  返回的结果是：

  ```elixir
  {:ok, cols, rows} | {:error, :no_connection} | {:error, reason}
  cols = %{String.t => non_neg_integer}
  rows = [[any]]
  reason = String.t
  ```

  对正常的返回结果，可以用 PGPool.get_field 方法来获取其中的字段数据。

  #### scmd

  scmd 执行 INSERT, UPDATE, DELETE 等修改数据库的 SQL 语句，比如：

  ```elixir
  PGPool.scmd(:mydbname, "DELETE FROM accounts WHERE id = 0")
  ```

  返回的结果是：

  ```elixir
  :ok | {:error, :no_connection} | {:error, reason}
  reason = String.t
  ```

  ### 扩展命令

  扩展命令对应于数据库的 `Prepared Statment`, 也分为两类：

  #### equery

  equery 执行 SELECT 语句，比如：

  ```elixir
  PGPool.squery(:mydbname, "SELECT * FROM accounts WHERE name = $1;", ["Alice"])
  ```

  扩展参数用 `$n` 来表示，n 从 1 开始。

  返回的结果是：

  ```elixir
  {:ok, cols, rows} | {:error, :no_connection} | {:error, reason}
  cols = %{String.t => non_neg_integer}
  rows = [[any]]
  reason = String.t
  ```

  对正常的返回结果，可以用 PGPool.get_field 方法来获取其中的字段数据。

  #### ecmd

  ecmd 执行 INSERT, UPDATE, DELETE 等修改数据库的 SQL 语句，比如：

  ```elixir
  PGPool.scmd(:mydbname, "DELETE FROM accounts WHERE id = $1", [ 0 ])
  ```

  返回的结果是：

  ```elixir
  :ok | {:error, :no_connection} | {:error, reason}
  reason = String.t
  ```

  ### 重试

  当数据库连接不存在时，squery/scmd, equery/ecmd 方法都会返回 `{:error,
  :no_connection}`, 如果需要自动重试，直到连接可用，可以在 squery/scmd,
  equery/ecmd 后增加一个 `retry_timeout` 参数。该参数设定了重试之前要等待的毫秒
  数。`retry_timeout` 也可以是 `:infinity`，这样 PGPool 一直要等待连接池可用才会
  返回。`retry_timeout` 的默认值是 0，即不重试，立刻返回。

  ```elixir
  PGPool.equery(:mydbname, "SELECT * FROM accounts WHERE name = $1", ["Alice"], 60000)
  ```

  ## 特殊类型

  Postgresql 支持 hstore 类型，这是一个 Key-Value 类型。PGPool 用 Map 类型来表示
  数据库的 hstore 类型，当参数中含有 Map 时，自动转换为 hstore 类型；当结果中有
  hstore 类型时，自动转换为 Map 类型。

  """
  @compile {:autoload, false}
  @on_load {:init, 0}

  def init do
    path = :filename.join(:code.priv_dir(:pgpool), 'hstore_to_map')

    case :erlang.load_nif(path, 0) do
      :ok -> :ok
      _ -> {:error, "The file `hstore_to_map` failed to load." <>
        " Try recompiling pgpool by running `mix deps.compile pgpool`" <>
        " and / or `MIX_ENV=test mix deps.compile pgpool`."}
    end
  end

  def start do
    :ok = ensure_started(:poolboy)
    :ok = ensure_started(:epgsql)
    :ok = ensure_started(:pgpool)
  end

  def stop do
    :ok = :application.stop(:pgpool)
    :ok = :application.stop(:epgsql)
    :ok = :application.stop(:poolboy)
  end

  @doc """
  执行可设定参数的 SELECT 语句。

  SELECT　语句的可变参数位用 $1 .. $n　表示，比如：

  ```elixir
  "SELECT id FROM account WHERE name = $1"
  ```

  ## 参数

  |名称|类型|说明|
  |--|--|--|
  |db|Keyword.t|在配置文件中的数据库名称|
  |stmt|String.t|SELECT　语句|
  |params|list|参数|
  |retry_timeout|integer/:infinity|等待重试的时间|

  params 中可用的元素类型有：

  |类型|
  |--|
  |String.t|
  |boolean|
  |integer|
  |non_neg_integer|
  |float|
  |%Map{String.t => String.t}|

  注意，数据库的 hstore 类型参数用 Map　的形式。

  ## 结果

  ###　成功

  ```elixir
  {:ok, columes, rows}
  ```
  其中，columes 是字段名称与下标的映射：

  ```elixir
  %{"col0" => 0, "col1" => 1, ...}
  ```

  rows 是字段内容的列表：

  ```elixir
  [[val0, val1, ...], ...]
  ```

  另外，hstore 类型的字段，结果用 Map 来表示。

  ### 失败

  ```elixir
  {:error, reason}
  {:error, :no_connection}
  ```

  since: 0.1.0

  """
  @spec equery(Keyword.t, String.t, [any], non_neg_integer | :infinity) :: {:ok, %{String.t => non_neg_integer}, [[any]]} | {:error, String.t} | {:error, :no_connection}
  def equery(db, stmt, params, retry_timeout \\ 0) do
    np = params
    |> Enum.map(fn x ->
      case is_map(x) do
        false -> x
        true -> map_to_hstore(x)
      end
    end)
    PGPool.Worker.equery(db, stmt, np, retry_timeout)
    |> handle_query_result
  end

  @doc """
  执行可设定参数的非 SELECT 语句。

  SQL　语句的可变参数位用 $1 .. $n　表示，比如：

  ```elixir
  "INSERT INTO account VALUES($1, $2)"
  ```

  ## 参数

  |名称|类型|说明|
  |--|--|--|
  |db|Keyword.t|在配置文件中的数据库名称|
  |stmt|String.t|SQL 语句|
  |params|list|参数|
  |retry_timeout|integer/:infinity|等待重试的时间|

  params 中可用的元素类型有：

  |类型|
  |--|
  |String.t|
  |boolean|
  |integer|
  |non_neg_integer|
  |float|
  |%Map{String.t => String.t}|

  注意，数据库的 hstore 类型参数用 Map　的形式。

  ## 结果

  ###　成功

  ```elixir
  :ok
  ```

  ### 失败

  ```elixir
  {:error, reason}
  {:error, :no_connection}
  ```

  since: 0.1.0

  """
  @spec ecmd(Keyword.t, String.t, [any], non_neg_integer | :infinity) :: {:ok, %{String.t => non_neg_integer}, [[any]]} | {:error, String.t} | {:error, :no_connection}
  def ecmd(db, stmt, params, retry_timeout \\ 0) do
    np = params
    |> Enum.map(fn x ->
      case is_map(x) do
        false -> x
        true -> map_to_hstore(x)
      end
    end)
    PGPool.Worker.equery(db, stmt, np, retry_timeout)
    |> handle_cmd_result
  end

  @doc """
  执行不可设定参数的 SELECT 语句。

  ```elixir
  "SELECT id FROM account WHERE name = 'Alice'"
  ```

  ## 参数

  |名称|类型|说明|
  |--|--|--|
  |db|Keyword.t|在配置文件中的数据库名称|
  |stmt|String.t|SELECT　语句|
  |retry_timeout|integer/:infinity|等待重试的时间|

  ## 结果

  ###　成功

  ```elixir
  {:ok, columes, rows}
  ```
  其中，columes 是字段名称与下标的映射：

  ```elixir
  %{"col0" => 0, "col1" => 1, ...}
  ```

  rows 是字段内容的列表：

  ```elixir
  [[val0, val1, ...], ...]
  ```

  另外，hstore 类型的字段，结果用 Map 来表示。

  ### 失败

  ```elixir
  {:error, reason}
  {:error, :no_connection}
  ```

  since: 0.1.0

  """
  @spec squery(Keyword.t, String.t, non_neg_integer | :infinity) :: {:ok, %{String.t => non_neg_integer}, [[any]]} | {:error, String.t}
  def squery(db, stmt, retry_timeout \\ 0) do
    PGPool.Worker.squery(db, stmt, retry_timeout)
    |> handle_query_result
  end

  @doc """
  执行不可设定参数的非 SELECT 语句。

  ```elixir
  "INSERT INTO account VALUES('Alice', 'secret-password')"
  ```

  ## 参数

  |名称|类型|说明|
  |--|--|--|
  |db|Keyword.t|在配置文件中的数据库名称|
  |stmt|String.t|SQL 语句|
  |retry_timeout|integer/:infinity|等待重试的时间|

  ## 结果

  ###　成功

  ```elixir
  :ok
  ```

  ### 失败

  ```elixir
  {:error, reason}
  {:error, :no_connection}
  ```

  since: 0.1.0

  """
  @spec scmd(Keyword.t, String.t, non_neg_integer | :infinity) :: {:ok, %{String.t => non_neg_integer}, [[any]]} | {:error, String.t}
  def scmd(db, stmt, retry_timeout \\ 0) do
    PGPool.Worker.squery(db, stmt, retry_timeout)
    |> handle_cmd_result
  end

  @doc """
  获取结果中的字段内容。注意，:null 将会被替换为 :nil

  ## 参数

  |名称|类型|说明|
  |--|--|--|
  |row|list|数据行|
  |col|String.t|列名称|
  |cols|%{String.t => non_neg_integer}|列名称与下标映射|

  ## 例子

      iex> PGPool.get_field(["a", "b", "c"], "B", %{"A" => 0, "B" => 1, "C" => 2})
      "b"

  since: 0.2.0
  """
  @spec get_field([any], String.t, %{String.t => non_neg_integer}) :: any
  def get_field(row, col, cols) do
    pos = Map.get(cols, col)
    case Enum.fetch!(row, pos) do
      :null -> :nil
      v -> v
    end
  end

  defp map_to_hstore(map) do
    str = map
    |> Map.to_list()
    |> Enum.reduce("", fn({k, v}, acc) ->
      acc <> ", \"" <> k <> "\" => \"" <> v <> "\""
    end)
    case String.length(str) > 0 do
      false -> str
      true ->
        <<_ :: size(16), rest :: binary>> = str
        rest
    end
  end

  defp hstore_to_map(_hstore, _map) do
    raise "NIF hstore_to_map/2 not implemented"
  end

  defp handle_query_result({:error, :no_connection} = result) do
    result
  end

  defp handle_query_result({:error, {_, _, _, _, error, _}}) do
    {:error, error}
  end

  defp handle_query_result({:ok, fields, rows}) do
    {cols, masks} = Enum.map(fields, fn {_, k, t, _, _, _} ->
      case t do
        :hstore -> {k, true}
        _ -> {k, false}
      end
    end)
    |> Enum.unzip
    {_count, colmap} = Enum.reduce(cols, {0, %{}}, fn x, {i, map} ->
      {i + 1, Map.put(map, x, i)}
    end)
    result = Enum.map(rows, fn x ->
      values = :erlang.tuple_to_list(x)
      Enum.map(0 .. :erlang.length(cols) - 1, fn i ->
        case Enum.fetch!(masks, i) do
          true ->
            case Enum.fetch!(values, i) do
              nil -> nil
              :null -> :null
              {kvs} -> kvs |> Enum.reduce(%{}, fn {k, v}, acc -> Map.put(acc, k, v) end)
              "" -> %{}
              v -> v |> String.split(",") |> Enum.reduce(%{}, &(hstore_to_map &1, &2))
            end
          false -> Enum.fetch!(values, i)
        end
      end)
    end)
    {:ok, colmap, result}
  end

  defp handle_cmd_result({:error, :no_connection} = result) do
    result
  end

  defp handle_cmd_result({:error, {_, _, _, _, error, _}}) do
    {:error, error}
  end

  defp handle_cmd_result(_any) do
    :ok
  end

  defp ensure_started(app) do
    case :application.start(app) do
      :ok -> :ok
      {:error, {:already_started, _app}} -> :ok
    end
  end
end
