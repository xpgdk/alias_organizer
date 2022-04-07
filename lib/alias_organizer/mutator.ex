defmodule AliasOrganizer.Mutator do
  alias AliasOrganizer.Alias

  def strip_alias_expressions([{do_expr, {:__block__, meta, block_content}}]) do
    stripped_block =
      block_content
      |> Enum.reject(fn
        {:alias, _meta, _body} ->
          true

        _ ->
          false
      end)

    [{do_expr, {:__block__, meta, stripped_block}}]
  end

  def strip_alias_expressions([{{:__block__, meta, args}, block_content}]) do
    [{{:__block__, meta, args}, block_content}]
  end

  defp always_expand_aliases(block, aliased_modules) do
    Sourceror.prewalk(block, fn
      {:__aliases__, meta, path}, state ->
        resolved_alias_path = Alias.resolve(aliased_modules, path)

        {{:__aliases__, meta, resolved_alias_path}, state}

      quoted, state ->
        {quoted, state}
    end)
  end

  def replace_aliases(
        [{do_expr, {:__block__, meta, block_content}}],
        short_version_map,
        aliased_modules
      ) do
    block_content =
      Enum.map(block_content, fn
        {:@, _meta, [{:moduledoc, _, _}]} = block ->
          block

        {:@, _meta, [{:behaviour, _, _}]} = block ->
          always_expand_aliases(block, aliased_modules)

        {:use, _, _} = block ->
          always_expand_aliases(block, aliased_modules)

        {:require, _, _} = block ->
          always_expand_aliases(block, aliased_modules)

        {:import, _, _} = block ->
          always_expand_aliases(block, aliased_modules)

        {:defmodule, _, _} = block ->
          block

        block ->
          Sourceror.prewalk(block, fn
            {:__aliases__, meta, path}, state ->
              resolved_alias_path = Alias.resolve(aliased_modules, path)

              # if Alias.global_module?(resolved_alias_path) do
                short_alias = Map.get(short_version_map, resolved_alias_path, resolved_alias_path)
                {{:__aliases__, meta, short_alias}, state}
              # else
              #   {{:__aliases__, meta, path}, state}
              # end

            quoted, state ->
              {quoted, state}
          end)
      end)

    [{do_expr, {:__block__, meta, block_content}}]
  end

  def replace_aliases(
        [{{:__block__, _meta, _args}, _expr}] = ast,
        _short_version_map,
        _aliased_modules
      ),
      do: ast

  def add_alias_expressions([{do_expr, {:__block__, meta, block_content}}], short_version_map) do
    alias_ast =
      short_version_map
      |> Enum.to_list()
      |> Enum.map(fn {long, short} -> Enum.take(long, 1 + length(long) - length(short)) end)
      |> Enum.reject(fn path -> Enum.count(path) == 1 end)
      # |> group_aliases_with_common_prefix()
      |> Enum.reject(fn
        {_prefix, []} -> true
        _ -> false
      end)
      |> Enum.sort_by(fn
        {prefix, _postfixes} ->
          Alias.alias_to_string(prefix)

        path ->
          Alias.alias_to_string(path)
      end)
      |> Enum.map(fn
        {prefix, postfixes} ->
          if Enum.count(postfixes) == 1 do
            {:alias, [], [{:__aliases__, [], hd(postfixes)}]}
          else
            postfixes =
              Enum.map(postfixes, fn postfix ->
                {:__aliases__, [], Enum.drop(postfix, Enum.count(prefix))}
              end)
              |> Enum.sort()

            {:alias, [],
             [
               {{:., [],
                 [
                   {:__aliases__, [], prefix},
                   :{}
                 ]}, [], postfixes}
             ]}
          end

        alias_path ->
          {:alias, [], [{:__aliases__, [], alias_path}]}
      end)

    alias_split_index =
      Enum.find_index(block_content, fn
        {:@, _meta, [{:moduledoc, _, _}]} -> false
        {:@, _meta, [{:behaviour, _, _}]} -> false
        {:use, _meta, _args} -> false
        {:require, _meta, _args} -> false
        {:import, _meta, _args} -> false
        _ -> true
      end) || 0

    {before_block, after_block} = Enum.split(block_content, alias_split_index)

    [{do_expr, {:__block__, meta, before_block ++ alias_ast ++ after_block}}]
  end

  def add_alias_expressions([{{:__block__, _meta, _args}, _expr}] = ast, _short_version_map),
    do: ast

  # defp group_aliases_with_common_prefix(alias_list) do
  #   possible_prefixes =
  #     alias_list
  #     |> Enum.map(&Enum.take(&1, Enum.count(&1) - 1))
  #     |> Enum.uniq()

  #   prefixes =
  #     possible_prefixes
  #     |> Enum.map(fn prefix ->
  #       included_paths =
  #         alias_list
  #         |> Enum.filter(&List.starts_with?(&1, prefix))
  #         |> Enum.uniq()

  #       {prefix, included_paths}
  #     end)
  #     |> Enum.reject(fn {_prefix, paths} -> Enum.count(paths) == 1 end)

  #   # Paths that are member of multiple prefixes need to be removed from the least specific one.
  #   prefixes =
  #     Enum.reduce(alias_list, prefixes, fn alias_path, prefixes ->
  #       {longest_prefix, _prefix_length} =
  #         prefixes
  #         |> Enum.filter(fn {_prefix, paths} -> alias_path in paths end)
  #         |> Enum.map(fn {prefix, _paths} -> {prefix, Enum.count(prefix)} end)
  #         |> Enum.max_by(fn {_prefix, length} -> length end, fn -> {nil, 0} end)

  #       # Now that we know the longest prefix (it is nil if the alias was not part of a prefix),
  #       # we can remove it from all other prefixes, but the longest
  #       prefixes
  #       |> Enum.map(fn {prefix, paths} ->
  #         if prefix != longest_prefix do
  #           {prefix, List.delete(paths, alias_path)}
  #         else
  #           {prefix, paths}
  #         end
  #       end)
  #     end)

  #   # If a prefix contains itself, remove it from itself, and add it explicitly.
  #   # I.e.
  #   # alias A.B
  #   # alias A.B.{One,Two}
  #   # A.B is both used as a prefix, but also used directly as an alias, so it needs
  #   # a dedicated entry
  #   prefixes =
  #     Enum.reduce(prefixes, [], fn {prefix, paths} = entry, acc ->

  #       if prefix in paths do
  #         new_entry = {prefix, Enum.reject(paths, &(&1 == prefix))}
  #         [new_entry | acc]
  #       else
  #         [entry | acc]
  #       end
  #     end)

  #   aliases_part_of_prefixes =
  #     alias_list
  #     |> Enum.filter(fn alias_path ->
  #       Enum.any?(prefixes, fn {_prefix, included_paths} ->
  #         alias_path in included_paths
  #       end)
  #     end)

  #   (alias_list
  #    |> Enum.reject(&(&1 in aliases_part_of_prefixes))) ++ prefixes
  #    |> Enum.uniq()
  # end
end
