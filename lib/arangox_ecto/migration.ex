defmodule ArangoXEcto.Migration do
  @type index_option ::
          {:type, atom}
          | {:unique, boolean}
          | {:sparse, boolean}
          | {:deduplication, boolean}
          | {:minLength, integer}

  defmodule Collection do
    defstruct [:name, :type]
  end

  defmodule Index do
    defstruct [:collection_name, :fields, :sparse, :unique, :deduplication, :minLength, type: :hash]
  end

  defmacro __using__(_) do
    # Init conn
    quote do
      import ArangoXEcto.Migration
    end
  end

  def collection(collection_name, type \\ :document) do
    %Collection{name: collection_name, type: collection_type(type)}
  end

  @spec index(String.t(), [String.t()], [index_option]) :: %Index{}
  def index(collection_name, fields, opts \\ []) do
    index = %Index{
      collection_name: collection_name,
      fields: fields
    }

    Enum.each(opts, fn {key, value} ->
      if key in struct_keys(index) do
        Map.put(index, key, index_opt_value(key, value))
      end
    end)

    index
  end

  def create(%Collection{} = collection) do
    {:ok, conn} = get_db_conn()

    case Arangox.post(conn, "/_api/collection", Map.from_struct(collection)) do
      {:ok, _, _} -> :ok
      {:error, %{status: status, message: message}} -> {:error, "#{status} - #{message}"}
    end
  end

  def create(%Index{collection_name: collection_name} = index) do
    {:ok, conn} = get_db_conn()

    case Arangox.post(conn, "/_api/index?collection=" <> collection_name, Map.from_struct(index)) do
      {:ok, _, _} -> :ok
      {:error, %{status: status, message: message}} -> {:error, "#{status} - #{message}"}
    end
  end

  def drop(%Collection{name: collection_name}) do
    {:ok, conn} = get_db_conn()

    case Arangox.delete(conn, "/_api/collection/" <> collection_name) do
      {:ok, _, _} -> :ok
      {:error, %{status: status, message: message}} -> {:error, "#{status} - #{message}"}
    end
  end

  defp get_db_conn do
    config(pool_size: 1)
    |> Arangox.start_link()
  end

  defp get_default_repo! do
    case Mix.Ecto.parse_repo([])
         |> List.first() do
      nil -> raise "No Default Repo Found"
      repo -> repo
    end
  end

  defp config(opts) do
    get_default_repo!().config()
    |> Keyword.merge(opts)
  end

  defp collection_type(:document), do: 2
  defp collection_type(:edge), do: 3

  @spec index_type(atom) :: String.t()
  defp index_type(type) when is_atom(type) do
    if type in struct_keys(%Index{}) do
      Atom.to_string(type)
    else
      "hash"
    end
  end

  defp index_type(type), do: "hash"

  defp index_opt_value(:type, value), do: index_type(value)
  defp index_opt_value(_, value), do: value

  defp struct_keys(%{} = struct), do: Map.keys(struct) |> List.delete(:__struct__)
end