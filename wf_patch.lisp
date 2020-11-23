;;;; File: wf_patch.lisp
;;;; Created Date: Monday, 23rd November 2020 2:01:32 pm
;;;; Author: Tianyu Gu (gty@franz.com)
(in-package #:cl-user)

(defpackage #:annoy.bindings
  (:use #:cl)
  (:import-from #:ff #:def-foreign-call)
  (:export #:annoy_alloc #:annoy_dealloc
           #:annoy_load #:annoy_get_n_items
           #:annoy_get_n_trees #:annoy_get_item
           #:annoy_get_nns_by_item #:annoy_get_nns_by_vector))

(defpackage #:annoy
  (:use #:cl #:annoy.bindings)
  (:export #:load-annoy-index-from-disk
           #:annoy-index-dim
           #:annoy-index-metric
           #:annoy-index-n-items
           #:annoy-index-n-trees
           #:annoy-index-get-item
           #:annoy-index-get-most-similar))

(in-package #:annoy.bindings)

(eval-when (:load-toplevel)
  (let ((path (pathname (concatenate 'string (excl:path-namestring *load-pathname*) "libannoy.so"))))
    (if (probe-file path)
        (load path)
        (error "Cannot find libannoy.so"))))

(def-foreign-call annoy_alloc
    ((dim :int fixnum) (metric (* :char) string))
  :returning :foreign-address
  :strings-convert t)

(def-foreign-call annoy_dealloc
    ((index :foreign-address))
  :returning :void)

(def-foreign-call annoy_load
    ((index :foreign-address) (filename (* :char) string) (prefault :int fixnum))
  :returning :foreign-address
  :strings-convert t)

(def-foreign-call annoy_get_n_items
    ((index :foreign-address))
  :returning :int)

(def-foreign-call annoy_get_n_trees
    ((index :foreign-address))
  :returning :int)

(def-foreign-call annoy_get_item
    ((index :foreign-address) (item :int fixnum) (v (:array :float)))
  :returning :void)

(def-foreign-call annoy_get_nns_by_item
    ((index :foreign-address) (item :int fixnum) (n :int fixnum) (search_k :int fixnum)
     (result (:array :int)) (distances (:array :float)))
  :returning :void)

(def-foreign-call annoy_get_nns_by_vector
    ((index :foreign-address) (w (:array :float)) (n :int fixnum) (search_k :int fixnum)
     (result (:array :int)) (distances (:array :float)))
  :returning :void)

(in-package #:annoy)

(defstruct (annoy-index (:constructor mk-annoy-index)
                        (:print-object (lambda (index o)
                                         (print-unreadable-object (index o :type t :identity t)
                                           (with-slots (dim metric n-items n-trees) index
                                               (format o "Dimensionality: ~d, Space: ~s, ~d Items, ~d Trees"
                                                       dim metric n-items n-trees))))))
  (ptr nil :read-only t)
  (dim 0 :read-only t :type fixnum)
  (metric "angular" :read-only t :type string)
  (n-items 0 :type fixnum)
  (n-trees 0 :type fixnum))

(defun positive-integer-p (x)
  (and (integerp x) (> x 0)))

(defun annoy-index-finalizer (index)
  (annoy_dealloc (annoy-index-ptr index)))

(defun load-annoy-index-from-disk (path &key dim (metric :angular))
  (unless (and (or (stringp path) (pathnamep path))
               (probe-file path))
    (error "path doesn NOT exist: ~a" path))
  (unless (positive-integer-p dim)
    (error "dim must be a positive integer: ~a" dim))

  (let* ((metric (ecase metric
                   (:angular "angular")
                   (:euclidean "euclidean")
                   (:manhattan "manhattan")
                   (:hamming "hamming")
                   (:dot "dot")))
         (index (mk-annoy-index :ptr (annoy_alloc dim metric)
                                :dim dim
                                :metric metric)))
    (excl:schedule-finalization index #'annoy-index-finalizer)
    (annoy_load (annoy-index-ptr index) path 0)
    (setf (annoy-index-n-items index) (annoy_get_n_items (annoy-index-ptr index))
          (annoy-index-n-trees index) (annoy_get_n_trees (annoy-index-ptr index)))
    index))

(defun annoy-index-get-item (index id)
  (declare (optimize speed (space 0) (safety 0)))
  (with-slots (ptr dim n-items) index
    (unless (and (integerp id) (>= n-items id 0))
      (error "id must be a non-negative integer and below ~d: ~a" n-items id))
    (let ((v (make-array dim :element-type 'single-float)))
      (annoy_get_item ptr id v)
      v)))


(defun annoy-index-get-most-similar (index id &key (topn 10))
  (declare (optimize speed (space 0) (safety 0)))
  (with-slots (ptr dim n-items) index
    (unless (and (integerp id) (>= n-items id 0))
      (error "id must be a non-negative integer and below ~d: ~a" n-items id))
    (unless (positive-integer-p topn)
      (error "topn must be a positive integer: ~a" topn))
    (unless (<= topn n-items)
      (error "topn is too big: ~d" topn))

    (incf topn)
    (let ((result (make-array topn :element-type '(unsigned-byte 32)))
          (distances (make-array topn :element-type 'single-float)))
      (annoy_get_nns_by_item ptr id topn -1 result distances)
      (let ((sims (loop
                     :for id* :across result
                     :for dis :across distances
                     :when (not (= id* id))
                     :collect (cons id* dis))))
        (if (= (length sims) topn)
            (butlast sims)
            sims)))))

(in-package #:db.agraph.user)

(defun fasttext-most-similar (word topn api)
  (unless topn (setq topn 10))
  (unless (and (integerp topn) (> topn 0))
    (error "topn must be a positive integer: ~a" topn))

  (unless api
    (let ((api* (sys:getenv "FASTTEXT_API_URL")))
      (if api*
          (setq api api*)
          (error "Cannot determine the url of FastText web service. Have you set FASTTEXT_SERVICE_URL environment variable?"))))

  (db.agraph.parser:read-json-into-lists
   (net.aserve.client:do-http-request api
     :method :post
     :query (list (cons "word" word) (cons "topn" topn))
     :user-agent "ACL")))

(ag.sbqe:defmagic-property (resource "http://example.org/fasttext#mostSimilar")
    :subject-arguments (sims)
    :object-arguments ((word :type :string) (topn optional :type :numeric) (api optional :type :string))
    :body (fasttext-most-similar word topn api))

(eval-when (:load-toplevel)
  (defparameter *annoy-index*
    (let ((path (sys:getenv "ANNOY_INDEX_PATH"))
          (dim (sys:getenv "ANNOY_INDEX_DIM"))
          (metric (sys:getenv "ANNOY_INDEX_METRIC")))
      (when (and path dim metric)
        (annoy:load-annoy-index-from-disk path
                                          :dim (parse-integer dim)
                                          :metric (intern (string-downcase metric) :keyword))))))

(defun ent->id (ent)
  (let ((triple (get-triple :s ent :p (resource "http://example.org/embeddings#hasID"))))
    (if triple
        (upi->number (object triple))
        (error "~a does not have an ID" ent))))

(defun id->ent (id)
  (flet ((filter (triple)
           (and triple
                (or (get-triple :s (subject triple))
                    (get-triple :o (subject triple))))))
    (let ((triple (get-triple :p (resource "http://example.org/embeddings#hasID")
                              :o (literal (format nil "~d" id)
                                          :datatype (resource "integer" "xsd"))
                              :filter #'filter)))
      (if triple
          (subject triple)
          (error "Cannot find entity by the given ID: ~a" id)))))

(defun embeddings-get-embedding (ent)
  (unless *annoy-index*
    (error "*annoy-index* is not available"))
  (literal
   (st-json:write-json-to-string
    (annoy:annoy-index-get-item *annoy-index* (ent->id ent)))))


(ag.sbqe:defmagic-property (resource "http://example.org/embeddings#getEmbedding")
    :subject-arguments (embed)
    :object-arguments ((ent :type :resource))
    :body (embeddings-get-embedding ent))

(defun embeddings-most-similar (ent topn)
  (unless *annoy-index*
    (error "*annoy-index* is not available"))
  (unless topn (setq topn 10))
  (let* ((id (ent->id ent))
         (sims (annoy:annoy-index-get-most-similar *annoy-index* id :topn topn)))
    (mapcar (lambda (sim) (id->ent (car sim))) sims)))

(ag.sbqe:defmagic-property (resource "http://example.org/embeddings#mostSimilar")
    :subject-arguments (sims)
    :object-arguments ((ent :type :resource) (topn optional :type :numeric))
    :body (embeddings-most-similar ent topn))
