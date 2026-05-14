;;;; package.lisp

(defpackage #:cl-trading-platform
  (:use #:cl)
  (:export
   ;; Base class and rate limiting
   #:platform
   #:rate
   #:rate-limiter
   #:timeout
   #:connect-timeout
   #:read-timeout
   #:platform-time
   #:platform-sleep
   #:make-platform-rate-limiter
   #:call-with-rate-limit
   #:with-rate-limit

   ;; Shared provider error shape
   #:trading-platform-error
   #:trading-platform-error-message
   #:trading-platform-error-status
   #:trading-platform-error-body
   #:trading-platform-error-payload

   ;; Provider-neutral platform protocol
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
   #:buy-limit
   #:sell-limit
   #:buy-market
   #:sell-market))
