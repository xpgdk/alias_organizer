defmodule AliasOrganizer.Shortener do
  alias AliasOrganizer.Alias

  @type t :: %{Alias.t() => Alias.t()}

  @spec determine_short_versions(Alias.registry()) :: t()
  def determine_short_versions(aliases) do
    aliases
    |> construct_initial_short_versions()
    |> include_additional_steps_for_conflicting_short_aliases()
    |> remove_problematic_short_aliases(aliases)
  end

  @spec construct_initial_short_versions(Alias.registry()) :: t()
  defp construct_initial_short_versions(aliases) do
    aliases
    |> Enum.sort()
    |> Enum.uniq()
    |> Enum.reject(&(Enum.count(&1) < 2))
    |> Map.new(fn alias_path ->
      {alias_path, [List.last(alias_path)]}
    end)
  end

  @spec include_additional_steps_for_conflicting_short_aliases(t()) :: t()
  defp include_additional_steps_for_conflicting_short_aliases(short_aliases) do
    short_alises_with_one_level_of_conflicts_resolved =
      find_and_resolve_conflicting_short_aliases(short_aliases)

    if short_aliases == short_alises_with_one_level_of_conflicts_resolved do
      short_alises_with_one_level_of_conflicts_resolved
    else
      include_additional_steps_for_conflicting_short_aliases(
        short_alises_with_one_level_of_conflicts_resolved
      )
    end
  end

  @spec find_and_resolve_conflicting_short_aliases(t()) :: t()
  defp find_and_resolve_conflicting_short_aliases(short_aliases) do
    short_aliases
    |> Map.new(fn {full_alias, short_alias} ->
      short_alias_values =
        short_aliases
        |> Map.delete(full_alias)
        |> Map.values()

      if short_alias in short_alias_values do
        new_short_alias =
          full_alias
          |> Enum.reverse()
          |> Enum.take(Enum.count(short_alias) + 1)

        {full_alias, Enum.reverse(new_short_alias)}
      else
        {full_alias, short_alias}
      end
    end)
  end

  defp remove_problematic_short_aliases(short_version_map, used_aliases) do
    # Any short alias, which starts with an atom that is used by any long
    # aliases is problematic

    Enum.reject(short_version_map, fn {_long_lookup, [first | _] = _short} ->
      [first] in used_aliases
    end)
    |> Map.new()
  end
end
