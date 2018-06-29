defmodule Snitch.Seed.Orders do
  @moduledoc false

  import Snitch.Tools.Helper.Order, only: [line_items_with_price: 2]

  alias Ecto.DateTime
  alias Snitch.Data.Schema.{LineItem, Order, ShippingCategory, User, Variant}
  alias Snitch.Repo

  require Logger

  @order %{
    number: nil,
    state: nil,
    user_id: nil,
    billing_address: nil,
    shipping_address: nil,
    adjustment_total: nil,
    promo_total: nil,
    item_total: nil,
    total: nil,
    inserted_at: DateTime.utc(),
    updated_at: DateTime.utc()
  }
  # @stock_items %{
  #   "origin" => %{
  #     counts: [10, 10, 10, 10, 00, 00],
  #     backorder: [:f, :f, :f, :f, :t, :t]
  #   },
  #   "warehouse" => %{
  #     counts: [00, 00, 8, 20, 10, 00],
  #     backorder: [:t, :f, :t, :f, :f, :f]
  #   }
  # }

  defp build_orders do
    variants = Repo.all(Variant)
    [user | _] = Repo.all(User)

    digest = [
      %{quantity: [5, 5, 1, 0, 0, 0, 0], user_id: user.id, state: :cart},
      %{quantity: [0, 0, 0, 0, 0, 100], user_id: user.id, state: :cart},
      %{quantity: [5, 0, 8, 12, 0, 0, 0], user_id: user.id, state: :cart}
    ]

    make_orders(digest, variants)
  end

  def seed_orders! do
    Repo.delete_all(Order)
    {orders, line_items} = build_orders()

    {count, order_structs} =
      Repo.insert_all(
        Order,
        orders,
        on_conflict: :nothing,
        conflict_target: [:number],
        returning: [:id]
      )

    Logger.info("Inserted #{count} orders.")

    line_items =
      order_structs
      |> Stream.zip(line_items)
      |> Enum.map(fn {%{id: id}, items} ->
        Enum.map(items, &Map.put(&1, :order_id, id))
      end)
      |> List.flatten()

    {count, _} = Repo.insert_all(LineItem, line_items)
    Logger.info("Inserted #{count} line-items.")
  end

  def make_orders(digest, variants) do
    digest
    |> Stream.with_index()
    |> Enum.map(fn {manifest, index} ->
      number = "#{Nanoid.generate()}-#{index}"
      line_items = line_items_with_price(variants, manifest.quantity)

      item_total =
        line_items
        |> Stream.map(&Map.fetch!(&1, :total))
        |> Enum.reduce(&Money.add!/2)

      order = %{
        @order
        | number: number,
          state: "#{manifest.state}",
          user_id: manifest[:user_id],
          billing_address: manifest[:address],
          shipping_address: manifest[:address],
          item_total: item_total,
          total: item_total
      }

      {order, line_items}
    end)
    |> Enum.unzip()
  end

  def seed_variants! do
    categories =
      ShippingCategory
      |> Repo.all()
      |> Enum.map(fn x ->
        Enum.take(Stream.repeatedly(fn -> x.id end), 2)
      end)
      |> List.flatten()

    Repo.insert_all(
      Variant,
      Enum.into(variants(categories), []),
      returning: [:id],
      on_conflict: :nothing
    )
  end

  def variants(categories) do
    0
    |> Stream.iterate(&(&1 + 1))
    |> Stream.map(&"shoes-nike-#{&1}")
    |> Stream.zip(categories)
    |> Stream.map(fn {sku, sc_id} ->
      %{random_variant() | sku: sku, shipping_category_id: sc_id}
    end)
  end

  def random_variant do
    price = random_price(9, 19)

    %{
      sku: nil,
      weight: Decimal.new("0.45"),
      height: Decimal.new("0.15"),
      depth: Decimal.new("0.1"),
      width: Decimal.new("0.4"),
      selling_price: price,
      shipping_category_id: nil,
      cost_price: Money.sub!(price, Money.new("1.499", :USD)),
      inserted_at: DateTime.utc(),
      updated_at: DateTime.utc()
    }
  end

  defp random_price(min, delta) do
    Money.new(:USD, "#{:rand.uniform(delta) + min}.99")
  end
end
