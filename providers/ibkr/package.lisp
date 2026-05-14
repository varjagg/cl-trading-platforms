;;;; package.lisp

(defpackage #:cl-trading-platforms.ibkr
  (:use #:cl)
  (:nicknames #:ctp-ibkr)
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
   #:ibkr-error
   #:ibkr-error-message
   #:ibkr-error-status
   #:ibkr-error-body
   #:ibkr-error-payload

   ;; Client Portal backend
   #:client-portal
   #:make-client-portal
   #:base-url
   #:account-id
   #:verify-ssl
   #:user-agent
   #:request-json

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

   ;; Session and account state
   #:auth-status
   #:tickle
   #:logout
   #:select-account
   #:get-iserver-accounts
   #:get-portfolio-accounts
   #:get-portfolio-subaccounts

   ;; Portfolio
   #:get-positions
   #:get-positions2
   #:get-portfolio-summary
   #:get-ledger

   ;; Contracts and market data
   #:search-contracts
   #:contract-info
   #:market-data-snapshot
   #:market-data-history

   ;; Orders
   #:make-order
   #:place-orders
   #:preview-orders
   #:modify-order
   #:cancel-order
   #:confirm-reply
   #:get-live-orders
   #:get-order-status
   #:get-trades
   #:place-limit-order
   #:buy-limit
   #:sell-limit
   #:place-market-order
   #:buy-market
   #:sell-market))
