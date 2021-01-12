defmodule ArangoXEcto.Migrator do
  require Logger
  require Ecto.Query

  alias ArangoXEcto.RepoConfig

  @migrations_collection "_migrations"
  @master_document "MASTER"

  def migrate(repo, args) do
    RepoConfig.start_link(repo)

    case OptionParser.parse!(args, aliases: @aliases, strict: @switches) do
      {[], []} ->
        up(repo)

      {[dir: "up"], _} ->
        up(repo)

      {_, ["up"]} ->
        up(repo)

      {[dir: "down"], _} ->
        down(repo)

      {_, ["down"]} ->
        down(repo)

      {_, ["rollback"]} ->
        down(repo)

      {_, _} ->
        Logger.error("Unknown arguments provided, #{inspect(Enum.join(args, " "))}")
    end
  end

  defp up(repo) do
    pending_migrations(repo)
    |> Enum.each(fn file_path ->
      case apply(migration_module(repo, file_path), :up, []) do
        :ok ->
          version = timestamp(file_path)
          update_versions(repo, version, @master_document)

          Logger.info("Successfully Migrated #{file_path}")

        {:error, reason} ->
          Logger.info("Unable to Migrate #{file_path}")
          Logger.error("Status: " <> inspect(reason))
      end
    end)
  end

  def down(repo) do
    [last_migrated_version | _] = versions(repo)

    module =
      last_migrated_version
      |> migration_path(repo)
      |> migration_module(repo)

    case apply(module, :down, []) do
      :ok ->
        remove_version(repo, last_migrated_version)
        Logger.info("Successfully Rolled Back #{last_migrated_version}")

      _ ->
        Logger.info("Unable to Rollback #{last_migrated_version}")
    end
  end

  defp migration_module(repo, path) do
    {{:module, module, _, _}, _} =
      path_to_priv_repo(repo)
      |> Path.join("migrations")
      |> Path.join(path)
      |> Code.eval_file()

    module
  end

  defp migration_path(repo, version) when not is_binary(version) do
    version
    |> to_string()
    |> migration_path(repo)
  end

  defp migration_path(repo, version) do
    path_to_priv_repo(repo)
    |> Path.join("migrations")
    |> File.ls!()
    |> Enum.find(&String.starts_with?(&1, version))
  end

  defp pending_migrations(repo) do
    path_to_priv_repo(repo)
    |> Path.join("migrations")
    |> File.ls!()
    |> Enum.filter(&(!String.starts_with?(&1, ".")))
    #    |> Enum.filter(&(timestamp(&1) not in versions()))
    |> Enum.sort(&(timestamp(&1) <= timestamp(&2)))
  end

  defp timestamp(path) do
    path
    |> String.split("_")
    |> hd()
    |> String.to_integer()
  end

  defp versions(repo) do
    migrated_versions(repo)
    |> Enum.sort(&(&1 >= &2))
  end

  @doc false
  def update_version(repo, version, master_document \\ @master_document) do
    update_version(repo, version, master_document)
  end

  @doc false
  def update_versions(repo, version, master_document) when is_binary(version) do
    update_versions(repo, String.to_integer(version), master_document)
  end

  @doc false
  def update_versions(repo, version, master_document) do
    {:ok, conn} = db(repo)

    new_versions = [version | migrated_versions(repo, master_document)]

    :ok = create_migration_collection(conn)
    upsert_migration_document(repo, conn, %{migrations: new_versions, _key: master_document}, master_document)
    new_versions
  end

  @doc false
  def create_migration_collection(conn, collection \\ @migrations_collection) do
     case Arangox.get(conn, "/_api/collection/#{collection}/properties") do
      {:ok, %Arangox.Response{body: %{"isSystem" => true}}} ->
        Logger.debug("_system migration collection found")
      {:ok, %Arangox.Response{body: %{"isSystem" => false}}} ->
        Logger.debug("Migration collection found")
      {:ok, _response} ->
        Logger.debug("Migration collection found")
      {:error, %Arangox.Error{status: 404}} ->
        Logger.warn("Migration collection not found, creating")
        Arangox.post!(conn, "/_api/collection", %{name: collection, type: 2, isSystem: true, waitForSync: false})
        :ok
    end
  end

  def upsert_migration_document(repo,
    conn,
    migration_versions,
    master_document \\ @master_document,
    collection \\ @migrations_collection) do

    document = "/_api/document/#{collection}"
    case Arangox.get(conn, "#{document}/#{master_document}") do
      {:ok, _response} ->
        Logger.debug("Migration document found, updating")
        Arangox.patch!(conn, "#{document}/#{master_document}", migration_versions)

      {:error, %Arangox.Error{status: 404}} ->
        Logger.debug("Migration document not found, creating")
        # TODO migrate existing migration from legacy
        legacy_versions = copy_legacy_migration(repo, migration_versions.migrations)
        Arangox.post!(conn, document, migration_versions)

      {:error, error} ->
        Logger.error("Error getting migration document #{inspect(error)}")
    end
  end

  def copy_legacy_migration(repo, migration_versions) do
    {:ok, conn} = system_db(repo)

    case Arangox.get(conn, "/_api/document/_migrations/MASTER") do
      {:ok, %Arangox.Response{body: body}} ->
        Logger.info("Legacy migrations collection found")

        legacy_migrations = Map.fetch!(body, "migrations")
        legacy_migrations ++ migration_versions
      _ ->
        Logger.info("Legacy migration not found")
        migration_versions
    end
  end

  @doc false
  def migrated_versions(repo, master_document \\ @master_document) do
    {:ok, conn} = db(repo)

    {:ok, versions} =
      query(conn, """
        RETURN DOCUMENT("#{@migrations_collection}/#{master_document}").migrations
      """)

    versions
  end

  @doc false
  def remove_version(repo, version) when is_binary(version),
    do: remove_version(repo, String.to_integer(version))

  def remove_version(repo, version, master_document \\ @master_document) do
    {:ok, conn} = db(repo, [])

    new_versions =
      migrated_versions(repo)
      |> List.delete(version)

    path = "/_api/document/#{@migrations_collection}/#{master_document}"
    Arangox.patch!(conn, path, %{migrations: new_versions})

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

  defp config(repo, opts) do
    repo.config()
    |> Keyword.merge(opts)
    |> ensure_endpoint_value()
  end

  defp ensure_endpoint_value(config) do
    if Keyword.has_key?(config, :endpoints) do
      config
    else
      Keyword.put(config, :endpoints, "http://localhost:8529")
    end
  end

  def db(repo, opts \\ []) do
    Arangox.start_link(config(repo, opts))
  end

  defp system_db(repo) do
    options = config(repo, pool_size: 1, database: "_system")

    Arangox.start_link(options)
  end

  defp pad(i) when i < 10, do: <<?0, ?0 + i>>
  defp pad(i), do: to_string(i)

  @doc false
  def path_to_priv_repo(repo) do
    app = Keyword.fetch!(repo.config(), :otp_app)
    priv_dir = "#{:code.priv_dir(app)}"

    repo_underscore =
      repo
      |> Module.split()
      |> List.last()
      |> Macro.underscore()

    Path.join([priv_dir, repo_underscore])
  end

  @doc false
  def timestamp do
    {{y, m, d}, {hh, mm, ss}} = :calendar.universal_time()
    "#{y}#{pad(m)}#{pad(d)}#{pad(hh)}#{pad(mm)}#{pad(ss)}"
  end
end

defmodule ArangoXEcto.RepoConfig do
  @doc false

  use Agent

  def start_link(repo) do
    Agent.start_link(fn -> repo.config() end, name: __MODULE__)
  end

  def config do
    Agent.get(__MODULE__, & &1)
  end
end
