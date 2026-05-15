;;;; package.lisp

(defpackage #:cl-trading-platforms.bitstamp
  (:use #:cl)
  (:nicknames #:ctp-bitstamp)
  (:import-from #:cl-trading-platforms
                #:platform
                #:rate
                #:rate-limiter
                #:timeout
                #:connect-timeout
                #:read-timeout
                #:platform-time
                #:platform-sleep
                #:with-rate-limit
                #:trading-platform-error
                #:trading-platform-error-message
                #:trading-platform-error-status
                #:trading-platform-error-body
                #:trading-platform-error-payload
                #:platform-status
                #:keepalive
                #:accounts
                #:portfolio
                #:positions
                #:live-orders
                #:order-status
                #:trades
                #:market-snapshot
                #:history-bars
                #:preview-platform-order
                #:submit-platform-order)
  (:export
   ;; Shared platform
   #:platform
   #:rate
   #:rate-limiter
   #:timeout
   #:connect-timeout
   #:read-timeout
   #:platform-time
   #:platform-sleep
   #:with-rate-limit

   ;; Conditions
   #:bitstamp-error
   #:bitstamp-error-message
   #:bitstamp-error-status
   #:bitstamp-error-body
   #:bitstamp-error-payload

   ;; Client
   #:client
   #:make-client
   #:simulated-platform
   #:make-simulated-platform
   #:base-url
   #:api-key
   #:api-secret
   #:customer-id
   #:subaccount-id
   #:verify-ssl
   #:user-agent
   #:default-market
   #:request-json
   #:read-credentials
   #:trades-path
   #:recorded-trades
   #:simulation-cursor
   #:simulated-orders
   #:simulated-trades
   #:simulated-balances
   #:simulated-order-counter
   #:simulated-trade-counter
   #:allow-negative-balances-p
   #:current-simulation-record
   #:advance-simulation
   #:reset-simulation
   #:read-recorded-trades-csv

   ;; Protocol
   #:platform-status
   #:keepalive
   #:accounts
   #:portfolio
   #:positions
   #:live-orders
   #:order-status
   #:trades
   #:market-snapshot
   #:history-bars
   #:preview-platform-order
   #:submit-platform-order

   ;; Symbols and formatting
   #:market-symbol
   #:decimal-string

   ;; Public API
   #:ticker
   #:hourly-ticker
   #:order-book
   #:transactions
   #:get-exchange-rate
   #:get-hourly-ticker
   #:get-order-book
   #:get-transactions

   ;; Private API
   #:account-balance
   #:get-account-balance
   #:user-transactions
   #:open-orders
   #:get-open-orders
   #:order-status
   #:get-order-status
   #:cancel-order
   #:cancel-all-orders
   #:place-limit-order
   #:place-buy-limit-order
   #:place-sell-limit-order
   #:place-market-order
   #:buy-limit
   #:sell-limit
   #:buy-market
   #:sell-market
   #:buy-btc-limit
   #:sell-btc-limit))
