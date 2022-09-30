# juniorbot

See [Manifold Markets](https://manifold.markets).

This bot is designed to make small but hopefully consistent returns off of
market probabilities at the tails--basically, betting that (e.g.) a market that
is soon to resolve and at 5% is actually more than 95% likely to resolve NO,
and this isn't priced in by the market because users don't want to tie up their
capital.

(Deployed [@JuniorBot](https://manifold.markets/JuniorBot).)

## Setup

Docker recommended. From the cloned repository:

```sh
docker build -t jr .
```

You can also run things the normal way if you like; the requirements are:

* lua (>=5.3)
  * lua-inspect
  * lua-http
  * fennel (>=1.1.0)

## Usage

Docker:

```sh
dr run -e MANIFOLD_API_KEY=your-api-key-here jr
```

Shell:

```sh
cd src && MANIFOLD_API_KEY=your-api-key-here fennel main.fnl
```

## License

MIT licensed. `json.lua` is included in this repository under the MIT license.
