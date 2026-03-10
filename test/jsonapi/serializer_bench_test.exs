defmodule JSONAPI.SerializerBenchTest do
  use ExUnit.Case, async: false

  @moduletag :bench

  defmodule UserView do
    use JSONAPI.View

    def fields, do: [:username, :first_name, :last_name]
    def type, do: "user"
    def relationships, do: []
  end

  defmodule CommentView do
    use JSONAPI.View

    def fields, do: [:body, :raw_body, :created_at, :updated_at]
    def type, do: "comment"
    def relationships, do: [user: {UserView, :include}]
  end

  defmodule PostView do
    use JSONAPI.View

    def fields, do: [:title, :body, :full_description, :inserted_at, :updated_at]
    def type, do: "mytype"

    def relationships do
      [
        author: {UserView, :include},
        best_comments: {CommentView, :include}
      ]
    end
  end

  setup do
    original_transformation = Application.get_env(:jsonapi, :field_transformation)
    original_cache = Application.get_env(:jsonapi, :cache_field_transformations)

    Application.put_env(:jsonapi, :field_transformation, :camelize)

    on_exit(fn ->
      if original_transformation do
        Application.put_env(:jsonapi, :field_transformation, original_transformation)
      else
        Application.delete_env(:jsonapi, :field_transformation)
      end

      if original_cache do
        Application.put_env(:jsonapi, :cache_field_transformations, original_cache)
      else
        Application.delete_env(:jsonapi, :cache_field_transformations)
      end

      # Clean up ETS table between runs
      try do
        :ets.delete(:jsonapi_field_cache)
      catch
        :error, :badarg -> :ok
      end
    end)

    :ok
  end

  defp build_post(id) do
    %{
      id: id,
      title: "Post #{id}",
      body: "Body text for post #{id}",
      full_description: "Full description of post #{id}",
      inserted_at: ~N[2024-01-15 12:00:00],
      updated_at: ~N[2024-01-16 12:00:00],
      author: %{
        id: id * 100,
        username: "user_#{id}",
        first_name: "First",
        last_name: "Last"
      },
      best_comments: [
        %{
          id: id * 1000 + 1,
          body: "Comment 1",
          raw_body: "<p>Comment 1</p>",
          created_at: ~N[2024-01-15 13:00:00],
          updated_at: ~N[2024-01-15 14:00:00],
          user: %{id: id * 100 + 1, username: "commenter_1", first_name: "C1", last_name: "L1"}
        },
        %{
          id: id * 1000 + 2,
          body: "Comment 2",
          raw_body: "<p>Comment 2</p>",
          created_at: ~N[2024-01-15 15:00:00],
          updated_at: ~N[2024-01-15 16:00:00],
          user: %{id: id * 100 + 2, username: "commenter_2", first_name: "C2", last_name: "L2"}
        }
      ]
    }
  end

  test "benchmark: cached vs uncached field transformations" do
    single_post = build_post(1)
    post_list = Enum.map(1..50, &build_post/1)
    conn = Plug.Conn.fetch_query_params(%Plug.Conn{})

    Benchee.run(
      %{
        "single record (cached)" => fn ->
          Application.put_env(:jsonapi, :cache_field_transformations, true)
          JSONAPI.Serializer.serialize(PostView, single_post, conn)
        end,
        "single record (uncached)" => fn ->
          Application.put_env(:jsonapi, :cache_field_transformations, false)
          JSONAPI.Serializer.serialize(PostView, single_post, conn)
        end,
        "50 records (cached)" => fn ->
          Application.put_env(:jsonapi, :cache_field_transformations, true)
          JSONAPI.Serializer.serialize(PostView, post_list, conn)
        end,
        "50 records (uncached)" => fn ->
          Application.put_env(:jsonapi, :cache_field_transformations, false)
          JSONAPI.Serializer.serialize(PostView, post_list, conn)
        end
      },
      time: 3,
      warmup: 1,
      memory_time: 1,
      print: [configuration: false]
    )
  end
end
