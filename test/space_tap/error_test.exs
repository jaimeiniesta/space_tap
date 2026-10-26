defmodule SpaceTAP.ErrorTest do
  use ExUnit.Case, async: true

  alias SpaceTAP.Error

  doctest Error

  describe "message/1" do
    test "starts with the HTTP status when there was a response" do
      error = %Error{type: :service_error, message: "Unknown table", status: 400}

      assert Exception.message(error) == "(HTTP 400) Unknown table"
    end

    test "is the message alone when there was no response" do
      error = %Error{type: :transport_error, message: "connection refused", status: nil}

      assert Exception.message(error) == "connection refused"
    end
  end

  test "is raised with the HTTP status in its message" do
    error = %Error{type: :http_error, message: "Bad Gateway", status: 502}

    assert_raise Error, "(HTTP 502) Bad Gateway", fn -> raise error end
  end
end
