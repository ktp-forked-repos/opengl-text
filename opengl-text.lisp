(in-package :opengl-text)

(defvar *opengl-active* t)
(defvar *coerce-em-to-power-of-two* t)

(defclass opengl-text ()
  ((font-loader :initarg :font :accessor font-loader-of)
   (emsquare :initarg :emsquare :initform 64 :accessor emsquare-of)
   (texture :initform nil :accessor texture-of)
   (texture-number :initform nil :accessor texture-number-of)
   (character-hash :initform (make-hash-table) :accessor character-hash-of)))

(defun ceiling-power-of-two (number)
  (expt 2 (ceiling (log number 2))))

(defmethod initialize-instance :after ((instance opengl-text) &rest initargs)
  (declare (ignore initargs))
  (when *coerce-em-to-power-of-two*
    (setf (emsquare-of instance)
	  (ceiling-power-of-two (emsquare-of instance)))))

(defmethod (setf emsquare-of) :after (new-value (object opengl-text))
  (when *coerce-em-to-power-of-two*
    (setf (slot-value object 'emsquare)
	  (ceiling-power-of-two (emsquare-of object)))))

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
	    (aa-state (aa:make-state))
	    (h (array-dimension tex-array 0)))
	(flet ((draw-function (x y alpha)
		 (if (array-in-bounds-p tex-array (- h y) x 0)
		     (setf (aref tex-array (- h y) x 0) 255
			   (aref tex-array (- h y) x 1) 255
			   (aref tex-array (- h y) x 2) 255
			   (aref tex-array (- h y) x 3) (clamp alpha 0 255))
		     (warn "Out of bounds: ~a ~a" x y))))
	  (aa:cells-sweep (vectors:update-state aa-state char-path) #'draw-function))))))

(defgeneric add-char (char gl-text)
  (:method ((char character) (gl-text opengl-text))
    (let ((charh (character-hash-of gl-text))
	  (em (emsquare-of gl-text)))
      (let ((new-count (1+ (hash-table-count charh))))
	(let ((new-size (if *coerce-em-to-power-of-two*
			    (ceiling-power-of-two (* em new-count))
			    (* em new-count))))
	  (let ((new-texture (if (or (null (texture-of gl-text))
				     (> new-size (array-dimension (texture-of gl-text) 0)))
				 (make-ffa (list em new-size 4) :uint8)
				 (texture-of gl-text)))
		(new-charh (make-hash-table))
		(new-count-ext (/ new-size em)))
	    (when (and (texture-of gl-text)
		       (not (eq (texture-of gl-text) new-texture)))
	      (map-subarray (texture-of gl-text) new-texture
			    :target-range `(:all (0 ,(1- (array-dimension (texture-of gl-text) 1))) :all)))
	    (draw-char-on char new-texture (* em (hash-table-count charh)) gl-text)
	    (let ((old-chars (sort (hash-table-alist charh)
				   #'< :key #'(lambda (k)
					       (aref (cdr k) 0 0)))))
	      (iter (for (old-char . nil) in old-chars)
		    (for i from 0)
		    (setf (gethash old-char new-charh)
			  (make-array '(4 2)
				      :initial-contents
				      (list (list (float (/ i new-count-ext)) (float 0))
					    (list (float (/ (1+ i) new-count-ext)) (float 0))
					    (list (float (/ (1+ i) new-count-ext)) (float 1))
					    (list (float (/ i new-count-ext)) (float 1))))))
	      (setf (character-hash-of gl-text) new-charh)
	      (setf (texture-of gl-text) new-texture)
	      (when *opengl-active*
	       (with-pointer-to-array (new-texture tex-pointer
						   :uint8
						   (reduce #'* (array-dimensions new-texture))
						   :copy-in)
		 (if (texture-number-of gl-text)
		     (cl-opengl:bind-texture :texture-2d (texture-number-of gl-text))
		     (let ((new-number (car (cl-opengl:gen-textures 1))))
		       (setf (texture-number-of gl-text) new-number)
		       (cl-opengl:bind-texture :texture-2d new-number)
		       (trivial-garbage:finalize gl-text #'(lambda ()
							     (gl:delete-textures (list new-number))))))
		 (cl-opengl:tex-image-2d :texture-2d 0 :rgba (array-dimension new-texture 1)
					 (array-dimension new-texture 0) 0 :rgba :unsigned-byte tex-pointer)))
	     (setf (gethash char new-charh)
		   (make-array '(4 2)
			       :initial-contents
			       (list (list (float (/ (1- new-count) new-count-ext)) (float 0))
				     (list (float (/ new-count new-count-ext)) (float 0))
				     (list (float (/ new-count new-count-ext)) (float 1))
				     (list (float (/ (1- new-count) new-count-ext)) (float 1))))))))))))


(defgeneric get-char-texture-coords (char gl-text)
  (:method ((char character) (gl-text opengl-text))
    (let ((char-coords (gethash char (character-hash-of gl-text))))
      (if char-coords
	  char-coords
	  (add-char char gl-text)))))

(defgeneric draw-gl-string (string gl-text)
  (:method ((string string) (gl-text opengl-text))
    ;; ensure that all characters are in a texture (adding characters changes coords)
    (map nil (rcurry #'get-char-texture-coords gl-text) (remove-duplicates string))
    (let ((l (length string)))
     (let ((vertices (make-ffa (list (* 4 l) 3) :float))
	   (tex-coords (make-ffa (list (* 4 l) 2) :float)))
       (iter (for c in-string string)
	     (for i from 0 by 4)
	     (for k from 0.0)
	     (let ((vertex (make-array '(4 3)
				       :initial-contents
				       (list (list k 0.0 0.0)
					     (list (1+ k) 0.0 0.0)
					     (list (1+ k) 1.0 0.0)
					     (list k 1.0 0.0))))
		   (tex-coord (get-char-texture-coords c gl-text)))
	       (map-subarray vertex vertices :target-range `((,i ,(+ i 3)) :all))
	       (map-subarray tex-coord tex-coords :target-range `((,i ,(+ i 3)) :all))))
       (with-pointers-to-arrays ((vertices v-pointer :float (length (find-original-array vertices)) :copy-in)
				 (tex-coords t-pointer :float (length (find-original-array tex-coords)) :copy-in))
	 (%gl:vertex-pointer 3 :float 0 v-pointer)
	 (%gl:tex-coord-pointer 2 :float 0 t-pointer)
	 (gl:bind-texture :texture-2d (texture-number-of gl-text))
	 (gl:tex-env :texture-env :texture-env-mode :replace)
	 (gl:tex-parameter :texture-2d :texture-min-filter :linear)
	 (gl:tex-parameter :texture-2d :texture-mag-filter :linear)
	 (gl:draw-arrays :quads 0 (* 4 (length string))))))))