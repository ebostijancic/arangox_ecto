defmodule Mix.Tasks.Ecto.Migrate.Arango do
  @moduledoc """
  Runs Migration/Rollback functions from migration modules
  """

  use Mix.Task

  import Mix.ArangoXEcto

  alias ArangoXEcto.Migrator

  @shortdoc "Runs Migration/Rollback functions from migration modules"

  @aliases [
    d: :dir
  ]

  @switches [
    dir: :string
  ]

  @impl true
  def run(args) do
    Mix.Task.run("app.start")

    repo = get_default_repo!()

    case Migrator.migrated_versions(repo) do
      [nil] ->
        Mix.raise("ArangoXEcto is not set up, run `mix ecto.setup.arango` first.")

      _ ->
        Mix.shell().info("Migrating repo #{repo}")
        Migrator.migrate(repo, args)
    end
  end
end
