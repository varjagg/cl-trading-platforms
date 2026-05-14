;;;; protocol.lisp

(in-package #:cl-trading-platforms)

(defgeneric platform-status (platform)
  (:documentation "Return a provider-specific health/session status payload."))

(defgeneric keepalive (platform)
  (:documentation "Refresh or check the provider session."))

(defgeneric accounts (platform &key portfolio &allow-other-keys)
  (:documentation "Return provider account metadata."))

(defgeneric portfolio (platform)
  (:documentation "Return portfolio summary data for PLATFORM."))

(defgeneric positions (platform &key page &allow-other-keys)
  (:documentation "Return current positions for PLATFORM."))

(defgeneric live-orders (platform &key filters force &allow-other-keys)
  (:documentation "Return currently live/open broker orders."))

(defgeneric order-status (platform order-id)
  (:documentation "Return provider status for ORDER-ID."))

(defgeneric trades (platform)
  (:documentation "Return recent provider trades/executions."))

(defgeneric market-snapshot (platform symbol &key fields &allow-other-keys)
  (:documentation "Return a provider-specific market snapshot for SYMBOL."))

(defgeneric history-bars (platform symbol &key period bar outside-rth exchange
                                           &allow-other-keys)
  (:documentation "Return historical bars for SYMBOL."))

(defgeneric preview-platform-order (platform request &key &allow-other-keys)
  (:documentation "Preview REQUEST where the provider supports previews."))

(defgeneric submit-platform-order (platform request &key live &allow-other-keys)
  (:documentation "Submit REQUEST to PLATFORM."))

(defgeneric buy-limit (platform symbol quantity price &rest keys)
  (:documentation "Place or build a buy limit order on PLATFORM."))

(defgeneric sell-limit (platform symbol quantity price &rest keys)
  (:documentation "Place or build a sell limit order on PLATFORM."))

(defgeneric buy-market (platform symbol quantity &rest keys)
  (:documentation "Place or build a buy market order on PLATFORM."))

(defgeneric sell-market (platform symbol quantity &rest keys)
  (:documentation "Place or build a sell market order on PLATFORM."))
