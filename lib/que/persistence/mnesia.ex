defmodule Que.Persistence.Mnesia do
  use Que.Persistence
  use Amnesia


  @moduledoc """
  Mnesia adapter to persist `Que.Job`s

  This module defines a Database and a Job Table in Mnesia to keep
  track of all Jobs, along with Mnesia transaction methods that
  provide an easy way to find, insert, update or destroy Jobs from
  the Database.

  It implements all callbacks defined in `Que.Persistence`, along
  with some `Mnesia` specific ones. You should read the
  `Que.Persistence` documentation if you just want to interact
  with the Jobs in database.


  ## Persisting to Disk

  `Que` works out of the box without any configuration needed, but
  initially all Jobs are not persisted to disk, and are only in
  memory. You'll need to create the Mnesia Schema on disk and create
  the Job Database for this to work.

  Que provides ways that automatically do this for you. First,
  specify the location where you want your Mnesia database to be
  created in your `config.exs` file. It's highly recommended that you
  specify your `Mix.env` in the path to keep development, test and
  production databases separate.

  ```
  config :mnesia, dir: 'mnesia/\#{Mix.env}/\#{node()}'
  # Notice the single quotes
  ```

  You can now either run the `Mix.Tasks.Que.Setup` mix task or call
  `Que.Persistence.Mnesia.setup!/0` to create the Schema, Database
  and Tables.
  """


  @config [
    db:     DB,
    table:  Jobs
  ]

  @db     Module.concat(__MODULE__, @config[:db])
  @store  Module.concat(@db, @config[:table])




  @doc """
  Creates the Mnesia Database for `Que` on disk

  This creates the Schema, Database and Tables for
  Que Jobs on disk for the current erlang `node` so
  Jobs are persisted across application restarts.
  Calling this momentarily stops the `:mnesia`
  application so you should make sure it's not being
  used when you do.

  ## On Production

  For a compiled release (`Distillery` or `Exrm`),
  start the application in console mode or connect a
  shell to the running release and simply call the
  method:

  ```
  $ bin/my_app remote_console

  iex(my_app@127.0.0.1)1> Que.Persistence.Mnesia.setup!
  :ok
  ```

  """
  @spec setup! :: :ok
  def setup! do
    nodes = [node()]

    # Create the DB directory (if custom path given)
    if path = Application.get_env(:mnesia, :dir) do
      :ok = File.mkdir_p!(path)
    end

    # Create the Schema
    Amnesia.stop
    Amnesia.Schema.create(nodes)
    Amnesia.start

    # Create the DB with Disk Copies
    @db.create!(disk: nodes)
    @db.wait(15000)
  end




  @doc "Returns the Mnesia configuration for Que"
  @spec __config__ :: Keyword.t
  def __config__ do
    [database: @db, table: @store]
  end





  defdatabase DB do
    @moduledoc false

    deftable Jobs, [{:id, autoincrement}, :arguments, :worker, :status, :ref, :pid, :created_at, :updated_at],
      type:  :ordered_set do

      @store     __MODULE__
      @moduledoc false



      @doc "Finds all Jobs"
      def find_all_jobs do
        Amnesia.transaction do
          keys()
          |> match
          |> parse_selection
        end
      end



      @doc "Find Completed Jobs"
      def find_completed_jobs do
        Amnesia.transaction do
          where(status == :completed)
          |> parse_selection
        end
      end



      @doc "Find Incomplete Jobs"
      def find_incomplete_jobs do
        Amnesia.transaction do
          where(status == :queued or status == :started)
          |> parse_selection
        end
      end



      @doc "Find Failed Jobs"
      def find_failed_jobs do
        Amnesia.transaction do
          where(status == :failed)
          |> parse_selection
        end
      end



      @doc "Find all Jobs for a worker"
      def find_jobs_for_worker(name) do
        Amnesia.transaction do
          where(worker == name)
          |> parse_selection
        end
      end



      @doc "Finds a Job in the DB"
      def find_job(job) do
        Amnesia.transaction do
          job
          |> normalize_id
          |> read
          |> to_que_job
        end
      end



      @doc "Inserts a new Que.Job in to DB"
      def create_job(job) do
        job
        |> Map.put(:created_at, NaiveDateTime.utc_now)
        |> update_job
      end



      @doc "Updates existing Que.Job in DB"
      def update_job(job) do
        Amnesia.transaction do
          job
          |> Map.put(:updated_at, NaiveDateTime.utc_now)
          |> to_db_job
          |> write
          |> to_que_job
        end
      end



      @doc "Deletes a Que.Job from the DB"
      def delete_job(job) do
        Amnesia.transaction do
          job
          |> normalize_id
          |> delete
        end
      end




      ## PRIVATE METHODS


      # Returns Job ID
      defp normalize_id(job) do
        cond do
          is_map(job) -> job.id
          true        -> job
        end
      end



      # Convert Que.Job to Mnesia Job
      defp to_db_job(%Que.Job{} = job) do
        struct(@store, Map.from_struct(job))
      end



      # Convert Mnesia DB Job to Que.Job
      defp to_que_job(nil), do: nil
      defp to_que_job(%@store{} = job) do
        struct(Que.Job, Map.from_struct(job))
      end



      # Convert Selection to Que.Job struct list
      defp parse_selection(selection) do
        selection
        |> Amnesia.Selection.values
        |> Enum.map(&to_que_job/1)
      end

    end
  end



  # Make sures that the DB exists (either
  # in memory or on disk)
  @doc false
  def initialize, do: @db.create


  @doc false
  defdelegate all,                to: @store,   as: :find_all_jobs

  @doc false
  defdelegate completed,          to: @store,   as: :find_completed_jobs

  @doc false
  defdelegate incomplete,         to: @store,   as: :find_incomplete_jobs

  @doc false
  defdelegate failed,             to: @store,   as: :find_failed_jobs

  @doc false
  defdelegate find(job),          to: @store,   as: :find_job

  @doc false
  defdelegate for_worker(worker), to: @store,   as: :find_jobs_for_worker

  @doc false
  defdelegate insert(job),        to: @store,   as: :create_job

  @doc false
  defdelegate update(job),        to: @store,   as: :update_job

  @doc false
  defdelegate destroy(job),       to: @store,   as: :delete_job

end
