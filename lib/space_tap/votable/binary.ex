defmodule SpaceTAP.VOTable.Binary do
  @moduledoc false

  # Reads the rows of a BINARY or BINARY2 stream, once decoded from its
  # base64 (VOTable 1.5 §5.3, §5.4, §5.6), as lists of values in the order of
  # the fields. A row is the cells of every field one after another, with
  # nothing between rows, so the stream ends where the last row does.

  alias SpaceTAP.Field
  alias SpaceTAP.VOTable.Value

  @spec rows(binary(), [Field.t()], :binary | :binary2) ::
          {:ok, [[term()]]} | {:error, String.t()}

  # A row without fields takes no bytes, so there would be no end to the
  # rows in the bytes left.
  def rows(<<>>, [], _serialization), do: {:ok, []}
  def rows(_bytes, [], _serialization), do: {:error, "the table has data but no fields"}

  # BINARY has no null flags: its nulls are a NaN or the null value of the
  # field (§5.5). It reads like BINARY2 with every flag unset.
  def rows(bytes, fields, :binary) do
    count = length(fields)
    read_rows(bytes, fields, {:unset, <<0::size(count)>>}, 1, [])
  end

  # §5.4: each row starts with (N+7)/8 bytes of null flags, one bit for each
  # of the N fields, the most significant bit of the first byte for the
  # first field. §5.4 gives the most significant bit of the second byte to
  # "the eighth" field, but by that count it belongs to the ninth.
  def rows(bytes, fields, :binary2),
    do: read_rows(bytes, fields, {:read, div(length(fields) + 7, 8)}, 1, [])

  # Errors name the row, counted from 1, since nothing else in a stream
  # shows where a cell is.
  defp read_rows(<<>>, _fields, _flags, _number, rows), do: {:ok, Enum.reverse(rows)}

  defp read_rows(bytes, fields, flags, number, rows) do
    with {:ok, row_flags, bytes} <- null_flags(bytes, flags, number),
         {:ok, row, rest} <- cells(bytes, fields, row_flags, number, []),
         do: read_rows(rest, fields, flags, number + 1, [row | rows])
  end

  defp null_flags(bytes, {:unset, flags}, _number), do: {:ok, flags, bytes}

  defp null_flags(bytes, {:read, size}, _number) when byte_size(bytes) >= size do
    {flags, rest} = :erlang.split_binary(bytes, size)
    {:ok, flags, rest}
  end

  defp null_flags(_bytes, {:read, _size}, number),
    do: {:error, "row #{number} ends in the middle of its null flags"}

  # The flag bits after the last field are left unread, although §5.4 says
  # they shall be unset: they belong to no cell.
  defp cells(bytes, [], _flags, _number, cells), do: {:ok, Enum.reverse(cells), bytes}

  # A set flag makes the cell null, whatever its bytes hold (§5.4).
  defp cells(bytes, [field | fields], <<1::1, flags::bitstring>>, number, cells) do
    case Value.skip_binary(bytes, field) do
      {:ok, rest} -> cells(rest, fields, flags, number, [nil | cells])
      {:error, message} -> {:error, "row #{number}, " <> message}
    end
  end

  defp cells(bytes, [field | fields], <<0::1, flags::bitstring>>, number, cells) do
    case Value.parse_binary(bytes, field) do
      {:ok, value, rest} -> cells(rest, fields, flags, number, [value | cells])
      {:error, message} -> {:error, "row #{number}, " <> message}
    end
  end
end
