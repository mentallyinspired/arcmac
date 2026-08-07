;;; early-init.el --- tangled from config.org -*- lexical-binding: t -*-
;; Edit config.org, not this file.

;; Fewer GCs during startup; back to a sane threshold afterwards.
(setq gc-cons-threshold (* 100 1024 1024))
(add-hook 'emacs-startup-hook
          (lambda () (setq gc-cons-threshold (* 16 1024 1024))))

(setq inhibit-startup-screen t
      frame-inhibit-implied-resize t)

;; Strip UI chrome before the first frame is drawn.
(push '(menu-bar-lines . 0) default-frame-alist)
(push '(tool-bar-lines . 0) default-frame-alist)
(push '(vertical-scroll-bars) default-frame-alist)

(startup-redirect-eln-cache
 (expand-file-name "arcmac/eln-cache"
                   (or (getenv "XDG_CACHE_HOME") "~/.cache")))
