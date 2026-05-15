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
   (simulation-cursor
    :accessor simulation-cursor
    :initarg :cursor
    :initform 0
    :documentation "Zero-based index into RECORDED-TRADES used for ticker snapshots.")
   (chronological-p
    :accessor chronological-p
    :initarg :chronological
    :initform t
    :documentation "When true, sort loaded rows from oldest to newest."))
  (:default-initargs :rate 0.001d0))

(defun make-simulated-platform (&rest initargs)
  (apply #'make-instance 'simulated-platform initargs))

(defmethod initialize-instance :after ((client simulated-platform)
                                       &key &allow-other-keys)
  (when (and (trades-path client)
             (null (recorded-trades client)))
    (setf (recorded-trades client)
          (read-recorded-trades-csv (trades-path client)
                                    :chronological (chronological-p client)))))

(defun blank-line-p (line)
  (every (lambda (char)
           (find char '(#\Space #\Tab #\Return #\Newline) :test #'char=))
         line))

(defun csv-header-p (fields)
  (and (member "unix" fields :test #'string-equal)
       (member "date" fields :test #'string-equal)
       (member "symbol" fields :test #'string-equal)))

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
    ((or (null value) (string= value "")) nil)
    ((numberp value) value)
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

(defun normalized-record (row)
  (let* ((unix (csv-number row "unix"))
         (date (csv-value row "date"))
         (symbol (csv-value row "symbol"))
         (open (csv-number row "open"))
         (high (csv-number row "high"))
         (low (csv-number row "low"))
         (close (csv-number row "close"))
         (volume-base (csv-number row "Volume BTC" "volume btc" "volume_base"))
         (volume-quote (csv-number row "Volume USD" "volume usd" "volume_quote")))
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

(defun read-recorded-trades-csv (path &key (chronological t))
  "Read a CryptoDataDownload Bitstamp CSV.

The expected file starts with a source URL line, followed by:

  unix,date,symbol,open,high,low,close,Volume BTC,Volume USD

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
                  (push (normalized-record (csv-fields->row headers fields))
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
    (remove-if-not
     (lambda (record)
       (or (null normalized-market)
           (string= normalized-market (record-market record))))
     (ensure-recorded-trades client))))

(defun clamp-cursor (client records)
  (max 0 (min (simulation-cursor client)
              (max 0 (1- (length records))))))

(defun current-simulation-record (client &optional (market (default-market client)))
  (let ((records (records-for-market client market)))
    (unless records
      (error 'bitstamp-error
             :message (format nil "No recorded Bitstamp rows for ~A." market)))
    (nth (clamp-cursor client records) records)))

(defmethod platform-time ((client simulated-platform))
  "Return the current simulation time as a Unix timestamp in seconds."
  (or (csv-value (current-simulation-record client) "timestamp")
      0))

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
    ("trades_path" . ,(and (trades-path client)
                           (namestring (pathname (trades-path client)))))))

(defmethod portfolio ((client simulated-platform))
  (accounts client))

(defmethod positions ((client simulated-platform) &key page &allow-other-keys)
  (declare (ignore page))
  nil)

(defmethod live-orders ((client simulated-platform)
                        &key filters force market &allow-other-keys)
  (declare (ignore filters force market))
  nil)

(defmethod order-status ((client simulated-platform) id)
  `(("id" . ,(api-string id))
    ("status" . "simulated")))

(defmethod trades ((client simulated-platform))
  (records-for-market client (default-market client)))

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
  (append request
          `(("id" . ,(format nil "SIM-~D" (get-universal-time)))
            ("status" . "simulated"))))
