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

(defun write-minute-bars-csv (stream)
  (format stream "timestamp,open,high,low,close,volume~%")
  (format stream "20,110,120,100,115,2~%")
  (format stream "10,100,110,90,105,3~%"))

(deftest simulated-bitstamp-platform
  (testing "recorded trades CSV is loaded in chronological order"
    (uiop:with-temporary-file (:pathname path :stream stream
                               :direction :output)
      (write-recorded-trades-csv stream)
      (finish-output stream)
      (let* ((client (make-simulated-platform :trades-path path))
             (records (history-bars client "btcusd")))
        (ok (= (length records) 2))
        (ok (= (cdr (assoc "unix" (first records) :test #'string=)) 10))
        (ok (= (cdr (assoc "close" (first records) :test #'string=)) 105)))))
  (testing "minute bar CSV is loaded with inferred market"
    (uiop:with-temporary-file (:pathname path :stream stream
                               :direction :output)
      (write-minute-bars-csv stream)
      (finish-output stream)
      (let* ((client (make-simulated-platform
                      :trades-path path
                      :default-market "btcusd"))
             (records (history-bars client "btcusd"))
             (first (first records)))
        (ok (= (length records) 2))
        (ok (= (cdr (assoc "unix" first :test #'string=)) 10))
        (ok (string= (cdr (assoc "symbol" first :test #'string=))
                     "BTC/USD"))
        (ok (= (cdr (assoc "close" first :test #'string=)) 105))
        (ok (= (cdr (assoc "Volume BTC" first :test #'string=)) 3))
        (ok (= (cdr (assoc "Volume USD" first :test #'string=)) 315)))))
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
        (ok (= (length (history-bars client "ethusd")) 1)))))
  (testing "simulated order submission records fills and balances"
    (uiop:with-temporary-file (:pathname path :stream stream
                               :direction :output)
      (write-recorded-trades-csv stream)
      (finish-output stream)
      (let* ((client (make-simulated-platform
                      :trades-path path
                      :balances '(("USD" . 100d0))))
             (result (submit-platform-order
                      client
                      '(("market" . "btcusd")
                        ("side" . "buy")
                        ("order_type" . "limit")
                        ("amount" . 0.5d0)
                        ("price" . 105)
                        ("client_order_id" . "C1"))))
             (fill (first (trades client)))
             (positions (positions client)))
        (ok (string= (cdr (assoc "status" result :test #'string=))
                     "Finished"))
        (ok (= (cdr (assoc "filled" result :test #'string=)) 0.5d0))
        (ok (string= (cdr (assoc "client_order_id" fill :test #'string=))
                     "C1"))
        (ok (= (cdr (assoc "amount" fill :test #'string=)) 0.5d0))
        (ok (= (cdr (assoc "BTC" positions :test #'string=)) 0.5d0))
        (ok (= (cdr (assoc "USD" positions :test #'string=)) 47.5d0)))))
  (testing "simulated all-in orders tolerate floating point dust"
    (uiop:with-temporary-file (:pathname path :stream stream
                               :direction :output)
      (write-recorded-trades-csv stream)
      (finish-output stream)
      (let* ((client (make-simulated-platform
                      :trades-path path
                      :balances '(("USD" . 100d0))))
             (amount (+ (/ 100d0 105d0) 1d-12))
             (result (submit-platform-order
                      client
                      `(("market" . "btcusd")
                        ("side" . "buy")
                        ("order_type" . "limit")
                        ("amount" . ,amount)
                        ("price" . 105)
                        ("client_order_id" . "C1"))))
             (positions (positions client)))
        (ok (string= (cdr (assoc "status" result :test #'string=))
                     "Finished"))
        (ok (< (abs (cdr (assoc "USD" positions :test #'string=))) 1d-9)))))
  (testing "simulated order submission rejects insufficient balances"
    (uiop:with-temporary-file (:pathname path :stream stream
                               :direction :output)
      (write-recorded-trades-csv stream)
      (finish-output stream)
      (let* ((client (make-simulated-platform :trades-path path))
             (result (submit-platform-order
                      client
                      '(("market" . "btcusd")
                        ("side" . "buy")
                        ("order_type" . "limit")
                        ("amount" . 0.5d0)
                        ("price" . 105)
                        ("client_order_id" . "C1")))))
        (ok (string= (cdr (assoc "status" result :test #'string=))
                     "Rejected"))
        (ok (string= (cdr (assoc "reject_reason" result :test #'string=))
                     "insufficient_balance"))
        (ok (= (length (trades client)) 0))))))
