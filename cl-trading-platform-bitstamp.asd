;;;; cl-trading-platform-bitstamp.asd

(asdf:defsystem #:cl-trading-platform-bitstamp
  :description "Bitstamp implementation for cl-trading-platform."
  :author "Eugene Zaikonnikov"
  :license "Proprietary, all rights reserved"
  :version "0.1.0"
  :serial t
  :depends-on (#:cl-trading-platform
               #:alexandria
               #:babel
               #:bordeaux-threads
               #:dexador
               #:ironclad
               #:quri
               #:yason)
  :components ((:file "providers/bitstamp/package")
               (:file "providers/bitstamp/client"))
  :in-order-to ((asdf:test-op
                 (asdf:test-op #:cl-trading-platform-bitstamp/test))))

(asdf:defsystem #:cl-trading-platform-bitstamp/test
  :description "Tests for cl-trading-platform-bitstamp"
  :author "Eugene Zaikonnikov"
  :license "Proprietary, all rights reserved"
  :depends-on (#:cl-trading-platform-bitstamp #:rove)
  :serial t
  :components ((:file "providers/bitstamp/tests"))
  :perform (asdf:test-op (op c)
             (declare (ignore op))
             (uiop:symbol-call :rove '#:run c)))
