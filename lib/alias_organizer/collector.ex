defmodule AliasOrganizer.Collector do
  alias AliasOrganizer.Alias

  @spec collect_aliased_modules(Macro.t()) :: [Alias.registry()]
  def collect_aliased_modules(body) do
    {_, acc} =
      body
      |> Sourceror.postwalk([], fn
        {:alias, _meta_1,
         [
           {:__aliases__, _meta_2, path}
         ]} = quoted,
        state ->
          {quoted, %{state | acc: [path | state.acc]}}

        {:alias, _meta_1, [{{:., _, [{:__aliases__, _, common_path}, :{}]}, _, block}]} = quoted,
        state ->
          paths = Enum.map(block, fn {:__aliases__, _, path} -> common_path ++ path end)

          {quoted, %{state | acc: paths ++ state.acc}}

        quoted, state ->
          {quoted, state}
      end)

    Enum.uniq(acc)
  end

  @spec collect_used_aliases(Macro.t(), Alias.registry()) :: list()
  def collect_used_aliases([{_do_expr, {:__block__, _meta, body}}], aliased_modules) do
    Enum.reduce(body, [], fn
      {:defmodule, _, _}, acc ->
        acc

      {:use, _, _}, acc ->
        acc

      {:import, _, _}, acc ->
        acc

      {:require, _, _}, acc ->
        acc

      {:@, _meta, [{:behaviour, _, _}]}, acc ->
        acc

      body, acc ->
        {_, acc} =
          Sourceror.prewalk(body, acc, fn
            {:__aliases__, _meta, [{:__MODULE__, _, _} | _]} = quoted, state ->
              {quoted, state}

            {:__aliases__, _meta, path} = quoted, state ->
              resolved_alias = Alias.resolve(aliased_modules, path)
              {quoted, %{state | acc: [resolved_alias | state.acc]}}

            quoted, state ->
              {quoted, state}
          end)

        acc
    end)
    |> Enum.uniq()
  end

  def collect_used_aliases([{{:__block__, _meta, _args}, _expr}], _aliased_modules), do: []
end
