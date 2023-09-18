defmodule Geo.JSON.Decoder do
  @moduledoc false

  alias Geo.{
    Point,
    PointZ,
    LineString,
    LineStringZ,
    Polygon,
    MultiPoint,
    MultiLineString,
    MultiLineStringZ,
    MultiPolygon,
    MultiPolygonZ,
    GeometryCollection
  }

  defmodule DecodeError do
    @type t :: %__MODULE__{message: String.t(), value: any}

    defexception [:message, :value]

    def message(%{message: nil, value: value}) do
      "unable to decode value: #{inspect(value)}"
    end

    def message(%{message: message}) do
      message
    end
  end

  @doc """
  Takes a map representing GeoJSON and returns a Geometry.

  Feature objects with null geometries will be stripped from a FeatureCollection,
  and a standalone Feature object with null geometry will be decoded to nil.
  """
  @spec decode!(map()) :: Geo.geometry() | nil
  def decode!(geo_json) do
    cond do
      Map.has_key?(geo_json, "geometries") ->
        crs = Map.get(geo_json, "crs")

        geometries =
          Enum.map(Map.get(geo_json, "geometries"), fn x ->
            do_decode(
              Map.get(x, "type"),
              Map.get(x, "coordinates"),
              Map.get(x, "properties", %{}),
              crs
            )
          end)

        %GeometryCollection{
          geometries: geometries,
          properties: Map.get(geo_json, "properties", %{})
        }

      Map.has_key?(geo_json, "coordinates") ->
        crs = Map.get(geo_json, "crs")

        do_decode(
          Map.get(geo_json, "type"),
          Map.get(geo_json, "coordinates"),
          Map.get(geo_json, "properties", %{}),
          crs
        )

      Map.get(geo_json, "type") == "Feature" ->
        do_decode(
          "Feature",
          Map.get(geo_json, "geometry"),
          Map.get(geo_json, "properties", %{}),
          Map.get(geo_json, "id", "")
        )

      Map.get(geo_json, "type") == "FeatureCollection" ->
        geometries =
          Map.get(geo_json, "features")
          |> Enum.map(fn x ->
            do_decode(
              Map.get(x, "type"),
              Map.get(x, "geometry"),
              Map.get(x, "properties", %{}),
              Map.get(x, "id", "")
            )
          end)
          |> Enum.reject(&is_nil/1)

        %GeometryCollection{
          geometries: geometries,
          properties: %{}
        }

      true ->
        raise DecodeError, value: geo_json
    end
  end

  @doc """
  Takes a map representing GeoJSON and returns a Geometry.
  """
  @spec decode(map()) :: {:ok, Geo.geometry() | nil} | {:error, DecodeError.t()}
  def decode(geo_json) do
    {:ok, decode!(geo_json)}
  rescue
    exception in [DecodeError] ->
      {:error, exception}
  end

  defp do_decode("Point", [x, y, z], properties, crs) do
    %PointZ{coordinates: {x, y, z}, srid: get_srid(crs), properties: properties}
  end

  defp do_decode("Point", [x, y], properties, crs) do
    %Point{coordinates: {x, y}, srid: get_srid(crs), properties: properties}
  end

  defp do_decode("Point", [], properties, crs) do
    %Point{coordinates: nil, srid: get_srid(crs), properties: properties}
  end

  defp do_decode("LineString", coordinates, properties, crs) do
    coordinates = Enum.map(coordinates, &list_to_tuple(&1))

    %LineString{coordinates: coordinates, srid: get_srid(crs), properties: properties}
  end

  defp do_decode("LineStringZ", coordinates, properties, crs) do
    coordinates = Enum.map(coordinates, &List.to_tuple(&1))

    %LineStringZ{coordinates: coordinates, srid: get_srid(crs), properties: properties}
  end

  defp do_decode("Polygon", coordinates, properties, crs) do
    coordinates =
      Enum.map(coordinates, fn sub_coordinates ->
        Enum.map(sub_coordinates, &list_to_tuple(&1))
      end)

    %Polygon{coordinates: coordinates, srid: get_srid(crs), properties: properties}
  end

  defp do_decode("MultiPoint", coordinates, properties, crs) do
    coordinates = Enum.map(coordinates, &list_to_tuple(&1))

    %MultiPoint{coordinates: coordinates, srid: get_srid(crs), properties: properties}
  end

  defp do_decode("MultiLineString", coordinates, properties, crs) do
    coordinates =
      Enum.map(coordinates, fn sub_coordinates ->
        Enum.map(sub_coordinates, &list_to_tuple(&1))
      end)

    %MultiLineString{coordinates: coordinates, srid: get_srid(crs), properties: properties}
  end
  
  defp do_decode("MultiLineStringZ", coordinates, properties, crs) do
    coordinates =
      Enum.map(coordinates, fn sub_coordinates ->
        Enum.map(sub_coordinates, &List.to_tuple(&1))
      end)

    %MultiLineStringZ{coordinates: coordinates, srid: get_srid(crs), properties: properties}
  end

  defp do_decode("MultiPolygon", coordinates, properties, crs) do
    coordinates =
      Enum.map(coordinates, fn sub_coordinates ->
        Enum.map(sub_coordinates, fn third_sub_coordinates ->
          Enum.map(third_sub_coordinates, &list_to_tuple(&1))
        end)
      end)

    %MultiPolygon{coordinates: coordinates, srid: get_srid(crs), properties: properties}
  end

  defp do_decode("MultiPolygonZ", coordinates, properties, crs) do
    coordinates =
      Enum.map(coordinates, fn sub_coordinates ->
        Enum.map(sub_coordinates, fn third_sub_coordinates ->
          Enum.map(third_sub_coordinates, &list_to_tuple(&1))
        end)
      end)

    %MultiPolygonZ{coordinates: coordinates, srid: get_srid(crs), properties: properties}
  end

  defp do_decode("Feature", nil, _properties, _id), do: nil

  defp do_decode("Feature", geometry, properties, _id) do
    do_decode(Map.get(geometry, "type"), Map.get(geometry, "coordinates"), properties, nil)
  end

  defp do_decode(type, [x, y, _z], properties, crs) do
    do_decode(type, [x, y], properties, crs)
  end

  defp do_decode(type, _, _, _) do
    raise DecodeError, message: "#{type} is not a valid type"
  end

  defp list_to_tuple([x, y | _]), do: {x, y}

  defp get_srid(%{"type" => "name", "properties" => %{"name" => "EPSG:" <> srid}}) do
    {srid, _} = Integer.parse(srid)
    srid
  end

  defp get_srid(%{"type" => "name", "properties" => %{"name" => srid}}) do
    srid
  end

  defp get_srid(nil) do
    nil
  end
end
