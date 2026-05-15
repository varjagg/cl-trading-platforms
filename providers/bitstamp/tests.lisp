;;;; tests.lisp

(defpackage #:cl-trading-platforms-bitstamp-tests
  (:use #:cl #:cl-trading-platforms.bitstamp)
  (:import-from #:rove
                #:deftest
                #:testing
                #:ok))

(in-package #:cl-trading-platforms-bitstamp-tests)

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
           (headers (cl-trading-platforms.bitstamp::authentication-headers
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
           (headers (cl-trading-platforms.bitstamp::authentication-headers
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

(defun write-recorded-trades-csv (stream)
  (format stream "https://www.CryptoDataDownload.com~%")
  (format stream "unix,date,symbol,open,high,low,close,Volume BTC,Volume USD~%")
  (format stream "20,1970-01-01 00:00:20,BTC/USD,110,120,100,115,2,230~%")
  (format stream "10,1970-01-01 00:00:10,BTC/USD,100,110,90,105,3,315~%")
  (format stream "30,1970-01-01 00:00:30,ETH/USD,10,12,9,11,5,55~%"))

(deftest simulated-bitstamp-platform
  (testing "recorded trades CSV is loaded in chronological order"
    (uiop:with-temporary-file (:pathname path :stream stream
                               :direction :output)
      (write-recorded-trades-csv stream)
      (finish-output stream)
      (let* ((client (make-simulated-platform :trades-path path))
             (records (trades client)))
        (ok (= (length records) 2))
        (ok (= (cdr (assoc "unix" (first records) :test #'string=)) 10))
        (ok (= (cdr (assoc "close" (first records) :test #'string=)) 105)))))
  (testing "ticker and market snapshot come from the simulation cursor"
    (uiop:with-temporary-file (:pathname path :stream stream
                               :direction :output)
      (write-recorded-trades-csv stream)
      (finish-output stream)
      (let* ((client (make-simulated-platform :trades-path path))
             (ticker (platform-status client)))
        (ok (= (platform-time client) 10))
        (ok (= (cdr (assoc "last" ticker :test #'string=)) 105))
        (advance-simulation client)
        (ok (= (platform-time client) 20))
        (let ((snapshot (market-snapshot client "btcusd")))
          (ok (= (cdr (assoc "last" snapshot :test #'string=)) 115))
          (ok (string= (cdr (assoc "source" snapshot :test #'string=))
                       "recorded-csv"))))))
  (testing "history bars can be filtered by market"
    (uiop:with-temporary-file (:pathname path :stream stream
                               :direction :output)
      (write-recorded-trades-csv stream)
      (finish-output stream)
      (let ((client (make-simulated-platform :trades-path path)))
        (ok (= (length (history-bars client "btcusd")) 2))
        (ok (= (length (history-bars client "ethusd")) 1))))))
