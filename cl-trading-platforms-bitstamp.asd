;;;; cl-trading-platforms-bitstamp.asd

(asdf:defsystem #:cl-trading-platforms-bitstamp
  :description "Bitstamp implementation for cl-trading-platforms."
  :author "Eugene Zaikonnikov"
  :license "Proprietary, all rights reserved"
  :version "0.1.0"
  :serial t
  :depends-on (#:cl-trading-platforms
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
                 (asdf:test-op #:cl-trading-platforms-bitstamp/test))))

(asdf:defsystem #:cl-trading-platforms-bitstamp/test
  :description "Tests for cl-trading-platforms-bitstamp"
  :author "Eugene Zaikonnikov"
  :license "Proprietary, all rights reserved"
  :depends-on (#:cl-trading-platforms-bitstamp #:rove)
  :serial t
  :components ((:file "providers/bitstamp/tests"))
  :perform (asdf:test-op (op c)
             (declare (ignore op))
             (uiop:symbol-call :rove '#:run c)))
