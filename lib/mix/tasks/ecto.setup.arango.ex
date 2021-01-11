defmodule Mix.Tasks.Ecto.Setup.Arango do
  @moduledoc """
  Sets up all necessary collection in _systems db for migrations and creates database
  """

  use Mix.Task
  import Mix.ArangoXEcto

  alias ArangoXEcto.Migrator

  @shortdoc "Sets up all necessary collections in _systems db for migrations"

  @impl true
  def run(_args) do
    Mix.Task.run("app.start")

    repo = get_default_repo!()

    case create_migrations(repo) do
      :ok ->
        create_master_document(repo)
        Mix.shell().info("Setup Complete")

      {:error, 409} ->
        Mix.shell().info("ArangoDB already setup for ecto")
    end
  end


end
