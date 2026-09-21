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
;; display-time-mode is enabled in the Modeline section, after its
;; settings.

(setq use-short-answers t
      ring-bell-function 'ignore
      isearch-lazy-count t
      scroll-margin 2
      which-key-idle-delay 0.4
      global-auto-revert-non-file-buffers t
      truncate-string-ellipsis "…")

(add-hook 'prog-mode-hook #'display-line-numbers-mode)

(defun nd/delete-trailing-whitespace-except-org ()
  "Clean trailing whitespace outside Org, preserving unfinished Org entries."
  (unless (derived-mode-p 'org-mode)
    (delete-trailing-whitespace)))

;; Also replace the old hook when this block is loaded in a running session.
(remove-hook 'before-save-hook #'delete-trailing-whitespace)
(add-hook 'before-save-hook #'nd/delete-trailing-whitespace-except-org)

(defun nd/buffer-category ()
  "Return the current buffer's work category, following indirect buffers."
  (with-current-buffer (or (buffer-base-buffer) (current-buffer))
    (let* ((file (and buffer-file-name (expand-file-name buffer-file-name)))
           (root (file-name-as-directory
                  (expand-file-name (if (boundp 'org-directory)
                                        org-directory "~/org/")))))
      (cond
       ((and file (or (equal file (concat root "inbox.org"))
                      (string-prefix-p (concat root "gtd/") file))) 'tasks)
       ((and file (string-prefix-p (concat root "journal/") file)) 'journals)
       ((and file (string-prefix-p (concat root "notes/") file)) 'notes)
       ((and file (string-prefix-p (concat root "ref/") file)) 'reference)
       ((derived-mode-p 'nd/contacts-mode) 'reference)
       ((null file) 'utilities)
       ((or (derived-mode-p 'prog-mode)
            (string-prefix-p (file-name-as-directory
                              (expand-file-name user-emacs-directory)) file)) 'code)))))

(defun nd/ibuffer-use-work-groups ()
  "Group Ibuffer by work purpose and display full buffer names."
  (setq-local ibuffer-formats
              (mapcar
               (lambda (format)
                 (mapcar (lambda (column)
                           (if (or (eq column 'name)
                                   (and (consp column) (eq (car column) 'name)))
                               '(name 48 -1 :left)
                             column))
                         format))
               ibuffer-formats)
              ibuffer-show-empty-filter-groups nil
              ibuffer-filter-groups
              '(("Tasks & projects" (predicate . (eq (nd/buffer-category) 'tasks)))
                ("Journals" (predicate . (eq (nd/buffer-category) 'journals)))
                ("Notes" (predicate . (eq (nd/buffer-category) 'notes)))
                ("Reference" (predicate . (eq (nd/buffer-category) 'reference)))
                ("Code & config" (predicate . (eq (nd/buffer-category) 'code)))
                ("Utilities" (predicate . (eq (nd/buffer-category) 'utilities))))))

(with-eval-after-load 'ibuffer
  (require 'ibuf-ext)
  (add-hook 'ibuffer-mode-hook #'nd/ibuffer-use-work-groups))

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

;; doom-themes and gnus each define one half of a face inheritance cycle:
;; gnus has `gnus-group-news-low' inherit `gnus-group-news-low-empty'
;; (gnus.el), and doom-themes points the same pair the other way. Nothing
;; complains until something defines those faces for real, at which point
;; the defface throws "Face inheritance results in inheritance cycle".
;;
;; It surfaces here as org noise — `org-load-modules-maybe' catches the
;; error and prints "Problems while trying to load feature `ol-gnus'"
;; (and `ol-eww', which reaches gnus too) on every org buffer, with the
;; actual error swallowed. Nothing to do with org: reproducible in emacs
;; -Q with load-theme + (require 'ol-gnus).
;;
;; Re-point the doom half at the mail face it should have used, breaking
;; the back edge. A user spec outranks the theme's, and it has to be set
;; before gnus loads, which is why it lives beside `load-theme' rather
;; than in a `with-eval-after-load'. Fixing the face rather than dropping
;; the org modules keeps it fixed for anything else that pulls gnus's
;; faces in.
(custom-set-faces
 '(gnus-group-news-low-empty ((t (:inherit gnus-group-mail-1-empty)))))

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

;; Icons come from "Symbols Nerd Font Mono", the family nerd-icons
;; hardcodes; module.nix installs it (nerd-fonts.symbols-only).
(require 'nerd-icons)
;; The modeline references `project-mode-line-format' on every
;; redisplay, so project.el has to be loaded, not merely autoloadable.
(require 'project)

;; Collapse every minor-mode lighter into a single "…" EXCEPT flymake,
;; whose lighter is the error/warning count and worth the space.
(setq mode-line-collapse-minor-modes '(not flymake-mode)
      ;; display-time otherwise trails a load average; the eww bar
      ;; already carries a clock, so keep this to just the time.
      display-time-default-load-average nil
      ;; Project name on the right (Emacs 30; off by default).
      project-mode-line t)

;; Enabled here rather than with the other built-in modes: the mode
;; renders once on activation, so it has to come after the settings
;; above or the first render still carries the load average.
(display-time-mode 1)

;; A battery segment only where there is a battery: battery.el leaves
;; this nil on a desktop, so one config is right on both mega and the
;; elitebook without consulting the host attrset.
(when (and (require 'battery nil t) battery-status-function)
  (display-battery-mode 1))

;; Evil state as a colored tag, replacing evil's own "<N>". The faces
;; inherit from semantic built-ins, so the theme keeps driving the
;; palette and nothing here hardcodes a Nord hex.
(defface my/mode-line-normal '((t :inherit font-lock-keyword-face :weight bold))
  "Face for the evil normal state tag.")
(defface my/mode-line-insert '((t :inherit success :weight bold))
  "Face for the evil insert state tag.")
(defface my/mode-line-visual '((t :inherit warning :weight bold))
  "Face for the evil visual state tag.")
(defface my/mode-line-replace '((t :inherit error :weight bold))
  "Face for the evil replace state tag.")
(defface my/mode-line-operator '((t :inherit font-lock-constant-face :weight bold))
  "Face for the evil operator state tag.")
(defface my/mode-line-emacs '((t :inherit font-lock-builtin-face :weight bold))
  "Face for the emacs (non-evil) state tag.")

(defvar my/mode-line-evil-states
  '((normal   "NOR" my/mode-line-normal)
    (insert   "INS" my/mode-line-insert)
    (visual   "VIS" my/mode-line-visual)
    (replace  "REP" my/mode-line-replace)
    (operator "OPR" my/mode-line-operator)
    (motion   "MOT" my/mode-line-normal)
    (emacs    "EMA" my/mode-line-emacs))
  "Tag text and face for each evil state.")

(defun my/mode-line-icon (fn name fallback)
  "Nerd-icon NAME looked up with FN, or FALLBACK on a terminal frame."
  (if (display-graphic-p) (funcall fn name) fallback))

(defun my/mode-line-state ()
  "Evil state tag, or blank padding outside evil."
  (if-let* ((entry (assq (bound-and-true-p evil-state) my/mode-line-evil-states)))
      (propertize (format " %s " (nth 1 entry)) 'face (nth 2 entry))
    "   "))

(defun my/mode-line-buffer-state ()
  "Read-only or modified indicator for the current buffer."
  (cond (buffer-read-only
         (my/mode-line-icon #'nerd-icons-faicon "nf-fa-lock" "%%"))
        ((buffer-modified-p)
         (my/mode-line-icon #'nerd-icons-mdicon "nf-md-circle_medium" "*"))
        (t " ")))

(defun my/mode-line-vc ()
  "Branch name with an icon, minus the backend prefix `vc-mode' adds.
`vc-mode' is a buffer-local string like \" Git-main\", so this costs
nothing per redisplay."
  (when (and vc-mode buffer-file-name)
    (concat (my/mode-line-icon #'nerd-icons-octicon "nf-oct-git_branch" "on")
            " "
            (string-trim (replace-regexp-in-string
                          "\\`[[:space:]]*[A-Za-z]+[-:@!?]" "" vc-mode))
            "  ")))

(setq-default mode-line-format
              '("%e"
                mode-line-front-space
                (:eval (my/mode-line-state))
                (:eval (my/mode-line-buffer-state))
                " "
                (:propertize "%b" face mode-line-buffer-id)
                "  "
                (:propertize "%l:%C" face shadow)
                mode-line-format-right-align
                (project-mode-line project-mode-line-format)
                "  "
                (:eval (my/mode-line-vc))
                mode-line-modes
                mode-line-misc-info
                mode-line-end-spaces))

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
        evil-undo-system 'undo-redo
        ;; The Modeline section renders the state as a colored tag; this
        ;; would otherwise add a second, plain "<N>" indicator.
        evil-mode-line-format nil)
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

;; `ispell-word' (what evil's z= and M-$ run) answers in a *Choices*
;; window at the TOP of the frame, and buries its accept/save commands
;; behind `?' — with two dictionaries live, saving a word is the common
;; case, not a rare one. flyspell-correct runs the same hunspell
;; suggestions through `completing-read', where [Save], [Accept
;; (session)] and [Accept (buffer)] are candidates you can see. Saving
;; writes to `ispell-personal-dictionary' above.
;;
;; Remapping the command rather than binding a key means z= and M-$ both
;; follow, since both were already `ispell-word'.
(use-package flyspell-correct
  :ensure nil
  :bind ([remap ispell-word] . flyspell-correct-at-point))

;; RET on a misspelled word corrects it. The binding goes in
;; `flyspell-mouse-map', which flyspell hangs off an overlay `keymap'
;; property covering the misspelling and nothing else (flyspell.el:1837),
;; so RET is untouched everywhere else — `evil-ret' in a file,
;; `org-agenda-switch-to' in the agenda. That property is also consulted
;; before evil's emulation maps, which is what makes the binding
;; reachable in normal state at all.
;;
;; The :filter decides per keypress: returning nil (rather than a
;; command) means the lookup falls through to the next keymap, so a
;; correctly spelled word leaves RET doing whatever it already did.
;; It declines with a region active or in insert/emacs state, where RET
;; is already doing something less interruptible.
;;
;; Set up on flyspell load, not flyspell-correct's: the command is
;; autoloaded, but the binding has to exist BEFORE the first RET or
;; there is nothing to trigger the load.
(with-eval-after-load 'flyspell
  (dolist (key (list (kbd "RET") [return]))
    (define-key flyspell-mouse-map key
      `(menu-item "" flyspell-correct-at-point
                  :filter ,(lambda (cmd)
                             (and (not (region-active-p))
                                  (not (and (bound-and-true-p evil-local-mode)
                                            (or (evil-insert-state-p)
                                                (evil-emacs-state-p))))
                                  (memq 'flyspell-incorrect (face-at-point nil t))
                                  cmd))))))

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
  (advice-add 'notmuch-bury-or-kill-this-buffer :after #'nd/notmuch-refresh-after-quit))

(defun nd/notmuch-sync (&optional wait)
  "Run the shared mail-sync command asynchronously.
With WAIT, queue behind any current sync, for mail just sent."
  (interactive)
  (let ((program (executable-find "mail-sync")))
    (unless program
      (user-error "Install the arcmac mail module (or scripts/mail-sync.sh as mail-sync)"))
    (message (if wait "Mail sync queued…" "Syncing mail…"))
    (make-process
     :name "notmuch-sync" :buffer (get-buffer-create "*notmuch-sync*")
     :command (append (list program) (when wait '("--wait")))
     :connection-type 'pipe :noquery t
     :sentinel
     (lambda (proc _event)
       (when (memq (process-status proc) '(exit signal))
         (cond
          ((and (eq (process-status proc) 'exit) (zerop (process-exit-status proc)))
           (when (fboundp 'notmuch-refresh-all-buffers) (notmuch-refresh-all-buffers))
           (message "Mail sync done"))
          ((and (eq (process-status proc) 'exit) (= (process-exit-status proc) 75))
           (message "Mail sync already running"))
          (t (message "Mail sync failed — see *notmuch-sync*"))))))))

(defun nd/mail-push-sent ()
  "Queue a full sync after sending, including when another sync is running."
  ;; A sync problem must not make an already sent message look unsent.
  (condition-case err
      (nd/notmuch-sync t)
    (error (message "Mail sent; sync unavailable: %s" (error-message-string err)))))
(add-hook 'message-sent-hook #'nd/mail-push-sent)

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
                          (cons (regexp-quote (cadr acct))
                                (format "%s/Sent +sent -inbox -unread" (car acct))))
                        nd/mail-accounts)
                (when nd/mail-accounts
                  (list (cons ".*" (format "%s/Sent +sent -inbox -unread"
                                           (caar nd/mail-accounts))))))))

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
  ;; Keep neighbouring windows intact; q restores the pre-agenda layout.
  (org-agenda-window-setup 'current-window)
  (org-agenda-restore-windows-after-quit t)
  ;; One inbox, one file per context, and the journal. Directory
  ;; entries mean a new gtd file needs no config change.
  (org-agenda-files
   '("~/org/inbox.org"
     "~/org/gtd/"
     "~/org/journal/"))
  ;; Archive out of the way rather than beside the file: %s is the file
  ;; name without its directory, so gtd/home.org lands in
  ;; archive/home.org_archive.
  (org-archive-location "~/org/archive/%s_archive::")
  (org-todo-keywords
   '((sequence "TODO(t)" "NEXT(n)" "WAIT(w@/!)" "|" "DONE(d!)" "CANC(k@)")
     (sequence "BACKLOG(b)" "PLAN(p)" "READY(r)" "ACTIVE(a)"
               "REVIEW(v)" "HOLD(h)" "|"
               "COMPLETED(c)" "DROPPED(x@)")))
  (org-log-done 'time)
  (org-log-into-drawer t)
  ;; Drawers folded on visit. `org-cycle-hide-drawer-startup' is already t
  ;; by default, but the default `showeverything' startup state is the one
  ;; value that explicitly overrides it (org-cycle.el: the whole drawer /
  ;; block / archive branch is skipped for it), so the :PROPERTIES: and
  ;; :LOGBOOK: drawers stayed open on every heading. `nofold' means the
  ;; same fully-unfolded headings, minus that override.
  (org-startup-folded 'nofold)
  (org-hide-emphasis-markers t)
  (org-ellipsis " ▼ ")
  ;; Indent headings and their body by nesting level. org-modern turns
  ;; off its own leading-star hiding under org-indent-mode, but
  ;; org-indent sets `org-hide-leading-stars' itself, so the bullet still
  ;; stands alone. Headings are monospace (see *Modern styling*), which
  ;; is what makes the steps line up at all — org-indent measures its
  ;; prefixes in space widths.
  (org-startup-indented t)
  (org-indent-indentation-per-level 1)
  (org-treat-insert-todo-heading-as-state-change t)
  ;; M-RET keeps a list item's text and children together.  Headings and
  ;; table cells retain their usual splitting behaviour.
  (org-M-RET-may-split-line '((item . nil) (default . t)))
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
  ;; Keep clarified work in the domain files. Structural headings at any
  ;; existing project depth are allowed; tasks and closed projects are not.
  (org-refile-targets '((nd/org-domain-files :maxlevel . 6)))
  (org-refile-target-verify-function #'nd/org-refile-target-p)
  (org-refile-use-outline-path 'full-file-path)
  (org-outline-path-complete-in-steps nil)
  (org-refile-allow-creating-parent-nodes 'confirm)
  ;; Own org-id database — never share Doom's.
  (org-id-locations-file (expand-file-name "org-id-locations" my/state-dir))
  ;; Link by ID, not by path. Doom set this and the port missed it: with
  ;; the default nil, `org-store-link' and the dashboard's org-ql blocks
  ;; emit file:/abs/path::*Heading, which any rename or retitle breaks.
  (org-id-link-to-org-use-id t)
  :config
  ;; File links and ID backlinks follow in the current window.
  (setf (alist-get 'file org-link-frame-setup) #'find-file)
  (add-to-list 'org-modules 'org-habit t))

;; `project' marks the project heading and nothing else. Without this it
;; is inherited by every action inside the project, and then "-project"
;; — the matcher every task block leans on — excludes exactly the
;; actions it exists to list. The context tags (@home/sigtuna/veltric/
;; nordic) are the opposite case: they SHOULD cascade, so tagging a
;; project carries its whole action tree into that context's view.
(setq org-tags-exclude-from-inheritance '("project" "focus" "meeting" "unprocessed"))

(setq org-tag-persistent-alist '(("@home" . ?h)
                                 ("sigtuna" . ?s)
                                 ("veltric" . ?v)
                                 ("nordic" . ?n)
                                 ("project" . ?p)
                                 ("focus" . ?F)
                                 ("meeting" . ?M)
                                 ("unprocessed" . ?U)
                                 ("eTjänst" . ?e)
                                 ("digitalpost" . ?d)
                                 ("sitevision" . ?S)
                                 ("VOF" . ?V)
                                 ("RPA" . ?R)
                                 ("möte" . ?m)
                                 ("idee" . ?i)
                                 ("joke" . ?j)
                                 ("insults" . ?u)
                                 ("original" . ?o)
                                 ("philosophy" . ?f)
                                 ("psychology" . ?y)
                                 ("ethos" . ?t)))

(setq org-tag-faces
      '(("project" . (:foreground "burlywood"))
        ("idee" . (:foreground "yellow" :weight bold))))

(setq org-todo-keyword-faces
      '(("TODO" . (:foreground "goldenrod" :weight bold))
        ("NEXT" . (:foreground "White" :background "ForestGreen" :weight bold))
        ;; ACTIVE inherits the slot STARTED used to hold: STARTED and VOID
        ;; came over from Doom and are not in `org-todo-keywords', so they
        ;; only ever styled text that cannot exist.
        ("ACTIVE" . (:foreground "White" :background "DarkViolet" :weight bold))
        ("WAIT" . (:foreground "White" :background "DarkOrange1" :weight bold))
        ("HOLD" . (:foreground "White" :background "SlateGray" :weight bold))
        ("DONE" . (:foreground "Silver" :weight regular))))

(setq org-priority-faces
      '((?A :foreground "#ff6c6b" :weight bold)
        (?B :foreground "#ffd966" :weight bold)
        (?C :foreground "#c678dd" :weight bold)))

(defun nd/org-modern-labels (alist)
  "Make ALIST of face plists render as filled org-modern labels."
  (mapcar (lambda (entry)
            (cons (car entry)
                  (if (plist-get (cdr entry) :background)
                      (cdr entry)
                    (append (cdr entry) '(:inverse-video t)))))
          alist))

(use-package org-modern
  :ensure nil
  :hook ((org-mode . org-modern-mode)
         ;; The agenda is assembled text, not an org buffer, so it needs
         ;; its own pass — labels there match the files they came from.
         (org-agenda-finalize . org-modern-agenda))
  :custom
  ;; Bullets per level (the org-bullets look). The default `fold' shows
  ;; ▶/▼ fold state in the star's place instead — swap if that reads
  ;; better than the ellipsis already does.
  (org-modern-star 'replace)
  ;; The block bar is drawn in the FRINGE, which stays pinned to the
  ;; window edge while visual-fill-column pushes text to the middle with
  ;; margins — the bar would float far left of the block it belongs to.
  ;; Block *names* are still styled; only the gutter rule is off.
  (org-modern-block-fringe nil)
  :config
  ;; 0.8 is org-modern's default and reads a little shrunken against
  ;; body text. These stay under 1.0 on purpose: the labels are boxed,
  ;; and at full height the box would add to the line height.
  (set-face-attribute 'org-modern-label nil :height 0.9)
  ;; Labels take their colour from the alists above, so those stay the
  ;; single source. They need one transform first: org-modern paints the
  ;; face straight onto the label, so a face carrying only a :foreground
  ;; gives tinted text in a box rather than a filled pill. Flipping it
  ;; with :inverse-video is exactly what org-modern's own default todo
  ;; face does; the keywords that already name a :background (NEXT, WAIT,
  ;; HOLD) are pills as written and are left alone.
  (setq org-modern-todo-faces (nd/org-modern-labels org-todo-keyword-faces)
        org-modern-tag-faces (nd/org-modern-labels org-tag-faces)
        org-modern-priority-faces (nd/org-modern-labels org-priority-faces)))

;; Tags right-align by padding to a fixed COLUMN, which assumes a tag
;; occupies its own character count. org-modern's are boxed labels at
;; :height 0.9 :width condensed, so their pixel width is not their
;; column width and the padding lands ragged no matter what. Park them
;; straight after the title instead.
(setq org-auto-align-tags nil
      org-tags-column 0)

(defun nd/org-journal-find-location ()
  "Open today's journal entry for capture without inserting a new heading."
  (org-journal-new-entry t)
  (unless (eq org-journal-file-type 'daily)
    (org-narrow-to-subtree))
  (goto-char (point-max)))


(defvar nd/capture-contact-name nil
  "Name being used by the current Contact capture.")

(defvar nd/capture-organization-name nil
  "Name being used by the current Organization capture.")

(defun nd/find-level-one-insertion-point (name)
  "Move to the alphabetical level-1 insertion point for NAME."
  (goto-char (point-min))
  (let ((case-fold-search t)
        found)
    (while (and (not found) (re-search-forward "^\\* " nil t))
      (let ((heading (org-get-heading t t t t)))
        (when (string-collate-lessp name heading nil t)
          (setq found (line-beginning-position)))))
    (goto-char (or found (point-max)))))

(defun nd/contact-find-location ()
  "Prompt for a contact name and find its alphabetical insertion point."
  (setq nd/capture-contact-name (string-trim (read-string "Name: ")))
  (when (string-empty-p nd/capture-contact-name) (user-error "A name is required"))
  (when (and (seq-some (lambda (entry)
                        (string-equal-ignore-case nd/capture-contact-name
                                                  (plist-get entry :name)))
                      (nd/contact-records))
             (not (yes-or-no-p "This name already exists. Create another person? ")))
    (user-error "Contact capture cancelled"))
  (nd/find-level-one-insertion-point nd/capture-contact-name))

(defun nd/organization-find-location ()
  "Prompt for an organization name and find its alphabetical insertion point."
  (setq nd/capture-organization-name (read-string "Organization name: "))
  (nd/find-level-one-insertion-point nd/capture-organization-name))

(defun nd/department-find-location ()
  "Prompt for a unit and its parent, then move to the parent heading."
  (setq nd/capture-organization-name (read-string "Unit name: "))
  (let* ((roster (nd/all-organization-roster))
         (parent (completing-read "Parent organization or unit: "
                                  (mapcar #'car roster) nil t))
         (id (cdr (assoc parent roster))))
    (unless id (user-error "Choose a parent unit"))
    (goto-char (or (org-find-entry-with-id id) (user-error "Parent unit not found")))))

(defun nd/read-tags (&rest required)
  "Prompt for multiple tags via CRM from `org-tag-persistent-alist'.
Returns tags wrapped as :tag1:tag2: or empty string if none picked."
  (let* ((candidates (mapcar (lambda (pair)
                               (if (consp pair) (car pair) pair))
                             org-tag-persistent-alist))
         (picked (delete-dups
                  (append required (completing-read-multiple "Tags: " candidates)))))
    (if picked
        (concat ":" (string-join picked ":") ":")
      "")))


(defvar nd/capture-default-title nil
  "Title captured by the Note capture template; reused in #+TITLE.")

(defun nd/notes-directory ()
  "The flat notes directory, created on first use."
  (let ((dir (expand-file-name "notes/" org-directory)))
    (unless (file-directory-p dir) (make-directory dir t))
    dir))

(defun nd/note-slug (title)
  "Filename stem for TITLE: lowercase ASCII words joined by dashes.
The real title lives in #+TITLE; the filename only has to be typeable
at a completion prompt and safe in a link, which rules out spaces and
the Swedish letters."
  (let* ((s (downcase title))
         (s (replace-regexp-in-string "[åä]" "a" s))
         (s (replace-regexp-in-string "[öø]" "o" s))
         (s (replace-regexp-in-string "[éè]" "e" s))
         (s (replace-regexp-in-string "ü" "u" s))
         (s (replace-regexp-in-string "[^a-z0-9]+" "-" s)))
    (string-trim s "-+" "-+")))

(defun nd/read-note-title ()
  "Read a nonempty note title."
  (let ((title (string-trim (read-string "Title: "))))
    (when (string-empty-p title) (user-error "A title is required"))
    title))

(defun nd/unique-note-file (path)
  "Return PATH or a numbered alternative, preserving existing notes.
File-visiting buffers reserve their names even before the first save."
  (let* ((path (expand-file-name path))
         (stem (file-name-sans-extension path))
         (extension (or (file-name-extension path t) ""))
         (candidate path)
         (number 2))
    (while (or (file-exists-p candidate) (get-file-buffer candidate))
      (setq candidate (format "%s-%d%s" stem number extension)
            number (1+ number)))
    candidate))

(defun nd/note-capture-file ()
  "Read a title and choose a new file for note capture."
  (setq nd/capture-default-title (nd/read-note-title))
  (let ((slug (nd/note-slug nd/capture-default-title)))
    (nd/unique-note-file
     (expand-file-name (concat (if (string-empty-p slug) "note" slug) ".org")
                       (nd/notes-directory)))))

(defun nd/org-meeting-heading ()
  "Return the nearest heading locally tagged meeting, including outside narrowing."
  (org-with-wide-buffer
   (unless (org-before-first-heading-p)
     (org-back-to-heading t)
     (catch 'meeting
       (while t
         (when (member "meeting" (org-get-tags nil t)) (throw 'meeting (point)))
         (unless (org-up-heading-safe) (throw 'meeting nil)))))))

(defvar nd/inbox-file "~/org/inbox.org"
  "The one capture target. Everything is routed out of it at review
time rather than filed into a context at capture time.")

(defun nd/action-to-inbox ()
  "File current line, heading, or region as a TODO into `nd/inbox-file'.
Adds a Backlink to the enclosing org entry (one level above, if the
cursor is already on a heading), preferring the enclosing meeting."
  (interactive)
  (when (and (save-excursion (beginning-of-line) (org-at-heading-p))
             (org-get-todo-state))
    (user-error "This is already a task; refile with SPC m r, or SPC m R for meeting links"))
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
         (inbox (expand-file-name nd/inbox-file))
         (src-pos (or (nd/org-meeting-heading)
                      (save-excursion
                        (org-back-to-heading t)
                        (when on-heading (org-up-heading-safe))
                        ;; Non-meeting entries retain their existing context.
                        (while (and (not (seq-intersection
                                          (org-get-tags)
                                          '("sigtuna" "veltric" "nordic" "@home")))
                                    (> (org-current-level) 2)
                                    (org-up-heading-safe)))
                        (point))))
         (src-title (org-with-wide-buffer
                      (goto-char src-pos)
                      (org-get-heading t t t t)))
         (src-id (org-with-wide-buffer
                   (goto-char src-pos)
                   (org-id-get-create)))
         (ts (format-time-string "[%Y-%m-%d %a %H:%M]")))
    (with-current-buffer (find-file-noselect inbox)
      (goto-char (point-max))
      (unless (bolp) (insert "\n"))
      (insert (format "* TODO %s\n%s\nBacklink: [[id:%s][%s]]\n"
                      action ts src-id src-title))
      (save-buffer))
    (message "Filed to inbox: %s" action)))

(defun nd/attach-url-and-insert ()
  "Attach a URL to the current entry and insert a link to it."
  (interactive)
  (call-interactively #'org-attach-url)
  (org-insert-last-stored-link 1))

(require 'org-refile)
(require 'org-id)
(require 'cl-lib)

;; Remove the earlier global override when reloading this block.
(advice-remove 'org-refile #'nd/org-refile-with-meeting-links)

(defun nd/org-refile-meeting-actions ()
  "Describe meeting actions in the subtree or region about to be moved.
Each record contains its heading index, meeting marker, and moved root's
heading index, source marker and original level.  Read only: even missing
IDs wait until a successful move."
  (when-let* ((file (buffer-file-name (buffer-base-buffer)))
              (_ (file-in-directory-p file
                                     (expand-file-name "journal/" org-directory))))
    (save-excursion
      (let* ((region (org-region-active-p))
             (start (if region
                        (save-excursion
                          (goto-char (region-beginning))
                          (line-beginning-position))
                      (org-back-to-heading t)
                      (point)))
             (end (if region (region-end) (org-end-of-subtree t t)))
             (index 0)
             (covered-until start)
             positions
             records)
        (org-with-wide-buffer
         (goto-char start)
         (while (and (< (point) end) (org-at-heading-p))
           (push (cons (point) index) positions)
           (when (and (>= (point) covered-until)
                      (member (org-get-todo-state)
                              '("TODO" "NEXT" "WAIT" "DONE" "CANC"))
                      (not (member "project" (org-get-tags nil t))))
             (let ((meeting
                    (save-excursion
                      (catch 'meeting
                        (while (org-up-heading-safe)
                          (when (member "meeting" (org-get-tags nil t))
                            (throw 'meeting (point))))))))
               ;; A meeting travelling with its tasks needs no return links.
               (when (and meeting (< meeting start))
                 (let ((root (point)))
                   ;; If a section is moved with its tasks, replace that
                   ;; section with one link at its original outline level.
                   (save-excursion
                     (while (and (org-up-heading-safe) (>= (point) start))
                       (setq root (point))))
                   (push (list index (copy-marker meeting)
                               (cdr (assq root positions))
                               ;; Deletion collapses these markers; advance
                               ;; them on insertion to retain selected order.
                               (copy-marker root t)
                               (save-excursion (goto-char root) (org-outline-level)))
                         records))
                 ;; A moved task's subtasks remain reachable through it.
                 (setq covered-until (save-excursion (org-end-of-subtree t t))))))
           (setq index (1+ index))
           (outline-next-heading)))
        (nreverse records)))))

(defun nd/org-append-id-link (id title prefix)
  "Append PREFIX and a link to ID in this entry's body unless already linked."
  (unless (nd/org-entry-links-to-id-p id)
    (goto-char (nd/org-next-heading))
    (skip-chars-backward " \t\n\r")
    (end-of-line)
    (insert "\n" prefix (org-link-make-string (concat "id:" id) title) "\n")))

(defun nd/org-link-refiled-meeting-action (meeting)
  "Link the moved task at point to MEETING and return its ID.
Return nil when rearranging a task within the same meeting."
  (let ((task (point-marker)))
    (unwind-protect
        ;; Rearranging tasks inside the same meeting needs no extra links.
        (unless (org-with-point-at meeting
                  (and (eq (or (buffer-base-buffer (marker-buffer task))
                               (marker-buffer task))
                           (or (buffer-base-buffer) (current-buffer)))
                       (<= (point) task)
                       (< task (save-excursion (org-end-of-subtree t t)))))
          (let* ((id (org-id-get-create))
                 (source (org-with-point-at meeting
                           (list (org-id-get-create) (org-get-heading t t t t)))))
            (org-with-point-at task
              (nd/org-append-id-link (car source) (cadr source) "Backlink: "))
            id))
      (set-marker task nil))))

(defun nd/org-leave-refiled-heading-link (origin level)
  "Leave a link to the moved heading at ORIGIN, using its original LEVEL."
  (let ((id (org-id-get-create))
        (title (org-get-heading t t t t)))
    (org-with-point-at origin
      (unless (bolp) (insert "\n"))
      (insert (make-string level ?*) " "
              (org-link-make-string (concat "id:" id) title))
      ;; A narrowed refile can leave the original terminating newline.
      (unless (eq (char-after) ?\n) (insert "\n")))))

(defun nd/org--refile-with-meeting-links (refile &rest args)
  "Call REFILE with ARGS, connecting meeting actions after a successful move.
Observe the insertion hook without editing either buffer until Org has
also removed the source.  This preserves region lengths and cancellation."
  (let* ((arg (car args))
         (records (when (and (derived-mode-p 'org-mode)
                             (not (org-before-first-heading-p))
                             (not org-refile-keep)
                             (memq arg '(nil 2)))
                    (nd/org-refile-meeting-actions)))
         destination)
    (unwind-protect
        (if (null records)
            (apply refile args)
          (let ((org-after-refile-insert-hook
                 (cons (lambda () (setq destination (copy-marker (point) t)))
                       org-after-refile-insert-hook)))
            (prog1 (apply refile args)
              (when destination
                (org-with-point-at destination
                  (let (roots)
                    (dolist (record records)
                      (goto-char destination)
                      (dotimes (_ (car record)) (outline-next-heading))
                      (when (nd/org-link-refiled-meeting-action (nth 1 record))
                        (unless (assq (nth 2 record) roots)
                          (push (nthcdr 2 record) roots))))
                    (dolist (root (nreverse roots))
                      (goto-char destination)
                      (dotimes (_ (car root)) (outline-next-heading))
                      (nd/org-leave-refiled-heading-link
                       (nth 1 root) (nth 2 root)))))))))
      (when destination (set-marker destination nil))
      (dolist (record records)
        (set-marker (nth 1 record) nil)
        (set-marker (nth 3 record) nil)))))

(defun nd/org-refile-with-meeting-links (&optional arg default-buffer rfloc msg)
  "Refile with links between journal meeting actions and their source.
Accept the same arguments and prefix commands as `org-refile'."
  (interactive "P")
  (nd/org--refile-with-meeting-links #'org-refile arg default-buffer rfloc msg))

(defun nd/org-agenda-refile-with-meeting-links (&optional goto rfloc no-update)
  "Refile the agenda entry with meeting links, preserving agenda updates."
  (interactive "P")
  (require 'org-agenda)
  ;; Scope the extra behaviour to this command, including errors and quits.
  (cl-letf (((symbol-function 'org-refile)
             (apply-partially #'nd/org--refile-with-meeting-links
                              (symbol-function 'org-refile))))
    (org-agenda-refile goto rfloc no-update)))

(require 'tabulated-list)
(require 'org-id)

(defun nd/contact-file (organizations)
  "Return the registry path, choosing organizations when ORGANIZATIONS is non-nil."
  (expand-file-name (if organizations "ref/organizations.org" "ref/people.org")
                    org-directory))

(defun nd/contact-records (&optional organizations)
  "Read registry records without changing IDs or moving the user's point.
People are level-one headings; organizational units have UNIT_TYPE."
  (with-current-buffer (find-file-noselect (nd/contact-file organizations))
    (org-with-wide-buffer
     (delq nil
           (org-map-entries
            (lambda ()
              (when (if organizations (org-entry-get nil "UNIT_TYPE")
                      (= (org-outline-level) 1))
                (list :id (org-entry-get nil "ID")
                      :name (org-get-heading t t t t)
                      :path (string-join (org-get-outline-path t t) " / ")
                      :aliases (condition-case nil
                                   (split-string-and-unquote
                                    (or (org-entry-get nil "ALIASES") ""))
                                 (error nil))
                      :context (or (org-entry-get nil "CONTEXT") "")
                      :unit (or (org-entry-get nil "ORG_UNIT") "")
                      :position (or (org-entry-get nil "POSITION") "")
                      :email (or (org-entry-get nil "EMAIL") "")
                      :phone (or (seq-find
                                  (lambda (value) (and value (not (string-empty-p value))))
                                  (mapcar (lambda (key) (org-entry-get nil key))
                                          '("TEL_MOBILE" "TEL_WORK" "TEL"))) "")
                      :review (org-entry-get nil "CONTACT_REVIEW")))))))))

(defun nd/contact-candidates (records &optional organizations)
  "Make unique completion labels mapped to RECORDS, including aliases.
Use full IDs only when otherwise identical labels need disambiguation."
  (let ((labels
         (delq nil
               (mapcar
                (lambda (entry)
                  (when (plist-get entry :id)
                    (cons
                     (replace-regexp-in-string
                      "," ";"
                      (concat
                       (plist-get entry (if organizations :path :name))
                       (when (plist-get entry :aliases)
                         (format " [%s]" (string-join (plist-get entry :aliases) " / ")))
                       (unless organizations
                         (format " — %s / %s"
                                 (plist-get entry :context)
                                 (org-link-display-format (plist-get entry :unit))))))
                     entry)))
                records))))
    (mapcar
     (lambda (pair)
       (cons (if (> (cl-count (car pair) labels :key #'car
                             :test #'string-equal-ignore-case) 1)
                 (format "%s <%s>" (car pair) (plist-get (cdr pair) :id))
               (car pair))
             (cdr pair)))
     labels)))

(defun nd/contact-resolve (choice candidates)
  "Resolve a displayed CHOICE or an exact name/alias to one record.
Unknown names return nil; ambiguous names require an explicit selection."
  (or (cdr (assoc-string choice candidates t))
      (let ((matches
             (delete-dups
              (mapcar #'cdr
                      (seq-filter
                       (lambda (pair)
                         (member (downcase choice)
                                 (mapcar #'downcase
                                         (cons (plist-get (cdr pair) :name)
                                               (plist-get (cdr pair) :aliases)))))
                       candidates)))))
        (when (> (length matches) 1)
          (user-error "Ambiguous name: %s; choose the full directory label" choice))
        (car matches))))

(defun nd/people-roster ()
  "Return unique alias-aware (LABEL . ID) contact choices."
  (mapcar (lambda (pair) (cons (car pair) (plist-get (cdr pair) :id)))
          (nd/contact-candidates (nd/contact-records))))

(defun nd/all-organization-roster ()
  "Return unique alias-aware (BREADCRUMB . ID) unit choices."
  (mapcar (lambda (pair) (cons (car pair) (plist-get (cdr pair) :id)))
          (nd/contact-candidates (nd/contact-records t) t)))

(defun nd/organization-heading-for-id (id)
  "Return the canonical organization heading for ID."
  (plist-get (seq-find (lambda (entry) (equal id (plist-get entry :id)))
                      (nd/contact-records t)) :name))

(defun nd/org-id-from-link (link)
  "Return the ID from an Org LINK string, or nil."
  (when (and link (string-match "\\[\\[id:\\([^]]+\\)\\]" link))
    (match-string 1 link)))

(defun nd/org-linked-values (text)
  "Split comma-separated TEXT without splitting inside Org links."
  (let ((start 0) values)
    (while (string-match org-link-bracket-re (or text "") start)
      (let ((before (substring text start (match-beginning 0)))
            (link (match-string 0 text))
            (end (match-end 0)))
        (setq values (append values (split-string before "," t "[ \t\n]+") (list link))
              start end)))
    (append values (split-string (substring (or text "") start) "," t "[ \t\n]+"))))

(defun nd/org-completion-with-current (current candidates)
  "Return (CANDIDATES . INITIAL-INPUT), retaining selections in CURRENT.
CANDIDATES maps labels to stored values.  Match links by ID, and keep
missing records as choices so editing another selection cannot drop them."
  (setq candidates (mapcar (lambda (pair) (cons (string-trim (car pair)) (cdr pair)))
                          candidates))
  (let (initial)
    (dolist (value (nd/org-linked-values current))
      (let* ((id (nd/org-id-from-link value))
             (existing (seq-find
                        (lambda (pair)
                          (if id (equal id (nd/org-id-from-link (cdr pair)))
                            (equal value (cdr pair)))) candidates))
             (label (or (car existing)
                        (replace-regexp-in-string "," ";" (org-link-display-format value)))))
        (unless existing
          (let ((base label) (suffix 1))
            (while (assoc label candidates)
              (setq label (format "%s <%d>" base suffix)
                    suffix (1+ suffix))))
          (push (cons label value) candidates))
        (push label initial)))
    (cons candidates (string-join (nreverse initial) ", "))))

(defun nd/read-organizational-unit (&optional current)
  "Select a unit ID link, initially CURRENT; empty input clears it."
  (let* ((choices (nd/org-completion-with-current
                   current
                   (mapcar (lambda (pair)
                             (cons (car pair)
                                   (org-link-make-string
                                    (concat "id:" (plist-get (cdr pair) :id))
                                    (plist-get (cdr pair) :name))))
                           (nd/contact-candidates (nd/contact-records t) t))))
         (choice (completing-read "Organisational unit (empty for none): "
                                  (car choices) nil t (cdr choices))))
    (or (cdr (assoc choice (car choices))) "")))

(defun nd/read-contact-context (&optional current)
  "Edit CURRENT context, suggesting existing and usual values."
  (downcase
   (string-trim
    (completing-read "Context (optional): "
                     (delete-dups
                      (append '("sigtuna" "private" "veltric" "nordic")
                              (mapcar (lambda (entry) (plist-get entry :context))
                                      (nd/contact-records))))
                     nil nil current)
    "[: \t]+" "[: \t]+")))

(defun nd/read-attendees (&optional current)
  "Edit CURRENT attendees by name/alias, retaining guests and deduplicating IDs."
  (let* ((candidates (nd/contact-candidates (nd/contact-records)))
         (choices (nd/org-completion-with-current
                   current
                   (mapcar (lambda (pair)
                             (cons (car pair)
                                   (org-link-make-string
                                    (concat "id:" (plist-get (cdr pair) :id))
                                    (plist-get (cdr pair) :name)))) candidates)))
         (picked (completing-read-multiple "Attendees (comma-separated): "
                                           (car choices) nil nil (cdr choices)))
         seen links)
    (dolist (raw picked)
      (let* ((name (string-trim raw))
             (stored (cdr (assoc name (car choices))))
             (entry (unless stored (nd/contact-resolve name candidates)))
             (value (or stored
                        (when entry
                          (org-link-make-string (concat "id:" (plist-get entry :id))
                                                (plist-get entry :name)))
                        name))
             (id (nd/org-id-from-link value))
             (key (if id (concat "id:" id) (concat "name:" (downcase value)))))
        (unless (or (string-empty-p name) (member key seen))
          (push key seen)
          (push value links))))
    (string-join (nreverse links) ", ")))

(defun nd/organization-subtree-ids (id)
  "Return IDs of the registered unit ID and its nested units."
  (with-current-buffer (find-file-noselect (nd/contact-file t))
    (org-with-wide-buffer
     (goto-char (or (and id (org-find-entry-with-id id))
                    (user-error "Choose an organizational unit")))
     (save-restriction
       (org-narrow-to-subtree)
       (delq nil (org-map-entries
                  (lambda () (when (org-entry-get nil "UNIT_TYPE") (org-id-get)))))))))

(defvar-local nd/contacts-unit-ids nil)
(defvar-local nd/contacts-context nil)
(defvar-local nd/contact-view-id nil)

(defun nd/contacts-refresh ()
  "Refresh directory rows from the registries, retaining its filters."
  (setq tabulated-list-entries
        (delq nil
              (mapcar
               (lambda (entry)
                 (when (and (plist-get entry :id)
                            (or (null nd/contacts-unit-ids)
                                (member (nd/org-id-from-link (plist-get entry :unit))
                                        nd/contacts-unit-ids))
                            (or (null nd/contacts-context)
                                (equal nd/contacts-context (plist-get entry :context))))
                   (list (plist-get entry :id)
                         (vector (plist-get entry :name) (plist-get entry :position)
                                 (org-link-display-format (plist-get entry :unit))
                                 (plist-get entry :context) (plist-get entry :email)
                                 (plist-get entry :phone)
                                 (string-join (plist-get entry :aliases) " / ")))))
               (nd/contact-records))))
  (tabulated-list-print t))

(define-derived-mode nd/contacts-mode tabulated-list-mode "Contacts"
  "Contact directory. RET opens a person; e edits details; h shows references."
  (setq tabulated-list-format [("Name" 26 t) ("Position" 26 t) ("Unit" 30 t)
                               ("Context" 10 t) ("Email" 25 t) ("Phone" 18 t)
                               ("Aliases" 20 t)]
        tabulated-list-padding 1
        tabulated-list-sort-key '("Name" . nil))
  (add-hook 'tabulated-list-revert-hook #'nd/contacts-refresh nil t)
  (tabulated-list-init-header))

(defun nd/contacts (&optional unit-ids title)
  "Open the contact directory, optionally limited to UNIT-IDS with TITLE."
  (interactive)
  (with-current-buffer (get-buffer-create "*Contacts*")
    (nd/contacts-mode)
    (setq nd/contacts-unit-ids unit-ids
          mode-line-process (list (concat ": " (or title "All contacts"))))
    (nd/contacts-refresh)
    (pop-to-buffer-same-window (current-buffer))
    (message "RET person · e details · h history · / context · o unit · a all · g refresh")))

(defun nd/contacts-filter-context ()
  "Filter this directory by context, keeping its selected organization."
  (interactive)
  (let ((choice (completing-read
                 "Context (blank for all): "
                 (delete-dups (mapcar (lambda (entry) (plist-get entry :context))
                                     (nd/contact-records))) nil t)))
    (setq nd/contacts-context (unless (string-empty-p choice) choice))
    (nd/contacts-refresh)
    (message "Context: %s" (or nd/contacts-context "all"))))

(defun nd/list-contacts-by-org-unit ()
  "Open contacts belonging to a selected unit or any of its descendants."
  (interactive)
  (let* ((roster (nd/all-organization-roster))
         (choice (completing-read "Organization or unit: " roster nil t)))
    (nd/contacts (nd/organization-subtree-ids (cdr (assoc choice roster))) choice)))

(defun nd/contact-current-id ()
  "Return the selected directory/person/link ID when it identifies a contact."
  (let ((id (cond ((derived-mode-p 'nd/contacts-mode) (tabulated-list-get-id))
                  ((derived-mode-p 'org-mode)
                   (or (let ((element (org-element-context)))
                         (when (and (eq (org-element-type element) 'link)
                                    (equal (org-element-property :type element) "id"))
                           (org-element-property :path element)))
                       (save-excursion
                         (unless (org-before-first-heading-p)
                           (org-back-to-heading t)
                           (while (org-up-heading-safe))
                           (org-entry-get nil "ID"))))))))
    (when (seq-some (lambda (entry) (equal id (plist-get entry :id)))
                    (nd/contact-records))
      id)))

(defun nd/contact-read-id ()
  "Use the contact at point or prompt for an unambiguous contact."
  (or (nd/contact-current-id)
      (let* ((candidates (nd/contact-candidates (nd/contact-records)))
             (choice (completing-read "Person: " candidates nil t))
             (entry (cdr (assoc choice candidates))))
        (or (plist-get entry :id) (user-error "Choose a person")))))

(defun nd/contact-open (&optional id)
  "Open/reuse a focused editable view of person ID, or choose a person."
  (interactive)
  (let* ((id (or id (nd/contact-read-id)))
         (base (find-file-noselect (nd/contact-file nil)))
         title start end view)
    (with-current-buffer base
      (org-with-wide-buffer
       (goto-char (or (org-find-entry-with-id id) (user-error "Contact not found")))
       (setq title (format "*Person: %s*" (org-get-heading t t t t))
             start (point)
             end (save-excursion (org-end-of-subtree t t) (point))
             view (or (seq-find (lambda (buffer)
                                  (and (eq (buffer-base-buffer buffer) base)
                                       (equal (buffer-local-value 'nd/contact-view-id buffer) id)))
                                (buffer-list))
                      (clone-indirect-buffer title nil)))))
    (with-current-buffer view
      (setq-local nd/contact-view-id id)
      (unless (equal title (buffer-name))
        (rename-buffer (generate-new-buffer-name title (buffer-name))))
      (widen)
      (narrow-to-region start end)
      (goto-char start)
      (org-fold-show-subtree))
    (pop-to-buffer-same-window view)
    view))

(defun nd/contact-edit-details (&optional field)
  "Edit one FIELD of the selected contact, directory entry or person view."
  (interactive)
  (let ((id (nd/contact-read-id)))
    (with-current-buffer (find-file-noselect (nd/contact-file nil))
      (org-with-wide-buffer
       (goto-char (or (org-find-entry-with-id id) (user-error "Contact not found")))
       (let* ((fields '(("Context" . "CONTEXT") ("Organisation" . "ORG_UNIT")
                        ("Position" . "POSITION") ("Email" . "EMAIL")
                        ("Mobile" . "TEL_MOBILE") ("Aliases" . "ALIASES")))
              (field (or field (completing-read "Contact detail: " fields nil t)))
              (property (or (cdr (assoc field fields)) (user-error "Unknown contact detail: %s" field)))
              (current (org-entry-get nil property))
              (value (pcase field
                       ("Context" (nd/read-contact-context current))
                       ("Organisation" (nd/read-organizational-unit current))
                       (_ (string-trim (read-string (concat field ": ") current))))))
         (org-entry-put nil property value))))
    (when (derived-mode-p 'nd/contacts-mode) (nd/contacts-refresh))))

(defun nd/contact-history (&optional id)
  "Find exact links to person ID in Org files and archives.
This is reference history, not a claim that every mention is attendance.
Search uses saved files; plain-text names cannot establish identity."
  (interactive)
  (require 'xref)
  (let* ((id (or id (nd/contact-read-id)))
         (pattern (regexp-quote (concat "[[id:" id "]")))
         (files (directory-files-recursively org-directory "\\.org\\(?:_archive\\)?\\'")))
    (xref-show-xrefs (lambda () (xref-matches-in-files pattern files)) nil)))

(defun nd/contacts-check ()
  "Report missing IDs, context, unresolved units and explicit review notes."
  (interactive)
  (let* ((units (nd/contact-records t))
         (ids (mapcar (lambda (entry) (plist-get entry :id)) units))
         rows)
    (dolist (entry (nd/contact-records))
      (let (issues)
        (unless (plist-get entry :id) (push "Missing ID" issues))
        (when (string-empty-p (plist-get entry :context)) (push "Context not set" issues))
        (when (and (not (string-empty-p (plist-get entry :unit)))
                   (not (member (nd/org-id-from-link (plist-get entry :unit)) ids)))
          (push "ORG_UNIT is not a registered unit" issues))
        (when (plist-get entry :review) (push (plist-get entry :review) issues))
        (when issues
          (push (format "- %s :: %s\n"
                        (if (plist-get entry :id)
                            (org-link-make-string (concat "id:" (plist-get entry :id))
                                                  (plist-get entry :name))
                          (plist-get entry :name))
                        (string-join (nreverse issues) "; ")) rows))))
    (with-current-buffer (get-buffer-create "*Contact checks*")
      (let ((inhibit-read-only t))
        (erase-buffer)
        (insert "#+title: Contact checks\n\n"
                (if rows (apply #'concat (nreverse rows)) "No contact issues found.\n"))
        (org-mode)
        (goto-char (point-min))
        (view-mode 1))
      (pop-to-buffer-same-window (current-buffer)))))

(dolist (binding '(("RET" . nd/contact-open) ("e" . nd/contact-edit-details)
                   ("h" . nd/contact-history)
                   ("/" . nd/contacts-filter-context) ("o" . nd/list-contacts-by-org-unit)
                   ("a" . nd/contacts) ("g" . revert-buffer) ("q" . quit-window)))
  (define-key nd/contacts-mode-map (kbd (car binding)) (cdr binding)))

(with-eval-after-load 'evil
  (evil-set-initial-state 'nd/contacts-mode 'normal)
  (dolist (binding '(("RET" . nd/contact-open) ("e" . nd/contact-edit-details)
                     ("h" . nd/contact-history)
                     ("/" . nd/contacts-filter-context) ("o" . nd/list-contacts-by-org-unit)
                     ("a" . nd/contacts) ("g" . revert-buffer) ("q" . quit-window)))
    (evil-define-key 'normal nd/contacts-mode-map (kbd (car binding)) (cdr binding))))

(defun nd/project-template (context)
  "Capture body for a new project in CONTEXT.
Projects take their state from the second sequence in
`org-todo-keywords'; actions take TODO/NEXT/WAIT from the first. Tags are written in
rather than prompted for — a project that is not tagged `project' is
invisible to every agenda block, and one without its context tag cannot
be filtered to."
  (concat "* PLAN %^{Project} :project:" context ":\n"
          ":PROPERTIES:\n:ID: %(org-id-new)\n:END:\n"
          "Klart när: \nNuläge: \nÅteruppta: %?\nUppdaterad: %U\n"
          "** Mål [/]\n- [ ] \n"
          "** Faser\n*** Fas 1\n"
          "** Risker och öppna frågor\n"))

(with-eval-after-load 'org
  (setq org-capture-templates
        `(("i" "Inbox — clarify later" entry (file ,nd/inbox-file)
           "* %?\n%U\n%a")

          ("p" "Project")
          ("ps" "Sigtuna" entry (file "~/org/gtd/sigtuna.org")
           ,(nd/project-template "sigtuna"))
          ("pv" "Veltric" entry (file "~/org/gtd/veltric.org")
           ,(nd/project-template "veltric"))
          ("pn" "Nordic" entry (file "~/org/gtd/nordic.org")
           ,(nd/project-template "nordic"))
          ("ph" "Home" entry (file "~/org/gtd/home.org")
           ,(nd/project-template "@home"))

          ("n" "Note" plain
           (file nd/note-capture-file)
           ":PROPERTIES:\n:ID:       %(org-id-new)\n:END:\n#+TITLE: %(progn nd/capture-default-title)\n#+AUTHOR: %n\n#+DATE: %u\n\n%?"
           :unnarrowed t)

          ("f" "Note at a path I pick" plain
           (file (lambda ()
                   (let* ((default-directory (nd/notes-directory))
                          (path (read-file-name "New org file: " default-directory)))
                     (nd/unique-note-file
                      (if (string-suffix-p ".org" path) path (concat path ".org"))))))
           ":PROPERTIES:\n:ID:       %(org-id-new)\n:END:\n#+TITLE: %(nd/read-note-title)\n#+AUTHOR: %n\n#+DATE: %u\n\n%?"
           :unnarrowed t)

          ("c" "Contact" entry
           (file+function ,(nd/contact-file nil) nd/contact-find-location)
           "* %(progn nd/capture-contact-name)\n:PROPERTIES:\n:ID:         %(org-id-new)\n:ALIASES:\n:CONTEXT:\n:ORG_UNIT:\n:POSITION:\n:EMAIL:\n:TEL_MOBILE:\n:END:\n%?"
           :empty-lines 1
           :insert-here t)

          ("o" "Organization" entry
           (file+function ,(nd/contact-file t)
                          nd/organization-find-location)
           "* %(progn nd/capture-organization-name)\n:PROPERTIES:\n:ID:        %(org-id-new)\n:ALIASES:\n:UNIT_TYPE: %^{Unit type||municipality|company|authority|association|university}\n:WEBSITE:   %^{Website}\n:EMAIL:     %^{Email}\n:TEL:       %^{Telephone}\n:END:\n%?"
           :empty-lines 1
           :insert-here t)

          ("d" "Organizational unit" entry
           (file+function ,(nd/contact-file t)
                          nd/department-find-location)
           "* %(progn nd/capture-organization-name)\n:PROPERTIES:\n:ID:        %(org-id-new)\n:ALIASES:\n:UNIT_TYPE: %^{Unit type||förvaltning|kontor|avdelning|enhet|team}\n:END:\n%?"
           :empty-lines 1)

          ("jm" "Meeting" plain (function nd/org-journal-find-location)
           "** %(format-time-string org-journal-time-format)%^{Title} :meeting:unprocessed:\n:PROPERTIES:\n:ID: %(org-id-new)\n:ATTENDEES:\n:ORG_UNIT:\n:END:\n%U\nProject: \n\n*** Agenda\n\n*** Notes\n%?\n\n*** Decisions\n\n*** Actions\n")
          ("jw" "Work log" plain (function nd/org-journal-find-location)
           "** %(format-time-string org-journal-time-format)%^{Title} %(nd/read-tags)\n- Done :: %?\n- Blockers ::\n")
          ("ji" "Idea" plain (function nd/org-journal-find-location)
           "** %(format-time-string org-journal-time-format)%^{Title} :idee:\n%?")))

  ;; Org registers pasted/captured IDs itself. Do not rescan the initiating
  ;; buffer from an after-finalize hook: that is not the capture target.
  )

(use-package org-journal
  :ensure nil
  :commands (org-journal-new-entry
             org-journal-open-current-journal-file
             org-journal-search)
  ;; Match the existing yearly files and enable journal commands on visit.
  :mode ("/org/journal/[0-9]\\{4\\}\\.org\\'" . org-journal-mode)
  :init
  ;; The upstream %Y%m%d default would create a second file for the year.
  (setq org-journal-dir "~/org/journal/"
        org-journal-date-format "%A, %Y %B %d"
        org-journal-file-format "%Y.org"
        org-journal-file-type 'yearly
        org-journal-file-header "#+title: Journal %Y\n#+startup: overview\n"))

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

(use-package org-download
  :ensure nil
  :after org
  :config
  ;; One directory for every binary: dragged-in images, org-attach's
  ;; id-addressed subdirectories, and the pile the Obsidian import left
  ;; behind all live in ~/org/attachments now.
  (setq org-download-image-dir "~/org/attachments"
        org-download-method 'directory
        org-download-heading-lvl nil))

(with-eval-after-load 'org-attach
  (setq org-attach-id-dir "~/org/attachments/"))

(defun nd/org-auto-save-p ()
  "Whether the current buffer is a local Org file under `org-directory'."
  (with-current-buffer (or (buffer-base-buffer) (current-buffer))
    (and buffer-file-name
         (derived-mode-p 'org-mode)
         (not (file-remote-p buffer-file-name))
         (file-in-directory-p buffer-file-name (expand-file-name org-directory)))))

;; This mode is global; an Org hook would enable saving for every file.
(remove-hook 'org-mode-hook #'auto-save-visited-mode)
(setq auto-save-visited-predicate #'nd/org-auto-save-p)
(auto-save-visited-mode 1)

(require 'org-id)
(require 'org-agenda)
(require 'org-element)
(require 'seq)

(defconst nd/org-project-states
  '("BACKLOG" "PLAN" "READY" "ACTIVE" "REVIEW" "HOLD" "COMPLETED" "DROPPED"))
(defconst nd/org-closed-project-states '("COMPLETED" "DROPPED" "DONE" "CANC"))

(defun nd/org-domain-files ()
  "Return the existing domain files under org-directory/gtd."
  (let ((directory (expand-file-name "gtd/" org-directory)))
    (when (file-directory-p directory)
      (directory-files directory t "\\`[^.].*\\.org\\'"))))

(defun nd/org-journal-files ()
  "Discover all yearly journals independently of agenda membership."
  (let ((directory (expand-file-name "journal/" org-directory)))
    (when (file-directory-p directory)
      (directory-files-recursively directory "\\.org\\'"))))

(defun nd/org-local-project-p ()
  "Whether this heading explicitly has the project tag."
  (member "project" (org-get-tags nil t)))

(defun nd/org-in-project-p (&optional states)
  "Whether this entry has a project ancestor, optionally in STATES."
  (save-match-data
    (save-restriction
      (widen)
      (save-excursion
        (org-back-to-heading t)
        (catch 'found
          (while t
            (when (and (nd/org-local-project-p)
                       (or (null states) (member (org-get-todo-state) states)))
              (throw 'found t))
            (unless (org-up-heading-safe) (throw 'found nil))))))))

(defun nd/org-next-heading ()
  "Return the next heading position, including children."
  (save-excursion (outline-next-heading) (point)))

(defun nd/org-hidden-entry-p ()
  (or (org-in-archived-heading-p) (org-in-commented-heading-p)))

(defun nd/org-skip-unavailable ()
  "Skip action selection in held, backlog, finished or someday work."
  (when (or (nd/org-hidden-entry-p)
            (member "someday" (org-get-tags))
            (nd/org-in-project-p
             (append '("HOLD" "BACKLOG") nd/org-closed-project-states)))
    (nd/org-next-heading)))

(defun nd/org-skip-finished ()
  "Keep dated obligations in held projects, but omit finished contexts."
  (when (or (nd/org-hidden-entry-p)
            (nd/org-in-project-p nd/org-closed-project-states))
    (nd/org-next-heading)))

(defun nd/org-skip-covered-project ()
  "Keep active projects lacking NEXT or a WAIT with a follow-up date."
  (when (or (nd/org-skip-unavailable)
            (save-match-data
              (save-excursion
                (save-restriction
                  (let ((org-agenda-skip-function nil)
                        (org-agenda-skip-function-global nil))
                    (catch 'covered
                      (org-map-entries
                       (lambda ()
                         (when (and (not (nd/org-local-project-p))
                                    (not (nd/org-skip-unavailable))
                                    (or (equal (org-get-todo-state) "NEXT")
                                        (and (equal (org-get-todo-state) "WAIT")
                                             (org-entry-get nil "SCHEDULED"))))
                           (throw 'covered t))) nil 'tree)
                      nil))))))
    (nd/org-next-heading)))

(defun nd/org-skip-valid-project ()
  "Keep project roots whose lifecycle state needs clarification."
  (when (or (nd/org-hidden-entry-p)
            (member (org-get-todo-state) nd/org-project-states))
    (nd/org-next-heading)))

(defun nd/org-skip-unless-residual ()
  "Keep unfinished non-project entries inside finished projects."
  (unless (and (not (nd/org-hidden-entry-p))
               (not (nd/org-local-project-p))
               (member (org-get-todo-state) org-not-done-keywords)
               (nd/org-in-project-p nd/org-closed-project-states))
    (nd/org-next-heading)))

(defun nd/org-skip-project-task ()
  "Keep standalone backlog entries, regardless of their heading depth."
  (when (or (nd/org-in-project-p) (nd/org-skip-unavailable))
    (nd/org-next-heading)))

(defun nd/org-skip-dated-wait ()
  "Keep waiting entries without a scheduled follow-up date."
  (when (or (nd/org-skip-finished) (org-entry-get nil "SCHEDULED"))
    (nd/org-next-heading)))

(defun nd/org-skip-inbox-structure ()
  "Keep open captures at the top level or under a domain heading."
  (let ((level (org-outline-level))
        (groups '("Sigtuna" "Home" "Nordic" "Veltric")))
    (unless
        (and (not (nd/org-hidden-entry-p))
             (not (member (org-get-todo-state) org-done-keywords))
             (or (and (= level 1)
                      (not (member (org-get-heading t t t t) groups)))
                 (and (= level 2)
                      (save-excursion
                        (org-up-heading-safe)
                        (member (org-get-heading t t t t) groups)))))
      (nd/org-next-heading))))

(defun nd/org-refile-target-p ()
  "Allow structural headings and open project roots as refile targets."
  (and (not (nd/org-skip-finished))
       (or (null (org-get-todo-state))
           (and (nd/org-local-project-p)
                (member (org-get-todo-state) org-not-done-keywords)))))

(defun nd/read-waiting-for (&optional current)
  "Read one contact or free-text owner, retaining CURRENT ID links."
  (let* ((candidates (nd/contact-candidates (nd/contact-records)))
         (choices (nd/org-completion-with-current
                   current
                   (mapcar (lambda (pair)
                             (cons (car pair)
                                   (org-link-make-string
                                    (concat "id:" (plist-get (cdr pair) :id))
                                    (plist-get (cdr pair) :name)))) candidates)))
         (name (string-trim
                (completing-read "Waiting for (contact or name): "
                                 (car choices) nil nil (cdr choices))))
         (stored (cdr (assoc name (car choices))))
         (entry (unless stored (nd/contact-resolve name candidates))))
    (when (string-empty-p name) (user-error "Choose who you are waiting for"))
    (or stored
        (when entry (org-link-make-string (concat "id:" (plist-get entry :id))
                                          (plist-get entry :name)))
        name)))

(defun nd/org-waiting-for ()
  "Set a task to WAIT with an owner and scheduled follow-up.
Works in Org and the agenda.  Prompts finish before any edits; the owner
and date replace WAIT's usual free-form state-change note."
  (interactive)
  (let* ((agenda (derived-mode-p 'org-agenda-mode))
         (marker (if agenda
                     (or (org-get-at-bol 'org-hd-marker) (org-get-at-bol 'org-marker))
                   (and (derived-mode-p 'org-mode) (point-marker)))))
    (unless (and (markerp marker) (marker-buffer marker))
      (user-error "Select an open task"))
    (org-with-point-at marker
      (org-with-wide-buffer
       (org-back-to-heading t)
       (when (or (nd/org-local-project-p)
                 (not (member (org-get-todo-state) '(nil "TODO" "NEXT" "WAIT"))))
         (user-error "Select an open task, not a project"))
       (let* ((owner (nd/read-waiting-for (org-entry-get nil "WAITING_FOR")))
              (scheduled (org-entry-get nil "SCHEDULED"))
              (date (org-read-date nil nil nil "Follow up: "
                                   (when scheduled (org-time-string-to-time scheduled)))))
         (atomic-change-group
           (let ((org-inhibit-logging t)
                 (org-log-reschedule nil))
             (org-entry-put nil "WAITING_FOR" owner)
             (org-todo "WAIT")
             (org-schedule nil date))))))
    (when agenda (org-agenda-redo))))

(defun nd/org-wait-prefix ()
  "Show a waiting entry's owner and follow-up in agenda prefixes."
  (let ((owner (org-entry-get nil "WAITING_FOR"))
        (date (org-entry-get nil "SCHEDULED")))
    (format "%s · %s | "
            (if (and owner (not (string-empty-p owner)))
                (org-link-display-format owner) "owner missing")
            (if date (substring date 1 -1) "no follow-up"))))

(defun nd/org-project-marker ()
  "Return a marker at the containing project, also from an agenda entry.
Look outside any narrowing, without changing the source buffer's view."
  (let ((marker (if (derived-mode-p 'org-agenda-mode)
                    (or (org-get-at-bol 'org-hd-marker)
                        (org-get-at-bol 'org-marker))
                  (and (derived-mode-p 'org-mode) (point-marker)))))
    (unless (and (markerp marker) (marker-buffer marker))
      (user-error "Select a project or one of its tasks"))
    (with-current-buffer (marker-buffer marker)
      (save-restriction
        (widen)
        (save-excursion
          (goto-char marker)
          (org-back-to-heading t)
          (while (and (not (nd/org-local-project-p)) (org-up-heading-safe)))
          (unless (nd/org-local-project-p)
            (user-error "No containing heading tagged :project:"))
          (copy-marker (point)))))))

(defun nd/org-project-summary-field (label)
  "Find a LABEL line in this entry's prose, returning (POSITION . VALUE).
Ignore child headings, drawers and literal examples."
  (save-excursion
    (org-back-to-heading t)
    (let ((end (nd/org-next-heading)))
      (forward-line)
      (catch 'field
        (while (re-search-forward (concat "^" (regexp-quote label) ":[ \t]*\\(.*\\)$") end t)
          (let ((position (line-beginning-position))
                (value (match-string-no-properties 1)))
            (when (eq (org-element-type (org-element-at-point)) 'paragraph)
              (throw 'field (cons position value)))))))))

(defun nd/org-project-set-summary-field (label value)
  "Set this entry's prose LABEL to VALUE, adding a missing line."
  (save-excursion
    (let ((field (nd/org-project-summary-field label)))
      (if field
          (progn (goto-char (car field))
                 (delete-region (point) (line-end-position)))
        (goto-char (nd/org-next-heading))
        (unless (bolp) (insert "\n")))
      (insert label ": " value)
      (unless field (insert "\n")))))

(defun nd/org-project-update ()
  "Edit Nuläge and Återuppta on the containing project's resume card.
Refresh Uppdaterad only when a summary changes or a missing field is added.
Works from a child, an indirect view or an agenda entry."
  (interactive)
  (let ((agenda (derived-mode-p 'org-agenda-mode))
        (marker (nd/org-project-marker)))
    (org-with-point-at marker
      (org-with-wide-buffer
       (let* ((status (nd/org-project-summary-field "Nuläge"))
              (resume (nd/org-project-summary-field "Återuppta"))
              (new-status (read-string "Nuläge: " (cdr status)))
              (new-resume (read-string "Återuppta: " (cdr resume))))
         (unless (and status resume
                      (equal new-status (cdr status)) (equal new-resume (cdr resume)))
           (atomic-change-group
             (nd/org-project-set-summary-field "Nuläge" new-status)
             (nd/org-project-set-summary-field "Återuppta" new-resume)
             (nd/org-project-set-summary-field
              "Uppdaterad" (format-time-string (org-time-stamp-format t t))))))))
    (when agenda (org-agenda-redo))))

(defun nd/org-project-at-point ()
  "Read the containing project's (ID TITLE), also from an agenda entry."
  (org-with-point-at (nd/org-project-marker)
    (let ((id (org-entry-get nil "ID")))
      (unless id (user-error "Create an ID on the project with SPC m I first"))
      (list id (org-get-heading t t t t)))))

(defvar-local nd/org-project-view-id nil
  "Project ID identifying a reusable indirect project view.")

(defun nd/org-open-project ()
  "Open or reuse an indirect view of the containing project.
Works from a project, one of its tasks, or an agenda entry.  Edits share
the original file; point, narrowing and folding are independent.  Reuse
is keyed by project ID and base buffer, not by the project title."
  (interactive)
  (let* ((marker (nd/org-project-marker))
         (source (marker-buffer marker))
         (base (or (buffer-base-buffer source) source))
         id title start end view existing)
    (with-current-buffer base
      (save-excursion
        (save-restriction
          (widen)
          (goto-char marker)
          (setq id (org-entry-get nil "ID"))
          (unless id (user-error "Create an ID on the project with SPC m I first"))
          (setq title (format "*Project: %s / %s*"
                              (if buffer-file-name (file-name-base buffer-file-name)
                                (buffer-name))
                              (org-get-heading t t t t))
                start (point)
                end (save-excursion (org-end-of-subtree t t) (point))
                existing
                (seq-find (lambda (buffer)
                            (and (eq (buffer-base-buffer buffer) base)
                                 (equal (buffer-local-value 'nd/org-project-view-id buffer)
                                        id)))
                          (buffer-list))
                ;; Cloning runs Org's hook for independent folding state.
                view (or existing (clone-indirect-buffer title nil))))))
    (with-current-buffer view
      (setq-local nd/org-project-view-id id)
      (unless (equal (buffer-name) title)
        (rename-buffer (generate-new-buffer-name title (buffer-name))))
      (widen)
      (narrow-to-region start end)
      (unless existing
        (goto-char start)
        (org-fold-hide-subtree)
        (org-fold-show-entry t)
        (org-fold-show-children)))
    (pop-to-buffer-same-window view)
    view))

(defun nd/org-entry-links-to-id-p (id)
  "Match an actual ID link in this entry's body, before any children."
  (save-match-data
    (save-excursion
      (save-restriction
        (org-back-to-heading t)
        (narrow-to-region (point) (nd/org-next-heading))
        (org-element-map (org-element-parse-buffer) 'link
          (lambda (link)
            (and (equal (org-element-property :type link) "id")
                 (equal (org-element-property :path link) id))) nil t)))))

(defun nd/org-project-meetings ()
  "Show meetings linking to this project across all yearly journals."
  (interactive)
  (let* ((project (nd/org-project-at-point))
         (files (nd/org-journal-files)))
    (require 'org-ql-search)
    (unless files (user-error "No journals found"))
    (org-ql-search files
      `(and (tags-local "meeting") (nd/org-entry-links-to-id-p ,(car project)))
      :narrow nil :super-groups nil :sort nil
      :title (concat "Meetings — " (cadr project)))))

(defun nd/org-read-project-links (&optional current)
  "Edit CURRENT project links, keeping existing closed or missing projects."
  (let (roster)
    (dolist (file (nd/org-domain-files))
      (with-current-buffer (find-file-noselect file)
        (org-with-wide-buffer
         (org-map-entries
          (lambda ()
            (when (and (nd/org-local-project-p) (not (nd/org-skip-finished)))
              (when-let* ((id (org-entry-get nil "ID")))
                (push (cons (format "%s / %s" (file-name-base file)
                                    (org-get-heading t t t t)) id) roster)))) nil nil))))
    (setq roster (nreverse roster))
    (let* ((candidates
            (mapcar
             (lambda (pair)
               (let ((label (replace-regexp-in-string "," ";" (car pair))))
                 (cons (if (> (cl-count label roster
                                       :key (lambda (item)
                                              (replace-regexp-in-string "," ";" (car item)))
                                       :test #'equal) 1)
                           (format "%s <%s>" label (cdr pair))
                         label)
                       (org-link-make-string (concat "id:" (cdr pair)) (car pair)))))
             roster))
           (choices (nd/org-completion-with-current current candidates)))
      (mapconcat
       (lambda (name) (cdr (assoc name (car choices))))
       (delete-dups
        (completing-read-multiple "Projects (comma-separated): "
                                  (car choices) nil t (cdr choices)))
       ", "))))

(defun nd/org-meeting-details (&optional field)
  "Edit one FIELD of the containing meeting, also from the agenda.
Existing selections are editable input; delete them to clear a field.
Meeting and review tags are preserved.  Use `org-set-tags-command' to
remove unprocessed after reviewing decisions and filing actions."
  (interactive)
  (let* ((agenda (derived-mode-p 'org-agenda-mode))
         (marker (if agenda
                     (or (org-get-at-bol 'org-hd-marker) (org-get-at-bol 'org-marker))
                   (and (derived-mode-p 'org-mode) (point-marker)))))
    (unless (and (markerp marker) (marker-buffer marker))
      (user-error "Select a meeting or an entry inside it"))
    (org-with-point-at marker
      (org-with-wide-buffer
       (goto-char (or (nd/org-meeting-heading)
                      (user-error "No containing heading tagged :meeting:")))
       (let ((field (or field (completing-read "Meeting detail: "
                                             '("Attendees" "Organisation" "Projects" "Tags")
                                             nil t))))
         (atomic-change-group
           (pcase field
             ("Attendees"
              (org-entry-put nil "ATTENDEES" (nd/read-attendees (org-entry-get nil "ATTENDEES"))))
             ("Organisation"
              (org-entry-put nil "ORG_UNIT" (nd/read-organizational-unit (org-entry-get nil "ORG_UNIT"))))
             ("Projects"
              (let* ((end (nd/org-next-heading))
                     (line (save-excursion
                             (forward-line 1)
                             (catch 'line
                               (while (re-search-forward "^Project:[ \t]*\\(.*\\)$" end t)
                                 (let ((found (cons (line-beginning-position)
                                                    (match-string-no-properties 1))))
                                   (when (eq (org-element-type (org-element-at-point)) 'paragraph)
                                     (throw 'line found)))))))
                     (value (nd/org-read-project-links (cdr line))))
                (if line
                    (progn (goto-char (car line))
                           (delete-region (point) (line-end-position)))
                  (org-end-of-meta-data t)
                  (unless (bolp) (insert "\n")))
                (insert "Project: " value)
                (unless line (insert "\n"))))
             ("Tags"
              (let* ((current (org-get-tags nil t))
                     (reserved '("meeting" "unprocessed"))
                     (picked (completing-read-multiple
                              "Tags (comma-separated): "
                              (seq-remove (lambda (tag) (member tag reserved))
                                          (mapcar #'car org-tag-persistent-alist))
                              nil nil (string-join (seq-difference current reserved) ", "))))
                (org-set-tags (delete-dups (append (seq-intersection current reserved) picked)))))
             (_ (user-error "Unknown meeting detail: %s" field)))))))
    (when agenda (org-agenda-redo))))

(defun nd/org-refresh-id-index ()
  "Index notes, domain files, journals and archives without changing agenda scope."
  (interactive)
  (org-id-update-id-locations
   (directory-files-recursively org-directory "\\.org\\(?:_archive\\)?\\'")))

(defun nd/org-open-work-view (key)
  "Open KEY across all domains, clearing old restrictions and filters."
  (org-agenda-remove-restriction-lock t)
  (let ((org-agenda-persistent-filter nil)) (org-agenda nil key)))

(defun nd/org-today () (interactive) (nd/org-open-work-view "D"))
(defun nd/org-next () (interactive) (nd/org-open-work-view "N"))
(defun nd/org-projects () (interactive) (nd/org-open-work-view "P"))
(defun nd/org-review () (interactive) (nd/org-open-work-view "R"))

(with-eval-after-load 'org-agenda
  (require 'nerd-icons)
  (setq org-agenda-category-icon-alist
        `(("task" ,(list (nerd-icons-faicon "nf-fa-tasks")) nil nil :ascent center)
          ("project" ,(list (nerd-icons-faicon "nf-fa-briefcase")) nil nil :ascent center)
          ("inbox" ,(list (nerd-icons-faicon "nf-fa-inbox")) nil nil :ascent center))))

(setq org-agenda-start-with-log-mode t
      org-agenda-block-separator 8411)

;; The built-in stuck command remains a rough fallback. The custom review
;; below also checks WAIT dates and held/archived descendants.
(setq org-stuck-projects '("+project/ACTIVE|REVIEW" ("NEXT" "WAIT") nil ""))

(defun nd/org-next-block (&optional match title)
  "An available-action block, optionally restricted by MATCH."
  `(tags-todo ,(or match "-project/NEXT")
     ((org-agenda-overriding-header ,(or title "NEXT — available actions"))
      (org-agenda-tags-todo-honor-ignore-options t)
      (org-agenda-todo-ignore-scheduled 'future)
      (org-agenda-skip-function 'nd/org-skip-unavailable))))

(defun nd/org-calendar-block (days)
  "A calendar block for DAYS, including held projects' obligations."
  `(agenda ""
     ((org-agenda-span ,days)
      (org-agenda-start-day nil)
      (org-agenda-start-on-weekday nil)
      (org-agenda-entry-types '(:deadline :scheduled :timestamp :sexp))
      (org-agenda-skip-deadline-prewarning-if-scheduled nil)
      (org-agenda-skip-function 'nd/org-skip-finished))))

(defun nd/org-wait-block (&optional undated)
  "Waiting tasks with owner and date; UNDATED limits to missing follow-ups."
  `(todo "WAIT"
         ((org-agenda-skip-function ',(if undated 'nd/org-skip-dated-wait
                                       'nd/org-skip-finished))
          (org-agenda-prefix-format '((todo . "  %-12:c%(nd/org-wait-prefix)")))
          (org-agenda-overriding-header ,(if undated "WAIT without a follow-up date"
                                          "Waiting — owner and follow-up")))))

(defun nd/org-project-blocks ()
  '((tags "project/ACTIVE|REVIEW"
          ((org-agenda-overriding-header "Active projects")))
    (tags "project/PLAN|READY|BACKLOG"
          ((org-agenda-overriding-header "Planning and backlog")))
    (tags "project/HOLD"
          ((org-agenda-overriding-header "Held projects")))
    (tags "project/COMPLETED|DROPPED|DONE|CANC"
          ((org-agenda-overriding-header "Finished projects — reconcile, then archive")))
    (tags "project"
          ((org-agenda-skip-function 'nd/org-skip-valid-project)
           (org-agenda-overriding-header "Projects needing a lifecycle state")))))

(defun nd/org-review-blocks ()
  `(,(nd/org-calendar-block 14)
    (tags "LEVEL>0"
          ((org-agenda-files (list (expand-file-name "inbox.org" org-directory)))
           (org-agenda-skip-function 'nd/org-skip-inbox-structure)
           (org-agenda-overriding-header "Inbox — clarify and refile")))
    (tags-todo "-project/TODO"
          ((org-agenda-files (nd/org-domain-files))
           (org-agenda-skip-function 'nd/org-skip-project-task)
           (org-agenda-overriding-header "Standalone backlog")))
    (tags "project/ACTIVE|REVIEW"
          ((org-agenda-skip-function 'nd/org-skip-covered-project)
           (org-agenda-overriding-header "Active projects without NEXT or dated WAIT")))
    ,(nd/org-wait-block t)
    ,(nd/org-wait-block)
    (alltodo ""
          ((org-agenda-skip-function 'nd/org-skip-unless-residual)
           (org-agenda-overriding-header "Open work under finished projects")))
    (tags "project"
          ((org-agenda-skip-function 'nd/org-skip-valid-project)
           (org-agenda-overriding-header "Projects needing a lifecycle state")))
    (tags "unprocessed"
          ((org-agenda-files (nd/org-journal-files))
           (org-agenda-overriding-header "Meetings still needing processing")))
    (alltodo ""
          ((org-agenda-files (nd/org-journal-files))
           (org-agenda-overriding-header "Journal tasks — refile to a domain")))))

(defconst nd/org-work-view-options
  '((org-agenda-skip-function-global nil)
    (org-agenda-skip-function nil)
    (org-agenda-tag-filter-preset nil)
    (org-agenda-category-filter-preset nil)
    (org-agenda-todo-ignore-with-date nil)
    (org-agenda-todo-ignore-scheduled nil)
    (org-agenda-todo-ignore-deadlines nil)
    (org-agenda-todo-ignore-timestamp nil)))

(defun nd/agenda-context (key description tag)
  "A domain overview with commitments, available actions and projects."
  `(,key ,description
     (,(nd/org-calendar-block 14)
      ,(nd/org-next-block)
      ,(nd/org-wait-block)
      ,@(nd/org-project-blocks))
     (,@(assq-delete-all 'org-agenda-tag-filter-preset
                         (copy-tree nd/org-work-view-options))
      (org-agenda-tag-filter-preset '(,(concat "+" tag)))
      (org-agenda-show-inherited-tags nil))))

(setq org-agenda-custom-commands
      `(("D" "Today"
         (,(nd/org-calendar-block 1)
          ,(nd/org-next-block "focus-project/NEXT" "Focus — optional selected action")
          ,(nd/org-next-block "-focus-project/NEXT"))
         ,nd/org-work-view-options)
        ("N" "Available NEXT actions" (,(nd/org-next-block)) ,nd/org-work-view-options)
        ("P" "Project portfolio" ,(nd/org-project-blocks) ,nd/org-work-view-options)
        ("R" "Weekly review" ,(nd/org-review-blocks) ,nd/org-work-view-options)
        ("W" "Waiting"
         (,(nd/org-wait-block))
         ,nd/org-work-view-options)
        ,(nd/agenda-context "wo" "Work OVERVIEW (Sigtuna)" "sigtuna")
        ,(nd/agenda-context "ho" "Home OVERVIEW" "@home")
        ,(nd/agenda-context "no" "Nordic OVERVIEW" "nordic")
        ,(nd/agenda-context "vo" "Veltric OVERVIEW" "veltric")
        ("wp" "Work PROJECTS" ,(nd/org-project-blocks)
         ((org-agenda-tag-filter-preset '("+sigtuna"))))
        ("ws" "Projects without NEXT or dated WAIT"
         ((tags "project/ACTIVE|REVIEW"
                ((org-agenda-skip-function 'nd/org-skip-covered-project))))
         ,nd/org-work-view-options)
        ("wd" "Work DONE"
         ((agenda ""
           ((org-agenda-files
             (file-expand-wildcards "~/org/archive/sigtuna*.org_archive"))
            (org-agenda-span 100) (org-agenda-start-day "-100d")
            (org-agenda-start-on-weekday nil)))))
        ("wm" "JOURNAL OVERVIEW"
         ((agenda ""
           ((org-agenda-files (nd/org-journal-files))
            (org-agenda-span 366) (org-agenda-start-day "-365")
            (org-agenda-start-on-weekday nil)))))
        ("V" "Week across all domains"
         (,(nd/org-calendar-block 7)) ,nd/org-work-view-options)))

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

(defun my/search-org ()
  "Full-text search across `org-directory' with ripgrep."
  (interactive)
  (require 'org)
  (unless (executable-find "rg")
    (user-error "Install ripgrep (included in the arcmac Home Manager module)"))
  (consult-ripgrep (expand-file-name org-directory)))

(defun nd/search-recoll ()
  "Search an optional Recoll index, with setup guidance when unavailable."
  (interactive)
  (require 'consult-recoll)
  (unless (executable-find consult-recoll-program)
    (user-error "Install Recoll (pkgs.recoll), configure indexed folders, then run recollindex"))
  ;; Probe the configured index without assuming its path. Respect custom
  ;; CLI flags (e.g. -c) and RECOLL_CONFDIR, just like the actual search.
  (let ((buffer (get-buffer-create "*recoll-check*")))
    (with-current-buffer buffer (erase-buffer))
    (unless (eq 0 (apply #'process-file consult-recoll-program nil buffer nil
                         (append (when (listp consult-recoll-search-flags)
                                   consult-recoll-search-flags)
                                 '("-n" "1" "arcmac_index_probe"))))
      (user-error "Recoll index unavailable: configure folders and run recollindex; see *recoll-check*")))
  (call-interactively #'consult-recoll))

(with-eval-after-load 'org
  (evil-define-key '(normal visual) org-mode-map
    (kbd "<leader>ma") #'nd/action-to-inbox
    (kbd "<leader>mb") #'nd/org-open-project
    (kbd "<leader>mB") #'org-babel-tangle
    ;; dates — the pair this map exists for
    (kbd "<leader>mds") #'org-schedule
    (kbd "<leader>mdd") #'org-deadline
    (kbd "<leader>mdt") #'org-time-stamp
    (kbd "<leader>mdT") #'org-time-stamp-inactive
    ;; entry state and metadata
    (kbd "<leader>mt") #'org-todo
    (kbd "<leader>mw") #'nd/org-waiting-for
    (kbd "<leader>mU") #'nd/org-project-update
    (kbd "<leader>mp") #'org-priority
    (kbd "<leader>mq") #'org-set-tags-command
    (kbd "<leader>mr") #'org-refile
    (kbd "<leader>mR") #'nd/org-refile-with-meeting-links
    (kbd "<leader>ms") #'org-sort
    (kbd "<leader>mo") #'org-set-property
    ;; org-archive-location sends these to ~/org/archive/, see Settings
    (kbd "<leader>mA") #'org-archive-subtree
    ;; org-id-link-to-org-use-id is t, so a stored link needs an ID to
    ;; point at — this is how an entry gets one before it is linked to
    (kbd "<leader>mI") #'org-id-get-create
    (kbd "<leader>mM") #'nd/org-project-meetings
    (kbd "<leader>mE") #'nd/org-meeting-details
    ;; clock
    (kbd "<leader>mci") #'org-clock-in
    (kbd "<leader>mco") #'org-clock-out
    (kbd "<leader>mcc") #'org-clock-cancel
    (kbd "<leader>mcg") #'org-clock-goto
    (kbd "<leader>mcR") #'org-clock-report
    (kbd "<leader>mcE") #'org-set-effort
    ;; links
    (kbd "<leader>mll") #'org-insert-link
    (kbd "<leader>mlL") #'org-store-link
    (kbd "<leader>mli") #'nd/attach-url-and-insert
    ;; the source block under point, in its own major mode
    (kbd "<leader>m'") #'org-edit-special
    (kbd "<leader>me") #'org-export-dispatch
    ;; Preserve the GUI Alt+Enter fix: insert list items inside lists.
    (kbd "M-<return>") #'org-meta-return))

(with-eval-after-load 'org-agenda
  (evil-define-key '(normal visual) org-agenda-mode-map
    ;; Same letters as the org-mode-map block above, via the agenda's own
    ;; commands — those operate on the entry the agenda line points at,
    ;; then refresh the line. The plain org-* versions would edit the
    ;; agenda buffer's own text instead.
    (kbd "<leader>mds") #'org-agenda-schedule
    (kbd "<leader>mdd") #'org-agenda-deadline
    (kbd "<leader>mt") #'org-agenda-todo
    (kbd "<leader>mw") #'nd/org-waiting-for
    (kbd "<leader>mU") #'nd/org-project-update
    (kbd "<leader>mp") #'org-agenda-priority
    (kbd "<leader>mq") #'org-agenda-set-tags
    (kbd "<leader>mr") #'org-agenda-refile
    (kbd "<leader>mR") #'nd/org-agenda-refile-with-meeting-links
    (kbd "<leader>mo") #'org-agenda-set-property
    (kbd "<leader>mA") #'org-agenda-archive
    (kbd "<leader>mb") #'nd/org-open-project
    (kbd "<leader>mM") #'nd/org-project-meetings
    (kbd "<leader>mE") #'nd/org-meeting-details
    (kbd "<leader>mci") #'org-agenda-clock-in
    (kbd "<leader>mco") #'org-agenda-clock-out
    (kbd "<leader>mcc") #'org-agenda-clock-cancel
    (kbd "<leader>mcg") #'org-agenda-clock-goto
    (kbd "<leader>mcE") #'org-agenda-set-effort
    ;; `<leader>' is a pseudo-key: evil binds the real SPC globally to a
    ;; lookup of [leader ...] across the active maps. evil-collection
    ;; binds SPC directly in this map, which outranks that global entry,
    ;; so the lookup never runs and every binding above is unreachable
    ;; until SPC is cleared here. nil (not `undefined') is the point — a
    ;; nil binding does not shadow, so SPC falls through to the leader.
    ;; This runs after evil-collection's own org-agenda setup: it
    ;; registers its `with-eval-after-load' during evil-collection-init,
    ;; up in *Evil*, which is earlier in this file than *Org*.
    (kbd "SPC") nil
    ;; Displaced by that; see the note in this section.
    (kbd "g SPC") #'org-agenda-show))

(defun my/find-in-notes ()
  "Find a file in `org-directory' (Doom's SPC n f)."
  (interactive)
  (require 'org) ; `org-directory' is set in a deferred use-package block
  (let ((default-directory org-directory))
    (project-find-file)))

;; Named commands rather than inline lambdas: which-key (and
;; `describe-key') show the command name, so an anonymous binding
;; renders as a useless "??"/"lambda" in the SPC n j listing.
(defun my/journal-capture-meeting ()
  "Capture a meeting into today's journal entry."
  (interactive)
  (org-capture nil "jm"))

(defun my/journal-capture-work-log ()
  "Capture a work log entry into today's journal entry."
  (interactive)
  (org-capture nil "jw"))

(defun my/journal-capture-idea ()
  "Capture an idea into today's journal entry."
  (interactive)
  (org-capture nil "ji"))

(with-eval-after-load 'evil
  (evil-define-key '(normal visual) 'global
    (kbd "<leader>X") #'org-capture
    (kbd "<leader>nf") #'my/find-in-notes
    (kbd "<leader>n/") #'my/search-org
    (kbd "<leader>nR") #'nd/search-recoll
    (kbd "<leader>nd") #'nd/org-today
    (kbd "<leader>nn") #'nd/org-next
    (kbd "<leader>np") #'nd/org-projects
    (kbd "<leader>nr") #'nd/org-review
    (kbd "<leader>ncd") #'nd/contacts
    (kbd "<leader>ncp") #'nd/contact-open
    (kbd "<leader>nce") #'nd/contact-edit-details
    (kbd "<leader>nco") #'nd/list-contacts-by-org-unit
    (kbd "<leader>nch") #'nd/contact-history
    (kbd "<leader>ncr") #'nd/contacts-check
    (kbd "<leader>njo") #'org-journal-open-current-journal-file
    (kbd "<leader>njn") #'org-journal-new-entry
    (kbd "<leader>njs") #'org-journal-search
    (kbd "<leader>njm") #'my/journal-capture-meeting
    (kbd "<leader>njl") #'my/journal-capture-work-log
    (kbd "<leader>nji") #'my/journal-capture-idea)

  (which-key-add-key-based-replacements
    "SPC n" "notes"
    "SPC n c" "contacts"
    "SPC n j" "journal"
    "SPC m" "mode"
    "SPC m c" "clock"
    "SPC m d" "dates"
    "SPC m l" "links"))
(put 'narrow-to-region 'disabled nil)
