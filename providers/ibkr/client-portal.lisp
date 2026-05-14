;;;; client-portal.lisp

(in-package #:cl-trading-platform.ibkr)

(alexandria:define-constant +client-portal-base-url+
    "https://localhost:5000/v1/api"
  :test #'string=)

(define-condition ibkr-error (trading-platform-error) ())

(defun ibkr-error-message (condition)
  (trading-platform-error-message condition))

(defun ibkr-error-status (condition)
  (trading-platform-error-status condition))

(defun ibkr-error-body (condition)
  (trading-platform-error-body condition))

(defun ibkr-error-payload (condition)
  (trading-platform-error-payload condition))

(defclass client-portal (platform)
  ((base-url
    :accessor base-url
    :initarg :base-url
    :initform +client-portal-base-url+)
   (account-id
    :accessor account-id
    :initarg :account-id
    :initform nil)
   (verify-ssl
    :accessor verify-ssl
    :initarg :verify-ssl
    :initform nil
    :documentation "False by default because the local gateway uses a self-signed certificate.")
   (user-agent
    :accessor user-agent
    :initarg :user-agent
    :initform "cl-trading-platform-ibkr/0.1"))
  (:default-initargs :rate 1/5))

(defun make-client-portal (&rest initargs)
  (apply #'make-instance 'client-portal initargs))

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
    (keyword (symbol-name value))
    (symbol (symbol-name value))))

(defun api-string (value)
  (typecase value
    (string value)
    (keyword (symbol-name value))
    (symbol (symbol-name value))
    (number (with-standard-io-syntax (write-to-string value)))))

(defun json-bool (value)
  (if value yason:true yason:false))

(defun bool-string (value)
  (if value "true" "false"))

(defun path-segment (value)
  (quri:url-encode (api-string value)))

(defun join-csv (values)
  (etypecase values
    (string values)
    (number (api-string values))
    (symbol (api-string values))
    (list (format nil "~{~A~^,~}" (mapcar #'api-string values)))
    (vector (join-csv (coerce values 'list)))))

(defun normalize-query-params (params)
  (loop for (key . value) in params
        when value
          collect (cons (api-name key) (api-string value))))

(defun endpoint-url (client endpoint &optional params)
  (let* ((path (ensure-leading-slash endpoint))
         (url (concatenate 'string
                           (trim-trailing-slashes (base-url client))
                           path))
         (query (normalize-query-params params)))
    (if query
        (concatenate 'string url "?" (quri:url-encode-params query))
        url)))

(defun json-string (object)
  (with-output-to-string (stream)
    (let ((yason:*list-encoder* #'yason:encode-alist))
      (yason:encode object stream))))

(defun parse-json-response (body)
  (cond
    ((and (stringp body) (plusp (length (string-trim '(#\Space #\Tab #\Newline #\Return) body))))
     (yason:parse body))
    ((stringp body) nil)
    (t body)))

(defun request-headers (client content headers)
  (append `(("Accept" . "application/json")
            ("User-Agent" . ,(user-agent client)))
          (when content
            '(("Content-Type" . "application/json")))
          headers))

(defun request-json (client method endpoint &key params content headers)
  (let* ((body (when content (json-string content)))
         (url (endpoint-url client endpoint params)))
    (handler-case
        (multiple-value-bind (response status response-headers final-url)
            (with-rate-limit (client)
              (dexador:request url
                               :method method
                               :headers (request-headers client body headers)
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
          (error 'ibkr-error
                 :message "Interactive Brokers HTTP request failed"
                 :status (dexador.error:response-status error)
                 :body error-body
                 :payload payload))))))

(defun resolved-account-id (client account-id)
  (or account-id
      (account-id client)
      (error 'ibkr-error
             :message "No account id was provided; pass :ACCOUNT-ID or set it on the CLIENT-PORTAL instance.")))

(defun auth-status (client)
  (request-json client :get "/iserver/auth/status"))

(defun tickle (client)
  (request-json client :get "/tickle"))

(defun logout (client)
  (request-json client :post "/logout"))

(defun select-account (client account-id)
  (let ((response (request-json client :post "/iserver/account"
                                :content `(("acctId" . ,account-id)))))
    (setf (account-id client) account-id)
    response))

(defun get-iserver-accounts (client)
  (request-json client :get "/iserver/accounts"))

(defun get-portfolio-accounts (client)
  (request-json client :get "/portfolio/accounts"))

(defun get-portfolio-subaccounts (client)
  (request-json client :get "/portfolio/subaccounts"))

(defun get-positions (client &key account-id (page 0) model sort direction period)
  (request-json client :get
                (format nil "/portfolio/~A/positions/~D"
                        (path-segment (resolved-account-id client account-id))
                        page)
                :params `(("model" . ,model)
                          ("sort" . ,sort)
                          ("direction" . ,direction)
                          ("period" . ,period))))

(defun get-positions2 (client &key account-id)
  (request-json client :get
                (format nil "/portfolio2/~A/positions"
                        (path-segment (resolved-account-id client account-id)))))

(defun get-portfolio-summary (client &key account-id)
  (request-json client :get
                (format nil "/portfolio/~A/summary"
                        (path-segment (resolved-account-id client account-id)))))

(defun get-ledger (client &key account-id)
  (request-json client :get
                (format nil "/portfolio/~A/ledger"
                        (path-segment (resolved-account-id client account-id)))))

(defun search-contracts (client symbol &key name (security-type "STK"))
  (request-json client :get "/iserver/secdef/search"
                :params `(("symbol" . ,symbol)
                          ("name" . ,(when name (bool-string name)))
                          ("secType" . ,security-type))))

(defun contract-info (client conid &key (security-type "STK") month strike right exchange)
  (request-json client :get "/iserver/secdef/info"
                :params `(("conid" . ,conid)
                          ("secType" . ,security-type)
                          ("month" . ,month)
                          ("strike" . ,strike)
                          ("right" . ,right)
                          ("exchange" . ,exchange))))

(defun market-data-snapshot (client conids &key fields since)
  (request-json client :get "/iserver/marketdata/snapshot"
                :params `(("conids" . ,(join-csv (if (listp conids) conids (list conids))))
                          ("fields" . ,(when fields (join-csv fields)))
                          ("since" . ,since))))

(defun market-data-history (client conid &key period bar outside-rth exchange)
  (request-json client :get "/iserver/marketdata/history"
                :params `(("conid" . ,conid)
                          ("period" . ,period)
                          ("bar" . ,bar)
                          ("outsideRth" . ,(when outside-rth (bool-string outside-rth)))
                          ("exchange" . ,exchange))))

(defun add-field (fields name value supplied-p &key boolean)
  (if supplied-p
      (acons name (if boolean (json-bool value) (or value :null)) fields)
      fields))

(defun make-order (&key
                     account-id
                     conid
                     conidex
                     security-type
                     customer-order-id
                     parent-id
                     order-type
                     listing-exchange
                     (single-group nil single-group-p)
                     (outside-rth nil outside-rth-p)
                     price
                     aux-price
                     side
                     ticker
                     tif
                     trailing-amount
                     trailing-type
                     referrer
                     quantity
                     cash-quantity
                     fx-quantity
                     (use-adaptive nil use-adaptive-p)
                     (currency-conversion nil currency-conversion-p)
                     allocation-method
                     (manual-indicator nil manual-indicator-p)
                     manual-order-time
                     external-operator
                     (deactivated nil deactivated-p)
                     strategy
                     strategy-parameters)
  (let ((fields nil))
    (flet ((maybe (name value)
             (when value
               (push (cons name value) fields))))
      (maybe "acctId" account-id)
      (maybe "conid" conid)
      (maybe "conidex" conidex)
      (maybe "secType" security-type)
      (maybe "cOID" customer-order-id)
      (setf fields (add-field fields "parentId" parent-id (not (null parent-id))))
      (maybe "orderType" order-type)
      (maybe "listingExchange" listing-exchange)
      (setf fields (add-field fields "isSingleGroup" single-group single-group-p :boolean t))
      (setf fields (add-field fields "outsideRTH" outside-rth outside-rth-p :boolean t))
      (maybe "price" price)
      (maybe "auxPrice" aux-price)
      (maybe "side" side)
      (maybe "ticker" ticker)
      (maybe "tif" tif)
      (maybe "trailingAmt" trailing-amount)
      (maybe "trailingType" trailing-type)
      (maybe "referrer" referrer)
      (maybe "quantity" quantity)
      (maybe "cashQty" cash-quantity)
      (maybe "fxQty" fx-quantity)
      (setf fields (add-field fields "useAdaptive" use-adaptive use-adaptive-p :boolean t))
      (setf fields (add-field fields "isCcyConv" currency-conversion currency-conversion-p :boolean t))
      (maybe "allocationMethod" allocation-method)
      (setf fields (add-field fields "manualIndicator" manual-indicator manual-indicator-p :boolean t))
      (maybe "manualOrderTime" manual-order-time)
      (maybe "extOperator" external-operator)
      (setf fields (add-field fields "deactivated" deactivated deactivated-p :boolean t))
      (maybe "strategy" strategy)
      (maybe "strategyParameters" strategy-parameters))
    (nreverse fields)))

(defun order-object-p (value)
  (and (listp value)
       (every (lambda (entry)
                (and (consp entry)
                     (stringp (car entry))))
              value)))

(defun order-vector (orders)
  (coerce (cond
            ((order-object-p orders) (list orders))
            ((vectorp orders) (coerce orders 'list))
            (t orders))
          'vector))

(defun orders-content (orders)
  `(("orders" . ,(order-vector orders))))

(defun place-orders (client orders &key account-id)
  (request-json client :post
                (format nil "/iserver/account/~A/orders"
                        (path-segment (resolved-account-id client account-id)))
                :content (orders-content orders)))

(defun preview-orders (client orders &key account-id)
  (request-json client :post
                (format nil "/iserver/account/~A/orders/whatif"
                        (path-segment (resolved-account-id client account-id)))
                :content (orders-content orders)))

(defun modify-order (client order-id order &key account-id)
  (request-json client :post
                (format nil "/iserver/account/~A/order/~A"
                        (path-segment (resolved-account-id client account-id))
                        (path-segment order-id))
                :content order))

(defun cancel-order (client order-id &key account-id)
  (request-json client :delete
                (format nil "/iserver/account/~A/order/~A"
                        (path-segment (resolved-account-id client account-id))
                        (path-segment order-id))))

(defun confirm-reply (client reply-id &key (confirmed t))
  (request-json client :post
                (format nil "/iserver/reply/~A" (path-segment reply-id))
                :content `(("confirmed" . ,(json-bool confirmed)))))

(defun get-live-orders (client &key filters (force nil force-p))
  (request-json client :get "/iserver/account/orders"
                :params `(("filters" . ,filters)
                          ("force" . ,(when force-p (bool-string force))))))

(defun get-order-status (client order-id)
  (request-json client :get
                (format nil "/iserver/account/order/status/~A"
                        (path-segment order-id))))

(defun get-trades (client)
  (request-json client :get "/iserver/account/trades"))

(defun normalized-side (side)
  (string-upcase (api-string side)))

(defun place-limit-order (client conid side quantity price
                          &key account-id (tif "DAY") listing-exchange outside-rth
                            customer-order-id referrer)
  (place-orders client
                (make-order :account-id (resolved-account-id client account-id)
                            :conid conid
                            :order-type "LMT"
                            :side (normalized-side side)
                            :quantity quantity
                            :price price
                            :tif tif
                            :listing-exchange listing-exchange
                            :outside-rth outside-rth
                            :customer-order-id customer-order-id
                            :referrer referrer)
                :account-id account-id))

(defun buy-limit (client conid quantity price &rest keys)
  (apply #'place-limit-order client conid "BUY" quantity price keys))

(defun sell-limit (client conid quantity price &rest keys)
  (apply #'place-limit-order client conid "SELL" quantity price keys))

(defun place-market-order (client conid side quantity
                           &key account-id (tif "DAY") listing-exchange outside-rth
                             customer-order-id referrer)
  (place-orders client
                (make-order :account-id (resolved-account-id client account-id)
                            :conid conid
                            :order-type "MKT"
                            :side (normalized-side side)
                            :quantity quantity
                            :tif tif
                            :listing-exchange listing-exchange
                            :outside-rth outside-rth
                            :customer-order-id customer-order-id
                            :referrer referrer)
                :account-id account-id))

(defun buy-market (client conid quantity &rest keys)
  (apply #'place-market-order client conid "BUY" quantity keys))

(defun sell-market (client conid quantity &rest keys)
  (apply #'place-market-order client conid "SELL" quantity keys))

;;; cl-trading-platform protocol implementation

(defmethod platform-status ((client client-portal))
  (auth-status client))

(defmethod keepalive ((client client-portal))
  (tickle client))

(defmethod accounts ((client client-portal) &key portfolio &allow-other-keys)
  (if portfolio
      (get-portfolio-accounts client)
      (get-iserver-accounts client)))

(defmethod portfolio ((client client-portal))
  (get-portfolio-summary client :account-id (account-id client)))

(defmethod positions ((client client-portal) &key (page 0) &allow-other-keys)
  (get-positions client :account-id (account-id client) :page page))

(defmethod live-orders ((client client-portal)
                        &key filters (force nil force-supplied-p)
                        &allow-other-keys)
  (if force-supplied-p
      (get-live-orders client :filters filters :force force)
      (get-live-orders client :filters filters)))

(defmethod order-status ((client client-portal) order-id)
  (get-order-status client order-id))

(defmethod trades ((client client-portal))
  (get-trades client))

(defmethod market-snapshot ((client client-portal) symbol
                            &key fields conid since &allow-other-keys)
  (market-data-snapshot client (or conid symbol) :fields fields :since since))

(defmethod history-bars ((client client-portal) symbol
                         &key period bar outside-rth exchange conid
                         &allow-other-keys)
  (market-data-history client
                       (or conid symbol)
                       :period period
                       :bar bar
                       :outside-rth outside-rth
                       :exchange exchange))

(defmethod preview-platform-order ((client client-portal) request
                                   &key account-id &allow-other-keys)
  (preview-orders client request :account-id account-id))

(defmethod submit-platform-order ((client client-portal) request
                                  &key live account-id &allow-other-keys)
  (declare (ignore live))
  (place-orders client request :account-id account-id))
