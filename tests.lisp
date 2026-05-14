;;;; tests.lisp

(defpackage #:cl-trading-platform-tests
  (:use #:cl #:cl-trading-platform)
  (:import-from #:rove
                #:deftest
                #:testing
                #:ok))

(in-package #:cl-trading-platform-tests)

(defclass test-platform (platform)
  ((slept
    :accessor slept
    :initform 0)))

(defmethod platform-sleep ((platform test-platform) duration)
  (incf (slept platform) duration))

(defmethod platform-status ((platform test-platform))
  (declare (ignore platform))
  :ok)

(deftest platform-base
  (testing "rate limiter is initialized"
    (let ((platform (make-instance 'test-platform :rate 1/10)))
      (ok (typep (rate-limiter platform) 'cl-rate-limiter:bucket))
      (ok (= (rate platform) 1/10))))
  (testing "with-rate-limit calls body"
    (let ((platform (make-instance 'test-platform))
          (count 0))
      (with-rate-limit (platform)
        (incf count))
      (ok (= count 1))))
  (testing "protocol generics dispatch"
    (ok (eq (platform-status (make-instance 'test-platform)) :ok))))
