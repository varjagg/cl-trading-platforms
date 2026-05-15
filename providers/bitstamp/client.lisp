;;;; client.lisp

(in-package #:cl-trading-platforms.bitstamp)

(alexandria:define-constant +bitstamp-base-url+
    "https://www.bitstamp.net"
  :test #'string=)

(alexandria:define-constant +auth-version+ "v2" :test #'string=)
(alexandria:define-constant +form-content-type+
    "application/x-www-form-urlencoded"
  :test #'string=)

(alexandria:define-constant +universal-to-unix-epoch+ 2208988800
  :test #'=)

(define-condition bitstamp-error (trading-platform-error) ())

(defun bitstamp-error-message (condition)
  (trading-platform-error-message condition))

(defun bitstamp-error-status (condition)
  (trading-platform-error-status condition))

(defun bitstamp-error-body (condition)
  (trading-platform-error-body condition))

(defun bitstamp-error-payload (condition)
  (trading-platform-error-payload condition))

(defclass client (platform)
  ((base-url
    :accessor base-url
    :initarg :base-url
    :initform +bitstamp-base-url+)
   (api-key
    :accessor api-key
    :initarg :api-key
    :initform nil)
   (api-secret
    :accessor api-secret
    :initarg :api-secret
    :initform nil)
   (customer-id
    :accessor customer-id
    :initarg :customer-id
    :initform nil
    :documentation "Kept for compatibility with old Farca credential files; Bitstamp v2 header auth does not use it.")
   (subaccount-id
    :accessor subaccount-id
    :initarg :subaccount-id
    :initform nil)
   (verify-ssl
    :accessor verify-ssl
    :initarg :verify-ssl
    :initform t)
   (default-market
    :accessor default-market
    :initarg :default-market
    :initform "btcusd")
   (user-agent
    :accessor user-agent
    :initarg :user-agent
    :initform "cl-trading-platforms-bitstamp/0.1"))
  (:default-initargs :rate 1/3))

(defvar *nonce-counter* 0)
(defvar *nonce-lock* (bt:make-lock "Bitstamp nonce lock"))

(defun make-client (&rest initargs)
  (apply #'make-instance 'client initargs))

(defun trim-trailing-slashes (string)
  (string-right-trim "/" string))

(defun ensure-leading-slash (string)
  (if (and (plusp (length string))
           (char= (char string 0) #\/))
      string
      (concatenate 'string "/" string)))

(defun api-name (value)
  (etypecase value
    (string value)
    (keyword (string-downcase (substitute #\_ #\- (symbol-name value))))
    (symbol (string-downcase (substitute #\_ #\- (symbol-name value))))))

(defun trim-decimal-zeroes (string)
  (let ((dot (position #\. string :from-end t)))
    (if dot
        (let ((trimmed (string-right-trim "0" string)))
          (cond ((string= trimmed "") "0")
                ((char= (char trimmed (1- (length trimmed))) #\.)
                 (subseq trimmed 0 (1- (length trimmed))))
                (t trimmed)))
        string)))

(defun decimal-string (value &key (places 8))
  (etypecase value
    (string value)
    (integer (write-to-string value))
    (number
     (trim-decimal-zeroes
      (format nil (format nil "~~,~DF" places)
              (coerce value 'double-float))))))

(defun api-string (value)
  (typecase value
    (null nil)
    (string value)
    (keyword (string-downcase (symbol-name value)))
    (symbol (string-downcase (symbol-name value)))
    (number (decimal-string value))
    (t (princ-to-string value))))

(defun normalize-params (params)
  (loop for (key . value) in params
        when value
          collect (cons (api-name key) (api-string value))))

(defun endpoint-url (client endpoint &optional params)
  (let* ((path (ensure-leading-slash endpoint))
         (url (concatenate 'string
                           (trim-trailing-slashes (base-url client))
                           path))
         (query (normalize-params params)))
    (if query
        (concatenate 'string url "?" (quri:url-encode-params query))
        url)))

(defun json-ref (object key &optional default)
  (cond
    ((hash-table-p object)
     (multiple-value-bind (value present-p) (gethash key object)
       (if present-p value default)))
    ((and (listp object) (every #'consp object))
     (let ((entry (assoc key object :test #'string=)))
       (if entry (cdr entry) default)))
    (t default)))

(defun parse-json-response (body)
  (cond
    ((and (stringp body)
          (plusp (length (string-trim '(#\Space #\Tab #\Newline #\Return)
                                      body))))
     (yason:parse body))
    ((stringp body) nil)
    (t body)))

(defun compact-market-symbol (value)
  (remove-if (lambda (char)
               (find char "/_- " :test #'char=))
             (string-downcase (api-string value))))

(defun market-symbol (base &optional quote)
  (if quote
      (concatenate 'string
                   (compact-market-symbol base)
                   (compact-market-symbol quote))
      (compact-market-symbol base)))

(defun market-endpoint (name market)
  (format nil "/api/v2/~A/~A/" name (market-symbol market)))

(defun request-body (content)
  (cond ((null content) nil)
        ((stringp content) content)
        ((listp content) (quri:url-encode-params (normalize-params content)))
        (t (error 'bitstamp-error
                  :message (format nil "Unsupported request body: ~S" content)))))

(defun unix-timestamp-millis ()
  (write-to-string (* 1000 (- (get-universal-time)
                              +universal-to-unix-epoch+))))

(defun random-hex (limit)
  (random limit))

(defun make-nonce ()
  (bt:with-lock-held (*nonce-lock*)
    (string-downcase
     (format nil "~8,'0X-~4,'0X-~4,'0X-~4,'0X-~4,'0X~8,'0X"
             (mod (- (get-universal-time) +universal-to-unix-epoch+)
                  #x100000000)
             (mod (incf *nonce-counter*) #x10000)
             (random-hex #x10000)
             (random-hex #x10000)
             (random-hex #x10000)
             (random-hex #x100000000)))))

(defun utf8-octets (string)
  (babel:string-to-octets string :encoding :utf-8))

(defun hmac-sha256-hex (secret text)
  (let ((hmac (ironclad:make-hmac (utf8-octets secret) :sha256)))
    (ironclad:update-hmac hmac (utf8-octets text))
    (string-downcase
     (ironclad:byte-array-to-hex-string (ironclad:hmac-digest hmac)))))

(defun uri-host-for-signature (uri)
  (let ((host (quri:uri-host uri))
        (port (quri:uri-port uri))
        (scheme (quri:uri-scheme uri)))
    (if (and port
             (not (or (and (string= scheme "https") (= port 443))
                      (and (string= scheme "http") (= port 80)))))
        (format nil "~A:~D" host port)
        host)))

(defun signing-message (client method url content-type nonce timestamp body)
  (let* ((uri (quri:uri url))
         (query (or (quri:uri-query uri) ""))
         (path (or (quri:uri-path uri) "/")))
    (concatenate 'string
                 "BITSTAMP " (api-key client)
                 (string-upcase (api-string method))
                 (uri-host-for-signature uri)
                 path
                 query
                 (or content-type "")
                 nonce
                 timestamp
                 +auth-version+
                 (or body ""))))

(defun ensure-credentials (client)
  (unless (and (api-key client) (api-secret client))
    (error 'bitstamp-error
           :message "Bitstamp API key and secret are required for this endpoint."))
  client)

(defun authentication-headers (client method url body)
  (ensure-credentials client)
  (let* ((nonce (make-nonce))
         (timestamp (unix-timestamp-millis))
         (content-type (when body +form-content-type+))
         (message (signing-message client method url content-type
                                   nonce timestamp body))
         (signature (hmac-sha256-hex (api-secret client) message)))
    (append `(("X-Auth" . ,(concatenate 'string "BITSTAMP " (api-key client)))
              ("X-Auth-Signature" . ,signature)
              ("X-Auth-Nonce" . ,nonce)
              ("X-Auth-Timestamp" . ,timestamp)
              ("X-Auth-Version" . ,+auth-version+))
            (when (subaccount-id client)
              `(("X-Auth-Subaccount-Id" . ,(subaccount-id client))))
            (when content-type
              `(("Content-Type" . ,content-type))))))

(defun request-headers (client body headers &key include-content-type)
  (append `(("Accept" . "application/json")
            ("User-Agent" . ,(user-agent client)))
          (when (and body include-content-type)
            `(("Content-Type" . ,+form-content-type+)))
          headers))

(defun request-json (client method endpoint &key params content headers authenticated)
  (let* ((body (request-body content))
         (url (endpoint-url client endpoint params))
         (auth-headers (when authenticated
                         (authentication-headers client method url body))))
    (handler-case
        (multiple-value-bind (response status response-headers final-url)
            (with-rate-limit (client)
              (dexador:request url
                               :method method
                               :headers (request-headers
                                         client
                                         body
                                         (append auth-headers headers)
                                         :include-content-type
                                         (and body (not authenticated)))
                               :content body
                               :connect-timeout (connect-timeout client)
                               :read-timeout (read-timeout client)
                               :insecure (not (verify-ssl client))))
          (values (parse-json-response response)
                  status
                  response-headers
                  final-url))
      (dexador.error:http-request-failed (error)
        (let* ((error-body (dexador.error:response-body error))
               (payload (ignore-errors (parse-json-response error-body))))
          (error 'bitstamp-error
                 :message "Bitstamp HTTP request failed"
                 :status (dexador.error:response-status error)
                 :body error-body
                 :payload payload))))))

(defun read-credentials (client path)
  "Read an old Farca three-line credentials file or a two-line key/secret file."
  (with-open-file (stream path :direction :input)
    (let ((first (read-line stream nil nil))
          (second (read-line stream nil nil))
          (third (read-line stream nil nil)))
      (cond (third
             (setf (customer-id client) first
                   (api-key client) second
                   (api-secret client) third))
            (second
             (setf (api-key client) first
                   (api-secret client) second))
            (t
             (error 'bitstamp-error
                    :message "Credentials file must contain api-key/api-secret or customer-id/api-key/api-secret.")))))
  client)

;;; Public endpoints

(defgeneric ticker (client market))

(defmethod ticker ((client client) market)
  (request-json client :get (market-endpoint "ticker" market)))

(defgeneric hourly-ticker (client market))

(defmethod hourly-ticker ((client client) market)
  (request-json client :get (market-endpoint "ticker_hour" market)))

(defgeneric order-book (client market &key group))

(defmethod order-book ((client client) market &key group)
  (request-json client :get (market-endpoint "order_book" market)
                :params `(("group" . ,group))))

(defgeneric transactions (client market &key time))

(defmethod transactions ((client client) market &key (time "hour"))
  (request-json client :get (market-endpoint "transactions" market)
                :params `(("time" . ,time))))

(defun get-exchange-rate (client from to)
  (ticker client (market-symbol from to)))

(defun get-hourly-ticker (client from to)
  (hourly-ticker client (market-symbol from to)))

(defun get-order-book (client from to)
  (order-book client (market-symbol from to)))

(defun get-transactions (client from to &optional (period "hour"))
  (transactions client (market-symbol from to) :time period))

;;; Private endpoints

(defun private-post (client endpoint &optional content)
  (request-json client :post endpoint
                :content content
                :authenticated t))

(defun account-balance (client)
  (private-post client "/api/v2/balance/"))

(defun get-account-balance (client)
  (account-balance client))

(defun user-transactions (client &key offset limit sort)
  (private-post client "/api/v2/user_transactions/"
                `(("offset" . ,offset)
                  ("limit" . ,limit)
                  ("sort" . ,sort))))

(defun open-orders (client &key market)
  (if market
      (private-post client
                    (format nil "/api/v2/open_orders/~A/"
                            (market-symbol market)))
      (private-post client "/api/v2/open_orders/all/")))

(defun get-open-orders (client)
  (open-orders client))

(defmethod order-status ((client client) id)
  (private-post client "/api/v2/order_status/"
                `(("id" . ,(api-string id)))))

(defun get-order-status (client id)
  (json-ref (order-status client id) "status"))

(defun cancel-order (client id)
  (private-post client "/api/v2/cancel_order/"
                `(("id" . ,(api-string id)))))

(defun cancel-all-orders (client)
  (private-post client "/api/v2/cancel_all_orders/"))

(defun place-limit-order (client market side amount price
                          &key limit-price daily-order client-order-id)
  (let ((side-name (cond ((string= (api-string side) "buy") "buy")
                         ((string= (api-string side) "sell") "sell")
                         (t (error 'bitstamp-error
                                   :message (format nil "Unknown order side ~A."
                                                    side))))))
    (private-post client
                  (format nil "/api/v2/~A/~A/" side-name (market-symbol market))
                  `(("amount" . ,(decimal-string amount :places 8))
                    ("price" . ,(decimal-string price :places 8))
                    ("limit_price" . ,(when limit-price
                                        (decimal-string limit-price :places 8)))
                    ("daily_order" . ,(when daily-order "true"))
                    ("client_order_id" . ,client-order-id)))))

(defun place-buy-limit-order (client amount price &optional limit-price)
  (place-limit-order client "btcusd" :buy amount price
                     :limit-price limit-price))

(defun place-sell-limit-order (client amount price &optional limit-price)
  (place-limit-order client "btcusd" :sell amount price
                     :limit-price limit-price))

(defun place-market-order (client market side amount
                           &key client-order-id)
  (let ((side-name (cond ((string= (api-string side) "buy") "buy")
                         ((string= (api-string side) "sell") "sell")
                         (t (error 'bitstamp-error
                                   :message (format nil "Unknown order side ~A."
                                                    side))))))
    (private-post client
                  (format nil "/api/v2/~A/market/~A/"
                          side-name
                          (market-symbol market))
                  `(("amount" . ,(decimal-string amount :places 8))
                    ("client_order_id" . ,client-order-id)))))

(defun buy-limit (client market amount price &rest keys)
  (apply #'place-limit-order client market :buy amount price keys))

(defun sell-limit (client market amount price &rest keys)
  (apply #'place-limit-order client market :sell amount price keys))

(defun buy-market (client market amount &rest keys)
  (apply #'place-market-order client market :buy amount keys))

(defun sell-market (client market amount &rest keys)
  (apply #'place-market-order client market :sell amount keys))

(defun buy-btc-limit (client amount price &key limit)
  (buy-limit client "btcusd" amount price :limit-price limit))

(defun sell-btc-limit (client amount price &key limit)
  (sell-limit client "btcusd" amount price :limit-price limit))

;;; cl-trading-platforms protocol implementation

(defmethod platform-status ((client client))
  (ticker client (default-market client)))

(defmethod keepalive ((client client))
  (platform-status client))

(defmethod accounts ((client client) &key portfolio &allow-other-keys)
  (declare (ignore portfolio))
  (account-balance client))

(defmethod portfolio ((client client))
  (account-balance client))

(defmethod positions ((client client) &key page &allow-other-keys)
  (declare (ignore page))
  (account-balance client))

(defmethod live-orders ((client client)
                        &key filters force market &allow-other-keys)
  (declare (ignore filters force))
  (open-orders client :market market))

(defmethod trades ((client client))
  (user-transactions client))

(defmethod market-snapshot ((client client) symbol
                            &key fields &allow-other-keys)
  (declare (ignore fields))
  (ticker client (market-symbol symbol)))

(defmethod preview-platform-order ((client client) request
                                   &key &allow-other-keys)
  (declare (ignore client))
  request)

(defun request-field (request key)
  (cdr (assoc key request :test #'string=)))

(defun submit-order-request (client request)
  (let ((market (request-field request "market"))
        (side (request-field request "side"))
        (order-type (request-field request "order_type"))
        (amount (request-field request "amount"))
        (price (request-field request "price"))
        (client-order-id (request-field request "client_order_id")))
    (cond ((string= order-type "limit")
           (place-limit-order client market side amount price
                              :client-order-id client-order-id))
          ((string= order-type "market")
           (place-market-order client market side amount
                               :client-order-id client-order-id))
          (t
           (error 'bitstamp-error
                  :message (format nil "Unsupported Bitstamp order type ~A."
                                   order-type))))))

(defmethod submit-platform-order ((client client) request
                                  &key live &allow-other-keys)
  (if live
      (submit-order-request client request)
      request))
