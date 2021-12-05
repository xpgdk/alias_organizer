defmodule AliasOrganizer do
  alias AliasOrganizer.{Alias, Collector, Mutator, Shortener}

  def process_files(files) when is_list(files) do
    Enum.each(files, &process_file/1)
  end

  def process_file(file) when is_binary(file) do
    IO.puts("Processing #{file}")

    input_ast =
      File.read!(file)
      |> Sourceror.parse_string!()

    output_ast =
      input_ast
      |> process_file_ast()

    if input_ast != output_ast do
      content =
        Sourceror.to_string(output_ast)
        |> insert_newline_between_alias_and_other_content()

      File.write!(file, content)
    end
  end

  @alias_without_two_newlines_pattern ~R/(alias.*[^{]\n)((?![ ]*(?:alias|\n) .*).*)/

  defp insert_newline_between_alias_and_other_content(content) do
    Regex.replace(@alias_without_two_newlines_pattern, content, "\\1\n\\2")
  end

  defp process_file_ast({:__block__, meta, block}) do
    {:__block__, meta, Enum.map(block, &process_file_ast/1)}
  end

  defp process_file_ast({:defmodule, _meta, _body} = quoted_module) do
    process_module(quoted_module)
  end

  defp process_file_ast({_cmd, _meta, _body} = ast_node), do: ast_node

  defp process_file_ast({x, y}) do
    {process_file_ast(x), process_file_ast(y)}
  end

  defp process_file_ast(list) when is_list(list) do
    Enum.map(list, &process_file_ast/1)
  end

  defp process_file_ast(x), do: x

  def process_module({:defmodule, meta, [alias_name | [body]]}) do
    module_name = Alias.alias_to_string(alias_name)

    if skip_module?(meta) do
      IO.puts("Skipping '#{module_name}'")

      body =
        body
        |> process_file_ast()

      {:defmodule, meta, [alias_name | [body]]}
    else
      IO.puts("Processing '#{module_name}'")

      aliased_modules = Collector.collect_aliased_modules(body)

      body_without_alias_expressions = Mutator.strip_alias_expressions(body)

      used_aliases =
        Collector.collect_used_aliases(body_without_alias_expressions, aliased_modules)

      short_version_map = Shortener.determine_short_versions(used_aliases)

      body =
        body_without_alias_expressions
        |> Mutator.replace_aliases(short_version_map, aliased_modules)
        |> Mutator.add_alias_expressions(short_version_map)
        |> process_file_ast()

      {:defmodule, meta, [alias_name | [body]]}
    end
  end

  defp skip_module?(meta) do
    leading_comments = Keyword.get(meta, :leading_comments, [])
    Map.get(List.last(leading_comments) || %{}, :text) == "# @NoOrganizeAliases"
  end
end
