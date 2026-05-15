;;;; simulated.lisp

(in-package #:cl-trading-platforms.bitstamp)

(defclass simulated-platform (client)
  ((trades-path
    :accessor trades-path
    :initarg :trades-path
    :initform nil
    :documentation "Path to a CryptoDataDownload Bitstamp CSV file.")
   (recorded-trades
    :accessor recorded-trades
    :initarg :recorded-trades
    :initform nil
    :documentation "Recorded OHLCV rows, normalized as Bitstamp-like trade records.")
   (recorded-trades-by-market
    :accessor recorded-trades-by-market
    :initform (make-hash-table :test #'equal)
    :documentation "Lazy cache of recorded rows keyed by normalized market.")
   (recorded-trade-vectors-by-market
    :accessor recorded-trade-vectors-by-market
    :initform (make-hash-table :test #'equal)
    :documentation "Lazy vector cache for cursor-based market replay.")
   (simulation-cursor
    :accessor simulation-cursor
    :initarg :cursor
    :initform 0
    :documentation "Zero-based index into RECORDED-TRADES used for ticker snapshots.")
   (chronological-p
    :accessor chronological-p
    :initarg :chronological
    :initform t
    :documentation "When true, sort loaded rows from oldest to newest.")
   (simulated-orders
    :accessor simulated-orders
    :initarg :orders
    :initform nil
    :documentation "Simulated private order ledger.")
   (simulated-trades
    :accessor simulated-trades
    :initarg :trades
    :initform nil
    :documentation "Simulated private fill ledger.")
   (simulated-balances
    :accessor simulated-balances
    :initarg :balances
    :initform (make-hash-table :test #'equal)
    :documentation "Simple simulated asset balances keyed by asset code.")
   (allow-negative-balances-p
    :accessor allow-negative-balances-p
    :initarg :allow-negative-balances
    :initform nil
    :documentation "When true, allow simulated fills to create negative balances.")
   (simulated-order-counter
    :accessor simulated-order-counter
    :initarg :order-counter
    :initform 0)
   (simulated-trade-counter
    :accessor simulated-trade-counter
    :initarg :trade-counter
    :initform 0))
  (:default-initargs :rate 0.001d0))

(defun make-simulated-platform (&rest initargs)
  (apply #'make-instance 'simulated-platform initargs))

(defparameter +known-quote-assets+
  '("USDT" "USDC" "USD" "EUR" "GBP" "BTC" "ETH"))

(defun market-display-symbol (market)
  (let ((normalized (string-upcase (market-symbol market))))
    (or (loop for quote in +known-quote-assets+
              for quote-length = (length quote)
              when (and (> (length normalized) quote-length)
                        (string= quote
                                 normalized
                                 :start2 (- (length normalized)
                                            quote-length)))
                return (format nil "~A/~A"
                               (subseq normalized
                                       0
                                       (- (length normalized) quote-length))
                               quote))
        normalized)))

(defmethod initialize-instance :after ((client simulated-platform)
                                       &key &allow-other-keys)
  (unless (hash-table-p (simulated-balances client))
    (setf (simulated-balances client)
          (make-simulated-balance-table (simulated-balances client))))
  (when (and (trades-path client)
             (null (recorded-trades client)))
    (setf (recorded-trades client)
          (read-recorded-trades-csv (trades-path client)
                                    :chronological (chronological-p client)
                                    :default-symbol
                                    (market-display-symbol
                                     (default-market client)))))
  (unless (hash-table-p (recorded-trades-by-market client))
    (setf (recorded-trades-by-market client)
          (make-hash-table :test #'equal)))
  (unless (hash-table-p (recorded-trade-vectors-by-market client))
    (setf (recorded-trade-vectors-by-market client)
          (make-hash-table :test #'equal))))

(defun blank-line-p (line)
  (every (lambda (char)
           (find char '(#\Space #\Tab #\Return #\Newline) :test #'char=))
         line))

(defun csv-header-p (fields)
  (or (and (member "unix" fields :test #'string-equal)
           (member "date" fields :test #'string-equal)
           (member "symbol" fields :test #'string-equal))
      (and (member "timestamp" fields :test #'string-equal)
           (member "open" fields :test #'string-equal)
           (member "high" fields :test #'string-equal)
           (member "low" fields :test #'string-equal)
           (member "close" fields :test #'string-equal)
           (member "volume" fields :test #'string-equal))))

(defun parse-csv-line (line)
  (let ((fields nil)
        (buffer (make-string-output-stream))
        (quoted nil)
        (index 0)
        (length (length line)))
    (labels ((emit-field ()
               (push (get-output-stream-string buffer) fields)
               (setf buffer (make-string-output-stream))))
      (loop while (< index length)
            for char = (char line index)
            do (cond
                 ((char= char #\")
                  (if (and quoted
                           (< (1+ index) length)
                           (char= (char line (1+ index)) #\"))
                      (progn
                        (write-char #\" buffer)
                        (incf index))
                      (setf quoted (not quoted))))
                 ((and (char= char #\,) (not quoted))
                  (emit-field))
                 (t
                  (write-char char buffer)))
               (incf index))
      (emit-field)
      (nreverse fields))))

(defun parse-csv-number (value)
  (cond
    ((numberp value) value)
    ((or (null value) (string= value "")) nil)
    (t
     (ignore-errors
       (let ((*read-eval* nil))
         (let ((parsed (read-from-string value)))
           (when (numberp parsed) parsed)))))))

(defun csv-value (row &rest keys)
  (loop for key in keys
        for entry = (assoc key row :test #'string-equal)
        when entry return (cdr entry)))

(defun csv-number (row &rest keys)
  (parse-csv-number (apply #'csv-value row keys)))

(defun normalized-record (row &key default-symbol)
  (let* ((unix (csv-number row "unix" "timestamp"))
         (date (csv-value row "date"))
         (symbol (or (csv-value row "symbol") default-symbol))
         (open (csv-number row "open"))
         (high (csv-number row "high"))
         (low (csv-number row "low"))
         (close (csv-number row "close"))
         (volume-base (csv-number row "Volume BTC" "volume btc"
                                  "volume_base" "volume" "amount"))
         (volume-quote (or (csv-number row "Volume USD" "volume usd"
                                       "volume_quote")
                           (and close volume-base (* close volume-base)))))
    `(("unix" . ,unix)
      ("date" . ,date)
      ("symbol" . ,symbol)
      ("open" . ,open)
      ("high" . ,high)
      ("low" . ,low)
      ("close" . ,close)
      ("Volume BTC" . ,volume-base)
      ("Volume USD" . ,volume-quote)
      ("timestamp" . ,unix)
      ("price" . ,close)
      ("last" . ,close)
      ("amount" . ,volume-base)
      ("volume" . ,volume-base)
      ("volume_quote" . ,volume-quote))))

(defun csv-fields->row (headers fields)
  (loop for header in headers
        for field in fields
        collect (cons header field)))

(defun read-recorded-trades-csv (path &key (chronological t)
                                      (default-symbol "BTC/USD"))
  "Read a CryptoDataDownload Bitstamp CSV.

The expected file starts with a source URL line, followed by:

  unix,date,symbol,open,high,low,close,Volume BTC,Volume USD

Minute-bar CSVs with this shape are also supported; their market symbol is
inferred from DEFAULT-SYMBOL:

  timestamp,open,high,low,close,volume

Rows are returned as alists containing those fields plus Bitstamp-like
\"timestamp\", \"price\", \"last\", \"amount\", \"volume\", and
\"volume_quote\" aliases."
  (with-open-file (stream path :direction :input)
    (let ((headers nil)
          (records nil))
      (loop for line = (read-line stream nil nil)
            while line
            for fields = (parse-csv-line line)
            do (cond
                 ((blank-line-p line))
                 ((null headers)
                  (when (csv-header-p fields)
                    (setf headers fields)))
                 (headers
                  (push (normalized-record (csv-fields->row headers fields)
                                           :default-symbol default-symbol)
                        records))))
      (unless headers
        (error 'bitstamp-error
               :message (format nil "Could not find Bitstamp CSV header in ~A."
                                path)))
      (let ((ordered (nreverse records)))
        (if chronological
            (sort ordered #'< :key (lambda (record)
                                    (or (csv-value record "unix") 0)))
            ordered)))))

(defun ensure-recorded-trades (client)
  (or (recorded-trades client)
      (when (trades-path client)
        (setf (recorded-trades client)
              (read-recorded-trades-csv (trades-path client)
                                        :chronological
                                        (chronological-p client))))
      (error 'bitstamp-error
             :message "Simulated Bitstamp platform has no recorded trades.")))

(defun record-market (record)
  (let ((symbol (csv-value record "symbol")))
    (and symbol (market-symbol symbol))))

(defun records-for-market (client market)
  (let ((normalized-market (and market (market-symbol market))))
    (cond
      ((null normalized-market)
       (ensure-recorded-trades client))
      (t
       (or (gethash normalized-market (recorded-trades-by-market client))
           (setf (gethash normalized-market
                          (recorded-trades-by-market client))
                 (remove-if-not
                  (lambda (record)
                    (string= normalized-market (record-market record)))
                  (ensure-recorded-trades client))))))))

(defun records-vector-for-market (client market)
  (let* ((normalized-market (and market (market-symbol market)))
         (cache-key (or normalized-market "")))
    (or (gethash cache-key (recorded-trade-vectors-by-market client))
        (setf (gethash cache-key (recorded-trade-vectors-by-market client))
              (coerce (records-for-market client market) 'vector)))))

(defun clamp-cursor (client records)
  (max 0 (min (simulation-cursor client)
              (max 0 (1- (length records))))))

(defun current-simulation-record (client &optional (market (default-market client)))
  (let ((records (records-vector-for-market client market)))
    (unless (plusp (length records))
      (error 'bitstamp-error
             :message (format nil "No recorded Bitstamp rows for ~A." market)))
    (aref records (clamp-cursor client records))))

(defmethod platform-time ((client simulated-platform))
  "Return the current simulation time as a Unix timestamp in seconds."
  (or (csv-value (current-simulation-record client) "timestamp")
      0))

(defparameter +simulated-balance-epsilon+ 1d-8)

(defun simulation-asset-code (asset)
  (string-upcase (api-string asset)))

(defun make-simulated-balance-table (&optional balances)
  (let ((table (make-hash-table :test #'equal)))
    (etypecase balances
      (null nil)
      (hash-table
       (maphash (lambda (asset amount)
                  (setf (gethash (simulation-asset-code asset) table)
                        (coerce amount 'double-float)))
                balances))
      (list
       (dolist (entry balances)
         (setf (gethash (simulation-asset-code (car entry)) table)
               (coerce (cdr entry) 'double-float)))))
    table))

(defun split-market-symbol (client market)
  (let* ((record (ignore-errors (current-simulation-record client market)))
         (symbol (and record (csv-value record "symbol")))
         (separator (and symbol (position #\/ symbol))))
    (cond (separator
           (values (subseq symbol 0 separator)
                   (subseq symbol (1+ separator))))
          (t
           (let* ((normalized (market-symbol market))
                  (length (length normalized))
                  (quote-start (max 0 (- length 3))))
             (values (subseq normalized 0 quote-start)
                     (subseq normalized quote-start)))))))

(defun simulated-balance (client asset)
  (gethash (simulation-asset-code asset) (simulated-balances client) 0d0))

(defun (setf simulated-balance) (value client asset)
  (setf (gethash (simulation-asset-code asset) (simulated-balances client))
        value))

(defun adjust-simulated-balance (client asset delta)
  (let ((code (simulation-asset-code asset)))
    (setf (gethash code (simulated-balances client))
          (let ((value (+ (gethash code (simulated-balances client) 0d0)
                          (coerce delta 'double-float))))
            (if (<= (abs value) +simulated-balance-epsilon+)
                0d0
                value)))))

(defun balances-alist (client)
  (let ((balances nil))
    (maphash (lambda (asset amount)
               (push (cons asset amount) balances))
             (simulated-balances client))
    (sort balances #'string< :key #'car)))

(defun reset-simulation (client)
  (setf (simulation-cursor client) 0)
  (current-simulation-record client))

(defun advance-simulation (client &optional (steps 1))
  (incf (simulation-cursor client) steps)
  (current-simulation-record client))

(defun simulated-ticker-payload (client market)
  (let* ((record (current-simulation-record client market))
         (volume-base (csv-value record "volume"))
         (volume-quote (csv-value record "volume_quote"))
         (vwap (when (and volume-base volume-quote (plusp volume-base))
                 (/ volume-quote volume-base))))
    `(("timestamp" . ,(csv-value record "timestamp"))
      ("open" . ,(csv-value record "open"))
      ("high" . ,(csv-value record "high"))
      ("low" . ,(csv-value record "low"))
      ("last" . ,(csv-value record "close"))
      ("bid" . ,(csv-value record "close"))
      ("ask" . ,(csv-value record "close"))
      ("volume" . ,volume-base)
      ("vwap" . ,vwap)
      ("symbol" . ,(csv-value record "symbol"))
      ("source" . "recorded-csv"))))

(defun next-simulated-order-id (client)
  (format nil "SIM-ORDER-~D" (incf (simulated-order-counter client))))

(defun next-simulated-trade-id (client)
  (format nil "SIM-FILL-~D" (incf (simulated-trade-counter client))))

(defun simulated-fill-price (client market)
  (csv-value (current-simulation-record client market) "close"))

(defun simulated-fill-p (order-type side limit-price fill-price)
  (cond ((string= order-type "market") t)
        ((null limit-price) nil)
        ((string= side "buy") (>= limit-price fill-price))
        ((string= side "sell") (<= limit-price fill-price))
        (t nil)))

(defun simulated-balance>= (available required)
  (or (>= available required)
      (<= (- required available)
          (max +simulated-balance-epsilon+
               (* +simulated-balance-epsilon+
                  (max 1d0 (abs required)))))))

(defun simulated-balance-sufficient-p (client market side amount price)
  (or (allow-negative-balances-p client)
      (multiple-value-bind (base quote)
          (split-market-symbol client market)
        (cond ((string= side "buy")
               (simulated-balance>= (simulated-balance client quote)
                                    (* amount price)))
              ((string= side "sell")
               (simulated-balance>= (simulated-balance client base)
                                    amount))
              (t nil)))))

(defun apply-simulated-fill (client market side amount price)
  (multiple-value-bind (base quote)
      (split-market-symbol client market)
    (let ((notional (* amount price)))
      (cond
        ((string= side "buy")
         (adjust-simulated-balance client base amount)
         (adjust-simulated-balance client quote (- notional)))
        ((string= side "sell")
         (adjust-simulated-balance client base (- amount))
         (adjust-simulated-balance client quote notional))))))

(defun make-simulated-fill (client order-id client-order-id market side amount price)
  (let ((trade-id (next-simulated-trade-id client))
        (timestamp (platform-time client)))
    `(("id" . ,trade-id)
      ("trade_id" . ,trade-id)
      ("order_id" . ,order-id)
      ("client_order_id" . ,client-order-id)
      ("symbol" . ,(string-upcase (market-symbol market)))
      ("market" . ,(market-symbol market))
      ("side" . ,side)
      ("amount" . ,amount)
      ("quantity" . ,amount)
      ("price" . ,price)
      ("timestamp" . ,timestamp)
      ("source" . "simulated-fill"))))

(defun submit-simulated-order (client request)
  (let* ((market (request-field request "market"))
         (side (request-field request "side"))
         (order-type (request-field request "order_type"))
         (amount (parse-csv-number (request-field request "amount")))
         (limit-price (parse-csv-number (request-field request "price")))
         (client-order-id (request-field request "client_order_id"))
         (order-id (next-simulated-order-id client))
         (fill-price (simulated-fill-price client market))
         (crossed-p (simulated-fill-p order-type side limit-price fill-price))
         (sufficient-balance-p
           (and crossed-p
                (simulated-balance-sufficient-p client
                                                market
                                                side
                                                amount
                                                fill-price)))
         (filled-p (and crossed-p sufficient-balance-p))
         (filled (if filled-p amount 0d0))
         (remaining (- amount filled))
         (status (cond (filled-p "Finished")
                       ((not crossed-p) "Open")
                       (t "Rejected")))
         (fill (when filled-p
                 (make-simulated-fill client
                                      order-id
                                      client-order-id
                                      market
                                      side
                                      amount
                                      fill-price)))
         (order `(("id" . ,order-id)
                  ("order_id" . ,order-id)
                  ("client_order_id" . ,client-order-id)
                  ("market" . ,(market-symbol market))
                  ("symbol" . ,(string-upcase (market-symbol market)))
                  ("side" . ,side)
                  ("order_type" . ,order-type)
                  ("amount" . ,amount)
                  ("quantity" . ,amount)
                  ("price" . ,(or limit-price fill-price))
                  ("status" . ,status)
                  ("filled" . ,filled)
                  ("filled_quantity" . ,filled)
                  ("remaining" . ,remaining)
                  ("remaining_quantity" . ,remaining)
                  ("avg_price" . ,(when filled-p fill-price))
                  ("timestamp" . ,(platform-time client))
                  ("reject_reason" . ,(when (and crossed-p
                                                  (not sufficient-balance-p))
                                         "insufficient_balance"))
                  ("source" . "simulated-order"))))
    (when fill
      (apply-simulated-fill client market side amount fill-price)
      (push fill (simulated-trades client)))
    (push order (simulated-orders client))
    order))

(defmethod ticker ((client simulated-platform) market)
  (simulated-ticker-payload client market))

(defmethod hourly-ticker ((client simulated-platform) market)
  (simulated-ticker-payload client market))

(defmethod order-book ((client simulated-platform) market &key group)
  (declare (ignore group))
  (let* ((record (current-simulation-record client market))
         (price (csv-value record "close"))
         (amount (csv-value record "volume")))
    `(("timestamp" . ,(csv-value record "timestamp"))
      ("bids" . ((,price ,amount)))
      ("asks" . ((,price ,amount)))
      ("source" . "recorded-csv"))))

(defmethod transactions ((client simulated-platform) market &key time)
  (declare (ignore time))
  (records-for-market client market))

(defmethod platform-status ((client simulated-platform))
  (ticker client (default-market client)))

(defmethod accounts ((client simulated-platform) &key portfolio &allow-other-keys)
  (declare (ignore portfolio))
  `(("simulated" . t)
    ("balances" . ,(balances-alist client))
    ("trades_path" . ,(and (trades-path client)
                           (namestring (pathname (trades-path client)))))))

(defmethod portfolio ((client simulated-platform))
  (accounts client))

(defmethod positions ((client simulated-platform) &key page &allow-other-keys)
  (declare (ignore page))
  (balances-alist client))

(defmethod live-orders ((client simulated-platform)
                        &key filters force market &allow-other-keys)
  (declare (ignore filters force))
  (remove-if-not
   (lambda (order)
     (and (string= (cdr (assoc "status" order :test #'string=)) "Open")
          (or (null market)
              (string= (market-symbol market)
                       (cdr (assoc "market" order :test #'string=))))))
   (reverse (simulated-orders client))))

(defmethod order-status ((client simulated-platform) id)
  (let ((lookup (api-string id)))
    (labels ((match-field-p (order key)
               (let ((value (cdr (assoc key order :test #'string=))))
                 (and value (string= lookup value)))))
      (or (find-if
           (lambda (order)
             (or (match-field-p order "id")
                 (match-field-p order "client_order_id")))
           (simulated-orders client))
          `(("id" . ,lookup)
            ("status" . "Unknown"))))))

(defmethod trades ((client simulated-platform))
  (reverse (simulated-trades client)))

(defmethod market-snapshot ((client simulated-platform) symbol
                            &key fields &allow-other-keys)
  (declare (ignore fields))
  (ticker client symbol))

(defmethod history-bars ((client simulated-platform) symbol
                         &key period bar outside-rth exchange
                         &allow-other-keys)
  (declare (ignore period bar outside-rth exchange))
  (records-for-market client symbol))

(defmethod submit-platform-order ((client simulated-platform) request
                                  &key live &allow-other-keys)
  (declare (ignore live))
  (submit-simulated-order client request))
