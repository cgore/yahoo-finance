;;;; Copyright (c) 2026, Christopher Mark Gore,
;;;; Soli Deo Gloria,
;;;; All rights reserved.
;;;;
;;;; 22 Forest Glade Court, Saint Charles, Missouri 63304 USA.
;;;; Web: http://cgore.com
;;;; Email: cgore@cgore.com
;;;;
;;;; Redistribution and use in source and binary forms, with or without
;;;; modification, are permitted provided that the following conditions are met:
;;;;
;;;;     * Redistributions of source code must retain the above copyright
;;;;       notice, this list of conditions and the following disclaimer.
;;;;
;;;;     * Redistributions in binary form must reproduce the above copyright
;;;;       notice, this list of conditions and the following disclaimer in the
;;;;       documentation and/or other materials provided with the distribution.
;;;;
;;;;     * Neither the name of Christopher Mark Gore nor the names of other
;;;;       contributors may be used to endorse or promote products derived from
;;;;       this software without specific prior written permission.
;;;;
;;;; THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
;;;; AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
;;;; IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
;;;; ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE
;;;; LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
;;;; CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
;;;; SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
;;;; INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
;;;; CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
;;;; ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
;;;; POSSIBILITY OF SUCH DAMAGE.

(uiop:define-package #:yahoo-finance
  (:use #:common-lisp #:sigma/behave #:yahoo-finance/rest-api)
  (:reexport #:yahoo-finance/rest-api)
  (:export #:unix-epoch
           #:unix->universal
           #:universal->unix
           #:canonicalize-unix
           #:canonicalize-interval
           #:daily-or-longer-p
           #:normalize-chart-window
           #:chart
           #:chart-result
           #:chart-meta
           #:ohlc-bar
           #:ohlc-bar-p
           #:ohlc-bar-time
           #:ohlc-bar-open
           #:ohlc-bar-high
           #:ohlc-bar-low
           #:ohlc-bar-close
           #:ohlc-bar-volume
           #:ohlc-bar-adjusted-close
           #:make-ohlc-bar
           #:result->bars
           #:ohlc-bar-tuple
           #:ohlc-bars-for-ingest
           #:ohlc-history
           #:load-chart-fixture
           #:version-string
           #:version-list
           #:version-major
           #:version-minor
           #:version-revision)
  (:import-from #:yahoo-finance/system
                #:version-string
                #:version-list
                #:version-major
                #:version-minor
                #:version-revision))
(in-package #:yahoo-finance)

(defparameter unix-epoch (encode-universal-time 0 0 0 1 1 1970 0)
  "Universal time of the UNIX epoch (1970-01-01T00:00:00Z).")

(defun unix->universal (unix)
  "Convert a UNIX timestamp in seconds or milliseconds to universal time.
Values above 10^11 are treated as milliseconds."
  (when unix
    (let ((seconds (if (> unix 100000000000)
                       (floor unix 1000)
                       unix)))
      (+ seconds unix-epoch))))

(defun universal->unix (universal)
  "Convert a Common Lisp universal time to UNIX seconds."
  (- universal unix-epoch))

(defun canonicalize-unix (value)
  "Turn VALUE into a UNIX-seconds string for period1/period2.
Integers greater than 10^11 are treated as milliseconds.
Integers greater than 3·10^9 are treated as universal times.
Everything else is passed through as unix seconds."
  (cond ((null value) nil)
        ((stringp value) value)
        ((integerp value)
         (princ-to-string
          (cond ((> value 100000000000) (floor value 1000))
                ((> value 3000000000) (universal->unix value))
                (t value))))
        (t (query-value value))))

(behavior 'unix->universal
  (should= unix-epoch (unix->universal 0))
  (should= 345479400 (universal->unix (unix->universal 345479400)))
  (spec "milliseconds"
    (should= (unix->universal 345479400)
             (unix->universal 345479400000))))

(behavior 'canonicalize-unix
  (should-string= "0" (canonicalize-unix 0))
  (should-string= "345479400" (canonicalize-unix 345479400))
  (should-string= "345479400" (canonicalize-unix 345479400000))
  (should-be-null (canonicalize-unix nil)))

;;;; -- Intervals and the range=max trap --------------------------------------

(defparameter *daily-or-longer*
  '("1d" "5d" "1wk" "1mo" "3mo")
  "Yahoo intervals that must not be paired with range=max (Yahoo downsamples).")

(defun daily-or-longer-p (interval)
  (member interval *daily-or-longer* :test #'string-equal))

(defun canonicalize-interval (interval)
  "Map a candlesticks short name or Yahoo interval onto Yahoo's strings.
Month is the string \"M\" or the keyword/string MO; :M and :m are the same
Lisp symbol and mean minute (1m)."
  (when interval
    (let* ((raw (cond ((stringp interval) interval)
                      ((symbolp interval) (symbol-name interval))
                      (t (princ-to-string interval))))
           (down (string-downcase raw)))
      (cond ((string= raw "M") "1mo")
            ((member down '("mo" "month" "monthly" "1mo") :test #'string=) "1mo")
            ((member down '("m" "1m" "min" "minute") :test #'string=) "1m")
            ((member down '("h" "1h" "hour" "hourly" "60m") :test #'string=) "1h")
            ((member down '("d" "1d" "day" "daily") :test #'string=) "1d")
            ((member down '("w" "wk" "1wk" "week" "weekly") :test #'string=) "1wk")
            ((member down '("5d") :test #'string=) "5d")
            ((member down '("3mo") :test #'string=) "3mo")
            ((member down '("ytd") :test #'string=) "ytd")
            (t down)))))

(behavior 'canonicalize-interval
  (should-string= "1d" (canonicalize-interval "d"))
  (should-string= "1d" (canonicalize-interval :d))
  (should-string= "1wk" (canonicalize-interval "w"))
  (should-string= "1mo" (canonicalize-interval "M"))
  (should-string= "1mo" (canonicalize-interval :mo))
  (should-string= "1m" (canonicalize-interval "m"))
  (should-string= "1h" (canonicalize-interval :h))
  (should-string= "5m" (canonicalize-interval "5m"))
  (should-be-null (canonicalize-interval nil)))

(defun unix-now-string ()
  (princ-to-string (universal->unix (get-universal-time))))

(defun normalize-chart-window (&key (interval "1d") range from to period1 period2)
  "Return a plist :interval :range :period1 :period2 for GET-CHART.

FROM/TO (or PERIOD1/PERIOD2) win over RANGE.  RANGE=max with a daily-or-longer
interval is rewritten to period1=0 / period2=now so Yahoo does not downsample
to quarterly bars.  With no window at all, daily-or-longer defaults to that
full-history pair; shorter intervals keep RANGE if the caller supplied one."
  (let ((interval (or (canonicalize-interval interval) "1d"))
        (p1 (or (canonicalize-unix period1) (canonicalize-unix from)))
        (p2 (or (canonicalize-unix period2) (canonicalize-unix to)))
        (range (and range
                    (if (stringp range)
                        range
                        (query-value range)))))
    (when (and p1 (not p2))
      (setf p2 (unix-now-string)))
    (cond ((and (string-equal range "max")
                (daily-or-longer-p interval))
           (list :interval interval
                 :range nil
                 :period1 (or p1 "0")
                 :period2 (or p2 (unix-now-string))))
          ((or p1 p2 range)
           (list :interval interval
                 :range (unless p1 range)
                 :period1 p1
                 :period2 p2))
          ((daily-or-longer-p interval)
           (list :interval interval
                 :range nil
                 :period1 "0"
                 :period2 (unix-now-string)))
          (t
           (list :interval interval
                 :range range
                 :period1 p1
                 :period2 p2)))))

(behavior 'normalize-chart-window
  (spec "range=max on daily becomes period1/period2"
    (let ((w (normalize-chart-window :interval "1d" :range "max")))
      (should-string= "1d" (getf w :interval))
      (should-be-null (getf w :range))
      (should-string= "0" (getf w :period1))
      (should-be-true (plusp (parse-integer (getf w :period2))))))
  (spec "default daily is full history, not range=max"
    (let ((w (normalize-chart-window)))
      (should-string= "1d" (getf w :interval))
      (should-be-null (getf w :range))
      (should-string= "0" (getf w :period1))))
  (spec "named range passes through"
    (let ((w (normalize-chart-window :range "1y")))
      (should-string= "1y" (getf w :range))
      (should-be-null (getf w :period1))))
  (spec "from/to win"
    (let ((w (normalize-chart-window :range "1y" :from 345479400 :to 345479500)))
      (should-be-null (getf w :range))
      (should-string= "345479400" (getf w :period1))
      (should-string= "345479500" (getf w :period2))))
  (spec "candlesticks short names"
    (should-string= "1wk" (getf (normalize-chart-window :interval "w" :range "1y")
                                :interval))))

;;;; -- Meta and bars ---------------------------------------------------------

(defun json-number (value)
  "Yason number, or NIL for JSON null / missing."
  (and (numberp value) value))

(defun chart-meta (result &key endpoint)
  "Plist of what Yahoo said about RESULT (a chart.result[0] hash table)."
  (let ((meta (json-ref result "meta")))
    (list :symbol (and meta (gethash "symbol" meta))
          :currency (and meta (gethash "currency" meta))
          :exchange-name (and meta (gethash "exchangeName" meta))
          :full-exchange-name (and meta (gethash "fullExchangeName" meta))
          :instrument-type (and meta (gethash "instrumentType" meta))
          :timezone (and meta (gethash "timezone" meta))
          :exchange-timezone-name (and meta (gethash "exchangeTimezoneName" meta))
          :gmt-offset (and meta (gethash "gmtoffset" meta))
          :first-trade-date (unix->universal
                             (and meta (gethash "firstTradeDate" meta)))
          :data-granularity (and meta (gethash "dataGranularity" meta))
          :long-name (and meta (gethash "longName" meta))
          :short-name (and meta (gethash "shortName" meta))
          :endpoint endpoint)))

(defclass ohlc-bar ()
  ((time
    :initarg :time
    :accessor ohlc-bar-time
    :documentation "A universal time: the open of the bar.")
   (open
    :initarg :open
    :accessor ohlc-bar-open
    :documentation "As-traded open.")
   (high
    :initarg :high
    :accessor ohlc-bar-high
    :documentation "As-traded high.")
   (low
    :initarg :low
    :accessor ohlc-bar-low
    :documentation "As-traded low.")
   (close
    :initarg :close
    :accessor ohlc-bar-close
    :documentation "As-traded close.")
   (volume
    :initarg :volume
    :accessor ohlc-bar-volume
    :initform nil
    :documentation "Volume, or NIL when Yahoo did not provide one.")
   (adjusted-close
    :initarg :adjusted-close
    :accessor ohlc-bar-adjusted-close
    :initform nil
    :documentation "Yahoo's split-and-dividend-adjusted close, or NIL."))
  (:documentation
   "One Yahoo chart bar: as-traded OHLC plus optional volume and adjusted close.
This is not a CANDLESTICKS:CANDLESTICK --- no instruments, duration, or
retrieval.  Use OHLC-BARS-FOR-INGEST to feed candlesticks."))

(defun ohlc-bar-p (object)
  (typep object 'ohlc-bar))

(defun make-ohlc-bar (&key time open high low close volume adjusted-close)
  (make-instance 'ohlc-bar
                 :time time
                 :open open
                 :high high
                 :low low
                 :close close
                 :volume volume
                 :adjusted-close adjusted-close))

(defmethod print-object ((bar ohlc-bar) stream)
  (print-unreadable-object (bar stream :type t)
    (format stream "@ ~A: o~A h~A l~A c~A"
            (ohlc-bar-time bar)
            (ohlc-bar-open bar)
            (ohlc-bar-high bar)
            (ohlc-bar-low bar)
            (ohlc-bar-close bar))))

(defun ohlc-bar-tuple (bar)
  "One ingest row for CANDLESTICKS:INGEST-CANDLESTICKS:
   (time open high low close volume adjusted-close)."
  (list (ohlc-bar-time bar)
        (ohlc-bar-open bar)
        (ohlc-bar-high bar)
        (ohlc-bar-low bar)
        (ohlc-bar-close bar)
        (ohlc-bar-volume bar)
        (ohlc-bar-adjusted-close bar)))

(defun ohlc-bars-for-ingest (bars)
  "Translate a sequence of OHLC-BAR into the list of tuples
   CANDLESTICKS:INGEST-CANDLESTICKS expects."
  (map 'list #'ohlc-bar-tuple bars))

(defun bar-blank-p (open high low close)
  (not (or open high low close)))

(defun result->bars (result)
  "List of OHLC-BAR from a chart result.
Bars whose OHLC are all null are dropped.  TIME is a universal time."
  (let* ((timestamps (json-ref result "timestamp"))
         (quote (json-ref result "indicators" "quote" 0))
         (opens (and quote (gethash "open" quote)))
         (highs (and quote (gethash "high" quote)))
         (lows (and quote (gethash "low" quote)))
         (closes (and quote (gethash "close" quote)))
         (volumes (and quote (gethash "volume" quote)))
         (adjs (json-ref result "indicators" "adjclose" 0 "adjclose"))
         (n (cond ((vectorp timestamps) (length timestamps))
                  ((listp timestamps) (length timestamps))
                  (t 0))))
    (loop for i from 0 below n
          for open = (json-number (json-elt opens i))
          for high = (json-number (json-elt highs i))
          for low = (json-number (json-elt lows i))
          for close = (json-number (json-elt closes i))
          unless (bar-blank-p open high low close)
          collect (make-ohlc-bar
                   :time (unix->universal (json-elt timestamps i))
                   :open open
                   :high high
                   :low low
                   :close close
                   :volume (json-number (json-elt volumes i))
                   :adjusted-close (json-number (json-elt adjs i))))))

(defun load-chart-fixture (&optional (name "aapl-chart-5d.json"))
  "Parse a checked-in chart JSON fixture.  Used by load-time specs."
  (let ((path (asdf:system-relative-pathname
               :yahoo-finance
               (merge-pathnames name "test-fixtures/")))
        (yason:*parse-json-arrays-as-vectors* t)
        (yason:*parse-json-booleans-as-symbols* t))
    (with-open-file (in path)
      (yason:parse in))))

(behavior 'result->bars
  (let* ((payload (load-chart-fixture))
         (result (unwrap-chart payload))
         (bars (result->bars result))
         (meta (chart-meta result)))
    (should= 5 (length bars))
    (should-string= "AAPL" (getf meta :symbol))
    (should-string= "USD" (getf meta :currency))
    (should-string= "NMS" (getf meta :exchange-name))
    (should-string= "NasdaqGS" (getf meta :full-exchange-name))
    (should-string= "EQUITY" (getf meta :instrument-type))
    (should-string= "1d" (getf meta :data-granularity))
    (should= 345479400
             (universal->unix (getf meta :first-trade-date)))
    (let ((bar (first bars)))
      (should-be-true (ohlc-bar-p bar))
      (should-be-a 'integer (ohlc-bar-time bar))
      (should-be-a 'number (ohlc-bar-open bar) (ohlc-bar-high bar)
                   (ohlc-bar-low bar) (ohlc-bar-close bar)
                   (ohlc-bar-volume bar) (ohlc-bar-adjusted-close bar))
      (should= 317.4599914550781d0 (ohlc-bar-open bar))
      (should= 311.29998779296875d0 (ohlc-bar-close bar)))
    (let ((last (car (last bars))))
      (should= 313.45001220703125d0 (ohlc-bar-close last))
      (should= 313.45001220703125d0 (ohlc-bar-adjusted-close last)))
    (let ((row (ohlc-bar-tuple (first bars))))
      (should= 7 (length row))
      (should= (ohlc-bar-time (first bars)) (first row))
      (should= (ohlc-bar-adjusted-close (first bars)) (seventh row)))
    (should= 5 (length (ohlc-bars-for-ingest bars)))
    (should-equal (ohlc-bar-tuple (first bars))
                  (first (ohlc-bars-for-ingest bars)))))

(behavior 'result->bars-skips-nulls
  (let* ((payload (let ((yason:*parse-json-arrays-as-vectors* t))
                    (yason:parse
                     "{\"chart\":{\"result\":[{\"timestamp\":[1,2],\"indicators\":{\"quote\":[{\"open\":[1,null],\"high\":[1,null],\"low\":[1,null],\"close\":[1,null],\"volume\":[10,null]}],\"adjclose\":[{\"adjclose\":[1,null]}]}}],\"error\":null}}")))
         (bars (result->bars (unwrap-chart payload))))
    (should= 1 (length bars))
    (should-be-true (ohlc-bar-p (first bars)))
    (should= 1 (ohlc-bar-open (first bars)))))

;;;; -- Public helpers --------------------------------------------------------

(sigma/control:function-alias 'get-chart 'chart)

(defun apply-window-to-get-chart (symbol window &rest extras)
  (apply #'get-chart symbol
         :interval (getf window :interval)
         :range (getf window :range)
         :period1 (getf window :period1)
         :period2 (getf window :period2)
         extras))

(defun chart-result (symbol &key (interval "1d") range from to period1 period2
                      events (include-adjusted-close t) include-pre-post
                      (cache t))
  "Unwrapped chart.result[0] for SYMBOL, after NORMALIZE-CHART-WINDOW."
  (let* ((window (normalize-chart-window :interval interval
                                         :range range
                                         :from from
                                         :to to
                                         :period1 period1
                                         :period2 period2))
         (payload (apply-window-to-get-chart
                   symbol window
                   :events events
                   :include-adjusted-close include-adjusted-close
                   :include-pre-post include-pre-post
                   :cache cache))
         (url (chart-uri symbol
                         :interval (getf window :interval)
                         :range (getf window :range)
                         :period1 (getf window :period1)
                         :period2 (getf window :period2)
                         :events events
                         :include-adjusted-close include-adjusted-close
                         :include-pre-post include-pre-post)))
    (unwrap-chart payload :url url)))

(defun ohlc-history (symbol &key (interval "1d") range from to period1 period2
                      events (include-adjusted-close t) include-pre-post
                      (cache t))
  "List of OHLC-BAR for SYMBOL.

The second value is a chart-meta plist (currency, exchange,
first-trade-date, the request :endpoint, ...).  Default window is full
daily history via period1/period2, not range=max.

This library does not depend on candlesticks.  Pass the bars through
OHLC-BARS-FOR-INGEST before CANDLESTICKS:INGEST-CANDLESTICKS."
  (let* ((window (normalize-chart-window :interval interval
                                         :range range
                                         :from from
                                         :to to
                                         :period1 period1
                                         :period2 period2))
         (payload (apply-window-to-get-chart
                   symbol window
                   :events events
                   :include-adjusted-close include-adjusted-close
                   :include-pre-post include-pre-post
                   :cache cache))
         (url (chart-uri symbol
                         :interval (getf window :interval)
                         :range (getf window :range)
                         :period1 (getf window :period1)
                         :period2 (getf window :period2)
                         :events events
                         :include-adjusted-close include-adjusted-close
                         :include-pre-post include-pre-post))
         (result (unwrap-chart payload :url url)))
    (values (result->bars result)
            (chart-meta result :endpoint url))))
