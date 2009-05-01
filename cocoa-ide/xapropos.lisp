(in-package "GUI")

(defclass xapropos-window-controller (ns:ns-window-controller)
  ((row-objects :foreign-type :id :reader row-objects)
   (search-category :initform :all :accessor search-category)
   (matched-symbols :initform (make-array 100 :fill-pointer 0 :adjustable t)
                    :accessor matched-symbols)
   ;; outlets
   (action-menu :foreign-type :id :accessor action-menu)
   (search-field :foreign-type :id :accessor search-field)
   (search-field-toolbar-item :foreign-type :id :accessor search-field-toolbar-item)
   (table-view :foreign-type :id :accessor table-view)
   (contextual-menu :foreign-type :id :accessor contextual-menu))
  (:metaclass ns:+ns-object))

(defconstant $all-symbols-item-tag 0)

(defvar *apropos-categories*
  '((0 . :all)
    (1 . :function)
    (2 . :variable)
    (3 . :class)
    (4 . :macro))
  "Associates search menu item tags with keywords.")

;;; action menu item tags
(defconstant $inspect-item-tag 0)
(defconstant $source-item-tag 1)

(objc:defmethod #/init ((wc xapropos-window-controller))
  (let ((self (#/initWithWindowNibName: wc #@"xapropos")))
    (unless (%null-ptr-p self)
      (setf (slot-value self 'row-objects) (make-instance'ns:ns-mutable-array)))
    self))

(objc:defmethod (#/windowDidLoad :void) ((wc xapropos-window-controller))
  (#/setDoubleAction: (table-view wc) (@selector #/inspect:)))

(objc:defmethod (#/dealloc :void) ((wc xapropos-window-controller))
  (#/release (slot-value wc 'row-objects))
  (call-next-method))

(objc:defmethod (#/search: :void) ((wc xapropos-window-controller) sender)
  (let* ((substring (#/stringValue sender)))
    ;;(#_NSLog #@"search for %@" :id substring)
    (apropos-search wc (lisp-string-from-nsstring substring))))

(defun apropos-search (wc substring)
  (with-accessors ((v matched-symbols)
                   (category search-category)
                   (array row-objects)) wc
    (setf (fill-pointer v) 0)
    (do-all-symbols (sym)
      (when (case category
              (:function (fboundp sym))
              (:variable (boundp sym))
              (:macro (macro-function sym))
              (:class (find-class sym nil))
              (t t))
        (when (ccl::%apropos-substring-p substring (symbol-name sym))
          (vector-push-extend sym v))))
    (setf v (sort v #'string-lessp))
    (#/removeAllObjects array)
    (dotimes (i (length v))
      (let ((n (#/null ns:ns-null)))
        (#/addObject: array n))))
  (#/reloadData (table-view wc)))

(objc:defmethod (#/setSearchCategory: :void) ((wc xapropos-window-controller) sender)
  (let* ((tag (#/tag sender))
         (label (if (= tag $all-symbols-item-tag)
                  #@"Search"
                  (#/stringWithFormat: ns:ns-string #@"Search (%@)" (#/title sender))))
         (pair (assoc tag *apropos-categories*)))
    (when pair
      (let* ((items (#/itemArray (#/menu sender))))
        (dotimes (i (#/count items))
          (#/setState: (#/objectAtIndex: items i) #$NSOffState)))
      (#/setState: sender #$NSOnState)
      (#/setLabel: (search-field-toolbar-item wc) label)
      (setf (search-category wc) (cdr pair))
      (#/search: wc (search-field wc)))))

(objc:defmethod (#/inspect: :void) ((wc xapropos-window-controller) sender)
  (declare (ignore sender))
  (let* ((row (#/selectedRow (table-view wc)))
         (clicked-row (#/clickedRow (table-view wc))))
    (when (/= clicked-row -1)
      (setq row clicked-row))
    (inspect (aref (matched-symbols wc) row))))

(objc:defmethod (#/source: :void) ((wc xapropos-window-controller) sender)
  (declare (ignore sender))
  (let* ((row (#/selectedRow (table-view wc)))
         (clicked-row (#/clickedRow (table-view wc))))
    (when (/= clicked-row -1)
      (setq row clicked-row))
    (hemlock::edit-definition (aref (matched-symbols wc) row))))

(objc:defmethod (#/validateMenuItem: #>BOOL) ((wc xapropos-window-controller) menu-item)
  (cond ((or (eql (action-menu wc) (#/menu menu-item))
             (eql (contextual-menu wc) (#/menu menu-item)))
         (let ((row (#/selectedRow (table-view wc)))
               (clicked-row (#/clickedRow (table-view wc)))
               (tag (#/tag menu-item)))
           (when (/= clicked-row -1)
             (setq row clicked-row))
           (when (/= row -1)
             (cond ((= tag $inspect-item-tag) t)
                   ((= tag $source-item-tag)
                    (let ((sym (aref (matched-symbols wc) row)))
                      (edit-definition-p sym)))
                   (t nil)))))
        (t t)))

(objc:defmethod (#/numberOfRowsInTableView: #>NSInteger) ((wc xapropos-window-controller)
                                                          table-view)
  (declare (ignore table-view))
  (length (matched-symbols wc)))

(objc:defmethod #/tableView:objectValueForTableColumn:row: ((wc xapropos-window-controller)
                                                            table-view table-column
                                                            (row #>NSInteger))
  (declare (ignore table-view table-column))
  (with-accessors ((array row-objects)
                   (syms matched-symbols)) wc
    (when (eql (#/objectAtIndex: array row) (#/null ns:ns-null))
      (let ((name (%make-nsstring (prin1-to-string (aref syms row)))))
        (#/replaceObjectAtIndex:withObject: array row name)
        (#/release name)))
    (#/objectAtIndex: array row)))
