;;;; platform.lisp

(in-package #:cl-trading-platform)

(defclass platform ()
  ((rate
    :accessor rate
    :initarg :rate
    :initform 1/5
    :documentation "Minimum number of seconds between outbound requests.")
   (rate-limiter
    :accessor rate-limiter
    :initarg :rate-limiter
    :initform nil
    :documentation "cl-rate-limiter bucket used to pace outbound requests.")
   (timeout
    :accessor timeout
    :initarg :timeout
    :initform 30)
   (connect-timeout
    :accessor connect-timeout
    :initarg :connect-timeout
    :initform 10)
   (read-timeout
    :accessor read-timeout
    :initarg :read-timeout
    :initform 30)))

(defgeneric platform-time (platform)
  (:documentation "Return a monotonically increasing timestamp in seconds."))

(defgeneric platform-sleep (platform duration)
  (:documentation "Sleep for DURATION seconds in PLATFORM's execution context."))

(defmethod platform-time ((platform platform))
  (declare (ignore platform))
  (/ (get-internal-real-time) internal-time-units-per-second))

(defmethod platform-sleep ((platform platform) duration)
  (declare (ignore platform))
  (sleep duration))

(defun make-platform-rate-limiter (rate)
  (unless (and (numberp rate) (plusp rate))
    (error "RATE must be a positive number."))
  (cl-rate-limiter:make-bucket :capacity 1d0
                               :leak-rate (/ 1d0 (coerce rate 'double-float))))

(defmethod initialize-instance :after ((platform platform) &key &allow-other-keys)
  (unless (rate-limiter platform)
    (setf (rate-limiter platform)
          (make-platform-rate-limiter (rate platform)))))

(defmethod (setf rate) :after ((value number) (platform platform))
  (setf (rate-limiter platform)
        (make-platform-rate-limiter value)))

(defun rate-limit-wait-duration (bucket increment level)
  (let* ((available (- (cl-rate-limiter:capacity bucket) level))
         (missing (- increment available))
         (leak-rate (cl-rate-limiter:leak-rate bucket)))
    (cond ((not (plusp missing)) 0d0)
          ((plusp leak-rate) (/ missing leak-rate))
          (t 1d0))))

(defun call-with-rate-limit (platform thunk)
  (loop with bucket = (rate-limiter platform)
        with increment = 1d0
        do (multiple-value-bind (allowed-p level)
               (cl-rate-limiter:consume bucket :increment increment)
             (when allowed-p
               (return))
             (platform-sleep platform
                             (rate-limit-wait-duration bucket increment level))))
  (funcall thunk))

(defmacro with-rate-limit ((platform) &body body)
  (let ((platform-var (gensym "PLATFORM-")))
    `(let ((,platform-var ,platform))
       (call-with-rate-limit ,platform-var (lambda () ,@body)))))

(define-condition trading-platform-error (error)
  ((message
    :reader trading-platform-error-message
    :initarg :message
    :initform "Trading platform request failed")
   (status
    :reader trading-platform-error-status
    :initarg :status
    :initform nil)
   (body
    :reader trading-platform-error-body
    :initarg :body
    :initform nil)
   (payload
    :reader trading-platform-error-payload
    :initarg :payload
    :initform nil))
  (:report
   (lambda (condition stream)
     (format stream "~A~@[ (HTTP ~D)~]~@[~%~A~]"
             (trading-platform-error-message condition)
             (trading-platform-error-status condition)
             (trading-platform-error-body condition)))))
