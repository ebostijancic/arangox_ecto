defmodule Mix.ArangoXEcto do
  # Based off of https://github.com/SquashConsulting/ecto_aql.
  @moduledoc false

  alias ArangoXEcto.Migrator

  @doc false
  def path_to_priv_repo(repo) do
    app = Keyword.fetch!(repo.config(), :otp_app)
    Path.join(Mix.Project.deps_paths()[app] || File.cwd!(), "priv/repo")
  end

  @doc false
  def timestamp do
    {{y, m, d}, {hh, mm, ss}} = :calendar.universal_time()
    "#{y}#{pad(m)}#{pad(d)}#{pad(hh)}#{pad(mm)}#{pad(ss)}"
  end

  @doc false
  def get_default_repo! do
    Mix.Ecto.parse_repo([])
    |> List.first()
    |> case do
      nil -> Mix.raise("No Default Repo Found")
      repo -> repo
    end
  end

  @doc false
  def create_migrations(repo) do
    {:ok, conn} = Migrator.db(repo)
    Migrator.create_migration_collection(conn)
  end

  @doc false
  def create_master_document(repo) do
    {:ok, conn} = Migrator.db(repo)

    Migrator.upsert_migration_document(repo, conn, %{migrations: [], _key: "MASTER"})
  end

  defp pad(i) when i < 10, do: <<?0, ?0 + i>>
  defp pad(i), do: to_string(i)
end
