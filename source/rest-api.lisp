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

(defpackage #:yahoo-finance/rest-api
  (:use :common-lisp :sigma/behave)
  (:export :*query1*
           :*query2*
           :*api*
           :*user-agent*
           :*api-cache-timeout-seconds*
           :*max-retries*
           :*retry-wait-seconds*
           :canonicalize-ticker
           :query-value
           :query
           :query-alist
           :json-ref
           :json-elt
           :http-get
           :http-get-cached
           :http-get-json
           :http-get-json-cached
           :http-get-json-do-not-cache
           :api-get
           :chart-path
           :chart-uri
           :http-status
           :http-body
           :api-error
           :rate-limited
           :chart-error
           :api-error-status
           :api-error-url
           :api-error-code
           :api-error-message
           :api-error-timestamp
           :api-error-body
           :chart-error-code
           :chart-error-description
           :classify-error
           :api-error-from
           :parse-error-envelope
           :unwrap-chart
           :get-chart))
(in-package :yahoo-finance/rest-api)

(defvar *query2* "https://query2.finance.yahoo.com"
  "Yahoo Finance query2 host.  This is the default; query1 429s more readily.")
(defvar *query1* "https://query1.finance.yahoo.com"
  "Yahoo Finance query1 host.  Set *API* to this if query2 is unhappy.")
(defvar *api* *query2*
  "The host actually used for requests.")

(defvar *user-agent*
  "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36"
  "Browser User-Agent.  Yahoo 429s requests that look like a bare HTTP library.")

(defvar *api-cache-timeout-seconds* 60)
(defvar *max-retries* 3)
(defvar *retry-wait-seconds* 2)

(defun canonicalize-ticker (symbol)
  "Yahoo tickers are uppercase strings: AAPL, BRK-B, ^GSPC."
  (cond ((null symbol) nil)
        ((stringp symbol) (string-upcase symbol))
        ((symbolp symbol) (string-upcase (symbol-name symbol)))
        (t (string-upcase (princ-to-string symbol)))))

(behavior 'canonicalize-ticker
  (should-string= "AAPL" (canonicalize-ticker "aapl"))
  (should-string= "AAPL" (canonicalize-ticker :aapl))
  (should-string= "^GSPC" (canonicalize-ticker "^gspc"))
  (should-be-null (canonicalize-ticker nil)))

(defun query-value (value)
  "Turn a Lisp value into a Yahoo query-string fragment.
T/:TRUE and :FALSE become true/false.  Symbols are downcased.  NIL drops."
  (cond ((eq value t)      "true")
        ((eq value :true)  "true")
        ((eq value :false) "false")
        ((null value)      nil)
        ((stringp value)   value)
        ((symbolp value)   (string-downcase (symbol-name value)))
        ((and (vectorp value) (not (stringp value)))
         (query-value (coerce value 'list)))
        ((listp value)
         (format nil "~{~A~^,~}" (mapcar #'query-value value)))
        (t (princ-to-string value))))

(defun query (&rest pairs)
  "Build a query list of (NAME VALUE) pairs from NAME VALUE ..., dropping NILs.
Pairs are proper lists so function-cache can hash them; HTTP-GET turns them
into an alist for QURI."
  (loop for (name value) on pairs by #'cddr
        for rendered = (query-value value)
        when rendered
        collect (list name rendered)))

(defun query-alist (query-args)
  (mapcar (lambda (pair)
            (if (and (consp pair) (consp (cdr pair)))
                (cons (first pair) (second pair))
                pair))
          query-args))

(behavior 'query-value
  (spec "booleans"
    (should-string= "true" (query-value t))
    (should-string= "true" (query-value :true))
    (should-string= "false" (query-value :false)))
  (spec "symbols and strings"
    (should-string= "1d" (query-value "1d"))
    (should-string= "max" (query-value :max)))
  (spec "numbers"
    (should-string= "0" (query-value 0))))

(behavior 'query
  (should-equal '(("interval" "1d") ("period1" "0"))
                (query "interval" "1d" "range" nil "period1" 0)))

;;;; -- JSON walking ----------------------------------------------------------

(defun json-elt (seq index)
  "Element INDEX of a Yason vector or list, or NIL."
  (cond ((null seq) nil)
        ((and (vectorp seq) (not (stringp seq))
              (integerp index) (< index (length seq)))
         (aref seq index))
        ((and (listp seq) (integerp index))
         (nth index seq))
        (t nil)))

(defun json-ref (object &rest keys)
  "Walk OBJECT by hash keys (strings) and vector/list indices (integers)."
  (dolist (key keys object)
    (setf object
          (cond ((null object) nil)
                ((and (hash-table-p object) (not (integerp key)))
                 (gethash key object))
                ((integerp key)
                 (json-elt object key))
                (t nil)))))

;;;; -- Error conditions ------------------------------------------------------

(define-condition api-error (error)
  ((status :initform nil :initarg :status :reader api-error-status)
   (url :initform nil :initarg :url :reader api-error-url)
   (error-code :initform nil :initarg :error-code :reader api-error-code)
   (error-message :initform nil :initarg :error-message :reader api-error-message)
   (timestamp :initform nil :initarg :timestamp :reader api-error-timestamp)
   (body :initform nil :initarg :body :reader api-error-body))
  (:report (lambda (condition stream)
             (format stream "Yahoo Finance API error [HTTP ~A~A]: ~A (url: ~A)"
                     (or (api-error-status condition) "?")
                     (if (api-error-code condition)
                         (format nil ", code ~A" (api-error-code condition))
                         "")
                     (or (api-error-message condition) "unknown error")
                     (or (api-error-url condition) "?"))))
  (:documentation "An error talking to Yahoo Finance.
STATUS is the HTTP status code; URL is the request URI; BODY is the raw
response body."))

(define-condition rate-limited (api-error) ()
  (:documentation "HTTP 429 -- Yahoo asked us to slow down."))

(define-condition chart-error (api-error)
  ((code :initform nil :initarg :code :reader chart-error-code)
   (description :initform nil :initarg :description :reader chart-error-description))
  (:documentation "The chart payload carried an error object, or had no result.
Yahoo sometimes returns HTTP 200 with chart.error set, e.g. a delisted symbol.")
  (:report (lambda (condition stream)
             (format stream "Yahoo Finance chart error~A: ~A (url: ~A)"
                     (if (chart-error-code condition)
                         (format nil " [~A]" (chart-error-code condition))
                         "")
                     (or (chart-error-description condition)
                         (api-error-message condition)
                         "empty chart result")
                     (or (api-error-url condition) "?")))))

(defun http-status (condition)
  (let ((fn (or (and (find-symbol "RESPONSE-STATUS" :dexador)
                     (fboundp (find-symbol "RESPONSE-STATUS" :dexador))
                     (symbol-function (find-symbol "RESPONSE-STATUS" :dexador)))
                (and (find-symbol "RESPONSE-STATUS" :dex)
                     (fboundp (find-symbol "RESPONSE-STATUS" :dex))
                     (symbol-function (find-symbol "RESPONSE-STATUS" :dex))))))
    (when fn
      (ignore-errors (funcall fn condition)))))

(defun http-body (condition)
  "The response body of a dexador/dex response condition, if any."
  (let ((fn (or (and (find-symbol "RESPONSE-BODY" :dexador)
                     (fboundp (find-symbol "RESPONSE-BODY" :dexador))
                     (symbol-function (find-symbol "RESPONSE-BODY" :dexador)))
                (and (find-symbol "RESPONSE-BODY" :dex)
                     (fboundp (find-symbol "RESPONSE-BODY" :dex))
                     (symbol-function (find-symbol "RESPONSE-BODY" :dex))))))
    (when fn
      (ignore-errors (funcall fn condition)))))

(defun parse-error-envelope (body)
  "Best-effort parse of a JSON error BODY.  Yahoo 429s are often plain HTML."
  (when (stringp body)
    (ignore-errors
      (let ((top (yason:parse body)))
        (when (hash-table-p top)
          top)))))

(defun classify-error (status &optional code message)
  (declare (ignore code message))
  (if (and (integerp status) (= status 429))
      'rate-limited
      'api-error))

(defun api-error-from (status body url)
  (let ((url (if (stringp url) url (format nil "~A" url))))
    (make-instance (classify-error status)
                   :status status
                   :url url
                   :error-message (format nil "HTTP status ~A from ~A" status url)
                   :body body)))

(behavior 'classify-error
  (should-eq 'rate-limited (classify-error 429))
  (should-eq 'api-error (classify-error 404))
  (should-eq 'api-error (classify-error 500)))

;;;; -- HTTP ------------------------------------------------------------------

(defun request-headers ()
  (list (cons "User-Agent" *user-agent*)
        (cons "Accept" "application/json")))

(defun http-get (url-components &key (query-args '()))
  "HTTP GET against *API*.  Retries 429s with backoff.  Sends *USER-AGENT*."
  (let ((uri (quri:make-uri :defaults (cond ((stringp url-components)
                                             (concatenate 'string *api* url-components))
                                            ((listp url-components)
                                             (apply #'concatenate 'string *api* url-components)))
                            :query (query-alist query-args)))
        (headers (request-headers)))
    (loop for attempt from 1 to *max-retries*
          do (handler-case
                 (return (dex:get uri :headers headers))
               (error (condition)
                 (let ((status (http-status condition)))
                   (if (and status
                            (= status 429)
                            (< attempt *max-retries*))
                       (sleep (* *retry-wait-seconds* attempt))
                       (if status
                           (error (api-error-from status (http-body condition) uri))
                           (error condition)))))))))

(function-cache:defcached
    (http-get-cached :timeout *api-cache-timeout-seconds*)
    (url-components &key (query-args '()))
  (http-get url-components :query-args query-args))

(defun http-get-json (url-components &key (query-args '()))
  "GET from Yahoo, parse JSON.  Arrays become vectors; booleans become symbols."
  (let ((yason:*parse-json-arrays-as-vectors*   t)
        (yason:*parse-json-booleans-as-symbols* t))
    (yason:parse (http-get url-components :query-args query-args))))

(function-cache:defcached
    (http-get-json-cached :timeout *api-cache-timeout-seconds*)
    (url-components &key (query-args '()))
  (http-get-json url-components :query-args query-args))

(sigma/control:function-alias 'http-get-json 'http-get-json-do-not-cache)

(defun api-get (path &key query (cache t))
  "GET PATH (already rooted at /...) with QUERY alist.  CACHE defaults to T."
  (if cache
      (http-get-json-cached path :query-args query)
      (http-get-json path :query-args query)))

;;;; -- Chart -----------------------------------------------------------------

(defun chart-path (symbol)
  "Path for GET-CHART, with the ticker URL-encoded (so ^GSPC works)."
  (format nil "/v8/finance/chart/~A"
          (quri:url-encode (canonicalize-ticker symbol))))

(defun chart-uri (symbol &key interval range period1 period2 events
                           include-adjusted-close include-pre-post)
  "The full URL GET-CHART would request.  Useful as a retrieval endpoint."
  (quri:render-uri
   (quri:make-uri :defaults (concatenate 'string *api* (chart-path symbol))
                  :query (query-alist
                          (query "interval" interval
                                 "range" range
                                 "period1" period1
                                 "period2" period2
                                 "events" events
                                 "includeAdjustedClose" include-adjusted-close
                                 "includePrePost" include-pre-post)))))

(defun chart-error-object (payload)
  "The chart.error hash from PAYLOAD, or NIL if Yahoo reported no error."
  (let ((err (json-ref payload "chart" "error")))
    (when (hash-table-p err)
      err)))

(defun unwrap-chart (payload &key url)
  "The first chart.result element, or a CHART-ERROR.
PAYLOAD is a Yason hash table as returned by GET-CHART."
  (let ((err (chart-error-object payload))
        (result (json-ref payload "chart" "result")))
    (when err
      (error 'chart-error
             :url url
             :code (gethash "code" err)
             :description (gethash "description" err)
             :error-message (gethash "description" err)
             :body payload))
    (let ((first (json-elt result 0)))
      (unless (hash-table-p first)
        (error 'chart-error
               :url url
               :error-message "empty chart result"
               :body payload))
      first)))

(defun get-chart (symbol &key interval range period1 period2 events
                           (include-adjusted-close t) include-pre-post
                           (cache t))
  "Raw GET /v8/finance/chart/{SYMBOL}.  Returns the top-level Yason hash table.
This is the thin wrapper: it does not rewrite range=max.  Use OHLC-HISTORY
for a Lisp series that avoids Yahoo's quarterly downsample."
  (api-get (chart-path symbol)
           :query (query "interval" interval
                         "range" range
                         "period1" period1
                         "period2" period2
                         "events" events
                         "includeAdjustedClose" include-adjusted-close
                         "includePrePost" include-pre-post)
           :cache cache))

(behavior 'chart-path
  (should-string= "/v8/finance/chart/AAPL" (chart-path "aapl"))
  (should-be-true (search "%5E" (chart-path "^GSPC"))))

(behavior 'unwrap-chart
  (spec "error object"
    (let ((payload (let ((yason:*parse-json-arrays-as-vectors* t))
                     (yason:parse
                      "{\"chart\":{\"result\":null,\"error\":{\"code\":\"Not Found\",\"description\":\"No data found, symbol may be delisted\"}}}"))))
      (handler-case
          (progn (unwrap-chart payload) (should-be-true nil))
        (chart-error (c)
          (should-string= "Not Found" (chart-error-code c))
          (should-be-true (search "delisted" (chart-error-description c)))))))
  (spec "empty result"
    (let ((payload (let ((yason:*parse-json-arrays-as-vectors* t))
                     (yason:parse "{\"chart\":{\"result\":[],\"error\":null}}"))))
      (handler-case
          (progn (unwrap-chart payload) (should-be-true nil))
        (chart-error (c)
          (should-be-true (search "empty" (api-error-message c))))))))
