;;;; tests.lisp

(defpackage #:cl-trading-platform-bitstamp-tests
  (:use #:cl #:cl-trading-platform.bitstamp)
  (:import-from #:rove
                #:deftest
                #:testing
                #:ok))

(in-package #:cl-trading-platform-bitstamp-tests)

(deftest symbol-and-formatting
  (testing "market symbol normalization"
    (ok (string= (market-symbol :btc :usd) "btcusd"))
    (ok (string= (market-symbol "BTC/USD") "btcusd"))
    (ok (string= (market-symbol "eth-usd") "ethusd")))
  (testing "decimal formatting is form-safe"
    (ok (string= (decimal-string 1 :places 8) "1"))
    (ok (string= (decimal-string 1.25d0 :places 8) "1.25"))
    (ok (string= (decimal-string 1/8 :places 8) "0.125"))))

(deftest request-signing-shape
  (testing "private auth headers follow Bitstamp v2 shape"
    (let* ((client (make-client :api-key "key"
                                :api-secret "secret"))
           (body "offset=1")
           (url "https://www.bitstamp.net/api/v2/user_transactions/")
           (headers (cl-trading-platform.bitstamp::authentication-headers
                     client :post url body)))
      (ok (string= (cdr (assoc "X-Auth" headers :test #'string=))
                   "BITSTAMP key"))
      (ok (cdr (assoc "X-Auth-Signature" headers :test #'string=)))
      (ok (= (length (cdr (assoc "X-Auth-Nonce" headers :test #'string=))) 36))
      (ok (string= (cdr (assoc "X-Auth-Version" headers :test #'string=))
                   "v2"))
      (ok (string= (cdr (assoc "Content-Type" headers :test #'string=))
                   "application/x-www-form-urlencoded"))))
  (testing "empty private body omits content type"
    (let* ((client (make-client :api-key "key"
                                :api-secret "secret"))
           (headers (cl-trading-platform.bitstamp::authentication-headers
                     client
                     :post
                     "https://www.bitstamp.net/api/v2/balance/"
                     nil)))
      (ok (not (assoc "Content-Type" headers :test #'string=))))))

(deftest farca-compatible-credentials
  (testing "old three-line credential files still load"
    (uiop:with-temporary-file (:pathname path :stream stream
                               :direction :output)
      (format stream "cid~%key~%secret~%")
      (finish-output stream)
      (let ((client (make-client)))
        (read-credentials client path)
        (ok (string= (customer-id client) "cid"))
        (ok (string= (api-key client) "key"))
        (ok (string= (api-secret client) "secret"))))))
