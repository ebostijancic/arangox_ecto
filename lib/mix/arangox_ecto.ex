defmodule Mix.ArangoXEcto do
  @moduledoc """
  Helpers for mix tasks

  Based off of https://github.com/SquashConsulting/ecto_aql.
  """

  def path_to_priv_repo(repo) do
    app = Keyword.fetch!(repo.config(), :otp_app)
    Path.join(Mix.Project.deps_paths()[app] || File.cwd!(), "priv/repo")
  end

  def timestamp do
    {{y, m, d}, {hh, mm, ss}} = :calendar.universal_time()
    "#{y}#{pad(m)}#{pad(d)}#{pad(hh)}#{pad(mm)}#{pad(ss)}"
  end

  def create_migrations do
    {:ok, conn} = system_db()

    case Arangox.post(conn, "/_api/collection", %{
           type: 2,
           isSystem: true,
           name: "_migrations"
         }) do
      {:ok, _, _} -> :ok
      {:error, %{status: status}} -> {:error, status}
    end
  end

  def create_master_document do
    {:ok, conn} = system_db()

    {:ok, _, _} =
      Arangox.post(conn, "/_api/document/_migrations", %{_key: "MASTER", migrations: []})
  end

  def migrated_versions do
    {:ok, conn} = system_db()

    {:ok, versions} =
      query(conn, """
        RETURN DOCUMENT("_migrations/MASTER").migrations
      """)

    versions
  end

  def update_versions(version) when is_binary(version),
    do: update_versions(String.to_integer(version))

  def update_versions(version) do
    {:ok, conn} = system_db()

    new_versions = [version | migrated_versions()]

    {:ok, _, _} =
      Arangox.patch(conn, "/_api/document/_migrations/MASTER", %{migrations: new_versions})

    new_versions
  end

  def remove_version(version) when is_binary(version),
    do: remove_version(String.to_integer(version))

  def remove_version(version) do
    {:ok, conn} = system_db()

    new_versions =
      migrated_versions()
      |> List.delete(version)

    {:ok, _, _} =
      Arangox.patch(conn, "/_api/document/_migrations/MASTER", %{migrations: new_versions})

    new_versions
  end

  defp query(conn, query_str) do
    Arangox.transaction(conn, fn cursor ->
      cursor
      |> Arangox.cursor(query_str)
      |> Enum.reduce([], fn resp, acc ->
        acc ++ resp.body["result"]
      end)
      |> List.flatten()
    end)
  end

  def get_default_repo! do
    case Mix.Ecto.parse_repo([])
         |> List.first() do
      nil -> Mix.raise("No Default Repo Found")
      repo -> repo
    end
  end

  defp config(opts) do
    case Keyword.fetch(get_default_repo!().config(), :endpoints) do
      {:ok, endpoints} -> [endpoints: endpoints] |> Keyword.merge(opts)
      :error -> [endpoints: "http://localhost:8529"] |> Keyword.merge(opts)
    end
  end

  defp system_db do
    options =
      config(
        pool_size: 1,
        database: "_system"
      )

    Arangox.start_link(options)
  end

  defp pad(i) when i < 10, do: <<?0, ?0 + i>>
  defp pad(i), do: to_string(i)
end