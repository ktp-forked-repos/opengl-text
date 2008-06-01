(in-package :opengl-text)

(defvar *opengl-active* nil)

(defclass opengl-text ()
  ((font-loader :initarg :font :accessor font-loader-of)
   (emsquare :initarg :emsquare :initform 64 :accessor emsquare-of)
   (texture :initform nil :accessor texture-of)
   (texture-number :initform nil :accessor texture-number-of)
   (character-hash :initform (make-hash-table) :accessor character-hash-of)))

(defun draw-char-on (char tex-array shift gl-text)
  (let ((bb (zpb-ttf:bounding-box (font-loader-of gl-text))))
    (let ((scaler (max (- (zpb-ttf:xmax bb)
			  (zpb-ttf:xmin bb))
		       (- (zpb-ttf:ymax bb)
			  (zpb-ttf:ymin bb)))))
      (let ((char-path (paths-ttf:paths-from-glyph (zpb-ttf:find-glyph char (font-loader-of gl-text))
						   :offset (paths:make-point (+ shift
										(* (emsquare-of gl-text)
										   (- (/ (zpb-ttf:xmin bb) scaler))))
									     (+ (1- (emsquare-of gl-text))
										(* (emsquare-of gl-text)
										   (/ (zpb-ttf:ymin bb) scaler))))
						   :scale-x (/ (emsquare-of gl-text) scaler)
						   :scale-y (- (/ (emsquare-of gl-text) scaler))))
	    (aa-state (aa:make-state)))
	(flet ((draw-function (x y alpha)
		 (if (array-in-bounds-p tex-array x y 0)
		     (setf (aref tex-array x y 0) 255
			   (aref tex-array x y 1) 255
			   (aref tex-array x y 2) 255
			   (aref tex-array x y 3) (clamp alpha 0 255))
		     (warn "Out of bounds: ~a ~a" x y))))
	  (aa:cells-sweep (vectors:update-state aa-state char-path) #'draw-function))))))

(defgeneric add-char (char gl-text)
  (:method ((char character) (gl-text opengl-text))
    (let ((charh (character-hash-of gl-text))
	  (em (emsquare-of gl-text)))
      (let ((new-count (1+ (hash-table-count charh))))
	(let ((new-texture (make-ffa (list (* em new-count) em 4) :uint8))
	     (new-charh (make-hash-table)))
	 (when (texture-of gl-text)
	  (map-into (find-original-array new-texture) #'identity (find-original-array (texture-of gl-text))))
	 (draw-char-on char new-texture (* em (hash-table-count charh)) gl-text)
	 (let ((old-chars (sort (hash-table-alist charh)
				#'< :key #'(lambda (k)
					     (aref (cdr k) 0)))))
	   (iter (for (old-char . nil) in old-chars)
		 (for i from 0)
		 (setf (gethash old-char new-charh)
		       (vector (float (/ i new-count))
			       (float 0)
			       (float (/ (1+ i) new-count))
			       (float 1))))
	   (setf (character-hash-of gl-text) new-charh)
	   (setf (texture-of gl-text) new-texture)
	   (setf (gethash char new-charh)
		 (vector (float (/ (1- new-count) new-count))
			 (float 0)
			 (float 1)
			 (float 1)))))))))


(defgeneric get-char-texture-coords (char gl-text)
  (:method ((char character) (gl-text opengl-text))
    (let ((char-coords (gethash char (character-hash-of gl-text))))
      (if char-coords
	  char-coords
	  (add-char char gl-text)))))