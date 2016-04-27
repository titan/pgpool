defmodule PGPool.Mixfile do
  use Mix.Project

  def project do
    [app: :pgpool,
     version: "0.1.0",
     elixir: "~> 1.2",
     compilers: [:make | Mix.compilers],
     aliases: aliases,
     build_embedded: Mix.env == :prod,
     start_permanent: Mix.env == :prod,
     deps: deps]
  end

  def application do
    [applications: [:logger, :epgsql, :poolboy]]
  end

  defp deps do
    [
      {:epgsql, "~> 3.1"},
      {:poolboy, "~> 1.5"},
      {:ex_doc, "~> 0.11", only: :dev}
    ]
  end

  defp aliases do
    # Execute the usual mix clean and our Makefile clean task
    [clean: ["clean", "clean.make"]]
  end

end

defmodule Mix.Tasks.Compile.Make do
  @shortdoc "Compiles helper in c_src"

  def run(_) do
    {result, _error_code} = System.cmd("make", [], stderr_to_stdout: true)
    Mix.shell.info result

    :ok
  end
end

defmodule Mix.Tasks.Clean.Make do
  @shortdoc "Cleans helper in c_src"

  def run(_) do
    {result, _error_code} = System.cmd("make", ['clean'], stderr_to_stdout: true)
    Mix.shell.info result

    :ok
  end
end
