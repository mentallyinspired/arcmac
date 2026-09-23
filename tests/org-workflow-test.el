;;; org-workflow-test.el --- Org workflow regressions -*- lexical-binding: t; -*-
;; Run: emacs --batch --quick -l tests/org-workflow-test.el -f ert-run-tests-batch-and-exit
(require 'ert)
(require 'cl-lib)
(require 'org)
(require 'org-agenda)
(require 'org-capture)
(require 'ob-core)
(require 'use-package)
(require 'ibuffer)
(require 'ibuf-ext)

(defvar nd/test-root (make-temp-file "arcmac-org-tests-" t))
(defvar my/state-dir nd/test-root)
(defvar nd/inbox-file (expand-file-name "inbox.org" nd/test-root))
(defconst nd/test-config
  (expand-file-name "../config.org" (file-name-directory (or load-file-name buffer-file-name))))

(defun nd/test-load-block (name)
  (with-temp-buffer
    (insert-file-contents nd/test-config)
    (org-mode)
    (goto-char (point-min))
    (unless (search-forward (concat "#+name: " name "\n") nil t)
      (error "Missing config block: %s" name))
    (forward-line)
    (let ((body (nth 1 (org-babel-get-src-block-info 'light))))
      (with-temp-buffer
        (insert ";;; -*- lexical-binding: t; -*-\n" body)
        (eval-buffer)))))

(dolist (name '("save-cleanup" "file-management" "buffer-management" "org-workflow" "org-settings" "org-tags"
               "org-work-agenda" "org-helpers" "org-meeting-refile" "org-contacts" "org-capture"
               "org-auto-save"))
  (nd/test-load-block name))

(setq org-directory nd/test-root
      org-agenda-files (list nd/inbox-file (expand-file-name "gtd/" nd/test-root)
                             (expand-file-name "journal/" nd/test-root))
      org-id-locations-file (expand-file-name "ids" nd/test-root)
      org-agenda-start-with-log-mode nil
      org-overriding-default-time (encode-time 0 0 12 16 9 2026))

(defun nd/test-agenda-at-fixture-date (function &rest args)
  "Run agenda FUNCTION with today matching the dated fixtures."
  ;; `org-overriding-default-time' controls date input, but not the
  ;; `org-today' clock used for agenda ranges and future scheduling.
  (cl-letf (((symbol-function 'org-today)
             (lambda () (time-to-days org-overriding-default-time))))
    (apply function args)))

(advice-add 'org-agenda :around #'nd/test-agenda-at-fixture-date)

(defun nd/test-file (name text)
  (let ((file (expand-file-name name nd/test-root)))
    (make-directory (file-name-directory file) t)
    (with-temp-file file (insert text))
    file))

(nd/test-file "inbox.org" "* Sigtuna :sigtuna:\n** Old capture\n** DONE Resolved capture\n* New top-level capture :@home:\n")
(nd/test-file "gtd/sigtuna.org"
 "#+FILETAGS: :sigtuna:\n* Standalone tasks\n** TODO Loose backlog\n* ACTIVE Pilot :project:\n:PROPERTIES:\n:ID: pilot-id\n:END:\n** Faser\n*** NEXT Available action\n*** NEXT Future action\nSCHEDULED: <2026-09-23 Wed>\n*** Appointment\n<2026-09-16 Wed 10:00>\n* HOLD Held project :project:\n** NEXT Held action\n** WAIT Held follow-up\nSCHEDULED: <2026-09-16 Wed>\n** TODO Held obligation\nDEADLINE: <2026-09-17 Thu>\n* ACTIVE Undated waiting project :project:\n** WAIT Unmonitored wait\n* ACTIVE Monitored project :project:\n** WAIT Monitored wait\nSCHEDULED: <2026-09-23 Wed>\n* COMPLETED Closed project :project:\n** TODO Residual action\nSCHEDULED: <2026-09-16 Wed>\n* ACTIVE Archived-next project :project:\n** Archive :ARCHIVE:\n*** NEXT Archived action\n* Legacy root :project:\n* Responsibility\n** Section\n*** TODO Deep standalone\n")
(nd/test-file "gtd/home.org" "#+FILETAGS: :@home:\n* Standalone tasks\n** NEXT Home action\n")
(nd/test-file "journal/2025.org"
 "* Historical meeting :meeting:\nProject: [[id:pilot-id][Pilot]]\n* Work log\nProject: [[id:pilot-id][Pilot]]\n")
(nd/test-file "journal/2026.org"
 "* Current meeting :meeting:unprocessed:\nProject: [[id:pilot-id][Pilot]]\n** TODO Journal action\n* Prefix collision :meeting:\nProject: [[id:pilot-id-extra][Another project]]\n* Child-only link :meeting:\n** Details\n[[id:pilot-id][Pilot]]\n* Literal example :meeting:\n#+begin_example\n[[id:pilot-id][Pilot]]\n#+end_example\n")

(defmacro nd/test-with-contacts (&rest body)
  "Run BODY in isolated registries, closing associated views afterwards."
  (declare (indent 0) (debug t))
  `(let ((org-directory (expand-file-name "contact-fixtures/" nd/test-root)))
     (nd/test-file "contact-fixtures/ref/people.org"
      "* Alex Example\n:PROPERTIES:\n:ID: person-a\n:ALIASES: Al \"A Example\"\n:CONTEXT: work\n:ORG_UNIT: [[id:team-id][Team]]\n:POSITION: Analyst\n:EMAIL: alex@example.invalid\n:TEL_MOBILE:\n:TEL_WORK: 123\n:END:\n** Notes\nShared notes.\n* Alex Example\n:PROPERTIES:\n:ID: person-b\n:CONTEXT: private\n:END:\n* Casey Sample\n:PROPERTIES:\n:ID: person-c\n:CONTEXT: work\n:ORG_UNIT: [[id:org-id][Example Org]]\n:END:\n* No ID\n")
     (nd/test-file "contact-fixtures/ref/organizations.org"
      "* Example Org\n:PROPERTIES:\n:ID: org-id\n:UNIT_TYPE: company\n:ALIASES: EO \"Example Company\"\n:END:\n** Team\n:PROPERTIES:\n:ID: team-id\n:UNIT_TYPE: team\n:ALIASES: Group\n:END:\n*** Background note\n:PROPERTIES:\n:ID: not-a-unit\n:END:\n")
     (unwind-protect (save-window-excursion ,@body)
       (dolist (buffer (buffer-list))
         (when (buffer-live-p buffer)
           (let* ((base (or (buffer-base-buffer buffer) buffer))
                  (file (buffer-local-value 'buffer-file-name base)))
             (when (and file (string-prefix-p org-directory file))
               (with-current-buffer base (set-buffer-modified-p nil))
               (kill-buffer buffer))))))))

(ert-deftest nd/files-delete-confirms-and-preserves-edits-on-cancel-or-error ()
  (dolist (action '(cancel fail delete))
    (let* ((file (nd/test-file "delete-current-file.txt" "Saved text.\n"))
           (buffer (find-file-noselect file))
           (delete-by-moving-to-trash nil))
      (unwind-protect
          (with-current-buffer buffer
            (goto-char (point-max))
            (insert "Unsaved text.\n")
            (cl-letf (((symbol-function 'yes-or-no-p)
                       (lambda (prompt)
                         (should (string-search file prompt))
                         (should (string-search "discard unsaved edits" prompt))
                         (not (eq action 'cancel)))))
              (if (eq action 'fail)
                  (cl-letf (((symbol-function 'delete-file)
                             (lambda (&rest _) (signal 'file-error '("Deletion failed")))))
                    (should-error (nd/delete-current-file) :type 'file-error))
                (nd/delete-current-file)))
            (if (eq action 'delete)
                (progn
                  (should-not (file-exists-p file))
                  (should-not (buffer-live-p buffer)))
              (should (buffer-live-p buffer))
              (should (buffer-modified-p))
              (should (string-search "Unsaved text." (buffer-string)))
              (should (equal "Saved text.\n"
                             (with-temp-buffer
                               (insert-file-contents file)
                               (buffer-string))))))
        (when (buffer-live-p buffer)
          (with-current-buffer buffer (set-buffer-modified-p nil))
          (kill-buffer buffer))))))

(ert-deftest nd/files-delete-refuses-nonfiles-and-indirect-views ()
  (cl-letf (((symbol-function 'yes-or-no-p)
             (lambda (&rest _) (ert-fail "Unexpected deletion prompt"))))
    (with-temp-buffer
      (should-error (nd/delete-current-file) :type 'user-error)
      (setq buffer-file-name (expand-file-name "not-on-disk.txt" nd/test-root))
      (should-error (nd/delete-current-file) :type 'user-error))
    (let* ((file (nd/test-file "delete-indirect-source.txt" "Keep this file.\n"))
           (base (find-file-noselect file))
           (view (make-indirect-buffer base " *delete-file-view*" t)))
      (unwind-protect
          (with-current-buffer view
            (should-error (nd/delete-current-file) :type 'user-error)
            (should (file-exists-p file))
            (should (buffer-live-p base)))
        (kill-buffer view)
        (kill-buffer base)))))

(ert-deftest nd/contacts-read-without-moving-point-or-narrowing ()
  (nd/test-with-contacts
    (with-current-buffer (find-file-noselect (nd/contact-file nil))
      (goto-char (point-min))
      (org-narrow-to-subtree)
      (let ((start (point)) (end (point-max)))
        (should (= 4 (length (nd/contact-records))))
        (should (= start (point)))
        (should (= end (point-max))))
      (should (equal "123" (plist-get (car (nd/contact-records)) :phone))))))

(ert-deftest nd/contacts-aliases-and-duplicate-names ()
  (nd/test-with-contacts
    (let* ((entries (nd/contact-records))
           (candidates (nd/contact-candidates entries)))
      (should (= 3 (length candidates)))
      (should (equal "person-a" (plist-get (nd/contact-resolve "A Example" candidates) :id)))
      (should (equal "person-a" (plist-get (nd/contact-resolve "al" candidates) :id)))
      (should-error (nd/contact-resolve "Alex Example" candidates) :type 'user-error)
      (should-not (nd/contact-resolve "Unknown guest" candidates))
      (should (equal "person-b" (plist-get (nd/contact-resolve (caar (cdr candidates)) candidates) :id)))
      (setf (plist-get (cadr entries) :context) "work"
            (plist-get (cadr entries) :unit) "[[id:team-id][Team]]"
            (plist-get (cadr entries) :aliases) '("Al" "A Example"))
      (let ((labels (mapcar #'car (nd/contact-candidates entries))))
        (should (= 3 (length (delete-dups labels))))
        (should (string-match-p "person-a" (car labels)))))))

(ert-deftest nd/contacts-attendees-canonicalize-deduplicate-and-keep-guests ()
  (nd/test-with-contacts
    (cl-letf (((symbol-function 'completing-read-multiple)
               (lambda (&rest _) '("Al" "A Example" "Guest" " guest " ""))))
      (should (equal "[[id:person-a][Alex Example]], Guest" (nd/read-attendees))))))

(ert-deftest nd/contacts-units-use-aliases-and-only-real-units ()
  (nd/test-with-contacts
    (should (= 2 (length (nd/all-organization-roster))))
    (should (string-match-p "Example Company" (caar (nd/all-organization-roster))))
    (should (equal '("org-id" "team-id") (nd/organization-subtree-ids "org-id")))
    (should-error (nd/organization-subtree-ids nil) :type 'user-error)
    (cl-letf (((symbol-function 'completing-read)
               (lambda (_prompt candidates &rest _) (caar candidates))))
      (should (equal "[[id:org-id][Example Org]]" (nd/read-organizational-unit))))))

(ert-deftest nd/contacts-unit-completion-keeps-nested-matches-with-prefix-collisions ()
  (nd/test-with-contacts
    (with-current-buffer (find-file-noselect (nd/contact-file t))
      (goto-char (point-max))
      (insert "** DigIT\n:PROPERTIES:\n:ID: digit-id\n:UNIT_TYPE: team\n:ALIASES: IT\n:END:\n"
              "* DigitalWorkforce\n:PROPERTIES:\n:ID: company-id\n:UNIT_TYPE: company\n:END:\n"
              "* IT Services\n:PROPERTIES:\n:ID: services-id\n:UNIT_TYPE: company\n:END:\n"))
    (let ((completion-styles '(partial-completion flex initials))
          (completion-ignore-case t)
          (label "Example Org / DigIT [IT]"))
      (dolist (input '("digit" "it"))
        (let ((prompts 0))
          (cl-letf (((symbol-function 'completing-read)
                     (lambda (_prompt candidates &rest _)
                       (cl-incf prompts)
                       (let* ((matches (completion-all-completions
                                        input candidates nil (length input)))
                              ;; Completion lists end with a base-size integer.
                              (labels (seq-take matches (safe-length matches))))
                         (should (member label labels)))
                       label))
                    ((symbol-function 'read-string) (lambda (&rest _) "New child"))
                    ((symbol-function 'nd/contacts)
                     (lambda (ids title)
                       (should (equal '("digit-id") ids))
                       (should (equal label title)))))
            (should (equal "[[id:digit-id][DigIT]]" (nd/read-organizational-unit)))
            (nd/list-contacts-by-org-unit)
            (with-current-buffer (find-file-noselect (nd/contact-file t))
              (nd/department-find-location)
              (should (equal "digit-id" (org-entry-get nil "ID")))))
          (should (= 3 prompts))))
      (should (equal '(partial-completion flex initials) completion-styles)))))

(ert-deftest nd/contacts-context-normalization ()
  (nd/test-with-contacts
    (cl-letf (((symbol-function 'completing-read) (lambda (&rest _) " :WORK: ")))
      (should (equal "work" (nd/read-contact-context))))))

(ert-deftest nd/contacts-directory-filter-and-refresh ()
  (nd/test-with-contacts
    (with-temp-buffer
      (nd/contacts-mode)
      (nd/contacts-refresh)
      (should (= 3 (length tabulated-list-entries)))
      (setq nd/contacts-unit-ids (nd/organization-subtree-ids "org-id"))
      (nd/contacts-refresh)
      (should (= 2 (length tabulated-list-entries)))
      (setq nd/contacts-context "private")
      (nd/contacts-refresh)
      (should-not tabulated-list-entries)
      (should (eq 'reference (nd/buffer-category))))))

(ert-deftest nd/contacts-focused-view-reuses-and-shares-text ()
  (nd/test-with-contacts
    (let* ((first (nd/contact-open "person-a"))
           (base (buffer-base-buffer first)))
      (should (eq first (nd/contact-open "person-a")))
      (with-current-buffer first
        (should (buffer-narrowed-p))
        (should (equal "person-a" (nd/contact-current-id)))
        (should-not (string-match-p "Casey" (buffer-string)))
        (goto-char (point-max))
        (insert "A shared edit.\n"))
      (with-current-buffer base
        (should (string-match-p "A shared edit" (buffer-string)))))))

(ert-deftest nd/contacts-history-exact-id-including-archives ()
  (nd/test-with-contacts
    (require 'xref)
    (nd/test-file "contact-fixtures/journal/2026.org"
                  "* Meeting\n:PROPERTIES:\n:ATTENDEES: [[id:person-a][Alex]]\n:END:\n[[id:person-a-extra][Different person]]\n")
    (nd/test-file "contact-fixtures/archive/old.org_archive"
                  "* Previous meeting\n[[id:person-a][Alex]]\n")
    (cl-letf (((symbol-function 'xref-show-xrefs)
               (lambda (fetcher _action)
                 (let ((hits (funcall fetcher)))
                   (should (= 2 (length hits)))
                   (should (seq-some
                            (lambda (hit)
                              (string-suffix-p ".org_archive"
                                               (xref-file-location-file (xref-item-location hit))))
                            hits))))))
      (nd/contact-history "person-a"))))

(ert-deftest nd/contacts-templates-use-canonical-property-names ()
  (let ((template (nth 4 (assoc "c" org-capture-templates))))
    (dolist (property '("ALIASES" "CONTEXT" "ORG_UNIT" "POSITION" "EMAIL" "TEL_MOBILE"))
      (should (string-search (concat ":" property ":") template)))
    (should-not (string-search ":NAME:" template))))

(ert-deftest nd/contacts-capture-asks-only-for-name ()
  (nd/test-with-contacts
    (let* ((template (copy-tree (assoc "c" org-capture-templates)))
           (org-capture-templates (list template))
           (org-capture-after-finalize-hook nil)
           prompts)
      (setf (nth 3 template) `(file+function ,(nd/contact-file nil) nd/contact-find-location))
      (cl-letf (((symbol-function 'read-string)
                 (lambda (prompt &rest _) (push prompt prompts) "Drew"))
                ((symbol-function 'completing-read)
                 (lambda (&rest _) (ert-fail "Unexpected metadata prompt"))))
        (org-capture nil "c")
        (insert "Met at the workshop.")
        (org-capture-finalize))
      (should (equal '("Name: ") prompts))
      (with-current-buffer (find-file-noselect (nd/contact-file nil))
        (nd/test-heading "Drew")
        (should (org-entry-get nil "ID"))
        (dolist (property '("CONTEXT" "ORG_UNIT" "POSITION" "EMAIL" "TEL_MOBILE"))
          (should (string-empty-p (or (org-entry-get nil property) ""))))))))

(ert-deftest nd/contacts-details-edit-one-field-from-person-view-or-directory ()
  (nd/test-with-contacts
    (nd/contact-open "person-a")
    (nd/test-heading "Notes")
    (cl-letf (((symbol-function 'read-string)
               (lambda (_prompt current &rest _)
                 (should (equal "Analyst" current)) "Coordinator")))
      (nd/contact-edit-details "Position"))
    (should (buffer-narrowed-p))
    (cl-letf (((symbol-function 'completing-read)
               (lambda (_prompt _candidates _predicate _match current &rest _)
                 (should (equal "work" current)) " :PRIVATE: ")))
      (nd/contact-edit-details "Context"))
    (cl-letf (((symbol-function 'nd/read-organizational-unit)
               (lambda (current)
                 (should (equal "[[id:team-id][Team]]" current))
                 "[[id:org-id][Example Org]]")))
      (nd/contact-edit-details "Organisation"))
    (nd/contacts)
    (set-buffer "*Contacts*")
    (goto-char (point-min))
    (while (and (not (eobp)) (not (equal "person-a" (tabulated-list-get-id)))) (forward-line))
    (should (equal "person-a" (tabulated-list-get-id)))
    (cl-letf (((symbol-function 'read-string)
               (lambda (_prompt current &rest _)
                 (should (equal "alex@example.invalid" current)) "")))
      (nd/contact-edit-details "Email"))
    (let ((person (seq-find (lambda (record) (equal "person-a" (plist-get record :id)))
                            (nd/contact-records))))
      (should (equal "Coordinator" (plist-get person :position)))
      (should (equal "private" (plist-get person :context)))
      (should (equal "[[id:org-id][Example Org]]" (plist-get person :unit)))
      (should (equal "" (plist-get person :email))))
    (with-current-buffer (find-file-noselect (nd/contact-file nil))
      (let ((before (buffer-string)))
        (nd/test-heading "Alex Example")
        (cl-letf (((symbol-function 'read-string) (lambda (&rest _) (signal 'quit nil))))
          (should (eq 'cancelled (condition-case nil (nd/contact-edit-details "Position")
                                  (quit 'cancelled)))))
        (should (equal before (buffer-string)))))))

(ert-deftest nd/contacts-capture-registers-target-id-without-rescanning-source ()
  (nd/test-with-contacts
    (let ((org-capture-templates
           (list (list "T" "Test contact" 'entry (list 'file (nd/contact-file nil))
                       "* Captured person\n:PROPERTIES:\n:ID: captured-person\n:END:\n%?")))
          (org-id-locations (make-hash-table :test 'equal))
          (org-id-locations-file (expand-file-name "test-ids" org-directory))
          (org-capture-after-finalize-hook nil))
      (org-capture nil "T")
      (org-capture-finalize)
      (should (equal (file-truename (nd/contact-file nil))
                     (file-truename (gethash "captured-person" org-id-locations)))))))

(defun nd/test-view (key)
  (switch-to-buffer "*scratch*")
  (org-agenda nil key)
  (with-current-buffer org-agenda-buffer-name
    (save-excursion
      (goto-char (point-min))
      (let (lines)
        (while (not (eobp))
          (unless (invisible-p (point))
            (push (buffer-substring-no-properties (line-beginning-position)
                                                 (line-end-position)) lines))
          (forward-line 1))
        (mapconcat #'identity (nreverse lines) "\n")))))

(defun nd/test-at (heading function)
  (with-current-buffer (find-file-noselect (expand-file-name "gtd/sigtuna.org" nd/test-root))
    (org-with-wide-buffer
     (goto-char (point-min))
     (search-forward heading)
     (beginning-of-line)
     (funcall function))))

(defmacro nd/test-with-navigation (&rest body)
  "Run BODY in an overview-folded file with a deeply nested task."
  (declare (indent 0) (debug t))
  `(let* ((file (nd/test-file
                "navigation/tasks.org"
                (concat
                 "#+startup: overview\n* ACTIVE Project :project:\nProject notes.\n"
                 "** Phase\nPhase notes.\n*** NEXT Target task\n"
                 ":PROPERTIES:\n:ID: navigation-task\n:END:\n"
                 ":LOGBOOK:\nA task log.\n:END:\nTask notes.\n"
                 "*** TODO Sibling task\nSibling notes.\n"
                 "** Other phase\n*** TODO Other phase task\n"
                 "* ACTIVE Other project :project:\n** TODO Other project task\n")))
          (org-agenda-files (list file))
          (org-id-locations (make-hash-table :test #'equal))
          (org-id-files nil)
          (org-inhibit-startup nil)
          (base (find-file-noselect file)))
     (org-id-add-location "navigation-task" file)
     (unwind-protect
         (save-window-excursion
           (switch-to-buffer base)
           (org-cycle-set-startup-visibility)
           ,@body)
       (with-current-buffer base (set-buffer-modified-p nil))
       (kill-buffer base))))

(defun nd/test-navigation-visibility ()
  "Check the task's outline and notes are visible, with other bodies folded."
  (dolist (text '("* ACTIVE Project" "** Phase" "*** NEXT Target task"
                  "Task notes." "*** TODO Sibling task" "** Other phase"))
    (save-excursion
      (goto-char (point-min))
      (search-forward text)
      (should-not (org-invisible-p (1- (point))))))
  (dolist (text '("Project notes." "Phase notes." ":ID: navigation-task"
                  "A task log." "Sibling notes." "Other phase task"
                  "Other project task"))
    (save-excursion
      (goto-char (point-min))
      (search-forward text)
      (should (org-invisible-p (1- (point)))))))

(ert-deftest nd/navigation-agenda-and-links-reveal-task-outline-and-notes ()
  (dolist (method '(agenda-switch agenda-goto id-link id-goto file-link))
    (ert-info ((format "Navigation method: %s" method))
      (nd/test-with-navigation
        (let ((before (buffer-string)))
          (save-excursion
            (search-forward "Target task")
            (should (org-invisible-p (point))))
          (pcase method
            ((or 'agenda-switch 'agenda-goto)
             (nd/test-view "N")
             (goto-char (point-min))
             (search-forward "Target task")
             (if (eq method 'agenda-switch) (org-agenda-switch-to) (org-agenda-goto)))
            ('id-link
             (switch-to-buffer "*scratch*")
             (org-link-open-from-string "[[id:navigation-task]]"))
            ('id-goto
             (switch-to-buffer "*scratch*")
             (org-id-goto "navigation-task"))
            ('file-link
             (switch-to-buffer "*scratch*")
             (org-link-open-from-string (format "[[file:%s::*Target task]]" file))))
          (should (eq base (current-buffer)))
          (should (equal "Target task" (org-get-heading t t t t)))
          (nd/test-navigation-visibility)
          (should (equal before (buffer-string)))
          (should-not (buffer-modified-p)))))))

(ert-deftest nd/navigation-reveal-preserves-point-and-sparse-tree-behaviour ()
  (nd/test-with-navigation
    (search-forward "Task notes.")
    (let ((position (point)))
      (org-fold-show-context 'link-search)
      (should (= position (point)))
      (nd/test-navigation-visibility))
    (org-cycle-set-startup-visibility)
    (goto-char (point-min))
    (search-forward "Target task")
    (beginning-of-line)
    (let ((org-fold-show-context-detail '((tags-tree . minimal))))
      (org-fold-show-context 'tags-tree))
    (should-not (org-invisible-p))
    (save-excursion
      (search-forward "Task notes.")
      (should (org-invisible-p (point))))))

(ert-deftest nd/navigation-links-into-drawers-keep-the-target-visible ()
  (nd/test-with-navigation
    (dolist (text '(":ID: navigation-task" "A task log."))
      (org-cycle-set-startup-visibility)
      (goto-char (point-min))
      (search-forward text)
      (let ((position (point)))
        (org-fold-show-context 'link-search)
        (should (= position (point)))
        (should-not (org-invisible-p (1- (point))))))))

(defmacro nd/test-with-project-portfolio (&rest body)
  "Run BODY with projects and nested NEXT tasks in an isolated agenda."
  (declare (indent 0) (debug t))
  `(let* ((file
           (nd/test-file
            "portfolio/work.org"
            (concat
             "* ACTIVE Same project :project:\n:PROPERTIES:\n:ID: parent-project\n:END:\n"
             "** Phase\n*** NEXT First action\n*** NEXT Future action\nSCHEDULED: <2099-01-01 Thu>\n"
             "*** TODO Later action\n*** DONE Finished action\n"
             "** Archive :ARCHIVE:\n*** NEXT Archived action\n"
             "** COMMENT Ignored\n*** NEXT Commented action\n"
             "** ACTIVE Same project :project:\n:PROPERTIES:\n:ID: nested-project\n:END:\n*** NEXT Nested action\n"
             "* ACTIVE Empty project :project:\n"
             "* PLAN Planned project :project:\n** NEXT Planned action\n"
             "* HOLD Held project :project:\n** NEXT Held action\n"
             "* COMPLETED Closed project :project:\n** NEXT Residual next\n"
             "* Legacy project :project:\n** NEXT Legacy action\n"
             "* NEXT Standalone action\n")))
          (org-agenda-files (list file)))
     (unwind-protect (save-window-excursion ,@body)
       (dolist (buffer (buffer-list))
         (when (and (buffer-live-p buffer)
                    (equal file (buffer-file-name (or (buffer-base-buffer buffer) buffer))))
           (with-current-buffer buffer (set-buffer-modified-p nil))
           (kill-buffer buffer))))))

(ert-deftest nd/projects-next-rows-group-by-project-and-retain-source-markers ()
  (nd/test-with-project-portfolio
    (let ((view (nd/test-view "P")))
      (dolist (excluded '("Later action" "Finished action" "Archived action"
                          "Commented action" "Standalone action"))
        (should-not (string-search excluded view))))
    (with-current-buffer org-agenda-buffer-name
      (goto-char (point-min))
      (let (owner owner-column tasks projects)
        (while (not (eobp))
          (let ((marker (org-get-at-bol 'org-hd-marker)))
            (when marker
              (let* ((column (save-excursion
                               (goto-char (text-property-any
                                           (point) (line-end-position) 'org-heading t))
                               (current-column)))
                     (projectp (org-with-point-at marker (nd/org-local-project-p))))
                (if projectp
                    (setq owner marker owner-column column projects (cons marker projects))
                  (should (> column owner-column))
                  (org-with-point-at marker
                    (should (equal "NEXT" (org-get-todo-state)))
                    (should (equal owner (nd/org-project-marker)))
                    (push (org-get-heading t t t t) tasks))))))
          (forward-line))
        (should (= 7 (length projects)))
        (should (equal (sort tasks #'string<)
                       (sort '("First action" "Future action" "Nested action" "Planned action"
                               "Held action" "Residual next" "Legacy action") #'string<)))))))

(ert-deftest nd/projects-next-rows-support-navigation-editing-and-refresh ()
  (nd/test-with-project-portfolio
    (nd/test-view "P")
    (with-current-buffer org-agenda-buffer-name
      (goto-char (point-min))
      (search-forward "Nested action")
      (beginning-of-line)
      (let ((marker (org-get-at-bol 'org-hd-marker))
            (indent (current-indentation)))
        (save-window-excursion
          (org-agenda-switch-to)
          (should (equal "Nested action" (org-get-heading t t t t))))
        (save-window-excursion
          (nd/org-open-project)
          (should (equal "nested-project" nd/org-project-view-id)))
        (org-agenda-schedule nil "2030-02-01")
        (should (= indent (current-indentation)))
        (should (equal marker (org-get-at-bol 'org-hd-marker)))
        (org-with-point-at marker
          (should (string-prefix-p "<2030-02-01" (org-entry-get nil "SCHEDULED"))))
        (let ((org-inhibit-logging t)) (org-agenda-todo "DONE"))
        (org-with-point-at marker (should (equal "DONE" (org-get-todo-state))))
        (should (= indent (current-indentation)))
        (org-agenda-redo)
        (should-not (string-search "Nested action" (buffer-string)))
        (should (string-search "Same project" (buffer-string)))
        (should (string-search "Future action" (buffer-string)))))))

(ert-deftest nd/work-next-availability ()
  (let ((view (nd/test-view "N")))
    (should (string-match-p "Available action" view))
    (should (string-match-p "Home action" view))
    (dolist (excluded '("Future action" "Held action" "Archived action" "Residual action"))
      (should-not (string-match-p excluded view)))))

(ert-deftest nd/work-commitments-survive-hold-and-domain-filter ()
  (dolist (key '("D" "wo"))
    (let ((view (nd/test-view key)))
      (dolist (included '("Appointment" "Held follow-up" "Held obligation"))
        (should (string-match-p included view)))
      (should-not (string-match-p "Residual action" view))))
  (should-not (string-match-p "Home action" (nd/test-view "wo"))))

(ert-deftest nd/work-review-preserves-all-capture-layouts ()
  (let ((view (nd/test-view "R")))
    (dolist (included '("Old capture" "New top-level capture" "Loose backlog"
                        "Deep standalone" "Unmonitored wait" "Residual action"
                        "Legacy root" "Current meeting" "Journal action"))
      (should (string-match-p included view)))
    (should-not (string-match-p "Resolved capture" view))))

(ert-deftest nd/work-coverage-needs-a-dated-wait ()
  (should (nd/test-at "* ACTIVE Pilot" #'nd/org-skip-covered-project))
  (should (nd/test-at "* ACTIVE Monitored project" #'nd/org-skip-covered-project))
  (should-not (nd/test-at "* ACTIVE Undated waiting project" #'nd/org-skip-covered-project))
  (should-not (nd/test-at "* ACTIVE Archived-next project" #'nd/org-skip-covered-project)))

(ert-deftest nd/work-project-type-does-not-inherit ()
  (nd/test-at "*** NEXT Available action"
              (lambda ()
                (should (member "sigtuna" (org-get-tags)))
                (should-not (member "project" (org-get-tags))))))

(ert-deftest nd/work-refile-destinations ()
  (should (nd/test-at "** Faser" #'nd/org-refile-target-p))
  (should (nd/test-at "* HOLD Held project" #'nd/org-refile-target-p))
  (should-not (nd/test-at "*** NEXT Available action" #'nd/org-refile-target-p))
  (should-not (nd/test-at "* COMPLETED Closed project" #'nd/org-refile-target-p)))

(defmacro nd/test-with-meeting-refile (journal &rest body)
  "Run BODY with isolated JOURNAL, source, target and other project buffers."
  (declare (indent 1) (debug t))
  `(let* ((org-directory (make-temp-file (expand-file-name "refile-" nd/test-root) t))
          (org-id-locations (make-hash-table :test 'equal))
          (org-id-files nil)
          (org-id-locations-file (expand-file-name "ids" org-directory))
          (org-bookmark-names-plist nil)
          (org-log-refile nil)
          (org-after-refile-insert-hook nil)
          (source (find-file-noselect
                   (nd/test-file (expand-file-name "journal/2026.org" org-directory)
                                 ,journal)))
          (target (find-file-noselect
                   (nd/test-file (expand-file-name "gtd/work.org" org-directory)
                                 "* ACTIVE Project :project:\n** Tasks\n")))
          (other (find-file-noselect
                  (nd/test-file (expand-file-name "gtd/other.org" org-directory)
                                "* ACTIVE Other project :project:\n")))
          (org-agenda-files (mapcar #'buffer-file-name (list source target other))))
     (unwind-protect
         (save-window-excursion ,@body)
       (dolist (buffer (list source target other))
         (when (buffer-live-p buffer)
           (with-current-buffer buffer (set-buffer-modified-p nil))
           (kill-buffer buffer))))))

(defun nd/test-heading (title)
  "Go to the heading named TITLE in the current buffer."
  (goto-char (point-min))
  (catch 'found
    (while (re-search-forward org-heading-regexp nil t)
      (beginning-of-line)
      (when (equal title (org-get-heading t t t t)) (throw 'found (point)))
      (forward-line))
    (error "No heading named %s" title)))

(defun nd/test-refile-location (buffer title)
  (with-current-buffer buffer
    (list title (buffer-file-name) nil (nd/test-heading title))))

(defun nd/test-refile-link-heading (id)
  "Find the plain heading linking to ID in the current buffer."
  (goto-char (point-min))
  (should (re-search-forward (concat "^\\*+ " (regexp-quote (concat "[[id:" id "]["))) nil t))
  (beginning-of-line)
  (should-not (org-get-todo-state))
  (should-not (org-id-get))
  (point))

(ert-deftest nd/refile-normal-command-does-not-add-meeting-links ()
  (dolist (view '(org agenda))
    (nd/test-with-meeting-refile
        "* Friday\n** Meeting :meeting:\n*** TODO Action\nDetails.\n*** TODO Later\n"
      (if (eq view 'org)
          (with-current-buffer source
            (nd/test-heading "Action")
            (org-refile nil nil (nd/test-refile-location target "Tasks")))
        (org-agenda nil "t")
        (with-current-buffer org-agenda-buffer-name
          (goto-char (point-min))
          (search-forward "TODO Action")
          (org-agenda-refile nil (nd/test-refile-location target "Tasks") t)))
      (with-current-buffer source
        (should (equal (buffer-string) "* Friday\n** Meeting :meeting:\n*** TODO Later\n")))
      (with-current-buffer target
        (nd/test-heading "Action")
        (should (equal "TODO" (org-get-todo-state)))
        (should (string-match-p "Details." (buffer-string))))
      (dolist (buffer (list source target))
        (with-current-buffer buffer
          (should-not (string-match-p "Backlink:\\|:ID:\\|\\[\\[id:" (buffer-string))))))))

(ert-deftest nd/refile-meeting-links-preserve-task-and-source-outline ()
  (nd/test-with-meeting-refile
      "* Friday\n** Planning meeting :meeting:\n:PROPERTIES:\n:ID: meeting-id\n:END:\nDecisions.\n*** Actions\nAction notes.\n**** TODO Before\nKeep this body.\n**** NEXT Send proposal\nSCHEDULED: <2026-09-21 Mon>\n:PROPERTIES:\n:ID: task-id\n:END:\n:LOGBOOK:\nExisting history.\n:END:\nTask details.\n***** TODO Check figures\n**** TODO After\nKeep this too.\n"
    (with-current-buffer source
      (nd/test-heading "Send proposal")
      (save-restriction
        (org-narrow-to-subtree)
        (nd/org-refile-with-meeting-links nil nil (nd/test-refile-location target "Tasks")))
      (should (equal (buffer-string)
                     "* Friday\n** Planning meeting :meeting:\n:PROPERTIES:\n:ID: meeting-id\n:END:\nDecisions.\n*** Actions\nAction notes.\n**** TODO Before\nKeep this body.\n**** [[id:task-id][Send proposal]]\n**** TODO After\nKeep this too.\n"))
      (nd/test-refile-link-heading "task-id")
      (should (= 4 (org-outline-level))))
    (with-current-buffer target
      (nd/test-heading "Send proposal")
      (should (equal "task-id" (org-entry-get nil "ID")))
      (should (equal "NEXT" (org-get-todo-state)))
      (should (equal "<2026-09-21 Mon>" (org-entry-get nil "SCHEDULED")))
      (should (nd/org-entry-links-to-id-p "meeting-id"))
      (should (string-match-p "Existing history." (buffer-string)))
      (should (string-match-p "Task details." (buffer-string)))
      (nd/test-heading "Check figures")
      (should (equal 4 (org-outline-level))))
    (should (equal (file-truename (buffer-file-name target))
                   (file-truename (gethash "task-id" org-id-locations))))))

(ert-deftest nd/refile-creates-missing-ids-and-retains-links-on-later-moves ()
  (nd/test-with-meeting-refile
      "* Friday\n** Meeting :meeting:\n*** Actions\n**** TODO Follow up\n"
    (with-current-buffer source
      (nd/test-heading "Follow up")
      (nd/org-refile-with-meeting-links nil nil (nd/test-refile-location target "Tasks")))
    (let ((meeting-id (with-current-buffer source
                        (nd/test-heading "Meeting") (org-id-get)))
          (task-id (with-current-buffer target
                     (nd/test-heading "Follow up") (org-id-get)))
          (journal-text (with-current-buffer source (buffer-string))))
      (should meeting-id)
      (should task-id)
      (with-current-buffer target
        (should (nd/org-entry-links-to-id-p meeting-id))
        (org-refile nil nil (nd/test-refile-location other "Other project"))
        (should-not (string-match-p "\\[\\[id:" (buffer-string))))
      (with-current-buffer other
        (nd/test-heading "Follow up")
        (should (equal task-id (org-id-get)))
        (should (nd/org-entry-links-to-id-p meeting-id)))
      (should (equal journal-text (with-current-buffer source (buffer-string))))
      (should (eq other (marker-buffer (org-id-find task-id 'marker))))
      (should (eq source (marker-buffer (org-id-find meeting-id 'marker)))))))

(ert-deftest nd/refile-reuses-backlink-and-preserves-other-references ()
  (nd/test-with-meeting-refile
      "* Friday\n** Meeting :meeting:\n:PROPERTIES:\n:ID: meeting-id\n:END:\n*** Actions\n- [[id:task-id][Original task label]]\n**** TODO Follow up\n:PROPERTIES:\n:ID: task-id\n:END:\nBacklink: [[id:meeting-id][Original meeting label]]\n"
    (with-current-buffer source
      (nd/test-heading "Follow up")
      (nd/org-refile-with-meeting-links nil nil (nd/test-refile-location target "Tasks"))
      (goto-char (point-min))
      (should (= 2 (how-many (regexp-quote "[[id:task-id]") (point-min) (point-max))))
      (should (string-match-p "Original task label" (buffer-string)))
      (nd/test-refile-link-heading "task-id")
      (should (= 4 (org-outline-level))))
    (with-current-buffer target
      (should (= 1 (how-many (regexp-quote "[[id:meeting-id]") (point-min) (point-max))))
      (should (string-match-p "Original meeting label" (buffer-string))))))

(ert-deftest nd/refile-multiple-actions-and-section ()
  (dolist (selection '(forward-region backward-region section))
    (nd/test-with-meeting-refile
        "* Friday\n** Meeting :meeting:\n*** Actions\n**** TODO One\n***** TODO Child\n**** WAIT Two\n**** TODO Three\n"
      (with-current-buffer source
        (let ((transient-mark-mode t))
          (if (eq selection 'section)
              (nd/test-heading "Actions")
            (let ((start (nd/test-heading "One"))
                  (end (nd/test-heading "Three")))
              (goto-char (if (eq selection 'forward-region) start end))
              (set-mark (if (eq selection 'forward-region) end start))
              (activate-mark)))
          (nd/org-refile-with-meeting-links nil nil (nd/test-refile-location target "Tasks"))))
      (dolist (title (if (eq selection 'section) '("One" "Two" "Three") '("One" "Two")))
        (let ((id (with-current-buffer target
                    (nd/test-heading title)
                    (should (search-forward "Backlink:" (nd/org-next-heading) t))
                    (org-id-get))))
          (should id)
          (unless (eq selection 'section)
            (with-current-buffer source
              (nd/test-refile-link-heading id)
              (should (= 4 (org-outline-level)))
              (should (org-up-heading-safe))
              (should (equal "Actions" (org-get-heading t t t t)))))))
      (with-current-buffer target
        (nd/test-heading "Child")
        (should-not (org-id-get)))
      (if (eq selection 'section)
          (let ((id (with-current-buffer target
                      (nd/test-heading "Actions") (org-id-get))))
            (should id)
            (with-current-buffer source
              (nd/test-refile-link-heading id)
              (should (= 3 (org-outline-level)))
              (should (= 1 (how-many (regexp-quote "[[id:") (point-min) (point-max))))))
        (with-current-buffer source
          (nd/test-heading "Actions")
          (outline-next-heading)
          (should (string-suffix-p "[One]]" (org-get-heading t t t t)))
          (outline-next-heading)
          (should (string-suffix-p "[Two]]" (org-get-heading t t t t)))
          (outline-next-heading)
          (should (equal "Three" (org-get-heading t t t t))))))))

(ert-deftest nd/refile-cancel-and-failure-do-not-add-links-or-ids ()
  (dolist (failure '(quit invalid-target))
    (nd/test-with-meeting-refile
        "* Friday\n** Meeting :meeting:\n*** TODO Action\n"
      (with-current-buffer source
        (nd/test-heading "Action")
        (let ((before (buffer-string)))
          (if (eq failure 'quit)
              (cl-letf (((symbol-function 'org-refile-get-location)
                         (lambda (&rest _) (signal 'quit nil))))
                (should (eq 'cancelled
                            (condition-case nil (nd/org-refile-with-meeting-links)
                              (quit 'cancelled)))))
            (should-error (nd/org-refile-with-meeting-links nil nil (nd/test-refile-location source "Action"))))
          (should (equal before (buffer-string)))
          (should-not (buffer-modified-p))))
      (should (= 0 (hash-table-count org-id-locations)))
      (with-current-buffer target (should-not (buffer-modified-p))))))

(ert-deftest nd/refile-copy-navigation-and-whole-meeting-keep-native-behaviour ()
  (dolist (operation '(copy keep navigate whole-meeting))
    (nd/test-with-meeting-refile
        "* Friday\n** Meeting :meeting:\n*** TODO Action\n"
      (with-current-buffer source
        (nd/test-heading (if (eq operation 'whole-meeting) "Meeting" "Action"))
        (let ((org-refile-keep (eq operation 'keep)))
          (nd/org-refile-with-meeting-links (pcase operation ('copy 3) ('navigate '(4)))
                      nil (nd/test-refile-location target "Tasks"))))
      (dolist (buffer (list source target))
        (with-current-buffer buffer
          (should-not (string-match-p "Backlink:\\|:ID:" (buffer-string))))))))

(ert-deftest nd/refile-within-meeting-and-nonmeeting-tasks-do-not-add-links ()
  (nd/test-with-meeting-refile
      "* Friday\n** Meeting :meeting:\n*** Actions\n**** TODO Action\n*** Later\n** Work log\n*** TODO Other action\n"
    (with-current-buffer source
      (let ((location (nd/test-refile-location source "Later")))
        (nd/test-heading "Action")
        (nd/org-refile-with-meeting-links nil nil location))
      (nd/test-heading "Other action")
      (nd/org-refile-with-meeting-links nil nil (nd/test-refile-location target "Tasks")))
    (dolist (buffer (list source target))
      (with-current-buffer buffer
        (should-not (string-match-p "Backlink:\\|:ID:" (buffer-string)))))))

(ert-deftest nd/refile-meeting-action-from-agenda ()
  (nd/test-with-meeting-refile
      "* Friday\n** Meeting :meeting:\n*** TODO Agenda action\n"
    (org-agenda nil "t")
    (with-current-buffer org-agenda-buffer-name
      (goto-char (point-min))
      (search-forward "Agenda action")
      (nd/org-agenda-refile-with-meeting-links nil (nd/test-refile-location target "Tasks") t))
    (let ((id (with-current-buffer target
                (nd/test-heading "Agenda action")
                (should (search-forward "Backlink:" nil t))
                (org-id-get))))
      (should id)
      (with-current-buffer source
        (nd/test-refile-link-heading id)
        (should (= 3 (org-outline-level)))))))

(ert-deftest nd/refile-agenda-opt-in-restores-normal-refiling ()
  (dolist (outcome '(success quit error))
    (nd/test-with-meeting-refile
        "* Friday\n** Meeting :meeting:\n*** TODO Linked action\n*** TODO Plain action\n"
      (org-agenda nil "t")
      (with-current-buffer org-agenda-buffer-name
        (goto-char (point-min))
        (search-forward "Linked action")
        (let ((original (symbol-function 'org-refile)))
          (if (eq outcome 'success)
              (nd/org-agenda-refile-with-meeting-links
               nil (nd/test-refile-location target "Tasks") t)
            (cl-letf (((symbol-function 'org-refile-get-location)
                       (lambda (&rest _) (signal outcome nil))))
              (should (eq 'cancelled
                          (condition-case nil
                              (nd/org-agenda-refile-with-meeting-links)
                            ((quit error) 'cancelled))))))
          (should (eq original (symbol-function 'org-refile))))
        (goto-char (point-min))
        (search-forward "Plain action")
        (org-agenda-refile nil (nd/test-refile-location other "Other project") t))
      (with-current-buffer other
        (nd/test-heading "Plain action")
        (should-not (org-id-get))
        (should-not (string-match-p "Backlink:" (buffer-string)))))))

(ert-deftest nd/refile-links-stay-at-source-when-moving-within-journal-file ()
  (dolist (layout '(before after adjacent))
    (nd/test-with-meeting-refile
        (concat (when (eq layout 'before) "* Destination\n")
                "* Friday\n** Meeting :meeting:\n:PROPERTIES:\n:ID: meeting-id\n:END:\n*** TODO First\n:PROPERTIES:\n:ID: first-id\n:END:\n*** TODO Second\n:PROPERTIES:\n:ID: second-id\n:END:\n"
                (when (eq layout 'after) "*** Context\nMeeting notes.\n* Destination\n"))
      (with-current-buffer source
        (let ((location (nd/test-refile-location source
                                                (if (eq layout 'adjacent)
                                                    "Friday" "Destination")))
              (transient-mark-mode t))
          (nd/test-heading "First")
          (set-mark (point))
          (nd/test-heading "Second")
          (org-end-of-subtree t t)
          (activate-mark)
          (nd/org-refile-with-meeting-links nil nil location))
        (nd/test-heading "Meeting")
        (outline-next-heading)
        (should (equal "[[id:first-id][First]]" (org-get-heading t t t t)))
        (should (= 3 (org-outline-level)))
        (outline-next-heading)
        (should (equal "[[id:second-id][Second]]" (org-get-heading t t t t)))
        (should (= 3 (org-outline-level)))
        (dolist (title '("First" "Second"))
          (nd/test-heading title)
          (should (equal "TODO" (org-get-todo-state)))
          (should (= 2 (org-outline-level)))
          (should (nd/org-entry-links-to-id-p "meeting-id")))))))

(ert-deftest nd/work-project-lookup-while-narrowed ()
  (nd/test-at "*** NEXT Available action"
              (lambda ()
                (save-restriction
                  (org-narrow-to-subtree)
                  (should (equal (nd/org-project-at-point) '("pilot-id" "Pilot")))))))

(ert-deftest nd/work-project-lookup-from-agenda ()
  (nd/test-view "N")
  (with-current-buffer org-agenda-buffer-name
    (goto-char (point-min))
    (re-search-forward "^ +sigtuna:.*NEXT Available action")
    (should (equal (nd/org-project-at-point) '("pilot-id" "Pilot")))))

(ert-deftest nd/work-meetings-match-exact-own-body-links ()
  (skip-unless (require 'org-ql nil t))
  (let ((org-ql-ask-unsafe-queries nil))
    (should (equal
             (sort (org-ql-select (nd/org-journal-files)
                     '(and (tags-local "meeting") (nd/org-entry-links-to-id-p "pilot-id"))
                     :action (lambda () (org-get-heading t t t t))) #'string<)
             '("Current meeting" "Historical meeting")))))

(ert-deftest nd/work-global-entry-clears-restrictions ()
  (nd/test-at "* ACTIVE Pilot" (lambda () (org-agenda-set-restriction-lock 'subtree)))
  (unwind-protect
      (progn
        (nd/org-today)
        (should (string-match-p "Home action"
                               (with-current-buffer org-agenda-buffer-name (buffer-string)))))
    (org-agenda-remove-restriction-lock t)))

(defvar org-journal-time-format)

(ert-deftest nd/capture-bottom-panel-preserves-and-restores-work-windows ()
  (dolist (split '(split-window-right split-window-below))
    (dolist (finish '(org-capture-finalize org-capture-kill))
      (save-window-excursion
        (delete-other-windows)
        (let* ((source (generate-new-buffer " *capture-source*"))
               (reference (generate-new-buffer " *capture-reference*"))
               (file (nd/test-file "capture-layout.org" ""))
               (org-capture-templates
                `(("T" "Test" entry (file ,file) "* %^{Title}\n%?")))
               (org-capture-after-finalize-hook nil)
               capture)
          (unwind-protect
              (progn
                (switch-to-buffer source)
                (let* ((origin (selected-window))
                       (neighbour (funcall split)))
                  (set-window-buffer neighbour reference)
                  (set-window-configuration (current-window-configuration))
                  (let ((layout (current-window-configuration)))
                    (cl-letf (((symbol-function 'completing-read)
                               (lambda (&rest _)
                                 ;; The preview must preserve the work windows too.
                                 (should (eq 'bottom (window-parameter nil 'window-side)))
                                 (should (eq source (window-buffer origin)))
                                 (should (eq reference (window-buffer neighbour)))
                                 "Panel capture")))
                      (org-capture nil "T"))
                    (setq capture (current-buffer))
                    (should org-capture-mode)
                    (should (buffer-base-buffer))
                    (should (= 3 (length (window-list))))
                    (should (eq 'bottom (window-parameter nil 'window-side)))
                    (should (= (window-total-width)
                               (window-total-width (frame-root-window))))
                    (should (eq source (window-buffer origin)))
                    (should (eq reference (window-buffer neighbour)))
                    (dolist (window (list origin neighbour))
                      (should (<= (nth 3 (window-edges window))
                                  (nth 1 (window-edges)))))
                    (insert "Text from the capture panel.")
                    (funcall finish)
                    (should-not (buffer-live-p capture))
                    (should (compare-window-configurations
                             layout (current-window-configuration)))
                    (with-current-buffer (find-file-noselect file)
                      (should (eq (not (null (string-search
                                             "Text from the capture panel."
                                             (buffer-string))))
                                  (eq finish 'org-capture-finalize)))))))
            (when (buffer-live-p capture)
              (with-current-buffer capture (org-capture-kill)))
            (kill-buffer source)
            (kill-buffer reference)
            (when-let* ((target (get-file-buffer file)))
              (with-current-buffer target (set-buffer-modified-p nil))
              (kill-buffer target))))))))

(ert-deftest nd/capture-inbox-opens-without-prompts ()
  (save-window-excursion
    (let* ((file (nd/test-file "capture-inbox.org" ""))
           (template (copy-tree (assoc "i" org-capture-templates)))
           (org-capture-templates (list template))
           (org-capture-after-finalize-hook nil))
      (setf (nth 3 template) `(file ,file))
      (cl-letf (((symbol-function 'read-string) (lambda (&rest _) (ert-fail "Unexpected prompt")))
                ((symbol-function 'completing-read-multiple) (lambda (&rest _) (ert-fail "Unexpected tags"))))
        (org-capture nil "i")
        (insert "Remember the proposal")
        (org-capture-finalize))
      (with-current-buffer (find-file-noselect file)
        (nd/test-heading "Remember the proposal")
        (should-not (org-get-todo-state))
        (should-not (org-get-tags nil t)))
      (kill-buffer (get-file-buffer file)))))

(ert-deftest nd/capture-notes-with-colliding-titles-and-paths-stay-separate ()
  (save-window-excursion
    (let* ((org-directory (make-temp-file (expand-file-name "note-captures-" nd/test-root) t))
           (org-capture-after-finalize-hook nil)
           ids)
      (unwind-protect
          (progn
            (dolist (key '("n" "n" "f"))
              (cl-letf (((symbol-function 'read-string) (lambda (&rest _) "Same title"))
                        ((symbol-function 'read-file-name)
                         (lambda (&rest _) (expand-file-name "same-title.org" (nd/notes-directory)))))
                (org-capture nil key)
                (insert (concat "Body from " key "."))
                (org-capture-finalize)))
            (should (equal '("same-title-2.org" "same-title-3.org" "same-title.org")
                           (directory-files (nd/notes-directory) nil "\\.org\\'")))
            (dolist (file (directory-files (nd/notes-directory) t "\\.org\\'"))
              (with-current-buffer (find-file-noselect file)
                (should (= 1 (how-many "^#\\+TITLE:" (point-min) (point-max))))
                (should (= 1 (how-many "^:ID:" (point-min) (point-max))))
                (goto-char (point-min))
                (re-search-forward "^:ID: +\\(.+\\)$")
                (push (match-string 1) ids)))
            (should (= 3 (length (delete-dups ids)))))
        (dolist (buffer (buffer-list))
          (when-let* ((file (buffer-local-value 'buffer-file-name buffer)))
            (when (file-in-directory-p file org-directory) (kill-buffer buffer))))))))

(ert-deftest nd/capture-note-names-handle-empty-slugs-and-unsaved-reservations ()
  (let ((org-directory (make-temp-file (expand-file-name "note-names-" nd/test-root) t)))
    (cl-letf (((symbol-function 'read-string) (lambda (&rest _) "   ")))
      (should-error (nd/note-capture-file) :type 'user-error))
    (should-not (file-exists-p (expand-file-name "notes" org-directory)))
    (cl-letf (((symbol-function 'read-string) (lambda (&rest _) "中文")))
      (should (equal (expand-file-name "notes/note.org" org-directory) (nd/note-capture-file))))
    (let* ((file (expand-file-name "notes/same.org" org-directory))
           (buffer (find-file-noselect file)))
      (unwind-protect
          (progn
            (should-not (file-exists-p file))
            (should (equal (expand-file-name "notes/same-2.org" org-directory)
                           (nd/unique-note-file file))))
        (kill-buffer buffer)))))

(ert-deftest nd/action-extraction-links-to-meeting-through-tagged-and-narrowed-sections ()
  (dolist (selection '(line region heading))
    (nd/test-with-meeting-refile
        "* Today :sigtuna:\n** Planning :meeting:\n*** Notes\nSend the proposal.\n**** Budget\nDiscuss estimates.\n"
      (let ((nd/inbox-file (nd/test-file (expand-file-name "inbox.org" org-directory) ""))
            (transient-mark-mode t)
            meeting-id)
        (with-current-buffer source
          (nd/test-heading "Notes")
          (org-narrow-to-subtree)
          (if (eq selection 'heading)
              (nd/test-heading "Budget")
            (forward-line)
            (when (eq selection 'region)
              (push-mark (point) t t)
              (end-of-line)))
          (nd/action-to-inbox)
          (should (buffer-narrowed-p))
          (nd/test-heading "Notes")
          (should-not (org-entry-get nil "ID"))
          (widen)
          (nd/test-heading "Planning")
          (setq meeting-id (org-entry-get nil "ID"))
          (should meeting-id))
        (with-current-buffer (find-file-noselect nd/inbox-file)
          (goto-char (point-min))
          (should (equal "TODO" (org-get-todo-state)))
          (should (nd/org-entry-links-to-id-p meeting-id))
          (should (string-search "][Planning]]" (buffer-string))))))))

(ert-deftest nd/meeting-capture-prompts-only-for-title-and-starts-in-notes ()
  (should (equal (nth 3 (assoc "jm" org-capture-templates))
                 '(function nd/org-journal-find-location)))
  (let* ((file (nd/test-file "capture-meeting.org" "* Today\n"))
         (target (find-file-noselect file))
         (org-journal-time-format "%H:%M ")
         (org-capture-after-finalize-hook nil)
         prompts)
    (unwind-protect
        (save-window-excursion
          (cl-letf (((symbol-function 'nd/org-journal-find-location)
                     (lambda () (set-buffer target) (goto-char (point-max))))
                    ((symbol-function 'read-string)
                     (lambda (&rest _) (ert-fail "Unexpected string prompt")))
                    ((symbol-function 'completing-read)
                     (lambda (prompt &rest _)
                       (should (string-match-p "Title" prompt))
                       (push prompt prompts)
                       "Planning"))
                    ((symbol-function 'completing-read-multiple)
                     (lambda (&rest _) (ert-fail "Unexpected metadata prompt"))))
            (org-capture nil "jm")
            (should (= 1 (length prompts)))
            (should (string-match-p "Title" (car prompts)))
            (should (equal "Notes" (org-get-heading t t t t)))
            (insert "A note taken during the meeting.\n")
            (cl-letf (((symbol-function 'completing-read-multiple)
                       (lambda (&rest _) '("Guest"))))
              (nd/org-meeting-details "Attendees"))
            (org-capture-finalize))
          (with-current-buffer target
            (goto-char (point-min))
            (re-search-forward "^\\*\\* .*Planning")
            (should (org-entry-get nil "ID"))
            (should (equal '("meeting" "unprocessed") (org-get-tags nil t)))
            (should (equal "Guest" (org-entry-get nil "ATTENDEES")))
            (should (string-search "A note taken during the meeting." (buffer-string)))))
      (when (buffer-live-p target)
        (with-current-buffer target (set-buffer-modified-p nil))
        (kill-buffer target))))
  (should-not (string-prefix-p "* TODO" (nth 4 (assoc "i" org-capture-templates)))))

(ert-deftest nd/meeting-attendee-edit-keeps-identities-guests-and-missing-contacts ()
  (nd/test-with-contacts
    (let ((current "[[id:person-b][Alex Example]], [[id:gone][Former, colleague]], Guest"))
      (cl-letf (((symbol-function 'completing-read-multiple)
                 (lambda (_prompt _candidates _predicate _match initial &rest _)
                   (should (string-search "private" initial))
                   (append (split-string initial ", " t) '("Al" "A Example")))))
        (should (equal (concat current ", [[id:person-a][Alex Example]]")
                       (nd/read-attendees current))))
      (cl-letf (((symbol-function 'completing-read-multiple) (lambda (&rest _) nil)))
        (should (equal "" (nd/read-attendees current)))))))

(ert-deftest nd/meeting-unit-edit-retains-current-and-can-clear ()
  (nd/test-with-contacts
    (dolist (current '("[[id:team-id][Team]]" "[[id:gone-unit][Former, unit]]"))
      (cl-letf (((symbol-function 'completing-read)
                 (lambda (_prompt _candidates _predicate _match initial &rest _) initial)))
        (should (equal current (nd/read-organizational-unit current)))))
    (cl-letf (((symbol-function 'completing-read) (lambda (&rest _) "")))
      (should (equal "" (nd/read-organizational-unit "[[id:team-id][Team]]"))))))

(ert-deftest nd/meeting-project-edit-retains-old-links-and-deduplicates ()
  (let ((current "[[id:retired-id][Old, project]]"))
    (cl-letf (((symbol-function 'completing-read-multiple)
               (lambda (_prompt candidates _predicate _match initial &rest _)
                 (let ((pilot (car (seq-find
                                    (lambda (pair) (equal "pilot-id" (nd/org-id-from-link (cdr pair))))
                                    candidates))))
                   (list initial pilot pilot)))))
      (should (equal (concat current ", [[id:pilot-id][sigtuna / Pilot]]")
                     (nd/org-read-project-links current))))))

(ert-deftest nd/meeting-project-edit-distinguishes-duplicate-names-and-keeps-closed-projects ()
  (let* ((org-directory (expand-file-name "project-choice-fixtures/" nd/test-root))
         (file (nd/test-file "project-choice-fixtures/gtd/work.org"
                            "* ACTIVE Same, name :project:\n:PROPERTIES:\n:ID: one\n:END:\n* ACTIVE Same, name :project:\n:PROPERTIES:\n:ID: two\n:END:\n* COMPLETED Closed :project:\n:PROPERTIES:\n:ID: closed\n:END:\n")))
    (unwind-protect
        (cl-letf (((symbol-function 'completing-read-multiple)
                   (lambda (_prompt candidates _predicate _match initial &rest _)
                     (should (= 3 (length (delete-dups (mapcar #'car candidates)))))
                     (let ((second (car (seq-find
                                         (lambda (pair) (equal "two" (nd/org-id-from-link (cdr pair))))
                                         candidates))))
                       (list initial second)))))
          (should (equal "[[id:closed][Closed]], [[id:two][work / Same, name]]"
                         (nd/org-read-project-links "[[id:closed][Closed]]"))))
      (when-let* ((buffer (get-file-buffer file))) (kill-buffer buffer)))))

(defmacro nd/test-with-meeting-details (&rest body)
  "Run BODY in a meeting buffer, initially inside its Notes section."
  (declare (indent 0) (debug t))
  `(with-temp-buffer
     (org-mode)
     (insert "* Today :sigtuna:\n** Planning :meeting:unprocessed:old:\n:PROPERTIES:\n:ID: meeting-id\n:ATTENDEES: Guest\n:ORG_UNIT: [[id:team-id][Team]]\n:END:\n[2026-09-21 Mon]\nProject: [[id:old-project][Old project]]\n\n*** Agenda\nAgenda text.\n*** Notes\nKeep these notes.\nProject: a literal note\n*** Decisions\nKeep these decisions.\n*** Actions\n**** TODO Follow up\n** Other meeting :meeting:\nProject: [[id:other-project][Other project]]\n")
     (nd/test-heading "Notes")
     (forward-line)
     ,@body))

(ert-deftest nd/meeting-details-edit-parent-while-narrowed-and-keep-other-fields ()
  (nd/test-with-meeting-details
    (org-narrow-to-subtree)
    (let ((before (buffer-string))
          (position (point)))
      (cl-letf (((symbol-function 'completing-read)
                 (lambda (&rest _) "Attendees"))
                ((symbol-function 'nd/read-attendees)
                 (lambda (current) (should (equal "Guest" current)) "Guest, Another guest")))
        (call-interactively #'nd/org-meeting-details))
      (should (buffer-narrowed-p))
      (should (= position (- (point) (length ", Another guest"))))
      (should (equal before (buffer-string))))
    (widen)
    (nd/test-heading "Planning")
    (should (equal "Guest, Another guest" (org-entry-get nil "ATTENDEES")))
    (should (equal "[[id:team-id][Team]]" (org-entry-get nil "ORG_UNIT")))
    (should (equal '("meeting" "old" "unprocessed") (sort (org-get-tags nil t) #'string<)))))

(ert-deftest nd/meeting-details-projects-stay-in-own-body-and-allow-clearing ()
  (dolist (missing '(nil t))
    (nd/test-with-meeting-details
      (save-excursion
        (goto-char (point-min))
        (re-search-forward "^Project:")
        (beginning-of-line)
        (insert "#+begin_example\nProject: leave this example alone\n#+end_example\n"))
      (when missing
        (save-excursion
          (goto-char (point-min))
          (re-search-forward "^Project: \\[\\[id:old-project.*\n")
          (replace-match "")))
      (cl-letf (((symbol-function 'nd/org-read-project-links)
                 (lambda (current)
                   (should (equal (unless missing "[[id:old-project][Old project]]") current))
                   "[[id:pilot-id][Pilot]]")))
        (nd/org-meeting-details "Projects"))
      (save-excursion
        (nd/test-heading "Planning")
        (should (nd/org-entry-links-to-id-p "pilot-id")))
      (should (string-search "Project: a literal note" (buffer-string)))
      (should (string-search "Project: leave this example alone" (buffer-string)))
      (should (string-search "Project: [[id:other-project][Other project]]" (buffer-string)))
      (cl-letf (((symbol-function 'nd/org-read-project-links) (lambda (_) "")))
        (nd/org-meeting-details "Projects"))
      (nd/test-heading "Planning")
      (should-not (nd/org-entry-links-to-id-p "pilot-id")))))

(ert-deftest nd/meeting-details-tags-preserve-review-status-without-inherited-tags ()
  (dolist (reviewed '(nil t))
    (nd/test-with-meeting-details
      (when reviewed
        (save-excursion (nd/test-heading "Planning") (org-set-tags '("meeting" "old"))))
      (cl-letf (((symbol-function 'completing-read-multiple)
                 (lambda (_prompt _candidates _predicate _match initial &rest _)
                   (should (equal "old" initial))
                   '("new"))))
        (nd/org-meeting-details "Tags"))
      (nd/test-heading "Planning")
      (should (equal (if reviewed '("meeting" "new") '("meeting" "new" "unprocessed"))
                     (sort (org-get-tags nil t) #'string<))))))

(ert-deftest nd/meeting-details-cancel-and-nonmeeting-leave-text-unchanged ()
  (nd/test-with-meeting-details
    (let ((before (buffer-string)))
      (dolist (field '("Attendees" "Organisation" "Projects" "Tags"))
        (cl-letf (((symbol-function 'completing-read) (lambda (&rest _) (signal 'quit nil)))
                  ((symbol-function 'completing-read-multiple) (lambda (&rest _) (signal 'quit nil))))
          (should (eq 'cancelled (condition-case nil (nd/org-meeting-details field)
                                  (quit 'cancelled)))))
        (should (equal before (buffer-string))))
      (goto-char (point-min))
      (should-error (nd/org-meeting-details "Attendees") :type 'user-error)
      (should (equal before (buffer-string))))))

(ert-deftest nd/meeting-details-from-agenda-edits-source ()
  (nd/test-with-meeting-details
    (let ((source (current-buffer))
          (marker (point-marker)) refreshed)
      (with-temp-buffer
        (org-agenda-mode)
        (let ((inhibit-read-only t))
          (insert (propertize "Planning\n" 'org-hd-marker marker)))
        (goto-char (point-min))
        (cl-letf (((symbol-function 'nd/read-attendees) (lambda (_) "Agenda guest"))
                  ((symbol-function 'org-agenda-redo) (lambda (&rest _) (setq refreshed t))))
          (nd/org-meeting-details "Attendees")))
      (should refreshed)
      (with-current-buffer source
        (nd/test-heading "Planning")
        (should (equal "Agenda guest" (org-entry-get nil "ATTENDEES")))))))

(ert-deftest nd/work-task-and-project-states-are-separate ()
  (should (member "WAIT(w@/!)" (car org-todo-keywords)))
  (should-not (member "WAIT(w@/!)" (cadr org-todo-keywords)))
  (should (member "PLAN(p)" (cadr org-todo-keywords)))
  (should (member "HOLD(h)" (cadr org-todo-keywords))))

(ert-deftest nd/edit-save-preserves-unfinished-org-entries ()
  (should-not (memq #'delete-trailing-whitespace before-save-hook))
  (dolist (text '("+ " "  - " "1. " "- [ ] " "* " "** " "*** TODO "))
    (with-temp-buffer
      (org-mode)
      (insert text)
      (let ((position (point)))
        (run-hooks 'before-save-hook)
        (should (= position (point)))
        (should (equal text (buffer-string)))))))

(ert-deftest nd/edit-auto-save-only-local-org-files-within-org-directory ()
  (let* ((root (make-temp-file (expand-file-name "auto-save-" nd/test-root) t))
         (org-directory (expand-file-name "org/" root))
         (make-backup-files nil)
         buffers)
    (unwind-protect
        (progn
          (dolist (name '("org/note.org" "org/code.el" "outside.org"))
            (let* ((file (nd/test-file (expand-file-name name root) "Original\n"))
                   (buffer (find-file-noselect file)))
              (push buffer buffers)
              (with-current-buffer buffer
                (goto-char (point-max))
                (insert "Pending change\n"))))
          (save-some-buffers t (lambda () (and (memq (current-buffer) buffers)
                                              (funcall auto-save-visited-predicate))))
          (dolist (buffer buffers)
            (with-current-buffer buffer
              (should (eq (buffer-modified-p) (not (string-suffix-p "/note.org" buffer-file-name))))))
          (make-symbolic-link (expand-file-name "outside.org" root)
                              (expand-file-name "escape.org" org-directory))
          (with-temp-buffer
            (org-mode)
            (dolist (file (list nil "/ssh:example.invalid:/notes.org"
                               (expand-file-name "escape.org" org-directory)))
              (setq buffer-file-name file)
              (should-not (nd/org-auto-save-p)))))
      (dolist (buffer buffers)
        (with-current-buffer buffer (set-buffer-modified-p nil))
        (kill-buffer buffer)))))

(ert-deftest nd/edit-save-still-cleans-non-org-buffers ()
  (with-temp-buffer
    (emacs-lisp-mode)
    (insert "(message \"hello\")   \n")
    (run-hooks 'before-save-hook)
    (should (equal (buffer-string) "(message \"hello\")\n"))))

(ert-deftest nd/edit-list-meta-return-keeps-whole-items ()
  ;; The vertical bar marks point before M-RET.
  (dolist (case '(("- Buy |milk and bread\n- Next item\n"
                   "- Buy milk and bread\n- \n- Next item\n")
                  ("- Parent |item\n  continuation text\n- Next item\n"
                   "- Parent item\n  continuation text\n- \n- Next item\n")
                  ("- Parent |item\n  - Child one\n  - Child two\n- Next item\n"
                   "- Parent item\n  - Child one\n  - Child two\n- \n- Next item\n")
                  ("- Parent item\n  - Child |one\n  - Child two\n"
                   "- Parent item\n  - Child one\n  - \n  - Child two\n")
                  ("- |Original item\n- Next item\n"
                   "- \n- Original item\n- Next item\n")
                  ("1. First |item\n2. Second\n"
                   "1. First item\n2. \n3. Second\n")))
    (with-temp-buffer
      (org-mode)
      (insert (car case))
      (goto-char (point-min))
      (search-forward "|")
      (delete-char -1)
      (org-meta-return)
      (should (equal (buffer-string) (cadr case))))))

(ert-deftest nd/edit-checkbox-insertion-keeps-item-text ()
  (with-temp-buffer
    (org-mode)
    (insert "- [ ] Buy milk and bread\n")
    (goto-char (point-min))
    (search-forward "Buy ")
    ;; M-S-RET uses the same no-splitting rule for a new checkbox.
    (org-insert-todo-heading nil)
    (should (equal (buffer-string) "- [ ] Buy milk and bread\n- [ ] \n"))))

(ert-deftest nd/edit-meta-return-still-splits-headings-and-tables ()
  (should (org-get-alist-option org-M-RET-may-split-line 'headline))
  (should (org-get-alist-option org-M-RET-may-split-line 'table))
  (with-temp-buffer
    (org-mode)
    (insert "* Heading with remaining text\n")
    (goto-char (point-min))
    (search-forward "Heading ")
    (org-meta-return)
    (should (equal (buffer-string) "* Heading \n* with remaining text\n"))))

(defmacro nd/test-with-project-buffer (&rest body)
  "Run BODY with a disposable project file BASE and a place for VIEW."
  (declare (indent 0) (debug t))
  `(save-window-excursion
     (let ((base (find-file-noselect
                  (nd/test-file "view-fixtures/projects.org"
                   "* ACTIVE Sample :project:\n:PROPERTIES:\n:ID: sample-id\n:END:\nResume card.\n** Section\n*** NEXT Task\nTask details.\n* ACTIVE Another :project:\n:PROPERTIES:\n:ID: another-id\n:END:\n** NEXT Other task\n")))
           view)
       (unwind-protect
           (progn (switch-to-buffer base) (goto-char (point-min)) ,@body)
         (dolist (buffer (buffer-list))
           (when (eq (buffer-base-buffer buffer) base) (kill-buffer buffer)))
         (when (buffer-live-p base)
           (with-current-buffer base (set-buffer-modified-p nil))
           (kill-buffer base))))))

(ert-deftest nd/waiting-selects-contact-alias-or-guest-and-retains-missing-contact ()
  (nd/test-with-contacts
    (dolist (case '(("Al" nil "[[id:person-a][Alex Example]]")
                    ("Visiting expert" nil "Visiting expert")
                    ("Former colleague" "[[id:missing][Former colleague]]"
                     "[[id:missing][Former colleague]]")))
      (cl-letf (((symbol-function 'completing-read) (lambda (&rest _) (car case))))
        (should (equal (nth 2 case) (nd/read-waiting-for (nth 1 case))))))
    (cl-letf (((symbol-function 'completing-read) (lambda (&rest _) " ")))
      (should-error (nd/read-waiting-for) :type 'user-error))))

(ert-deftest nd/waiting-updates-task-from-narrowed-view-and-agenda ()
  (dolist (context '(org agenda))
    (nd/test-with-project-buffer
      (let ((org-agenda-files (list (buffer-file-name base))))
        (nd/test-heading "Task")
        (org-entry-put nil "WAITING_FOR" "Previous owner")
        (org-schedule nil "2026-09-23")
        (if (eq context 'org)
            (org-narrow-to-subtree)
          (org-agenda nil "t")
          (goto-char (point-min))
          (search-forward "NEXT Task"))
        (cl-letf (((symbol-function 'nd/read-waiting-for)
                   (lambda (current)
                     (should (equal "Previous owner" current))
                     "[[id:person-a][Alex Example]]"))
                  ((symbol-function 'org-read-date)
                   (lambda (&rest args)
                     ;; org-schedule also parses the supplied date.
                     (if (equal (nth 3 args) "Follow up: ")
                         (progn
                           (should (equal "2026-09-23" (format-time-string "%F" (nth 4 args))))
                           "2026-09-25")
                       (apply nd/test-original-read-date args)))))
          (nd/org-waiting-for))
        (when (eq context 'org) (should (buffer-narrowed-p)))
        (with-current-buffer base
          (save-restriction
            (widen)
            (nd/test-heading "Task")
            (should (equal "WAIT" (org-get-todo-state)))
            (should (equal "[[id:person-a][Alex Example]]" (org-entry-get nil "WAITING_FOR")))
            (should (string-prefix-p "<2026-09-25" (org-entry-get nil "SCHEDULED")))
            (should (search-forward "Task details." nil t))))
        (org-agenda nil "W")
        (should (string-match-p "Alex Example · 2026-09-25" (buffer-string)))
        (should (string-match-p "WAIT Task" (buffer-string)))))))

(defvar nd/test-original-read-date (symbol-function 'org-read-date))

(ert-deftest nd/waiting-cancellation-and-invalid-targets-preserve-text ()
  (nd/test-with-project-buffer
    (nd/test-heading "Task")
    (let ((before (buffer-string)))
      (cl-letf (((symbol-function 'nd/read-waiting-for) (lambda (&rest _) "Guest"))
                ((symbol-function 'org-read-date) (lambda (&rest _) (signal 'quit nil))))
        (should (eq 'cancelled (condition-case nil (nd/org-waiting-for) (quit 'cancelled)))))
      (should (equal before (buffer-string)))
      (should-not (buffer-modified-p)))
    (nd/test-heading "Sample")
    (should-error (nd/org-waiting-for) :type 'user-error)
    (nd/test-heading "Task")
    (let ((org-inhibit-logging t)) (org-todo "DONE"))
    (should-error (nd/org-waiting-for) :type 'user-error)))

(ert-deftest nd/waiting-review-shows-missing-owner-and-date ()
  (nd/test-with-project-buffer
    (let ((org-agenda-files (list (buffer-file-name base))))
      (nd/test-heading "Task")
      (let ((org-inhibit-logging t)) (org-todo "WAIT"))
      (org-agenda nil "R")
      (should (string-match-p "owner missing · no follow-up | WAIT Task" (buffer-string))))))

(ert-deftest nd/project-update-adds-card-and-preserves-view-and-children ()
  (nd/test-with-project-buffer
    (setq view (nd/org-open-project))
    (nd/test-heading "Task")
    (org-narrow-to-subtree)
    (let ((children (buffer-string)))
      (cl-letf (((symbol-function 'read-string)
                 (lambda (prompt current &rest _)
                   (should-not current)
                   (if (equal prompt "Nuläge: ") "Plan agreed" "Ask for estimate"))))
        (nd/org-project-update))
      (should (buffer-narrowed-p))
      (should (equal children (buffer-string))))
    (with-current-buffer base
      (goto-char (point-min))
      (should (equal "Plan agreed" (cdr (nd/org-project-summary-field "Nuläge"))))
      (should (equal "Ask for estimate" (cdr (nd/org-project-summary-field "Återuppta"))))
      (should (string-prefix-p "[" (cdr (nd/org-project-summary-field "Uppdaterad"))))
      (should (string-match-p "Resume card." (buffer-string)))
      (should (= 1 (how-many "^Nuläge:" (point-min) (point-max)))))))

(ert-deftest nd/project-update-edits-own-card-from-agenda-and-ignores-examples ()
  (nd/test-with-project-buffer
    (goto-char (point-min))
    (org-end-of-meta-data t)
    (insert "#+begin_example\nNuläge: Example\n#+end_example\nNuläge: Old status\nÅteruppta: Old step\nUppdaterad: [2020-01-01 Wed]\n")
    (nd/test-heading "Task")
    (org-end-of-meta-data t)
    (insert "Nuläge: Child status\n")
    (let ((org-agenda-files (list (buffer-file-name base))))
      (org-agenda nil "t")
      (goto-char (point-min))
      (search-forward "NEXT Task")
      (cl-letf (((symbol-function 'read-string)
                 (lambda (prompt current &rest _)
                   (if (equal prompt "Nuläge: ")
                       (progn (should (equal "Old status" current)) "New status")
                     (should (equal "Old step" current)) "New step"))))
        (nd/org-project-update)))
    (with-current-buffer base
      (goto-char (point-min))
      (should (equal "New status" (cdr (nd/org-project-summary-field "Nuläge"))))
      (should (equal "New step" (cdr (nd/org-project-summary-field "Återuppta"))))
      (should-not (equal "[2020-01-01 Wed]" (cdr (nd/org-project-summary-field "Uppdaterad"))))
      (should (string-match-p "Nuläge: Example" (buffer-string)))
      (should (string-match-p "Nuläge: Child status" (buffer-string))))))

(ert-deftest nd/project-update-no-change-or-cancellation-keeps-timestamp-and-text ()
  (nd/test-with-project-buffer
    (org-end-of-meta-data t)
    (insert "Nuläge: Current\nÅteruppta: Next\nUppdaterad: [2020-01-01 Wed]\n")
    (nd/test-heading "Task")
    (let ((before (buffer-string)))
      (cl-letf (((symbol-function 'read-string) (lambda (_prompt current &rest _) current)))
        (nd/org-project-update))
      (should (equal before (buffer-string)))
      (cl-letf (((symbol-function 'read-string)
                 (lambda (prompt &rest _)
                   (if (equal prompt "Nuläge: ") "Changed" (signal 'quit nil)))))
        (should (eq 'cancelled (condition-case nil (nd/org-project-update) (quit 'cancelled)))))
      (should (equal before (buffer-string))))))

(ert-deftest nd/edit-auto-save-preserves-project-view-entry-spaces ()
  (nd/test-with-project-buffer
    (setq view (nd/org-open-project))
    (goto-char (point-max))
    (insert "** Draft\n+ \n** \n")
    (backward-char)
    (let ((position (point))
          (make-backup-files nil))
      ;; The idle auto-save timer calls save-some-buffers on file buffers.
      ;; Restrict this test to the base file behind our indirect view.
      (save-some-buffers t (lambda () (and (eq (current-buffer) base)
                                          (funcall auto-save-visited-predicate))))
      (should (= position (point)))
      (should-not (buffer-modified-p base))
      (with-temp-buffer
        (insert-file-contents (buffer-file-name base))
        (should (search-forward "** Draft\n+ \n** \n" nil t))))))

(ert-deftest nd/buffers-project-view-reuses-and-shares-edits ()
  (nd/test-with-project-buffer
    (search-forward "*** NEXT Task")
    (beginning-of-line)
    (org-narrow-to-subtree)
    (let ((position (point)) (start (point-min)) (end (point-max)))
      (setq view (nd/org-open-project))
      (should (eq (current-buffer) view))
      (should (eq (buffer-base-buffer) base))
      (should (string-prefix-p "*Project: projects / Sample*" (buffer-name)))
      (should (looking-at "\\* ACTIVE Sample"))
      (should-not (string-match-p "Other task" (buffer-string)))
      (with-current-buffer base
        (should (= position (point)))
        (should (= start (point-min)))
        (should (= end (point-max))))
      (search-forward "Task details.")
      (let ((resume (point)))
        (should (eq view (nd/org-open-project)))
        (should (= resume (point))))
      (insert " Shared edit.")
      (with-current-buffer base
        (should (string-match-p "Shared edit" (buffer-string)))
        (should (buffer-modified-p)))
      (should (= 1 (length (seq-filter (lambda (buffer)
                                        (eq (buffer-base-buffer buffer) base))
                                      (buffer-list)))))
      (kill-buffer view)
      (should (buffer-live-p base))
      (with-current-buffer base
        (should (buffer-modified-p))
        (should (string-match-p "Shared edit" (buffer-string)))))))

(ert-deftest nd/buffers-project-view-refreshes-title-and-bounds ()
  (nd/test-with-project-buffer
    (setq view (nd/org-open-project))
    (with-current-buffer base
      (goto-char (point-min))
      (org-edit-headline "Renamed")
      (search-forward "* ACTIVE Another")
      (beginning-of-line)
      (insert "** NEXT Added from source\n")
      (goto-char (point-min))
      (should (eq view (nd/org-open-project))))
    (with-current-buffer view
      (should (equal (buffer-name) "*Project: projects / Renamed*"))
      (should (string-match-p "Added from source" (buffer-string)))
      (should-not (string-match-p "Other task" (buffer-string))))
    (with-current-buffer base
      (goto-char (point-max))
      (search-backward "** NEXT Other task")
      (let ((other (nd/org-open-project)))
        (should-not (eq other view))
        (should (equal (buffer-local-value 'nd/org-project-view-id other) "another-id"))
        (should (buffer-live-p view))))))

(ert-deftest nd/buffers-project-folds-are-independent ()
  (nd/test-with-project-buffer
    (org-fold-hide-subtree)
    (let ((card (save-excursion (search-forward "Resume card.") (point))))
      (should (org-invisible-p card))
      (setq view (nd/org-open-project))
      (should-not (org-invisible-p card))
      (with-current-buffer base (should (org-invisible-p card)))
      (org-fold-show-all)
      (with-current-buffer base (should (org-invisible-p card))))))

(ert-deftest nd/buffers-project-views-distinguish-duplicate-titles ()
  (nd/test-with-project-buffer
    (setq view (nd/org-open-project))
    (with-current-buffer base
      (goto-char (point-max))
      (search-backward "* ACTIVE Another")
      (org-edit-headline "Sample")
      (let* ((other (nd/org-open-project)) (name (buffer-name other)))
        (should-not (eq other view))
        (with-current-buffer other
          (should (eq other (nd/org-open-project)))
          (should (equal name (buffer-name))))))))

(ert-deftest nd/buffers-project-view-from-agenda ()
  (save-window-excursion
    (nd/test-view "N")
    (goto-char (point-min))
    (re-search-forward "^ +sigtuna:.*NEXT Available action")
    (let ((view (nd/org-open-project)))
      (unwind-protect
          (progn
            (should (eq view (current-buffer)))
            (should (equal nd/org-project-view-id "pilot-id"))
            (should (eq (nd/buffer-category) 'tasks))
            (should (string-match-p "Available action" (buffer-string)))
            (should-not (string-match-p "Held action" (buffer-string))))
        (kill-buffer view)))))

(ert-deftest nd/buffers-project-view-refuses-missing-id-and-nonprojects ()
  (with-temp-buffer
    (org-mode)
    (insert "* No project\n** TODO Task\n* Project without ID :project:\n")
    (goto-char (point-min))
    (should-error (nd/org-open-project) :type 'user-error)
    (search-forward "Project without ID")
    (let ((buffers (buffer-list)))
      (should-error (nd/org-open-project) :type 'user-error)
      (should (equal buffers (buffer-list))))
    (should-not (org-entry-get nil "ID"))))

(ert-deftest nd/buffers-agenda-preserves-and-restores-window-layout ()
  (should (eq org-agenda-window-setup 'current-window))
  (should org-agenda-restore-windows-after-quit)
  (save-window-excursion
    (delete-other-windows)
    (switch-to-buffer "*scratch*")
    (let* ((origin (selected-window))
           (neighbour (split-window-right))
           (reference (get-buffer-create " *agenda-window-test*")))
      (unwind-protect
          (progn
            (set-window-buffer neighbour reference)
            ;; Batch Emacs initially counts the minibuffer in root height.
            ;; Normalize that once before comparing restored geometry.
            (set-window-configuration (current-window-configuration))
            (let ((layout (current-window-configuration)))
              (nd/org-today)
              (should (eq origin (selected-window)))
              (should (= 2 (length (window-list))))
              (should (eq reference (window-buffer neighbour)))
              (org-agenda-quit)
              (should (compare-window-configurations layout (current-window-configuration)))))
        (kill-buffer reference)))))

(ert-deftest nd/buffers-ibuffer-renders-full-project-names ()
  (let ((project (generate-new-buffer
                  "*Project: sigtuna / Ett långt projektnamn som är längre än fyrtioåtta tecken*")))
    (unwind-protect
        (with-temp-buffer
          (ibuffer-mode)
          (dotimes (format (length ibuffer-formats))
            (setq ibuffer-current-format format)
            (ibuffer-update nil t)
            (goto-char (point-min))
            (should (search-forward (buffer-name project) nil t))))
      (kill-buffer project))))

(ert-deftest nd/buffers-ibuffer-groups-by-purpose-without-dropping-files ()
  (with-temp-buffer
    (ibuffer-mode)
    (should-not ibuffer-show-empty-filter-groups)
    (let ((groups ibuffer-filter-groups)
          (user-emacs-directory (expand-file-name "config/" nd/test-root)))
      (dolist (spec '(("inbox.org" org-mode "Tasks & projects")
                      ("gtd/sigtuna.org" org-mode "Tasks & projects")
                      ("journal/2026.org" org-mode "Journals")
                      ("notes/idea.org" org-mode "Notes")
                      ("ref/templates/project.org" org-mode "Reference")
                      ("config/config.org" org-mode "Code & config")
                      ("src/test.el" emacs-lisp-mode "Code & config")
                      (nil fundamental-mode "Utilities")
                      ("notes-other/file.org" org-mode nil)
                      ("archive/closed.org" org-mode nil)))
        (with-temp-buffer
          (funcall (nth 1 spec))
          (setq buffer-file-name (and (car spec) (expand-file-name (car spec) nd/test-root)))
          (let ((matches (seq-filter
                          (lambda (group)
                            (ibuffer-included-in-filters-p (current-buffer) (cdr group)))
                          groups)))
            (should (equal (mapcar #'car matches)
                           (and (nth 2 spec) (list (nth 2 spec)))))))))))
