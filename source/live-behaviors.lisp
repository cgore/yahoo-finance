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

;;;; Live Yahoo Finance checks.  Loaded only by TEST-OP when
;;;; YAHOO_FINANCE_LIVE_TESTS is set, so ordinary loads never hit the network.

(in-package #:yahoo-finance)

(behavior 'ohlc-history-live
  (handler-case
      (multiple-value-bind (bars meta)
          (ohlc-history "AAPL"
                        :from 1704067200   ; 2024-01-01 UTC
                        :to 1706745600)    ; 2024-02-01 UTC
        (should-be-true (>= (length bars) 15))
        (should-string= "AAPL" (getf meta :symbol))
        (should-string= "USD" (getf meta :currency))
        (should-string= "EQUITY" (getf meta :instrument-type))
        (should-be-true (search "chart/AAPL" (getf meta :endpoint)))
        (let ((bar (first bars)))
          (should-be-true (ohlc-bar-p bar))
          (should-be-a 'integer (ohlc-bar-time bar))
          (should-be-a 'number (ohlc-bar-open bar) (ohlc-bar-high bar)
                       (ohlc-bar-low bar) (ohlc-bar-close bar)
                       (ohlc-bar-adjusted-close bar))
          (should= 7 (length (ohlc-bar-tuple bar)))))
    (rate-limited (condition)
      (declare (ignore condition))
      ;; Yahoo 429s; do not fail the suite on a polite skip.
      t)))
