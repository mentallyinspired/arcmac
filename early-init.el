;;; early-init.el --- tangled from config.org -*- lexical-binding: t -*-
;; Edit config.org, not this file.

;; Fewer GCs during startup; back to a sane threshold afterwards.
(setq gc-cons-threshold (* 100 1024 1024))
(add-hook 'emacs-startup-hook
          (lambda () (setq gc-cons-threshold (* 16 1024 1024))))

(setq inhibit-startup-screen t
      frame-inhibit-implied-resize t)

;; Emacs sizes a frame in whole character cells by default, so when a
;; window manager hands it an arbitrary geometry — Windows snap/tiling
;; through WSLg is the case that shows it — it rounds DOWN to the last
;; whole column and row and leaves the remainder as dead space at the
;; right and bottom edges. A gap up to one line tall and one column wide.
;; Pixelwise resizing lets the frame take the size it was actually given.
;; Set here rather than in init.el: it has to be in effect before the
;; first frame is created.
(setq frame-resize-pixelwise t
      window-resize-pixelwise t)

;; Strip UI chrome before the first frame is drawn.
(push '(menu-bar-lines . 0) default-frame-alist)
(push '(tool-bar-lines . 0) default-frame-alist)
(push '(vertical-scroll-bars) default-frame-alist)

(startup-redirect-eln-cache
 (expand-file-name "arcmac/eln-cache"
                   (or (getenv "XDG_CACHE_HOME") "~/.cache")))
