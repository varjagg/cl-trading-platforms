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

## License

LGPL-3.0-or-later.
