defmodule PGPool.Mixfile do
  use Mix.Project

  def project do
    [app: :pgpool,
     version: "0.2.1",
     elixir: "~> 1.2",
     compilers: [:nif | Mix.compilers],
     build_embedded: Mix.env == :prod,
     start_permanent: Mix.env == :prod,
     deps: deps]
  end

  def application do
    [mod: {PGPool.Application, []},
     applications: [:logger, :epgsql, :poolboy]]
  end

  defp deps do
    [
      {:epgsql, "~> 3.2"},
      {:poolboy, "~> 1.5"},
      {:ex_doc, "~> 0.12", only: :dev}
    ]
  end
end


defmodule Mix.Tasks.Compile.Nif do
  @shortdoc "Compiles helper in c_src"

  def run(_) do
    File.rm_rf!("priv")
    File.mkdir("priv")
    {exec, args} =
      case :os.type do
        {:unix, os} when os in [:freebsd, :openbsd] ->
          {"gmake", ["priv/hstore_to_map.so"]}
        _ ->
          {"make", ["priv/hstore_to_map.so"]}
      end

    if System.find_executable(exec) do
      build(exec, args)
      Mix.Project.build_structure
      :ok
    else
      nocompiler_error(exec)
    end
  end

  def build(exec, args) do
    {result, error_code} = System.cmd(exec, args, stderr_to_stdout: true)
    IO.binwrite result
    if error_code != 0, do: build_error(exec)
  end

  defp nocompiler_error(exec) do
    raise Mix.Error, message: nocompiler_message(exec) <> nix_message
  end

  defp build_error(_) do
    raise Mix.Error, message: build_message <> nix_message
  end

  defp nocompiler_message(exec) do
  """
  Could not find the program `#{exec}`.

  You will need to install the C compiler `#{exec}` to be able to build
  PGPool.

  """
  end

  defp build_message do
  """
  Could not compile PGPool.

  Please make sure that you are using Erlang / OTP version 18.0 or later
  and that you have a C compiler installed.

  """
  end

  defp nix_message do
  """
  Please follow the directions below for the operating system you are
  using:

  Mac OS X: You need to have gcc and make installed. Try running the
  commands `gcc --version` and / or `make --version`. If these programs
  are not installed, you will be prompted to install them.

  Linux: You need to have gcc and make installed. If you are using
  Ubuntu or any other Debian-based system, install the packages
  `build-essential`. Also install `erlang-dev` package if not
  included in your Erlang/OTP version.

  """
  end

end
