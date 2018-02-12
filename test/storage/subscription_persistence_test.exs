defmodule EventStore.Storage.SubscriptionPersistenceTest do
  use EventStore.StorageCase

  alias EventStore.{Config,ProcessHelper,Storage}

  @all_stream "$all"
  @subscription_name "test_subscription"

  test "create subscription" do
    {:ok, subscription} = Storage.subscribe_to_stream(@all_stream, @subscription_name)

    verify_subscription(subscription)
  end

  test "create subscription when already exists" do
    {:ok, subscription1} = Storage.subscribe_to_stream(@all_stream, @subscription_name)
    {:ok, subscription2} = Storage.subscribe_to_stream(@all_stream, @subscription_name)

    verify_subscription(subscription1)
    verify_subscription(subscription2)

    assert subscription1.subscription_id == subscription2.subscription_id
  end

  test "list subscriptions" do
    {:ok, subscription} = Storage.subscribe_to_stream(@all_stream, @subscription_name)
    {:ok, subscriptions} = Storage.subscriptions()

    assert length(subscriptions) > 0
    assert Enum.member?(subscriptions, subscription)
  end

  test "remove subscription when exists" do
    {:ok, subscriptions} = Storage.subscriptions
    initial_length = length(subscriptions)

    {:ok, _subscription} = Storage.subscribe_to_stream(@all_stream, @subscription_name)
    :ok = Storage.unsubscribe_from_stream(@all_stream, @subscription_name)

    {:ok, subscriptions} = Storage.subscriptions
    assert length(subscriptions) == initial_length
  end

  test "acquire exclusive subscription lock" do
    assert :ok = Storage.try_acquire_exclusive_lock(1)
  end

  test "acquire and release lock by connection" do
    config = Config.parsed() |> Config.default_postgrex_opts()

    {:ok, conn1} = Postgrex.start_link(config)
    {:ok, conn2} = Postgrex.start_link(config)

    # conn1 acquire lock
    assert :ok = Storage.Subscription.try_acquire_exclusive_lock(conn1, 1)

    # conn2 cannot acquire lock
    assert {:error, :lock_already_taken} = Storage.Subscription.try_acquire_exclusive_lock(conn2, 1)

    # conn1 can acquire same lock multiple times
    assert :ok = Storage.Subscription.try_acquire_exclusive_lock(conn1, 1)

    # shutdown conn1 process should release its locks
    ProcessHelper.shutdown(conn1)

    # conn2 can now acquire lock
    assert :ok = Storage.Subscription.try_acquire_exclusive_lock(conn2, 1)

    ProcessHelper.shutdown(conn2)
  end

  test "remove subscription when not found should not fail" do
    :ok = Storage.unsubscribe_from_stream(@all_stream, @subscription_name)
  end

  test "ack last seen event by id" do
    {:ok, _subscription} = Storage.subscribe_to_stream(@all_stream, @subscription_name)

    :ok = Storage.ack_last_seen_event(@all_stream, @subscription_name, 1)

    {:ok, subscriptions} = Storage.subscriptions

    subscription = subscriptions |> Enum.reverse |> hd

    verify_subscription(subscription, 1)
  end

  test "ack last seen event by stream version" do
    {:ok, _subscription} = Storage.subscribe_to_stream(@all_stream, @subscription_name)

    :ok = Storage.ack_last_seen_event(@all_stream, @subscription_name, 1)

    {:ok, subscriptions} = Storage.subscriptions

    subscription = subscriptions |> Enum.reverse |> hd

    verify_subscription(subscription, 1)
  end

  defp verify_subscription(subscription, last_seen \\ nil)

  defp verify_subscription(subscription, last_seen) do
    assert subscription.subscription_id > 0
    assert subscription.stream_uuid == @all_stream
    assert subscription.subscription_name == @subscription_name
    assert subscription.last_seen == last_seen
    assert subscription.created_at != nil
  end
end
