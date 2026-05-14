;;;; cl-trading-platform-ibkr.asd

(asdf:defsystem #:cl-trading-platform-ibkr
  :description "Interactive Brokers Client Portal implementation for cl-trading-platform."
  :author "Eugene Zaikonnikov"
  :license "Proprietary, all rights reserved"
  :version "0.1.0"
  :serial t
  :depends-on (#:cl-trading-platform
               #:alexandria
               #:dexador
               #:quri
               #:yason)
  :components ((:file "providers/ibkr/package")
               (:file "providers/ibkr/client-portal")))
