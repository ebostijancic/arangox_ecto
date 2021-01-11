defmodule ArangoXEctoMigratorTest do
  use ExUnit.Case

  alias ArangoXEctoTest.Repo
  alias ArangoXEcto.Migrator

  @collection "_migrations_test"

  setup_all do
    %{pid: conn} = Ecto.Adapter.lookup_meta(Repo)

    [conn: conn]
  end

  test "create migration collection if not existent", %{conn: conn} do
    assert :ok = Migrator.create_migration_collection(conn, @collection)
    Arangox.get!(conn, "/_api/collection/#{@collection}")
  end

  test  "upsert migration document", %{conn: conn} do
    # assert :ok = Migrator.create_migration_collection(conn, @collection)

    versions = %{migrations: [1, 2, 3]}
    assert %Arangox.Response{status: 202} = Migrator.upsert_migration_document(Repo, conn, versions, "MASTER", @collection)
  end
end
