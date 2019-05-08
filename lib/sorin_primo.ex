defmodule SorinPrimo do

  @doc """
  High-level function for querying Primo's Brief Search API.

  Takes a query string as a string, a search limit as an integer, an offset
  as an integer, and filters as a map.

  Returns a map containing the number of results, and a list of results
  formatted like Sorin Resource structs.

  Queries sorin.exs for certain fields required by Primo's API.

  ## Example

      iex> search("Proust", 2, 0, %{})
      {num_results: 159875, results: [%{}, %{}]}


  """
  def search(search_string, limit, offset, filters) do
    encoded_search_string =
      search_string |> String.trim() |> URI.encode()

    parsed_filters =
      filters
      |> Enum.map(fn {k, v} -> parse_filter(k, v) end)
      |> Enum.filter(& !is_nil(&1))
      |> Enum.join("%7C%2C%7C")

    response =
      "#{Application.get_env(:sorin_primo, :api_gateway_url)}/v1/search?" <>
      "inst=#{Application.get_env(:sorin_primo, :inst)}" <>
      "&vid=#{Application.get_env(:sorin_primo, :vid)}" <>
      "&tab=#{Application.get_env(:sorin_primo, :tab)}" <>
      "&scope=#{Application.get_env(:sorin_primo, :scope)}"<>
      "&q=#{filters["search_by"] || "any"},contains,#{encoded_search_string}" <>
      "&newspapersActive=true" <>
      "&newspapersSearch=#{Application.get_env(:sorin_primo, :newspapers_search)}" <>
      "&apikey=#{Application.get_env(:sorin_primo, :api_key)}" <>
      "&lang=#{Application.get_env(:sorin_primo, :lang)}" <>
      "&pcAvailability=false" <>
      "&offset=#{offset}" <>
      "&limit=#{limit}" <>
      "&qInclude=#{parsed_filters}" <>
    (if filters["sort_by"], do: "&sort=#{filters["sort_by"]}", else: "") <>
      "&blendFacetsSeparately=true"
    |> HTTPoison.get([], [timeout: 15_000, recv_timeout: 15_000])
    |> handle_request()

    num_results =
      response
      |> Map.get("info")
      |> Map.get("total")

    results =
      response
      |> Map.get("docs")
      |> Enum.map(fn(x) -> parse(x) end) # Returns list of maps

    %{num_results: num_results, results: results}
  end

  @doc """
  Maps fields from Primo's Brief Search API results to maps with the same
  fields as a Resource struct.

  """
  def parse(result) do
    #
    # NOTE: "coverage", "relation", "direct_url", and "rights" are mapped to
    #       nil because they are not returned by Primo, but should be returned
    #       to the outer Search module to keep it generic.
    #
    #       "availability_status" and "sublocation" are mapped for display in
    #       search results, but are not part of the Resource schema.
    #
    catalog_url =
      "#{Application.get_env(:sorin_primo, :catalog_url_root)}" <>
      "fulldisplay?docid=#{result["pnx"]["control"]["recordid"]}" <>
      "&context=#{result["context"]}" <>
      "&vid=#{Application.get_env(:sorin_primo, :vid)}" <>
      "&search_scope=#{Application.get_env(:sorin_primo, :scope)}" <>
      "&tab=#{Application.get_env(:sorin_primo, :tab)}" <>
      "&lang=#{Application.get_env(:sorin_primo, :lang)}"

    %{
      "availability_status" => result["delivery"]["bestlocation"]["availabilityStatus"],
      "call_number"         => result["delivery"]["bestlocation"]["callNumber"],
      "catalog_url"         => catalog_url,
      "contributor"         => parse_string(result["pnx"]["display"]["contributor"]),
      "coverage"            => nil,
      "creator"             => parse_string(result["pnx"]["display"]["creator"]),
      "date"                => parse_field(result["pnx"]["addata"]["date"]),
      "description"         => parse_field(result["pnx"]["display"]["description"]),
      "direct_url"          => nil,
      "doi"                 => parse_field(result["pnx"]["addata"]["doi"]),
      "ext_collection"      => parse_field(result["pnx"]["facets"]["collection"]),
      "format"              => parse_field(result["pnx"]["display"]["format"]),
      "identifier"          => parse_field(result["pnx"]["control"]["recordid"]),
      "is_part_of"          => parse_field(result["pnx"]["display"]["ispartof"]),
      "issue"               => parse_field(result["pnx"]["addata"]["issue"]),
      "journal"             => parse_field(result["pnx"]["addata"]["jtitle"]),
      "language"            => parse_field(result["pnx"]["display"]["language"]),
      "page_end"            => parse_field(result["pnx"]["addata"]["epage"]),
      "page_start"          => parse_field(result["pnx"]["addata"]["spage"]),
      "pages"               => parse_field(result["pnx"]["addata"]["pages"]),
      "publisher"           => parse_field(result["pnx"]["addata"]["pub"]),
      "relation"            => nil,
      "rights"              => nil,
      "series"              => parse_field(result["pnx"]["addata"]["seriestitle"]),
      "source"              => "Primo (new Search API)",
      "subject"             => parse_string(result["pnx"]["display"]["subject"]),
      "sublocation"         => result["delivery"]["bestlocation"]["subLocation"],
      "title"               => parse_field(result["pnx"]["display"]["title"]),
      "type"                => parse_field(result["pnx"]["display"]["type"]),
      "volume"              => parse_field(result["pnx"]["addata"]["volume"])
    }
  end

  @doc """
  Helper function for parsing the JSON results of a Primo Brief Search API
  request.

  """
  def handle_request({:ok, %{status_code: 200, body: body}}) do
    Jason.decode!(body)
  end

  @doc """
  Helper function for returning the last value in a specified field.

  """
  def parse_field(field) do
    if(field, do: field |> Enum.at(-1))
  end

  @doc """
  Helper function for selecting, formatting, and returning the first string
  from a specified field.

  """
  def parse_string(field) do
    if field do
      field
      |> List.first()
      |> String.split(";", trim: true)
      |> Enum.map(&String.trim(&1))
    end
  end

  ###################################
  # FILTER PARSING
  ################

  @doc """
  Helper function for parsing filter inputs and returning the API output that will be strung together.

  """
  def parse_filter(key, value) do
    # The Key (which is the base variable in sorin.exs), the value is
    # what's passed in from the form (which might be the variable at
    # the entries level)

    # Determine where the "variable" is located. If it's a "radio"
    # input, it will be top level. If it's not, it will be under
    # the entries.
    custom_api_parameter = if Enum.find_value(Application.get_env(:sorin_search_filter, :filters), fn filter -> filter.variable === key end) do
      Application.get_env(:sorin_search_filter, :filters) |> Enum.find( fn filter -> filter.variable === key end)
      |> Map.fetch!(:entries)
      |> Enum.find(fn entry ->
      # Check to make sure the entry has a variable key
      if Map.has_key?(entry, :variable) do
        entry.variable === value
      else
        # Map of entries returned has either min_variable or Max_variable
        Map.has_key?(entry, :min_variable) || Map.has_key?(entry, :max_variable)
      end
      end)
    else
      Application.get_env(:sorin_search_filter, :filters) |> Enum.find_value( fn filter -> filter.entries |> Enum.find_value( fn entry -> if Map.has_key?(entry, :api_parameter) && entry[:api_parameter] != "" && entry[:variable] === key, do: entry end) end)
    end
    
    # Set this variable because you cannot get inside a comparison
    # "when" set to nil for odd balls like dates.
    api_variable = if custom_api_parameter[:variable], do: custom_api_parameter[:variable], else: nil

    case {key, value} do
      {key, true} when key === api_variable ->
        IO.inspect ("first " <> key)
        custom_api_parameter[:api_parameter]
      {key, value} when key === api_variable and value != "" ->
        IO.inspect ("second")
        custom_api_parameter[:api_parameter] |> String.replace("$VALUE", value)
      {"publish_date", dates} ->
      # If the default values are passed in, do not apply the filter
      if dates[custom_api_parameter[:min_variable]] === custom_api_parameter[:min_value] and dates[custom_api_parameter[:max_variable]] === custom_api_parameter[:max_value] do
        nil
      else
        "facet_searchcreationdate,include," <>
          "%5B#{dates[custom_api_parameter[:min_variable]]}" <>
          "%20TO%20#{dates[custom_api_parameter[:max_variable]]}%5D"
      end
      {_, _} -> nil
    end
  end
  
end