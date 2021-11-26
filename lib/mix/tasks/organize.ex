defmodule Mix.Tasks.Organize do
  @shortdoc "Organize usage of aliases within a single Elixir source file"

  use Mix.Task

  @impl Mix.Task
  def run(files) do
    Mix.Project.compile_path()
    |> String.to_charlist()
    |> :code.add_path()

    AliasOrganizer.process_files(files)

    :ok
  end
end
