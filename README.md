# SorinPrimo

Sorin Primo is a Sorin extension that provides the [ExLibris Primo Brief Search API](https://developers.exlibrisgroup.com/primo/apis/docs/primoSearch/R0VUIC9wcmltby92MS9zZWFyY2g=/) as a catalog search endpoint.

Sorin catalog search extensions are responsible for two services:

* Receiving search requests from Sorin's `Search` module, rebuilding them as appropriate for the given catalog's API, and issuing them to the catalog;
* Receiving the catalog's results, parsing them into Elixir maps based on Sorin's `Resource` schema, and returning them to the `Search` module, which returns them to the client.

Sorin Primo encodes all of this functionality in `lib/sorin_primo.ex`.

## Installation

1. Add the following to Sorin's root-level `mix.exs`:

```elixir
def deps do
  [
    ...,
    {:sorin_primo, git: "https://github.com/seulibrary/Sorin-Primo.git"},
  ]
end
```

2. From the root of the application:

```sh
$ mix deps.get && mix deps.compile
```

3. Edit the `search` stanza in `sorin.exs` to point it at `SorinPrimo`:

```elixir
config :search,
  search_target: SorinPrimo
```

4. Add the following stanza to `sorin.exs`, updating keys as necessary:

```elixir
config :sorin_primo,
  api_gateway_url: "https://api-na.hosted.exlibrisgroup.com/primo",
  api_key: "[Your key]",
  inst: "[Your institution code]",
  vid: "[The View ID you want to search]",
  tab: "[The tab you want to search]",
  scope: "[The scope you want to search]",
  catalog_url_root: "[Root of URL at which rscs should be viewed on Primo]",
  lang: "en_US", # Or whatever you need it to be
  newspapers_search: false # Or true, if you prefer
```

## Notes:

* If you have other catalog extensions installed, it is not necessary to remove their configuration stanzas from `sorin.exs`.
* If you are using the _Sorin Search Filter_ extension, it will be necessary to update it to accommodate [Primo's API](https://developers.exlibrisgroup.com/primo/apis/docs/primoSearch/R0VUIC9wcmltby92MS9zZWFyY2g=/). See the README file for _Sorin Search Filter_ for instructions.
* This extension is currently designed for the Primo hosted service, but would probably be straightforward to implement for on-premises.
* If you do not already have one, you will need to get [ExLibris API keys](https://developers.exlibrisgroup.com/primo/apis/).
