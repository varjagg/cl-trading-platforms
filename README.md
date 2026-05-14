# cl-trading-platform

Shared Common Lisp trading platform protocol.

This project owns the provider-neutral protocol and provider implementations
that Baryga should agree on:

- a rate-limited `platform` base class backed by `cl-rate-limiter`
- common timeout/rate accessors
- a shared provider error shape
- protocol generics for status, account data, market data, open orders, trades,
  and basic order commands
- `cl-trading-platform-ibkr`, the Interactive Brokers Client Portal
  implementation
- `cl-trading-platform-bitstamp`, the Bitstamp HTTP API implementation

Provider systems own concrete HTTP APIs and implement the protocol generics.
Baryga still owns application-level risk policy, strategy runtime,
broker-order journals, and fill reconciliation.

```lisp
(ql:quickload :cl-trading-platform)

(defclass my-platform (cl-trading-platform:platform) ())

(defmethod cl-trading-platform:platform-status ((platform my-platform))
  :ok)
```

Provider systems:

```lisp
(ql:quickload :cl-trading-platform-ibkr)
(ql:quickload :cl-trading-platform-bitstamp)

(defparameter *ibkr*
  (ctp-ibkr:make-client-portal :account-id "DU1234567"))

(defparameter *bitstamp*
  (ctp-bitstamp:make-client))
```

## License

Proprietary, all rights reserved.
