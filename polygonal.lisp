(in-package :opengl-text)

(defclass polygonal-opengl-text ()
  ((font-loader :accessor font-loader-of :initarg :font-loader)
   (vertices :accessor vertices-of :initarg :vertices)
   (character-hash :accessor character-hash-of :initarg :character-hash :initform (make-hash-table))))

(defclass polygonal-glyph ()
  ((character :accessor character-of :initarg :character)
   (glyph     :accessor glyph-of     :initarg :glyph)
   (start     :accessor start-of     :initarg :start)
   (count     :accessor count-of     :initarg :count)))

(defgeneric add-polygonal-character (character gl-text)
  (:method ((character character) (gl-text polygonal-opengl-text))
    (let ((char-ffa (tesselate-character character (font-loader-of gl-text)))
          (ver-ffa (vertices-of gl-text)))
      (let ((new-ffa (make-ffa (+ (length char-ffa) (length ver-ffa)) :double)))
        (setf (subseq new-ffa 0 (length ver-ffa)) ver-ffa)
        (setf (subseq new-ffa (length ver-ffa)) char-ffa)
        (setf (gethash character (character-hash-of gl-text))
              (make-instance 'polygonal-glyph
                             :character character
                             :glyph (zpb-ttf:find-glyph character (font-loader-of gl-text))
                             :start (/ (length ver-ffa) 3)
                             :count (/ (length char-ffa) 3)))))))

(defmethod ensure-characters ((characters sequence) (gl-text polygonal-opengl-text))
  (let ((more-chars (set-difference characters (hash-table-keys (character-hash-of gl-text)))))
    (when more-chars
      (mapc (rcurry #'add-polygonal-character gl-text) more-chars))))

(defmethod draw-gl-string ((string string) (gl-text polygonal-opengl-text) &key (kerning t) (depth-shift 0.0))
  (ensure-characters (remove-duplicates string) gl-text)
  (gl:disable :texture-2d)
  (let ((vertices (vertices-of gl-text))
        (font (font-loader-of gl-text))
        (chash (character-hash-of gl-text)))
    (with-pointer-to-array (vertices vertex-pointer :double (length vertices) :copy-in)
      (%gl:vertex-pointer 3 :double 0 vertex-pointer)
      ;; so that string begins at 0,0,0
      (gl:translate (- (zpb-ttf:xmin (zpb-ttf:bounding-box font))
                       (zpb-ttf:xmin (zpb-ttf:bounding-box (zpb-ttf:find-glyph (char string 0) font))))
                    (zpb-ttf:descender font)
                    0)
      (iter (with scaler = (zpb-ttf:units/em font))
            (for c in-string string)
            (for polyglyph = (gethash c chash))
            (for g = (glyph-of polyglyph))
            (for gp previous g initially nil)
            (when (and gp kerning)
              (gl:translate (/ (zpb-ttf:kerning-offset gp g font) scaler) 0 0))
            (gl:draw-arrays :triangles (start-of polyglyph) (count-of polyglyph))
            (gl:translate (/ (+ (zpb-ttf:advance-width g)) scaler) 0 depth-shift)))))