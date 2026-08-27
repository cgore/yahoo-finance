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

(defpackage yahoo-finance/system
  (:use :common-lisp
        :asdf)
  (:export :author
           :copyright
           :version-string
           :version-list
           :version-major
           :version-minor
           :version-revision))
(in-package :yahoo-finance/system)

(defparameter author "Christopher Mark Gore <cgore@cgore.com>")
(defparameter copyright "Copyright (c) 2026, Christopher Mark Gore, Soli Deo Gloria, all rights reserved.")
(defparameter version-major    0)
(defparameter version-minor    1)
(defparameter version-revision 0)

(defun version-list ()
  (list version-major version-minor version-revision))

(defun version-string ()
  (format nil "~{~A.~A.~A~}" (version-list)))

(defsystem "yahoo-finance"
  :description "Unofficial Common Lisp client for Yahoo Finance chart data"
  :version #.(version-string)
  :author author
  :license "BSD-3-Clause"
  :homepage "https://github.com/cgore/yahoo-finance"
  :source-control (:git "https://github.com/cgore/yahoo-finance.git")
  :bug-tracker "https://github.com/cgore/yahoo-finance/issues"
  :depends-on ("dexador" "function-cache" "quri" "sigma" "yason")
  :components ((:module "source"
                :components ((:file "main" :depends-on ("rest-api"))
                             (:file "rest-api"))))

  ;; Specs live in the sources as BEHAVIOR/SHOULD forms (sigma/behave) and run
  ;; at load time.  TEST-OP reloads every source file so those assertions run
  ;; again.  Set YAHOO_FINANCE_LIVE_TESTS=1 to also hit Yahoo's chart host.
  :perform (test-op (operation system)
                    (declare (ignore operation))
                    (labels ((reload (component)
                               (typecase component
                                 (cl-source-file
                                  (load (component-pathname component)))
                                 (parent-component
                                  (map nil #'reload (component-children component))))))
                      (reload system)
                      (when (uiop:getenv "YAHOO_FINANCE_LIVE_TESTS")
                        (load (system-relative-pathname system
                                                        "source/live-behaviors.lisp"))))))
