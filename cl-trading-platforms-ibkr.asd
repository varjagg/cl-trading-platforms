;;;; cl-trading-platforms-ibkr.asd

(asdf:defsystem #:cl-trading-platforms-ibkr
  :description "Interactive Brokers Client Portal implementation for cl-trading-platforms."
  :author "Eugene Zaikonnikov"
  :license "Proprietary, all rights reserved"
  :version "0.1.0"
  :serial t
  :depends-on (#:cl-trading-platforms
               #:alexandria
               #:dexador
               #:quri
               #:yason)
  :components ((:file "providers/ibkr/package")
               (:file "providers/ibkr/client-portal")))
