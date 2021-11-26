defmodule AliasOrganizer.Alias do
  @type t :: [atom()]
  @type registry :: [t()]

  def alias_to_string({:__aliases__, _meta, path}) do
    alias_to_string(path)
  end

  def alias_to_string(path) when is_list(path) do
    path
    |> Enum.map(&to_string/1)
    |> Enum.join(".")
  end

  @spec resolve(registry(), t()) :: t()
  def resolve(registry, [first_part | tail] = alias_path) do
    found =
      Enum.find(registry, fn registered_alias ->
        List.starts_with?(Enum.reverse(registered_alias), [first_part])
      end)

    if found do
      found ++ tail
    else
      alias_path
    end
  end
end
