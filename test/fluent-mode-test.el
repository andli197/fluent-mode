;;; fluent-test --- Tests for fluent mode
;;; Commentary:

;; Regression testing for package fluent.

;;; Code:
;; (require 'fluent-execution)

(require 'subr-x)

(defun wrap-compile (testfn)
  "Bind the compile function symbol to store the input in `saved-command' for later inspection by tests."
  (cl-letf (((symbol-function 'compile)
             (lambda (command &optional comint) (setq saved-command command))))
    (funcall testfn)))

(ert-deftest fluent-add--can-add-custom-command-to-execution-list ()
  (let ((fluent-command '()))
    (fluent-add "test command")
    (should (= (length fluent-command) 1))
    (should (string-equal (car fluent-command) "test command"))))

(ert-deftest fluent-clear--is-removing-all-commands ()
  (let ((fluent-command '()))
    (fluent-add "first")
    (fluent-add "second")
    (fluent-add "third")
    (should (= (length fluent-command) 3))
    (fluent-clear)
    (should (= (length fluent-command) 0))))

(ert-deftest fluent-toggle-remote-compile--can-toggle-remote-compilation ()
  (let ((fluent--remote-compilation '()))
    (fluent-toggle-remote-compile)
    (should (eq fluent--remote-compilation t))
    (fluent-toggle-remote-compile)
    (should (eq fluent--remote-compilation '()))))

(ert-deftest fluent--remote-build-host--can-be-custom-set ()
  (let ((fluent--remote-build-host '()))
    (fluent-set-remote-host "abcdef")
    (should (string-equal fluent--remote-build-host "abcdef"))))

(ert-deftest fluent--generate-compilation-command--empty-command-result-in-empty-string ()
  (let ((fluent-command '())
        (saved-command '())
        (fluent-prepend-compilation-commands '()))
    (wrap-compile (lambda () (fluent-compile)))
    (should (string-equal saved-command ""))))

(ert-deftest fluent--generate-compilation-command--separates-list-arguments-by-dual-ampersands-and-reverses-order ()
  (let ((saved-command '())
        (fluent-command '("third" "second" "first"))
        (fluent-prepend-compilation-commands '()))
    (wrap-compile (lambda () (fluent-compile)))
    (should (string-equal saved-command "first && second && third"))))

(ert-deftest fluent--generate-compilation-command--stores-last-command ()
  (let ((saved-command '())
        (fluent-command '("third" "second" "first")))
    (should (equal fluent--last-command '("third" "second" "first")))))

(ert-deftest fluent--generate-full-compilation-command--is-not-adding-ssh-when-disabled ()
  (let ((saved-command '())
        (fluent--remote-compilation '())
        (fluent-prepend-compilation-commands '()))
    (wrap-compile (lambda () (fluent--compile-and-log '("test"))))
    (should (string-equal saved-command "test"))))

(ert-deftest fluent--generate-full-compilation-command--is-adding-the-ssh-command-when-set-to-remote ()
  (let ((saved-command '())
        (fluent--remote-build-host "localhost")
        (fluent--remote-compilation t))
    (wrap-compile (lambda () (fluent--compile-and-log '("test"))))
    (should (string-prefix-p "ssh localhost" saved-command))))

(ert-deftest fluent--last-command--does-not-store-ssh-or-host ()
  (let ((fluent--last-command '())
        (fluent--remote-compilation t)
        (fluent--remote-build-host "123.456.789.0"))
    (wrap-compile (lambda () (fluent--compile-and-log '("c" "b" "a"))))
    (should (equal fluent--last-command '("c" "b" "a")))))

(ert-deftest fluent-prepend-compilation-commands--are-used-when-building-command-but-not-included-in-last-command ()
  (let ((saved-command "")
        (fluent-prepend-compilation-commands
         '((lambda () "second") (lambda () "first"))))
    (wrap-compile (lambda () (fluent--compile-and-log '("c" "b" "a"))))
    (should (string-prefix-p "first && second" saved-command))
    (should (equal fluent--last-command '("c" "b" "a")))))

(ert-deftest fluent--get-all-elisp-expressions-from-string ()
  (should (equal (fluent--get-all-elisp-expressions-from-string "") '()))
  (should (equal (fluent--get-all-elisp-expressions-from-string "ls -la") '()))
  (should (equal (fluent--get-all-elisp-expressions-from-string "{foobar}")
                 '("{foobar}")))
  (should (equal (seq-difference
                  (fluent--get-all-elisp-expressions-from-string "{foo}{bar}")
                  '("{bar}" "{foo}"))
                 '()))
  )

(ert-deftest fluent-evaluate-elisp-expression-string ()
  (let ((test-variable "variable value")
        (test-list '("foo" "bar")))
    (should (equal (fluent-evaluate-elisp-expression-string "") ""))
    (should (equal
             (fluent-evaluate-elisp-expression-string "{test-variable}")
             "variable value"))
    (should (equal (fluent-evaluate-elisp-expression-string "foobar")
                   "foobar"))
    (defun test-function () "function value")
    (should (equal (fluent-evaluate-elisp-expression-string "{(test-function)}")
                   "function value"))
    (should (equal (fluent-evaluate-elisp-expression-string
                    "{(test-function)} and {test-variable}")
                   "function value and variable value"))
    (should (equal
             (fluent-evaluate-elisp-expression-string
              "{(string-join (list (test-function) test-variable) \", \")}")
             "function value, variable value"))
    (should (equal (fluent-evaluate-elisp-expression-string "{test-list}")
                   "foo && bar"))
    ))

(ert-deftest fluent-compile-accepts-lisp-functions-and-variables-and-evaluates-it-at-compilation ()
  (let ((saved-command)
        (test-tmp "first")
        (test-mutable-function (lambda () (format "function: %s" test-tmp)))
        (fluent-prepend-compilation-commands '((lambda () "uptime")))
        (fluent--remote-build-host '())
        (fluent--remote-compilation '())
        (test-host "192.168.0.1")
        (remote-build-host (lambda () (format "%s" test-host))))
    (wrap-compile (lambda ()
                    (fluent--compile-and-log '("{(test-mutable-function)}"))))
    (should (equal saved-command "uptime && function: first"))

    (setq test-tmp "second")
    (wrap-compile (lambda ()
                    (fluent--compile-and-log '("{(test-mutable-function)}"))))
    (should (equal saved-command "uptime && function: second"))

    (wrap-compile (lambda ()
                    (fluent--compile-and-log '("{test-tmp}"))))
    (should (equal saved-command "uptime && second"))

    (setq fluent--remote-compilation t)
    (fluent-set-remote-host "{(remote-build-host)}")
    (wrap-compile (lambda ()
                    (fluent--compile-and-log '("{test-tmp}"))))
    (should (equal saved-command "ssh 192.168.0.1 \"uptime && second\""))
    ))

(ert-deftest fluent-execute-commands-direct-option ()
  (let ((fluent--single-command-execution '()))
    (fluent-toggle-single-command-execution)
    (should (equal fluent--single-command-execution t))
    ))

(ert-deftest fluent-evaluate-elisp-expression-tests ()
  (let ((test-var "test value")
        (test-list '("foo" "bar"))
        (test-var1 "value1")
        (test-var2 "{test-var1}"))
    (should (equal (fluent-evaluate-elisp-expression "") ""))
    (should (equal (fluent-evaluate-elisp-expression "command") "command"))
    (should (equal (fluent-evaluate-elisp-expression "{test-var}") "test value"))
    (should (equal (fluent-evaluate-elisp-expression '("command")) "command"))
    (should (equal
             (fluent-evaluate-elisp-expression '("{test-var}")) "test value"))
    (should (equal
             (fluent-evaluate-elisp-expression '("{test-var}" "{test-var}"))
             "test value && test value"))
    (should (equal (fluent-evaluate-elisp-expression "{test-list}")
                   "foo && bar"))
    (should (equal (fluent-evaluate-elisp-expression "{test-var2}") "value1"))
    ))

(provide 'fluent-test)
;;; fluent-test ends here
