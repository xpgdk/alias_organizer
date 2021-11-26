defmodule AliasOrganizer.Shortener do
  alias AliasOrganizer.Alias

  @type t :: %{Alias.t() => Alias.t()}

  @spec determine_short_versions(Alias.registry()) :: t()
  def determine_short_versions(aliases) do
    aliases
    |> Enum.sort()
    |> Enum.uniq()
    |> Enum.reject(&(Enum.count(&1) < 2))
    |> Enum.reduce(%{}, fn alias_path, short_aliases ->
      short_alias = find_shortest_available_alias_path(short_aliases, alias_path)

      Map.put(short_aliases, short_alias, alias_path)
    end)
    |> Map.new(fn {short, long} -> {long, short} end)
    |> remove_problematic_short_aliases()
  end

  defp find_shortest_available_alias_path(short_aliases, alias_path) do
    reversed_path =
      alias_path
      |> Enum.reverse()

    baf(short_aliases, [hd(reversed_path)], tl(reversed_path))
  end

  defp baf(short_aliases, rev_candidate, rev_tail) do
    if not Map.has_key?(short_aliases, Enum.reverse(rev_candidate)) do
      Enum.reverse(rev_candidate)
    else
      baf(short_aliases, rev_candidate ++ [hd(rev_tail)], tl(rev_tail))
    end
  end

  defp remove_problematic_short_aliases(short_version_map) do
    # Any short alias, which starts with an atom that is used by any long
    # aliases is problematic

    Enum.reject(short_version_map, fn {long_lookup, [first | _]} ->
      local_overlap? =
        if Enum.find(short_version_map, fn {long, _short} ->
             long_lookup != long and first in long
           end) == nil do
          false
        else
          true
        end

      global_overlap? = global_module?(first)

      local_overlap? or global_overlap?
    end)
    |> Map.new()
  end

  defp global_module?(module) do
    try do
      Module.concat([module]).__info__(:module)
      true
    rescue
      _ -> false
    end
  end
end
