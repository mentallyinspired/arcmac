;;; init.el --- tangled from config.org -*- lexical-binding: t -*-
;; Edit config.org, not this file.

;; Declared before the local file loads so its setq wins (defvar only
;; sets unbound variables).
(defvar nd/font-size 16
  "Default face font size in PIXELS; per machine via arcmac-local.el.")

(defvar nd/mail-accounts nil
  "List of mail accounts (NAME ADDRESS KEY), primary account first
\(see mail.nix); KEY jumps to the inbox saved search.  Set in
arcmac-local.el.")

(load (expand-file-name "arcmac-local.el"
                        (or (getenv "XDG_CONFIG_HOME") "~/.config"))
      t)

(defvar my/state-dir
  (expand-file-name "arcmac/"
                    (or (getenv "XDG_STATE_HOME") "~/.local/state"))
  "Runtime state directory, kept out of the git checkout.")

(make-directory (expand-file-name "auto-saves/" my/state-dir) t)

(setq custom-file (expand-file-name "custom.el" my/state-dir))
(when (file-exists-p custom-file)
  (load custom-file))

(setq backup-directory-alist
      `(("." . ,(expand-file-name "backups/" my/state-dir)))
      auto-save-file-name-transforms
      `((".*" ,(expand-file-name "auto-saves/" my/state-dir) t))
      create-lockfiles nil)

;; Everything else that defaults to user-emacs-directory. These must be
;; set BEFORE the modes are enabled (they are — see Built-in defaults).
(setq savehist-file          (expand-file-name "history" my/state-dir)
      save-place-file        (expand-file-name "places.eld" my/state-dir)
      recentf-save-file      (expand-file-name "recentf.eld" my/state-dir)
      bookmark-default-file  (expand-file-name "bookmarks.eld" my/state-dir)
      project-list-file      (expand-file-name "projects.eld" my/state-dir)
      tramp-persistency-file-name (expand-file-name "tramp" my/state-dir)
      transient-levels-file  (expand-file-name "transient/levels.el" my/state-dir)
      transient-values-file  (expand-file-name "transient/values.el" my/state-dir)
      transient-history-file (expand-file-name "transient/history.el" my/state-dir))

(savehist-mode 1)                 ; minibuffer history across sessions
(save-place-mode 1)               ; reopen files at point
(recentf-mode 1)
(electric-pair-mode 1)
(which-key-mode 1)                ; built-in since Emacs 30
(repeat-mode 1)
(pixel-scroll-precision-mode 1)
(global-auto-revert-mode 1)
(column-number-mode 1)
(global-subword-mode 1)           ; CamelCase word motions
(display-time-mode 1)

(setq use-short-answers t
      ring-bell-function 'ignore
      isearch-lazy-count t
      scroll-margin 2
      which-key-idle-delay 0.4
      global-auto-revert-non-file-buffers t
      truncate-string-ellipsis "…")

(add-hook 'prog-mode-hook #'display-line-numbers-mode)
(add-hook 'before-save-hook #'delete-trailing-whitespace)

(when (and (eq system-type 'gnu/linux)
           (string-match-p "microsoft"
                           (with-temp-buffer
                             (insert-file-contents "/proc/version")
                             (buffer-string))))
  (setq browse-url-generic-program
        (or (executable-find "wslview") "explorer.exe")
        browse-url-browser-function #'browse-url-generic))

;; Same font-spec form as Doom: an integer :size is PIXELS (16px ≈ 12pt),
;; not points — a :height of 160 (16pt) renders ~1/3 larger than Doom did.
;;
;; In the daemon, init runs before any GUI frame exists, and a
;; set-face-attribute :font applied against the dummy tty frame is
;; silently dropped — client frames then fall back to the GTK default
;; font. So apply fonts per-frame; the hook is idempotent.
(defun my/apply-fonts (&optional frame)
  (when (display-graphic-p frame)
    (with-selected-frame (or frame (selected-frame))
      (set-face-attribute 'default nil
                          :font (font-spec :family "FiraCode Nerd Font Mono"
                                           :size nd/font-size
                                           :weight 'semi-light))
      (set-face-attribute 'variable-pitch nil
                          :family "Overpass Nerd Font"))))
(if (daemonp)
    (add-hook 'after-make-frame-functions #'my/apply-fonts)
  (my/apply-fonts))

(load-theme 'doom-nord t)

;; Same face tweaks as the Doom config: italic comments and keywords,
;; and scaled variable-pitch markdown headers.
(set-face-attribute 'font-lock-comment-face nil :slant 'italic)
(set-face-attribute 'font-lock-keyword-face nil :slant 'italic)

(with-eval-after-load 'markdown-mode
  (dolist (spec '((markdown-header-face-1 . 1.7)
                  (markdown-header-face-2 . 1.6)
                  (markdown-header-face-3 . 1.5)
                  (markdown-header-face-4 . 1.4)
                  (markdown-header-face-5 . 1.3)
                  (markdown-header-face-6 . 1.2)))
    (set-face-attribute (car spec) nil
                        :weight 'bold
                        :family "Overpass Nerd Font"
                        :height (cdr spec))))

(defun my/minibuffer-truncate-lines ()
  "Keep minibuffer lines unwrapped."
  (setq truncate-lines t))

(defun my/flex-noinsert-try-completion (string table pred point)
  "Flex `try-completion' that never auto-extends the input on TAB.
- no candidates          -> nil (no match)
- exactly one candidate  -> complete it fully
- two or more candidates -> return STRING unchanged, so TAB only
  pops the *Completions* list and inserts nothing.
STRING, TABLE, PRED and POINT are the usual `try-completion' args."
  (let ((all (completion-flex-all-completions string table pred point)))
    (cond
     ((null all) nil)
     ((= (safe-length all) 1)
      (let ((sole (car all)))
        (if (string= sole string) t (cons sole (length sole)))))
     (t (cons string point)))))

(use-package minibuffer
  :ensure nil
  :bind ( :map minibuffer-visible-completions-up-down-map
          ("C-n" . minibuffer-next-completion)
          ("C-p" . minibuffer-previous-completion))
  :hook ((minibuffer-setup . cursor-intangible-mode)
         (minibuffer-setup . my/minibuffer-truncate-lines))
  :custom
  (tab-always-indent 'complete)
  (completion-auto-help t)
  (completion-auto-select t)
  (completion-eager-update t)          ; Emacs 31
  (completion-eager-display t)         ; Emacs 31
  (minibuffer-visible-completions 'up-down)
  (completion-ignore-case t)
  (completion-show-help nil)
  (completion-styles '(partial-completion flex initials))
  ;; project-file: scattered-letter flex matches are noise for file
  ;; names — require the typed text as a contiguous substring instead.
  (completion-category-overrides '((eglot-capf (styles flex-noinsert))
                                   (project-file (styles substring))))
  (completions-format 'one-column)
  (completions-max-height 10)
  (completions-sort 'historical)
  (enable-recursive-minibuffers t)
  (read-buffer-completion-ignore-case t)
  (read-file-name-completion-ignore-case t)
  (minibuffer-prompt-properties
   '(read-only t intangible t cursor-intangible t face minibuffer-prompt))
  (minibuffer-depth-indicate-mode t)
  (minibuffer-electric-default-mode t)
  :config
  (add-to-list 'completion-styles-alist
               '(flex-noinsert
                 my/flex-noinsert-try-completion
                 completion-flex-all-completions
                 "Flex matching that never extends input on TAB."))
  (put 'flex-noinsert 'completion--adjust-metadata
       'completion--flex-adjust-metadata))

(add-hook 'prog-mode-hook #'completion-preview-mode)

(use-package evil
  :ensure nil
  :init
  ;; All of these must be set before evil loads.
  (setq evil-want-keybinding nil   ; required by evil-collection
        evil-want-C-u-scroll t
        evil-want-fine-undo t
        evil-undo-system 'undo-redo)
  :config
  (evil-mode 1))

(use-package evil-collection
  :ensure nil
  :after evil
  :config
  (evil-collection-init))

(use-package undo-fu-session
  :ensure nil
  :config
  (setq undo-limit 8000000
        undo-fu-session-directory
        (expand-file-name "undo-fu-session/" my/state-dir))
  (undo-fu-session-global-mode 1))

(defun my/evil-lookup ()
  "Show documentation for the symbol at point via eldoc."
  (eldoc-doc-buffer t))

(setq evil-lookup-func #'my/evil-lookup)

(with-eval-after-load 'evil
  (evil-define-key 'normal 'global
    (kbd "gD") #'xref-find-references))

(defun my/find-config ()
  "Open this config's config.org."
  (interactive)
  (find-file (expand-file-name "config.org" user-emacs-directory)))

(defun my/find-in-notes ()
  "Find a file in `org-directory' (Doom's SPC n f)."
  (interactive)
  (require 'org) ; `org-directory' is set in a deferred use-package block
  (let ((default-directory org-directory))
    (project-find-file)))

;; Register commands under one prefix, same letters as the Doom-era
;; SPC r map (all built-ins; `r' upgrades to consult-register in P4).
(defvar-keymap my/register-map
  :doc "Register commands."
  "c"   #'copy-to-register
  "f"   #'frameset-to-register
  "i"   #'insert-register
  "j"   #'jump-to-register
  "l"   #'list-registers
  "n"   #'number-to-register
  "v"   #'view-register
  "w"   #'window-configuration-to-register
  "+"   #'increment-register
  "SPC" #'point-to-register
  "r"   #'consult-register)

(with-eval-after-load 'evil
  (evil-set-leader '(normal visual) (kbd "SPC"))

  (evil-define-key '(normal visual) 'global
    (kbd "<leader>SPC") #'execute-extended-command
    ;; Doom quick keys — pure muscle memory
    (kbd "<leader>.") #'find-file
    (kbd "<leader>,") #'switch-to-buffer
    (kbd "<leader>:") #'execute-extended-command
    (kbd "<leader>;") #'eval-expression
    (kbd "<leader>`") #'evil-switch-to-windows-last-buffer
    (kbd "<leader>u") #'universal-argument
    ;; files
    (kbd "<leader>ff") #'find-file
    (kbd "<leader>fr") #'recentf-open
    (kbd "<leader>fs") #'save-buffer
    (kbd "<leader>fd") #'dired-jump
    (kbd "<leader>fp") #'my/find-config
    ;; buffers — mirrors Doom's SPC b, built-in/evil commands only
    (kbd "<leader>bb") #'switch-to-buffer
    (kbd "<leader>bd") #'kill-current-buffer
    (kbd "<leader>bk") #'kill-current-buffer
    (kbd "<leader>bi") #'ibuffer
    (kbd "<leader>bn") #'next-buffer
    (kbd "<leader>b]") #'next-buffer
    (kbd "<leader>bp") #'previous-buffer
    (kbd "<leader>b[") #'previous-buffer
    (kbd "<leader>bl") #'evil-switch-to-windows-last-buffer
    (kbd "<leader>bm") #'bookmark-set
    (kbd "<leader>bM") #'bookmark-delete
    (kbd "<leader>bN") #'evil-buffer-new
    (kbd "<leader>br") #'revert-buffer
    (kbd "<leader>bR") #'rename-buffer
    (kbd "<leader>bs") #'save-buffer
    (kbd "<leader>bS") #'evil-write-all
    (kbd "<leader>bx") #'scratch-buffer
    (kbd "<leader>bz") #'bury-buffer
    (kbd "<leader>bc") #'clone-indirect-buffer-other-window
    ;; notes
    (kbd "<leader>nf") #'my/find-in-notes
    ;; open (agenda here; mail joins in the Mail section)
    (kbd "<leader>oa") #'org-agenda
    ;; git (magit; evil keys via evil-collection)
    (kbd "<leader>gg") #'magit-status
    (kbd "<leader>gd") #'magit-diff-dwim
    (kbd "<leader>gb") #'magit-blame-addition
    (kbd "<leader>gl") #'magit-log-current
    ;; search
    (kbd "<leader>ss") #'occur
    (kbd "<leader>sp") #'project-find-regexp
    (kbd "<leader>si") #'imenu
    ;; code — eglot/flymake (only meaningful in LSP buffers)
    (kbd "<leader>ca") #'eglot-code-actions
    (kbd "<leader>cr") #'eglot-rename
    (kbd "<leader>cf") #'eglot-format
    (kbd "<leader>cx") #'flymake-show-buffer-diagnostics
    (kbd "<leader>cX") #'flymake-show-project-diagnostics
    ;; toggles
    (kbd "<leader>tl") #'display-line-numbers-mode
    (kbd "<leader>tw") #'visual-line-mode
    (kbd "<leader>tf") #'flymake-mode
    (kbd "<leader>th") #'hl-line-mode
    (kbd "<leader>tH") #'global-hl-line-mode
    (kbd "<leader>tt") #'toggle-truncate-lines
    (kbd "<leader>tS") #'cycle-ispell-languages
    ;; quit
    (kbd "<leader>qq") #'save-buffers-kill-terminal
    ;; whole built-in prefix maps
    (kbd "<leader>p") project-prefix-map
    (kbd "<leader>w") evil-window-map
    (kbd "<leader>h") help-map
    (kbd "<leader>r") my/register-map
    ;; Doom's SPC TAB TAB (vector form: kbd can't splice TAB after <leader>)
    (vconcat (kbd "<leader>") (kbd "TAB TAB")) #'comment-line)

  ;; SPC w IS Doom's window map: Doom binds evil-window-map there too
  ;; (h/j/k/l move, H/J/K/L swap, s/v split, c close, o only, w cycle,
  ;; +/-/</> resize, = balance...). Doom's one addition worth keeping is
  ;; undo/redo of window layouts via the built-in winner-mode. Bindings
  ;; on evil-window-map also work under C-w, exactly like in Doom.
  (winner-mode 1)
  (define-key evil-window-map "u" #'winner-undo)
  (define-key evil-window-map "U" #'winner-redo)

  (which-key-add-key-based-replacements
    "SPC f" "files"
    "SPC n" "notes"
    "SPC b" "buffers"
    "SPC o" "open"
    "SPC g" "git"
    "SPC s" "search"
    "SPC c" "code"
    "SPC t" "toggles"
    "SPC q" "quit"
    "SPC p" "project"
    "SPC w" "windows"
    "SPC h" "help"
    "SPC r" "registers"))

(setq treesit-font-lock-level 4)

(setq major-mode-remap-alist
      '((sh-mode         . bash-ts-mode)
        (python-mode     . python-ts-mode)
        (js-mode         . js-ts-mode)
        (javascript-mode . js-ts-mode)
        (js-json-mode    . json-ts-mode)))

(dolist (entry '(("\\.go\\'"           . go-ts-mode)
                 ("/go\\.mod\\'"       . go-mod-ts-mode)
                 ("\\.rs\\'"           . rust-ts-mode)
                 ("\\.ya?ml\\'"        . yaml-ts-mode)
                 ("\\.nix\\'"          . nix-ts-mode)
                 ("\\.\\(zig\\|zon\\)\\'" . zig-ts-mode)))
  (add-to-list 'auto-mode-alist entry))

(defvar nd/eglot-servers
  '((nix-ts-mode    . "nixd")
    (go-ts-mode     . "gopls")
    (rust-ts-mode   . "rust-analyzer")
    (python-ts-mode . "pyright-langserver")
    (bash-ts-mode   . "bash-language-server")
    (js-ts-mode     . "typescript-language-server")
    (yaml-ts-mode   . "yaml-language-server")
    (zig-ts-mode    . "zls"))
  "Language-server binary that must exist for eglot to start per mode.")

(defun nd/eglot-ensure ()
  "`eglot-ensure', but only when the mode's server is installed."
  (when-let* ((bin (alist-get major-mode nd/eglot-servers))
              ((executable-find bin)))
    (eglot-ensure)))

(use-package eglot
  :ensure nil
  :hook ((nix-ts-mode go-ts-mode rust-ts-mode python-ts-mode
          bash-ts-mode js-ts-mode yaml-ts-mode zig-ts-mode)
         . nd/eglot-ensure)
  :custom
  (eglot-autoshutdown t)
  :config
  (add-to-list 'eglot-server-programs '(nix-ts-mode . ("nixd")))
  (add-to-list 'eglot-server-programs '(zig-ts-mode . ("zls"))))

(use-package magit
  :ensure nil
  :commands (magit-status magit-diff-dwim magit-blame-addition magit-log-current))

(use-package diff-hl
  :ensure nil
  :config
  (global-diff-hl-mode 1)
  (diff-hl-flydiff-mode 1)
  (add-hook 'magit-pre-refresh-hook #'diff-hl-magit-pre-refresh)
  (add-hook 'magit-post-refresh-hook #'diff-hl-magit-post-refresh))

(add-hook 'prog-mode-hook #'hl-todo-mode)

(setq ispell-personal-dictionary "~/org/.hunspell_personal")

(with-eval-after-load 'ispell
  (ispell-set-spellchecker-params)
  (ispell-hunspell-add-multi-dic "en_US,sv_SE")
  (setq ispell-dictionary "en_US,sv_SE"))

(add-hook 'text-mode-hook #'flyspell-mode)
(add-hook 'prog-mode-hook #'flyspell-prog-mode)

(defvar my-ispell-languages '("en_US,sv_SE" "sv_SE" "en_US")
  "List of Ispell dictionaries to cycle through.")

(defun cycle-ispell-languages ()
  "Cycle to the next Ispell dictionary."
  (interactive)
  (setq my-ispell-languages
        (append (cdr my-ispell-languages)
                (list (car my-ispell-languages))))
  (let ((lang (car my-ispell-languages)))
    (ispell-change-dictionary lang)
    (message "Switched to dictionary: %s" lang)))

(with-eval-after-load 'flymake
  (define-key flymake-mode-map (kbd "M-n") #'flymake-goto-next-error)
  (define-key flymake-mode-map (kbd "M-p") #'flymake-goto-prev-error))

(setq dired-listing-switches "-alh --group-directories-first"
      dired-dwim-target t)

(use-package notmuch
  :ensure nil
  :commands (notmuch notmuch-search notmuch-hello))

(with-eval-after-load 'notmuch
  ;; Stock notmuch lists oldest first; newest on top is what mail should do.
  ;; (Doom's notmuch module set this too — not part of the literal port.)
  (setq notmuch-search-oldest-first nil)

  ;; One inbox saved-search per account; the jump key comes with the
  ;; account entry (nix derives the name's initial unless overridden,
  ;; and rejects collisions at build time).
  (setq notmuch-saved-searches
        (mapcar (lambda (acct)
                  (list :name (format "%s/inbox" (car acct))
                        :query (format "tag:inbox and path:%s/**" (car acct))
                        :key (nth 2 acct)))
                nd/mail-accounts))

  (defun nd/notmuch-account-searches (acct)
    `((:name "inbox"   :query ,(format "tag:inbox and path:%s/**" acct))
      (:name "flagged" :query ,(format "tag:flagged and path:%s/**" acct))
      (:name "archive" :query ,(format "folder:%s/Inbox and not tag:inbox" acct))
      (:name "sent"    :query ,(format "folder:%s/Sent" acct))
      (:name "drafts"  :query ,(format "folder:%s/Drafts" acct))
      (:name "junk"    :query ,(format "folder:%s/Junk" acct))
      (:name "trash"   :query ,(format "folder:%s/Trash" acct))))
  (defun nd/notmuch-hello-insert-account (acct)
    (notmuch-hello-insert-searches
     acct (nd/notmuch-account-searches acct)
     :show-empty-searches t))
  (setq notmuch-hello-sections
        (append (list #'notmuch-hello-insert-header)
                (mapcar (lambda (acct)
                          (lambda () (nd/notmuch-hello-insert-account acct)))
                        (mapcar #'car nd/mail-accounts))
                (list #'notmuch-hello-insert-search
                      #'notmuch-hello-insert-alltags
                      #'notmuch-hello-insert-footer))))

(setq shr-use-colors nil)

(with-eval-after-load 'notmuch
  (defun nd/notmuch-plain-uninformative-p (content)
    "Non-nil if text/plain CONTENT is not a real message: blank, or HTML/CSS
boilerplate that some senders dump into the text/plain part."
    (or (not (stringp content))
        (let* ((s (string-trim content))
               (head (downcase (substring s 0 (min (length s) 1000)))))
          (or (string-empty-p s)
              (< (length s) 10)
              ;; Starts with HTML markup.
              (string-match-p "\\`<\\(!doctype\\|html\\|head\\|body\\|div\\|table\\|meta\\|span\\|style\\)\\b" head)
              ;; Reads as CSS / email styling boilerplate rather than prose.
              (string-match-p "@media\\|@import\\|mso-[a-z]\\|-webkit-\\|#outlook\\|mj-column\\|{[^{}]*:[^{}]*;[^{}]*}" head)))))

  (defun nd/notmuch-text-uninformative-p (msg)
    "Non-nil if MSG has a text/plain part whose content is uninformative."
    (let (has-plain junk)
      (cl-labels ((walk (parts)
                    (dolist (p parts)
                      (let ((ct (downcase (or (plist-get p :content-type) "")))
                            (content (plist-get p :content)))
                        (cond
                         ((string= ct "text/plain")
                          (setq has-plain t)
                          (when (nd/notmuch-plain-uninformative-p content) (setq junk t)))
                         ((listp content) (walk content)))))))
        (walk (plist-get msg :body)))
      (and has-plain junk)))

  (defun nd/notmuch-discouraged (msg)
    (if (nd/notmuch-text-uninformative-p msg)
        '("text/plain")
      '("text/html" "multipart/related")))
  (setq notmuch-multipart/alternative-discouraged #'nd/notmuch-discouraged)

  (defun nd/notmuch-show-toggle-images ()
    "Toggle remote images for this message buffer and re-render."
    (interactive)
    (setq-local notmuch-show-text/html-blocked-images
                (if notmuch-show-text/html-blocked-images nil "."))
    (notmuch-show-refresh-view)
    (message "Remote images %s"
             (if notmuch-show-text/html-blocked-images "blocked" "shown")))

  (defun nd/notmuch-html-part (parts)
    "First text/html leaf in the notmuch part tree PARTS, or nil."
    (catch 'found
      (cl-labels ((walk (ps)
                    (dolist (p ps)
                      (when (string= (downcase (or (plist-get p :content-type) ""))
                                     "text/html")
                        (throw 'found p))
                      (when (listp (plist-get p :content))
                        (walk (plist-get p :content))))))
        (walk parts))
      nil))

  (defun nd/notmuch-show-view-in-browser ()
    "Open the current message's HTML part in the system browser.
Each view leaves a notmuch-msg-*.html file in /tmp (mode 600); they are
not deleted here and get cleaned up when /tmp is wiped at reboot."
    (interactive)
    (let* ((msg (notmuch-show-get-message-properties))
           (part (nd/notmuch-html-part (plist-get msg :body))))
      (unless part (user-error "Message has no text/html part"))
      (browse-url-of-file
       (make-temp-file "notmuch-msg-" nil ".html"
                       (notmuch-get-bodypart-text msg part nil)))))

  (defun nd/notmuch-show-toggle-part-at-point ()
    "Toggle visibility of the message part containing point."
    (interactive)
    (let* ((extent (get-text-property (point) :notmuch-message-extent))
           (limit (if extent (car extent) (point-min)))
           (b (or (button-at (point)) (previous-button (point))))
           found)
      (while (and b (>= (button-start b) limit) (not found))
        (if (eq (button-type b) 'notmuch-show-part-button-type)
            (setq found b)
          (setq b (previous-button (button-start b)))))
      (unless found (user-error "No message part at point"))
      (notmuch-show-toggle-part-invisibility found))))

(with-eval-after-load 'notmuch
  (defun nd/notmuch-show-delete ()
    "Delete the current message and show the next thread in the search."
    (interactive)
    (notmuch-show-tag '("+deleted" "-inbox"))
    (notmuch-show-next-thread-show))

  (defun nd/notmuch-refresh-after-quit (&rest _)
    (when (derived-mode-p 'notmuch-search-mode 'notmuch-hello-mode)
      (notmuch-refresh-this-buffer)))
  (advice-add 'notmuch-bury-or-kill-this-buffer :after #'nd/notmuch-refresh-after-quit)

  (defun nd/notmuch-sync ()
    "Full mail sync: fetch, index, push tag changes (mbsync → notmuch → mbsync)."
    (interactive)
    (message "Syncing mail…")
    (set-process-sentinel
     (start-process-shell-command
      "notmuch-sync" "*notmuch-sync*"
      "mbsync -a && notmuch new && mbsync -a")
     (lambda (proc _event)
       (if (zerop (process-exit-status proc))
           (progn (notmuch-refresh-all-buffers)
                  (message "Mail sync done"))
         (message "Mail sync failed — see *notmuch-sync*"))))))

(setq sendmail-program (executable-find "msmtp")
      message-send-mail-function #'message-send-mail-with-sendmail
      mail-specify-envelope-from t
      mail-envelope-from 'header
      message-sendmail-envelope-from 'header)

;; Fcc: each account files its own Sent; anything else falls back to the
;; primary (first) account.
(with-eval-after-load 'notmuch
  (setq notmuch-fcc-dirs
        (append (mapcar (lambda (acct)
                          (cons (cadr acct)
                                (format "%s/Sent +sent -inbox -unread" (car acct))))
                        nd/mail-accounts)
                (when nd/mail-accounts
                  (list (cons ".*" (format "%s/Sent +sent -inbox -unread"
                                           (caar nd/mail-accounts))))))))

(defun nd/mail-push-sent ()
  (when-let* ((mbsync (executable-find "mbsync")))
    (apply #'start-process "mbsync-sent" nil mbsync
           (mapcar (lambda (acct) (format "%s:Sent" (car acct)))
                   nd/mail-accounts))))
(add-hook 'message-sent-hook #'nd/mail-push-sent)

(with-eval-after-load 'evil
  (evil-define-key '(normal visual) 'global
    (kbd "<leader>om") #'notmuch))

(with-eval-after-load 'notmuch
  (evil-define-key 'normal notmuch-show-mode-map
    (kbd "d") #'nd/notmuch-show-delete
    (kbd "<leader>mi") #'nd/notmuch-show-toggle-images
    (kbd "<leader>mv") #'nd/notmuch-show-view-in-browser
    (kbd "<leader>mp") #'nd/notmuch-show-toggle-part-at-point)
  (dolist (map (list notmuch-hello-mode-map notmuch-search-mode-map
                     notmuch-show-mode-map notmuch-tree-mode-map))
    (evil-define-key 'normal map (kbd "?") #'notmuch-help))
  (dolist (map (list notmuch-hello-mode-map notmuch-search-mode-map
                     notmuch-tree-mode-map))
    (evil-define-key 'normal map (kbd "gR") #'nd/notmuch-sync)))

(use-package org
  :ensure nil
  :bind (("C-c a" . org-agenda)
         ("C-c c" . org-capture))
  :custom
  (org-directory "~/org/")
  (calendar-week-start-day 1)
  (org-agenda-start-on-weekday 1)
  (org-agenda-files
   '("~/org/sigtuna/projects.org"
     "~/org/sigtuna/inbox.org"
     "~/org/veltric/projects.org"
     "~/org/veltric/inbox.org"
     "~/org/nordic/projects.org"
     "~/org/nordic/inbox.org"
     "~/org/home/inbox.org"
     "~/org/home/projects.org"
     "~/org/journal/"))
  (org-todo-keywords
   '((sequence "TODO(t)" "NEXT(n)" "|" "DONE(d!)")
     (sequence "BACKLOG(b)" "PLAN(p)" "READY(r)" "ACTIVE(a)"
               "REVIEW(v)" "WAIT(w@/!)" "HOLD(h)" "|"
               "COMPLETED(c)" "CANC(k@)")))
  (org-log-done 'time)
  (org-log-into-drawer t)
  (org-hide-emphasis-markers t)
  (org-ellipsis " ▼ ")
  (org-indent-indentation-per-level 1)
  (org-treat-insert-todo-heading-as-state-change t)
  (org-table-convert-region-max-lines 20000)
  (org-image-actual-width nil)
  (org-imenu-depth 4)
  (org-fontify-done-headline t)
  ;; [[arch-wiki:Name_of_Page][Description]] etc.
  (org-link-abbrev-alist
   '(("google" . "http://www.google.com/search?q=")
     ("arch-wiki" . "https://wiki.archlinux.org/index.php/")
     ("wiki" . "https://en.wikipedia.org/wiki/")
     ("omap" . "https://nominatim.openstreetmap.org/search?q=%s&polygon=1")))
  ;; Refile across all agenda files by full path; flex completion
  ;; narrows "sig inbox" style just fine.
  (org-refile-targets '((org-agenda-files :maxlevel . 3)))
  (org-refile-use-outline-path 'full-file-path)
  (org-outline-path-complete-in-steps nil)
  (org-refile-allow-creating-parent-nodes 'confirm)
  ;; Own org-id database — never share Doom's.
  (org-id-locations-file (expand-file-name "org-id-locations" my/state-dir))
  :config
  (add-to-list 'org-modules 'org-habit t))

(setq org-tag-persistent-alist '(("@home" . ?h)
                                 ("sigtuna" . ?s)
                                 ("veltric" . ?v)
                                 ("nordic" . ?n)
                                 ("project" . ?p)
                                 ("idee" . ?i)))

(setq org-tag-faces
      '(("project" . (:foreground "burlywood"))
        ("idee" . (:foreground "yellow" :weight bold))))

(setq org-todo-keyword-faces
      '(("TODO" . (:foreground "goldenrod" :weight bold))
        ("NEXT" . (:foreground "White" :background "ForestGreen" :weight bold))
        ("STARTED" . (:foreground "White" :background "DarkViolet" :weight bold))
        ("WAIT" . (:foreground "White" :background "DarkOrange1" :weight bold))
        ("HOLD" . (:foreground "White" :background "SlateGray" :weight bold))
        ("VOID" . (:foreground "White" :background "Brown" :weight bold))
        ("DONE" . (:foreground "Silver" :weight regular))))

(setq org-priority-faces
      '((?A :foreground "#ff6c6b" :weight bold)
        (?B :foreground "#ffd966" :weight bold)
        (?C :foreground "#c678dd" :weight bold)))

(defun nd/org-journal-find-location ()
  "Open today's journal entry for capture without inserting a new heading."
  (org-journal-new-entry t)
  (unless (eq org-journal-file-type 'daily)
    (org-narrow-to-subtree))
  (goto-char (point-max)))

(defun nd/people-roster ()
  "Return an alist of (NAME . ID) for every level-1 heading in people.org."
  (with-current-buffer (find-file-noselect "~/org/databases/people.org")
    (org-with-wide-buffer
     (org-map-entries
      (lambda ()
        (cons (org-get-heading t t t t) (org-id-get)))
      "LEVEL=1"))))

(defun nd/read-tags ()
  "Prompt for multiple tags via CRM from `org-tag-persistent-alist'.
Returns tags wrapped as :tag1:tag2: or empty string if none picked."
  (let* ((candidates (mapcar (lambda (pair)
                               (if (consp pair) (car pair) pair))
                             org-tag-persistent-alist))
         (picked (completing-read-multiple "Tags: " candidates)))
    (if picked
        (concat ":" (string-join picked ":") ":")
      "")))

(defun nd/read-attendees ()
  "Prompt for attendees from people.org; return comma-separated id-links.
Names not in the roster pass through as plain text."
  (let* ((roster (nd/people-roster))
         (picked (completing-read-multiple
                  "Attendees: " (mapcar #'car roster))))
    (mapconcat
     (lambda (name)
       (if-let ((id (cdr (assoc name roster))))
           (format "[[id:%s][%s]]" id name)
         name))
     picked ", ")))

(defvar nd/capture-default-title nil
  "Title captured by the Default file capture template; reused in #+TITLE.")

(defvar nd/action-inboxes
  '(("Sigtuna" . "~/org/sigtuna/inbox.org")
    ("Veltric" . "~/org/veltric/inbox.org")
    ("Nordic"  . "~/org/nordic/inbox.org")
    ("Home"    . "~/org/home/inbox.org"))
  "Inboxes selectable by `nd/action-to-inbox'.")

(defun nd/action-to-inbox ()
  "File current line, heading, or region as a TODO into a chosen inbox.
Adds a Backlink to the enclosing org entry (one level above, if the
cursor is already on a heading) so the TODO retains its context."
  (interactive)
  (let* ((on-heading (save-excursion
                       (beginning-of-line)
                       (looking-at-p org-heading-regexp)))
         (raw (cond
               ((use-region-p)
                (buffer-substring-no-properties
                 (region-beginning) (region-end)))
               (on-heading
                (org-get-heading t t t t))
               (t (thing-at-point 'line t))))
         (action (string-trim
                  (replace-regexp-in-string
                   "^[ \t]*[-+*][ \t]*" "" raw)))
         (target (completing-read
                  "Inbox: " (mapcar #'car nd/action-inboxes) nil t))
         (inbox (expand-file-name (cdr (assoc target nd/action-inboxes))))
         (src-pos (save-excursion
                    (org-back-to-heading t)
                    (when on-heading (org-up-heading-safe))
                    ;; Keep walking up to find the entry heading:
                    ;; either tagged with a company tag, or at journal
                    ;; entry level (<= 2). Stops at whichever comes first.
                    (while (and (not (seq-intersection
                                      (org-get-tags)
                                      '("sigtuna" "veltric" "nordic" "@home")))
                                (> (org-current-level) 2)
                                (org-up-heading-safe)))
                    (point)))
         (src-title (save-excursion
                      (goto-char src-pos)
                      (org-get-heading t t t t)))
         (src-id (save-excursion
                   (goto-char src-pos)
                   (org-id-get-create)))
         (ts (format-time-string "[%Y-%m-%d %a %H:%M]")))
    (with-current-buffer (find-file-noselect inbox)
      (goto-char (point-max))
      (unless (bolp) (insert "\n"))
      (insert (format "* TODO %s\n%s\nBacklink: [[id:%s][%s]]\n"
                      action ts src-id src-title))
      (save-buffer))
    (message "Filed to %s: %s" target action)))

(defun nd/attach-url-and-insert ()
  "Attach a URL to the current entry and insert a link to it."
  (interactive)
  (call-interactively #'org-attach-url)
  (org-insert-last-stored-link 1))

(with-eval-after-load 'org
  (setq org-capture-templates
        '(("s" "Sigtuna")
          ("si" "Inbox" entry (file "~/org/sigtuna/inbox.org")
           "* TODO %? %(nd/read-tags)\n%U\n%a")
          ("sp" "Project" entry (file "~/org/sigtuna/projects.org")
           "* TODO %^{Title} %(nd/read-tags)\n%U\n%a\n%?")

          ("v" "Veltric")
          ("vi" "Inbox" entry (file "~/org/veltric/inbox.org")
           "* TODO %? %(nd/read-tags)\n%U\n%a")
          ("vp" "Project" entry (file "~/org/veltric/projects.org")
           "* TODO %^{Title} %(nd/read-tags)\n%U\n%a\n%?")

          ("n" "Nordic")
          ("ni" "Inbox" entry (file "~/org/nordic/inbox.org")
           "* TODO %? %(nd/read-tags)\n%U\n%a")
          ("np" "Project" entry (file "~/org/nordic/projects.org")
           "* TODO %^{Title} %(nd/read-tags)\n%U\n%a\n%?")

          ("h" "Home")
          ("hi" "Inbox" entry (file "~/org/home/inbox.org")
           "* TODO %? %(nd/read-tags)\n%U\n%a")
          ("hp" "Project" entry (file "~/org/home/projects.org")
           "* TODO %^{Title} %(nd/read-tags)\n%U\n%a\n%?")

          ("f" "New file" plain
           (file (lambda ()
                   (let* ((default-directory (expand-file-name "~/org/"))
                          (path (read-file-name "New org file: " default-directory)))
                     (if (string-suffix-p ".org" path) path (concat path ".org")))))
           ":PROPERTIES:\n:ID:       %(org-id-new)\n:END:\n#+TITLE: %^{Title}\n#+AUTHOR: %n\n#+DATE: %u\n\n%?"
           :unnarrowed t)

          ("d" "Default file" plain
           (file (lambda ()
                   (let* ((title (read-string "Title: "))
                          (filename (replace-regexp-in-string " " "_" title))
                          (dir (expand-file-name "~/org/default/")))
                     (unless (file-directory-p dir) (make-directory dir t))
                     (setq nd/capture-default-title title)
                     (expand-file-name (concat filename ".org") dir))))
           ":PROPERTIES:\n:ID:       %(org-id-new)\n:END:\n#+TITLE: %(progn nd/capture-default-title)\n#+AUTHOR: %n\n#+DATE: %u\n\n%?"
           :unnarrowed t)

          ("jm" "Meeting" plain (function nd/org-journal-find-location)
           "** %(format-time-string org-journal-time-format)%^{Title} %(nd/read-tags)\n:PROPERTIES:\n:ATTENDEES: %(nd/read-attendees)\n:END:\n- Agenda :: %?\n- Notes ::\n*** Actions\n")
          ("jw" "Work log" plain (function nd/org-journal-find-location)
           "** %(format-time-string org-journal-time-format)%^{Title} %(nd/read-tags)\n- Done :: %?\n- Blockers ::\n")
          ("ji" "Idea" plain (function nd/org-journal-find-location)
           "** %(format-time-string org-journal-time-format)%^{Title} :idee:\n%?")))

  ;; Keep the org-id database current for anything captured under ~/org.
  ;; (Doom also invalidated the projectile cache here — project.el needs
  ;; no equivalent.)
  (add-hook 'org-capture-after-finalize-hook
            (lambda ()
              (when (and (buffer-file-name)
                         (string-prefix-p (expand-file-name "~/org/")
                                          (buffer-file-name)))
                (org-id-update-id-locations (list (buffer-file-name)))))))

(use-package org-journal
  :ensure nil
  :commands (org-journal-new-entry
             org-journal-open-current-journal-file
             org-journal-next-entry
             org-journal-previous-entry
             org-journal-search)
  ;; Journal files are extensionless (e.g. 20260101) and org-journal
  ;; registers their mode association only once it's loaded — without
  ;; this, a directly opened journal file lands in fundamental-mode
  ;; (no org, no visual-fill-column, nothing).
  :mode ("/org/journal/[0-9]\\{8\\}\\'" . org-journal-mode)
  :init
  ;; The default regexp only matches *.org, so ~/org/journal/ in
  ;; org-agenda-files contributed NOTHING to the agenda (silently
  ;; broken in Doom too — same default, same extensionless files).
  (setq org-agenda-file-regexp "\\`[^.].*\\.org\\'\\|\\`[0-9]+\\'")
  (setq org-journal-dir "~/org/journal/"
        org-journal-date-format "%A, %Y %B %d"
        org-journal-file-type 'yearly))

(defun nd/org-mode-visual-fill ()
  (setq visual-fill-column-width 140
        visual-fill-column-center-text t)
  ;; Word-boundary soft wrap (Doom's word-wrap module did this).
  ;; Note: centering is only visible in windows WIDER than 140 cols
  ;; (~1800px at this font size) — narrower windows word-wrap at the
  ;; window edge instead, by design.
  (visual-line-mode 1)
  (visual-fill-column-mode 1))

(add-hook 'org-mode-hook #'nd/org-mode-visual-fill)
(add-hook 'org-mode-hook #'auto-save-visited-mode)

(use-package org-download
  :ensure nil
  :after org
  :config
  (setq org-download-image-dir "~/org/assets"
        org-download-method 'directory
        org-download-heading-lvl nil))

(setq org-agenda-start-with-log-mode t
      org-agenda-block-separator 8411)

(setq org-stuck-projects
      '("+project/-DONE-COMPLETED-CANC-VOID"
        ("NEXT" "STARTED" "ACTIVE")
        nil ""))

(with-eval-after-load 'org-agenda
  (require 'nerd-icons)
  (setq org-agenda-category-icon-alist
        `(("task" ,(list (nerd-icons-faicon "nf-fa-tasks")) nil nil :ascent center)
          ("project" ,(list (nerd-icons-faicon "nf-fa-briefcase")) nil nil :ascent center)
          ("inbox" ,(list (nerd-icons-faicon "nf-fa-inbox")) nil nil :ascent center))))

(setq org-agenda-custom-commands
      '(("wd" "Work DONE"
         ((agenda ""
                  ((org-agenda-files '("~/org/sigtuna/inbox.org_archive"))
                   (org-agenda-span 100)
                   (org-agenda-start-day "-100d")
                   (org-agenda-start-on-weekday nil)
                   (org-agenda-show-inherited-tags nil)))))

        ("wp" "Work PROJECTS"
         ((tags-todo "project+LEVEL=1-someday"
                     ((org-agenda-files '("~/org/sigtuna/projects.org"))
                      (org-agenda-prefix-format "%l%l")
                      (org-agenda-show-inherited-tags nil)
                      (org-agenda-overriding-header "PROJEKT")))))

        ("ws" "Stuck projects" stuck "")

        ("wm" "JOURNAL OVERVIEW"
         ((agenda ""
                  ((org-agenda-files '("~/org/journal/"))
                   (org-agenda-span 366)
                   (org-agenda-start-day "-365")
                   (org-agenda-start-on-weekday nil)
                   (org-agenda-show-inherited-tags nil)))))

        ("wo" "Work OVERVIEW"
         ((agenda ""
                  ((org-agenda-span 14)
                   (org-agenda-start-on-weekday nil)
                   (org-agenda-skip-function '(org-agenda-skip-entry-if 'nottodo '("TODO")))
                   (org-agenda-show-inherited-tags nil)))

          (tags-todo "project+LEVEL=1-someday"
                     ((org-agenda-overriding-header "Projekt")
                      (org-agenda-prefix-format "%i%l%l")
                      (org-agenda-show-inherited-tags nil)
                      (org-agenda-dim-blocked-tasks nil)))

          (tags-todo "+RPA-someday-project"
                     ((org-agenda-overriding-header "Tasks - RPA")
                      (org-agenda-prefix-format "%i%l%l")
                      (org-agenda-show-inherited-tags nil)))

          (tags-todo "+eTjänst-someday-project"
                     ((org-agenda-overriding-header "Tasks - eTjänst")
                      (org-agenda-prefix-format "%i%l%l")
                      (org-agenda-show-inherited-tags nil)))

          (tags-todo "-RPA-eTjänst-someday-project"
                     ((org-agenda-overriding-header "Tasks - Annat")
                      (org-agenda-prefix-format "%i%l%l")
                      (org-agenda-show-inherited-tags nil)))

          (tags-todo "+someday"
                     ((org-agenda-overriding-header "Someday")
                      (org-agenda-prefix-format "%i%l%l")
                      (org-agenda-show-inherited-tags nil)))))

        ("V" "Custom day agenda"
         ((agenda "" ((org-agenda-span 7)))
          (tags-todo "task"
                     ((org-agenda-overriding-header "Urgent")))))))

(with-eval-after-load 'org
  (require 'org-ql-search)
  ;; Newer org-ql asks "could contain arbitrary code — execute?" for
  ;; every sexp query, which would fire on each dashboard refresh.
  ;; The queries are our own org files; skip the prompt.
  (setq org-ql-ask-unsafe-queries nil)
  (cl-defun org-dblock-write:my-org-ql (params)
      "Insert content for org-ql dynamic block at point according to PARAMS.
  Valid parameters include:
   :scope    The scope to consider for the Org QL query. This can
              be one of the following:
              `buffer'              the current buffer
              `org-agenda-files'    all agenda files
              `org-directory'       all org files
              `(\"path\" ...)'      list of buffer names or file paths
              `all'                 all agenda files, and org-mode buffers

    :query    An Org QL query expression in either sexp or string
              form.

    :columns  A list of columns, including `heading', `todo',
              `property',`priority',`deadline',`scheduled',`closed'.
              Each column may also be specified as a list with the
              second element being a header string.  For example,
              to abbreviate the priority column: (priority \"P\").
              For certain columns, like `property', arguments may
              be passed by specifying the column type itself as a
              list.  For example, to display a column showing the
              values of a property named \"milestone\", with the
              header being abbreviated to \"M\":

                ((property \"milestone\") \"M\").

    :sort     One or a list of Org QL sorting methods
              (see `org-ql-select').

    :take     Optionally take a number of results from the front (a
              positive number) or the end (a negative number) of
              the results.

    :ts-format  Optional format string used to format
                timestamp-based columns.

  For example, an org-ql dynamic block header could look like:

    #+BEGIN: org-ql :query (todo \"UNDERWAY\") :columns (priority todo heading) :sort (priority date) :ts-format \"%Y-%m-%d %H:%M\""
      (-let* (((&plist :scope :query :columns :sort :ts-format :take) params)
              (query (cl-etypecase query
                       (string (org-ql--query-string-to-sexp query))
                       (list  ;; SAFETY: Query is in sexp form: ask for confirmation, because it could contain arbitrary code.
                        (org-ql--ask-unsafe-query query)
                        query)))
              (columns (or columns '(heading todo (priority "P"))))
              (scope (cond ((and (listp scope) (seq-every-p #'stringp scope)) scope)
                           ((string-equal scope "org-agenda-files") (org-agenda-files))
                           ((or (not scope) (string-equal scope "buffer")) (current-buffer))
                           ((string-equal scope "org-directory") (org-ql-search-directories-files))
                           (t (user-error "Unknown scope '%s'" scope))))
              ;; MAYBE: Custom column functions.
              (format-fns
               ;; NOTE: Backquoting this alist prevents the lambdas from seeing
               ;; the variable `ts-format', so we use `list' and `cons'.
               (list (cons 'todo (lambda (element)
                                   (org-element-property :todo-keyword element)))
                     (cons 'heading (lambda (element)
                                      (cond
                                       ((and org-id-link-to-org-use-id
                                             (org-element-property :ID element))
                                        (org-make-link-string (format "id:%s" (org-element-property :ID element))
                                                              (org-element-property :raw-value element)))
                                       ((org-element-property :file element)
                                        (org-make-link-string (format "file:%s::*%s"
                                                                      (org-element-property :file element)
                                                                      (org-element-property :raw-value element))
                                                              (org-element-property :raw-value element)))
                                       (t (org-make-link-string (org-element-property :raw-value element)
                                                                (org-link-display-format
                                                                 (org-element-property :raw-value element)))))
                                      ))
                     (cons 'priority (lambda (element)
                                       (--when-let (org-element-property :priority element)
                                         (char-to-string it))))
                     (cons 'deadline (lambda (element)
                                       (--when-let (org-element-property :deadline element)
                                         (ts-format ts-format (ts-parse-org-element it)))))
                     (cons 'scheduled (lambda (element)
                                        (--when-let (org-element-property :scheduled element)
                                          (ts-format ts-format (ts-parse-org-element it)))))
                     (cons 'closed (lambda (element)
                                     (--when-let (org-element-property :closed element)
                                       (ts-format ts-format (ts-parse-org-element it)))))
                     (cons 'property (lambda (element property)
                                       (org-element-property (intern (concat ":" (upcase property))) element)))))
              (elements (org-ql-query :from scope
                                      :where query
                                      :select '(org-element-put-property (org-element-headline-parser (line-end-position)) :file (buffer-file-name))
                                      :order-by sort)))
        (when take
          (setf elements (cl-etypecase take
                           ((and integer (satisfies cl-minusp)) (-take-last (abs take) elements))
                           (integer (-take take elements)))))
        (cl-labels ((format-element
                     (element) (string-join (cl-loop for column in columns
                                                     collect (or (pcase-exhaustive column
                                                                   ((pred symbolp)
                                                                    (funcall (alist-get column format-fns) element))
                                                                   (`((,column . ,args) ,_header)
                                                                    (apply (alist-get column format-fns) element args))
                                                                   (`(,column ,_header)
                                                                    (funcall (alist-get column format-fns) element)))
                                                                 ""))
                                            " | ")))
          ;; Table header
          (insert "| " (string-join (--map (pcase it
                                             ((pred symbolp) (capitalize (symbol-name it)))
                                             (`(,_ ,name) name))
                                           columns)
                                    " | ")
                  " |" "\n")
          (insert "|- \n")  ; Separator hline
          (dolist (element elements)
            (insert "| " (format-element element) " |" "\n"))
          (delete-char -1)
          (org-table-align))))
  )

(with-eval-after-load 'org
  (evil-define-key '(normal visual) org-mode-map
    (kbd "<leader>ma") #'nd/action-to-inbox
    (kbd "<leader>mB") #'org-babel-tangle
    (kbd "<leader>mli") #'nd/attach-url-and-insert))

(defun my/search-org ()
  "Full-text search across ~/org with ripgrep."
  (interactive)
  (consult-ripgrep "~/org/"))

(with-eval-after-load 'evil
  (evil-define-key '(normal visual) 'global
    (kbd "<leader>X") #'org-capture
    (kbd "<leader>n/") #'my/search-org
    (kbd "<leader>nR") #'consult-recoll
    (kbd "<leader>njo") #'org-journal-open-current-journal-file
    (kbd "<leader>njj") #'org-journal-new-entry
    (kbd "<leader>njn") #'org-journal-next-entry
    (kbd "<leader>njp") #'org-journal-previous-entry
    (kbd "<leader>njs") #'org-journal-search
    (kbd "<leader>njm") (lambda () (interactive) (org-capture nil "jm"))
    (kbd "<leader>njl") (lambda () (interactive) (org-capture nil "jw"))
    (kbd "<leader>nji") (lambda () (interactive) (org-capture nil "ji")))

  (which-key-add-key-based-replacements
    "SPC n" "notes"
    "SPC n j" "journal"
    "SPC m" "mode"
    "SPC m l" "links"))
