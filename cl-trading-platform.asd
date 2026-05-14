;;;; cl-trading-platform.asd

(asdf:defsystem #:cl-trading-platform
  :description "Shared Common Lisp trading platform protocol and rate-limited base class."
  :author "Eugene Zaikonnikov"
  :license "Proprietary, all rights reserved"
  :version "0.1.0"
  :serial t
  :depends-on (#:cl-rate-limiter
               #:bordeaux-threads)
  :components ((:file "package")
               (:file "platform")
               (:file "protocol"))
  :in-order-to ((asdf:test-op (asdf:test-op #:cl-trading-platform/test))))

(asdf:defsystem #:cl-trading-platform/test
  :description "Tests for cl-trading-platform"
  :author "Eugene Zaikonnikov"
  :license "Proprietary, all rights reserved"
  :depends-on (#:cl-trading-platform #:rove)
  :serial t
  :components ((:file "tests"))
  :perform (asdf:test-op (op c)
             (declare (ignore op))
             (uiop:symbol-call :rove '#:run c)))
