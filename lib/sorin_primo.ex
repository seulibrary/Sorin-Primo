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
      search_string |> String.trim() |> URI.encode_www_form()

    parsed_filters =
      filters
      |> Enum.map(fn {k, v} -> parse_filter(k, v) end)
      |> Enum.filter(& !is_nil(&1))
      |> Enum.filter(fn x -> x != "" end)
      |> Enum.join("%7C%2C%7C")

    response =
      "#{Application.get_env(:sorin_primo, :primo_url)}/v1/search?" <>
      "inst=#{Application.get_env(:sorin_primo, :inst)}" <>
      "&vid=#{Application.get_env(:sorin_primo, :vid)}" <>
      "&tab=#{Application.get_env(:sorin_primo, :tab)}" <>
      "&scope=#{Application.get_env(:sorin_primo, :scope)}"<>
      "&q=#{filters["search_by"] || "any"},contains,#{encoded_search_string}" <>
      "&apikey=#{Application.get_env(:sorin_primo, :api_key)}" <>
    (if (filters["item_type"] == "newspapers"), do:
      "&newspapersActive=true&newspapersSearch=true",
	else: "&newspapersActive=true&newspapersSearch=false" ) <>
      "&lang=#{Application.get_env(:sorin_primo, :lang)}" <>
      "&pcAvailability=false" <>
      "&offset=#{offset}" <>
      "&limit=#{limit}" <>
      "&qInclude=#{parsed_filters}" <>
    (if filters["sort_by"], do: "&sort=#{filters["sort_by"]}", else: "") <>
      "&blendFacetsSeparately=true"
    |> HTTPoison.get([], timeout: 15_000, recv_timeout: 15_000)
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

  defp parse(result) do
    # If the result is either not a newspaper article or is one and
    # has the right unique ID field for newspapers populated, passes
    # the result to build_resource/1. Otherwise returns an empty map.
    resource_type = result["pnx"]["display"]["type"] |> Enum.at(-1)
    has_newspaper_id = result["pnx"]["control"]["addsrcrecordid"]
    cond do
      (resource_type != "newspaper_article") || has_newspaper_id ->
	build_resource_map(result)
      true -> %{}
    end
  end

  defp build_resource_map(result) do
    # Extracts fields from Primo's Brief Search API results and uses them
    # to construct a map formatted for rendering as a Core.Resources.Resource.
    #
    # NOTES:
    #
    # - "coverage", "relation", "direct_url", and "rights" are mapped to nil
    #   because although they are not returned by Primo, they should still be
    #   returned in order to keep the outer Search module generic across
    #   catalogs.
    #
    # - "availability_status" and "sublocation" are returned for display in
    #   search results for the convenience of end users, but are not part of
    #   the Resource schema.
    #
    # - "identifier" and "catalog_url" have to be populated differently for
    #   newspaper articles and all other resources.
    #
    identifier =
      case parse_field(result["pnx"]["display"]["type"]) do
	"newspaper_article" ->
	  "BM_" <> parse_field(result["pnx"]["control"]["addsrcrecordid"])
	_ -> parse_field(result["pnx"]["control"]["recordid"])
      end

    full_display =
      case parse_field(result["pnx"]["display"]["type"]) do
	"newspaper_article" ->
	  "npfulldisplay?docid=#{identifier}"
	_ -> "fulldisplay?docid=#{identifier}"
      end

    catalog_url =
      "#{Application.get_env(:sorin_primo, :catalog_url_root)}" <>
      full_display <>
      "&context=#{result["context"]}" <>
      "&vid=#{Application.get_env(:sorin_primo, :vid)}" <>
      "&lang=#{Application.get_env(:sorin_primo, :lang)}"

    %{
      "availability_status" => result["delivery"]["bestlocation"]["availabilityStatus"],
      "call_number"         => result["delivery"]["bestlocation"]["callNumber"],
      "catalog_url"         => catalog_url,
      "contributor"         => result["pnx"]["addata"]["addau"],
      "coverage"            => nil,
      "creator"             => result["pnx"]["addata"]["au"],
      "date"                => parse_field(result["pnx"]["addata"]["date"]),
      "description"         => parse_field(result["pnx"]["display"]["description"]),
      "direct_url"          => nil,
      "doi"                 => parse_field(result["pnx"]["addata"]["doi"]),
      "ext_collection"      => parse_field(result["pnx"]["facets"]["collection"]),
      "format"              => parse_field(result["pnx"]["display"]["format"]),
      "identifier"          => identifier,
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
      "subject"             => result["pnx"]["display"]["subject"],
      "sublocation"         => result["delivery"]["bestlocation"]["subLocation"],
      "title"               => parse_field(result["pnx"]["display"]["title"]),
      "type"                => parse_field(result["pnx"]["display"]["type"]),
      "volume"              => parse_field(result["pnx"]["addata"]["volume"])
    }
  end

  defp handle_request({:ok, %{status_code: 200, body: body}}) do
    Jason.decode!(body)
  end

  defp parse_field(field) do
    # Primo returns most of its values wrapped up in a list; this
    # function extracts the value we want from the list.
    if(field, do: field |> Enum.at(-1))
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
      {key, "true"} when key === api_variable ->
        custom_api_parameter[:api_parameter]
      {key, value} when key === "item_type" and value != "newspapers" -> 
        custom_api_parameter[:api_parameter] |> String.replace("$VALUE", value)
      {key, value} when key === api_variable and value != "" and value != "false" ->
        # "false" values do not mean "do not include", false is just the reverse of true, 
        # and is what the FE sends. This might have to be re-visited in the future depending
        # on other filter functionality
        custom_api_parameter[:api_parameter] |> String.replace("$VALUE", value)
      {"publish_date", dates} ->
        # If the default values are passed in, do not apply the filter
        parsed_dates = String.split(dates, ",")
        
        if String.to_integer(List.first(parsed_dates)) === custom_api_parameter[:min_value] and String.to_integer(List.last(parsed_dates)) === custom_api_parameter[:max_value] do
          nil
        else
          "facet_searchcreationdate,include," <>
          "%5B#{List.first(parsed_dates)}" <>
          "%20TO%20#{List.last(parsed_dates)}%5D"
        end
      {_, _} -> nil
    end
  end
  
end
