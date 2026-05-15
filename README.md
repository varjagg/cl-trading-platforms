# cl-trading-platforms

Shared Common Lisp trading platform protocol.

This project owns the provider-neutral protocol and provider implementations
that Baryga should agree on:

- a rate-limited `platform` base class backed by `cl-rate-limiter`
- common timeout/rate accessors
- a shared provider error shape
- protocol generics for status, account data, market data, open orders, trades,
  and basic order commands
- `cl-trading-platforms-ibkr`, the Interactive Brokers Client Portal
  implementation
- `cl-trading-platforms-bitstamp`, the Bitstamp HTTP API implementation

Provider systems own concrete HTTP APIs and implement the protocol generics.
Baryga still owns application-level risk policy, strategy runtime,
broker-order journals, and fill reconciliation.

The shared `platform-time` generic is the platform clock. Live providers may
use process monotonic time; simulated providers should return data time. The
Bitstamp simulated platform returns the current CSV row's Unix timestamp so
simulation consumers can stamp events with historical time.

```lisp
(ql:quickload :cl-trading-platforms)

(defclass my-platform (cl-trading-platforms:platform) ())

(defmethod cl-trading-platforms:platform-status ((platform my-platform))
  :ok)
```

Provider systems:

```lisp
(ql:quickload :cl-trading-platforms-ibkr)
(ql:quickload :cl-trading-platforms-bitstamp)

(defparameter *ibkr*
  (ctp-ibkr:make-client-portal :account-id "DU1234567"))

(defparameter *bitstamp*
  (ctp-bitstamp:make-client))
```

Bitstamp also has an offline simulated platform for recorded
CryptoDataDownload CSV files such as
`/Users/eugene/datasets/cryptocurrencies/Bitstamp_BTCUSD_d.csv`:

```lisp
(defparameter *sim*
  (ctp-bitstamp:make-simulated-platform
   :trades-path #P"/Users/eugene/datasets/cryptocurrencies/Bitstamp_BTCUSD_d.csv"
   :balances '(("USD" . 10000d0)
               ("BTC" . 0d0))))

(ctp-bitstamp:platform-status *sim*)     ; ticker-shaped payload at cursor
(ctp-bitstamp:platform-time *sim*)       ; current CSV Unix timestamp
(ctp-bitstamp:history-bars *sim* "btcusd")
(ctp-bitstamp:advance-simulation *sim*)
```

Submitting an order to the simulated Bitstamp platform records an immediate
fill when the order crosses the current CSV row close, updates simple base and
quote balances, and exposes fills through the shared `trades` protocol.
Balances must be seeded; orders that would create a negative balance are
rejected unless `:allow-negative-balances t` is set explicitly.

The expected CSV shape is:

```text
https://www.CryptoDataDownload.com
unix,date,symbol,open,high,low,close,Volume BTC,Volume USD
```

Simpler minute-bar files are also accepted when the simulated platform has a
default market such as `btcusd`; quote volume is derived from `close * volume`:

```text
timestamp,open,high,low,close,volume
```

## License

LGPL-3.0-or-later.
