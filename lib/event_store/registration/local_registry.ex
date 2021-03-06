defmodule EventStore.Registration.LocalRegistry do
  @moduledoc """
  Pub/sub using Elixir's local `Registry` module, restricted to running on a
  single node only.
  """

  @behaviour EventStore.Registration

  @doc """
  Return the local supervisor child spec.
  """
  @spec child_spec() :: [:supervisor.child_spec()]
  @impl EventStore.Registration
  def child_spec do
    [
      Supervisor.child_spec(
        {
          Registry,
          keys: :duplicate, name: EventStore.PubSub, partitions: System.schedulers_online()
        },
        id: EventStore.PubSub
      )
    ]
  end

  @doc """
  Subscribes the caller to the given topic.
  """
  @spec subscribe(binary) :: :ok | {:error, term}
  @impl EventStore.Registration
  def subscribe(topic) do
    with {:ok, _} <- Registry.register(EventStore.PubSub, topic, []) do
      :ok
    end
  end

  @doc """
  Is the caller subscribed to the given topic?
  """
  @spec subscribed?(binary) :: true | false
  @impl EventStore.Registration
  def subscribed?(topic) do
    subscriptions = Registry.lookup(EventStore.PubSub, topic)
    caller = self()

    Enum.any?(subscriptions, fn
      {^caller, _} -> true
      _ -> false
    end)
  end

  @doc """
  Broadcasts message on given topic.
  """
  @spec broadcast(binary, term) :: :ok | {:error, term}
  @impl EventStore.Registration
  def broadcast(topic, message) do
    Registry.dispatch(EventStore.PubSub, topic, fn entries ->
      for {pid, _} <- entries, do: send(pid, message)
    end)
  end
end
