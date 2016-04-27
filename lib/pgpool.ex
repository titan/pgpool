defmodule PGPool do

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

  @doc """
  执行可设定参数的 SELECT 语句。

  SELECT　语句的可变参数位用 $1 .. $n　表示，比如：

  ```elixir
  "SELECT id FROM account WHERE name = $1"
  ```

  ## 参数

  |名称|类型|说明|
  |--|--|--|
  |stmt|String.t|SELECT　语句|
  |params|list|参数|

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
  ```

  since: 0.1.0

  """
  @spec equery(String.t, [any]) :: {:ok, %{String.t => non_neg_integer}, [[any]]} | {:error, String.t}
  def equery(stmt, params) do
    np = params
    |> Enum.map(fn x ->
      case is_map(x) do
        false -> x
        true -> map_to_hstore(x)
      end
    end)
    :poolboy.transaction(:pgpool, fn(pid) ->
      GenServer.call(pid, {:equery, stmt, np})
      |> handle_query_result
    end)
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
  |stmt|String.t|SQL 语句|
  |params|list|参数|

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
  ```

  since: 0.1.0

  """
  @spec ecmd(String.t, [any]) :: {:ok, %{String.t => non_neg_integer}, [[any]]} | {:error, String.t}
  def ecmd(stmt, params) do
    np = params
    |> Enum.map(fn x ->
      case is_map(x) do
        false -> x
        true -> map_to_hstore(x)
      end
    end)
    :poolboy.transaction(:pgpool, fn(pid) ->
      GenServer.call(pid, {:equery, stmt, np})
      |> handle_cmd_result
    end)
  end

  @doc """
  执行不可设定参数的 SELECT 语句。

  ```elixir
  "SELECT id FROM account WHERE name = 'Alice'"
  ```

  ## 参数

  |名称|类型|说明|
  |--|--|--|
  |stmt|String.t|SELECT　语句|

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
  ```

  since: 0.1.0

  """
  @spec squery(String.t) :: {:ok, %{String.t => non_neg_integer}, [[any]]} | {:error, String.t}
  def squery(stmt) do
    :poolboy.transaction(:pgpool, fn(pid) ->
      GenServer.call(pid, {:squery, stmt})
      |> handle_query_result
    end)
  end

  @doc """
  执行不可设定参数的非 SELECT 语句。

  ```elixir
  "INSERT INTO account VALUES('Alice', 'secret-password')"
  ```

  ## 参数

  |名称|类型|说明|
  |--|--|--|
  |stmt|String.t|SQL 语句|

  ## 结果

  ###　成功

  ```elixir
  :ok
  ```

  ### 失败

  ```elixir
  {:error, reason}
  ```

  since: 0.1.0

  """
  @spec scmd(String.t) :: {:ok, %{String.t => non_neg_integer}, [[any]]} | {:error, String.t}
  def scmd(stmt) do
    :poolboy.transaction(:pgpool, fn(pid) ->
      GenServer.call(pid, {:squery, stmt})
      |> handle_cmd_result
    end)
  end

  @doc """
  获取结果中的字段内容。

  ## 参数

  |名称|类型|说明|
  |--|--|--|
  |row|list|数据行|
  |col|String.t|列名称|
  |cols|%{String.t => non_neg_integer}|列名称与下标映射|

  ## 例子

      iex> PGPool.get_field(["a", "b", "c"], "B", %{"A" => 0, "B" => 1, "C" => 2})
      "b"

  since: 0.1.0
  """
  @spec get_field([any], String.t, %{String.t => non_neg_integer}) :: any
  def get_field(row, col, cols) do
    pos = Map.get(cols, col)
    Enum.fetch!(row, pos)
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

  defp handle_query_result({:error, {_, _, _, error, _}}) do
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
    colmap = Enum.reduce(cols, {0, %{}}, fn x, {i, map} ->
      {i + 1, Map.put(map, x, i)}
    end)
    result = Enum.map(rows, fn x ->
      values = :erlang.tuple_to_list(x)
      Enum.map(0 .. :erlang.length(cols) - 1, fn i ->
        case Enum.fetch!(masks, i) do
          true -> Enum.fetch!(values, i) |> String.split(",") |> Enum.reduce(%{}, &(hstore_to_map &1, &2))
          false -> Enum.fetch!(values, i)
        end
      end)
    end)
    {:ok, colmap, result}
  end

  defp handle_cmd_result({:error, {_, _, _, error, _}}) do
    {:error, error}
  end

  defp handle_cmd_result(_any) do
    :ok
  end
end
