;; yDiff - a language-aware tool for comparing programs
;; Copyright (C) 2011 Yin Wang (yinwang0@gmail.com)

;; This program is free software: you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <http://www.gnu.org/licenses/>.


(load "parsec.ss")

(define *delims* (list "("  ")"  "["  "]"  "{"  "}" ","  "`"  ";" "#"))

(define *operators*
  (list
   ">>>="
   "<<="  ">>="  ">>>"  "->*"  "..."
   "&&"  "||"  ">>"  "<<"  "++"  "--"
   "=="  "!="  ">="  "<="  "+="  "-="  "*="  "/="  "^="  "&="  "|="
   "->"  ".*"  "::"
   "="  "+"  "-"  "*"  "/"  "%"  "<"  ">"  "!"  ":"  "?"  "."
   "^"  "|"  "&"  "~"
))

;;---------------- parameters for the scanner ---------------
(define *line-comment*  (list "//"))
(define *comment-start*  "/*")
(define *comment-end*    "*/")
(define *quotation-marks*  '(#\" #\'))
(define *significant-whitespaces*
  (list #\newline #\linefeed #\u2028 #\u2029))




;-------------------------------------------------------------
;                          parsers
;-------------------------------------------------------------

;; literals
(:: $id
    ($pred
     (lambda (t)
       (and (Token? t)
            (id? (Token-text t))))))


(::= $identifier 'identifier
     (@? ($$ "::"))
     (@* $id (@* $type-parameter) ($$ "::"))
     (@? ($$ "~")) $id)


;; (::= $identifier 'identifier
;;      (@? ($$ "::")) $scope-resolution (@? ($$ "~")) $id)


(:: $numeral-literal
    ($pred
     (lambda (t)
       (and (Token? t)
            (numeral? (Token-text t))))))

(:: $char-literal ($pred Char?))
(:: $string-literal ($pred Str?))
(:: $newline ($pred Newline?))
(:: $comment ($pred Comment?))


;; delimeters
(::  |,|   (@_ ","))
(::  |;|   (@~ ";"))
(::  |:|   (@_ ":"))
(::  |(|   (@~ "("))
(::  |)|   (@~ ")"))
(::  |[|   (@~ "["))
(::  |]|   (@~ "]"))
(::  |{|   (@~ "{"))
(::  |}|   (@~ "}"))



;; redefine sequence to get over newlines
;; the definition of |\n| must not contain any call to @seq

(define $glob1
  (lambda (p)
    (lambda ()
      (lambda (toks stk ctx)
        (letv ([(t r) ((p) toks stk ctx)])
          (cond
           [(not t) (values #f #f)]
           [else
            (values '() r)]))))))

(define @*1
  (lambda (p)
    (lambda ()
      (lambda (toks stk ctx)
        (let loop ([toks toks] [nodes '()])
          (cond
           [(null? toks)
            (values (apply append (reverse nodes)) '())]
           [else
            (letv ([(t r) ((p) toks stk ctx)])
              (cond
               [(not t)
                (values (apply append (reverse nodes)) toks)]
               [else
                (loop r (cons t nodes))]))]))))))

(define @!1
  (lambda (p)
    (lambda ()
      (lambda (toks stk ctx)
        (letv ([(t r) ((p) toks stk ctx)])
          (cond
           [(not t) (values (list (car toks)) (cdr toks))]
           [else (values #f #f)]))))))


(::  |\n|  ($glob1 (@*1 $newline)))
(::  |;\n| (@or |;| |\n|))


(define old-seq @seq)

(define @seq
  (lambda ps
    (let ([psj (join ps |\n|)])
      (apply old-seq `(,|\n| ,@psj ,|\n|)))))


(::= $macro-defintion 'macro
     (@~ "#")
     (@*1 (old-seq (@*1 (@and (@!1 ($$ "\\")) (@!1 $newline))) ($$ "\\") (@*1 $newline)))
     (old-seq (@*1 (@!1 $newline)) ($glob1 $newline) ($glob1 (@*1 $newline)))
)


(:: $directive
    (@or ($$ "ifdef")
         ($$ "define")
         ($$ "undef")
         ($$ "endif")))


;;------------------ starting point -----------------
(::= $program 'program
     (@* $statement)
)



(:: $statement
    (@or $macro-defintion
         $empty-statement
         $access-label
         $statement-block

         $if-statement
         $switch-statement
         $do-while-statement
         $while-statement
         $for-statement
         $for-in-statement
         $continue-statement
         $break-statement

         $return-statement
         $with-statement
         $labelled-statement
         $try-statement

         $namespace-definition
         $using-namespace

         $class-definition
         $function-definition
         $function-declaration
         $variable-definition
         $enum-declaration

         $extended-assembly
         $inline-assembly

         $expression-statement
))


(:: $empty-statement |;|)


(::= $enum-declaration 'enum
     (@~ "enum") (@? $identifier)
     |{|
       (@? (@.@  (@= 'name-value $identifier  (@? $initializer))  |,|))
     |}|
     |;|
)


(::= $access-label 'access-label
     $access-specifier (@~ ":"))


(::= $statement-block 'block
     |{|  (@* $statement)  |}|
)


(::= $namespace-definition 'namespace
     (@~ "namespace") $identifier
     |{|  (@* $statement)  |}|
)

(::= $using-namespace 'using-namespace
     (@~ "using") (@~ "namespace") $identifier)



;;--------------------------------------------
(::= $class-definition 'class

     (@or ($$ "class")
          ($$ "struct")
          ($$ "union"))

     (@* (@= 'declspec
             (@or ($$ "_declspec") ($$ "__declspec")) |(|  $expression  |)|))

     (@or (@= 'signature (@= 'name $identifier |;| ))

          (@...
              (@= 'signature (@= 'name (@? $identifier))) (@? (@... (@_ ":") $base-clause))
              (@= 'body  |{|  (@* $statement)  |}|) )
          ))


(::= $base-clause 'bases
     (@.@ $base-specifier |,|)
)


(::= $base-specifier 'base-specifier
     (@? $access-specifier) $identifier)


(::= $access-specifier 'access-specifier
     (@or ($$ "public")
          ($$ "protected")
          ($$ "private")
          ($$ "virtual")))


;;---------- function definition and declaration ------------

(::= $function-declaration 'function-declaration
     (@= 'signature
         (@? ($$ "typedef"))
         (@? $access-specifier) (@? $modifiers) (@? $type)
         (@= 'name (@or $identifier
                        (@... |(| ($$ "*") $identifier |)|)) )
         $formal-parameter-list)
     (@? ($$ "const"))
     (@? $initializer)
)


(::= $function-definition 'function
     (@= 'signature
         (@or (@... (@? $modifiers) $type
                    (@= 'name $identifier ) $formal-parameter-list)

              (@... (@= 'name $identifier ) $formal-parameter-list)))
     (@? $initializer)
     $function-body)


(::= $type 'type
     (@? $modifiers) (@or $primitive-type
                          $ctype
                          $identifier)
     (@* $type-parameter) (@* $ptr-suffix))


(::= $type-parameter 'type-parameter
     (@~ "<") (@.@ (@or $type $numeral-literal) |,|) (@~ ">"))


(::= $ptr-suffix 'suffix
     (@or ($$ "*")
          ($$ "&")))


(::= $formal-parameter-list 'parameters
     |(|  (@? (@.@ $type-variable |,|)) (@? |,| ($$ "..."))  |)|
)


(::= $type-variable 'type-variable
     (@? $modifiers) $type (@? $identifier) (@? $array-suffix))


(::= $function-body 'body
     |{|  (@* $statement)  |}|
)



(::= $variable-definition 'variable-definition
     $variable-declaration-list |;|
)


(:: $variable-declaration-list
    (@... (@? $modifiers) $type (@.@ $variable-declaration |,|)))


(::= $variable-declaration 'variable-declaration
     $identifier (@? $variable-declaration-suffix)
     (@? $initializer))


(::= $modifiers 'modifiers
     (@+ (@or ($$ "const")
              ($$ "static")
              ($$ "inline"))))

(:: $primitive-type
     (@or (@...
           (@or ($$ "signed")
                ($$ "unsigned"))
           (@or ($$ "int")
                ($$ "char")
                ($$ "long")
                ($$ "double")
                ($$ "float")))
          (@or ($$ "signed")
               ($$ "unsigned"))))

(::= $ctype 'ctype
     (@or ($$ "struct")
          ($$ "enum"))
     $identifier
)


(::= $variable-declaration-suffix 'suffix
     (@or (@... |[|  $expression  |]|))
)

(::= $initializer 'initializer
     (@or (@... (@_ "=") $expression)
          (@... (@_ ":") $expression)
          (@... (@_ "(") $expression (@_ ")"))))








(::= $if-statement 'if
     ($$ "if")  (@= 'test |(| $expression |)|) $statement
     (@? (@= 'else ($$ "else") $statement))
)


; ($eval $if-statement (scan "if (x<1) { return x; } else { return 0;}"))



;; doWhileStatement
;; 	: 'do' LT!* statement LT!* 'while' LT!* '(' expression ')' (LT | ';')!
;; 	;

(::= $do-while-statement 'do-while
    ($$ "do") $statement
    (@= 'while-do ($$ "while")  (@= 'test |(| $expression |)|   ))
    |;|
)


; ($eval $do-while-statement (scan "do {x = x + 1 } while (x < 5);"))



;; whileStatement
;; 	: 'while' LT!* '(' LT!* expression LT!* ')' LT!* statement
;; 	;

(::= $while-statement 'while
     ($$ "while")  (@= 'test |(| $expression |)|   )
     $statement
)



(::= $for-statement 'for
     ($$ "for") (@= 'iter
                    |(| (@? $for-initaliser) |;|
                    (@? $expression)     |;|
                    (@? $expression)
                    |)|
                    )
     $statement
)




(::= $for-initaliser 'for-initializer
     (@or (@= 'variable-declaration
              $variable-declaration-list)

          $expression
))




;; for JS
(::= $for-in-statement 'for-in
     ($$ "for") (@= 'iter
                    |(|  (@? $for-in-initalizer) ($$ "in") $expression  |)|)
     $statement
)


(::= $for-in-initalizer 'for-in-initializer
     (@or (@= 'variable-declaration
              ($$ "var") $variable-declaration-list)

          $expression
))



(::= $continue-statement 'continue
     ($$ "continue") (@= 'label (@? $identifier)) |;|
)


(::= $break-statement 'break
     ($$ "break") (@= 'label (@? $identifier)) |;|
)


(::= $return-statement 'return
     ($$ "return") (@= 'value (@? $expression)) |;|
)


(::= $with-statement 'with
     ($$ "with") (@= 'obj |(|  $expression  |)|)
     $statement
)


(::= $labelled-statement 'labelled-statement
     $identifier |:| $statement
)


(::= $switch-statement 'switch
     ($$ "switch")  |(| $expression |)|
     |{|  (@* $case-clause)
          (@? (@... $default-clause
                    (@* $case-clause)))
     |}|
)


(::= $case-clause 'case-clause
     ($$ "case") $expression |:| (@* $statement)
)


(::= $default-clause 'default-clause
    ($$ "default") |:| (@* $statement)
)


;; throw is an expression in C++
;; (::= $throw-statement 'throw
;;      ($$ "throw") $expression  |;|
;; )


(::= $try-statement 'try
     ($$ "try") $statement-block
     (@or $finally-clause
          (@... $catch-clause (@? $finally-clause))))


(::= $catch-clause 'catch
     ($$ "catch") |(| $identifier |)| $statement-block)


(::= $finally-clause 'finally
     ($$ "finally") $statement-block)


(::= $expression-statement 'expression-statement
     $expression |;|)




;-------------------------------------------------------------
;                       expressions
;-------------------------------------------------------------

;; utility for constructing operators
(define op
  (lambda (s)
    (@= 'op ($$ s))))


(:: $expression
    $comma-expression
    )




;; 18. comma
;;--------------------------------------------
(:: $comma-expression
    (@or (@= 'comma
             (@... $assignment-expression |,|
                   (@.@ $assignment-expression |,|)))
         $assignment-expression))



;; 17. throw
;;--------------------------------------------
(::= $throw-expression 'throw
     (@or (@... (@~ "throw")) $expression
          $assignment-expression)
)


;; 16. assignment
;;--------------------------------------------
(:: $assignment-expression
    (@or (@= 'assignment
             $conditional-expression
             $assignment-operator
             $assignment-expression)

         $conditional-expression
         ))


(:: $assignment-operator
     (@or (op "=")
          (op "*=")
          (op "/=")
          (op "%=")
          (op "+=")
          (op "-=")
          (op "<<=")
          (op ">>=")
          (op ">>>=")
          (op "&=")
          (op "^=")
          (op "|=")))



;; 15.	?:	 Ternary conditional
;;--------------------------------------------
(:: $conditional-expression
    (@or (@= 'conditional-expression
             (@= 'test $logical-or-expression)
             (@~ "?") (@= 'then $conditional-expression)
             (@~ ":") (@= 'else $conditional-expression))

         $logical-or-expression
         ))


; ($eval $conditional-expression (scan "x > 0? x-1 : x"))




;; 14.	||	 Logical OR
;;--------------------------------------------
(:: $logical-or-expression
     (@or (@infix-left 'binop
                       $logical-and-expression
                       (op "||"))

          $logical-and-expression
          ))



;; 13.	&&	 Logical AND
;;--------------------------------------------
(:: $logical-and-expression
     (@or (@infix-left 'binop
                       $bitwise-or-expression
                       (op "&&"))

          $bitwise-or-expression
          ))



;; 12.	|	 Bitwise OR (inclusive or)
;;--------------------------------------------
(:: $bitwise-or-expression
     (@or (@infix-left 'binop
                       $bitwise-xor-expression
                       (op "|"))

          $bitwise-xor-expression
          ))



;; 11.	^	 Bitwise XOR (exclusive or)
;;--------------------------------------------
(:: $bitwise-xor-expression
     (@or (@infix-left 'binop
                       $bitwise-and-expression
                       (op "^"))

          $bitwise-and-expression
          ))



;; 10.	&	 Bitwise AND
;;--------------------------------------------
(:: $bitwise-and-expression
     (@or (@infix-left 'binop
                       $equality-expression
                       (op "&"))

       $equality-expression
       ))



;; 9. equality
;;--------------------------------------------
(:: $equality-expression
     (@or (@infix-left 'binop
                       $relational-expression
                       $equality-operator)

          $relational-expression
          ))

(:: $equality-operator
     (@or (op "==")
          (op "!=")
          (op "===")
          (op "!==")
))




;; 8. relational
;;--------------------------------------------
(:: $relational-expression
     (@or (@infix-left 'binop
                       $bitwise-shift-expression
                       $relational-operator)

          $bitwise-shift-expression
          ))

(:: $relational-operator
     (@or (op "<")
          (op "<=")
          (op ">")
          (op ">=")
          (op "instanceof")
          (op "in")
          ))




;; 7. bitwise shift
;;--------------------------------------------
(:: $bitwise-shift-expression
    (@or (@infix-left 'binop
                      $additive-expression
                      $shift-operator)

         $additive-expression
))

(:: $shift-operator
    (@or (op "<<")
         (op ">>")
         (op ">>>")
         ))




;; 6. additive
;;--------------------------------------------
(:: $additive-expression
    (@or (@infix-left 'binop
                      $multiplicative-expression
                      $additive-operator)

         $multiplicative-expression
))


(:: $additive-operator
    (@or (op "+")
         (op "-")))


;; ($eval $additive-expression (scan "x + y + z"))




;; 5. multiplicative
;;--------------------------------------------
(:: $multiplicative-expression
    (@or (@infix-left 'binop
                      $unary-expression
                      $multiplicative-operator)

         $unary-expression))

(:: $multiplicative-operator
    (@or (op "*")
         (op "/")
         (op "%")))




;; unary =
;; 3. prefix
;; 2. postfix
;;--------------------------------------------
(:: $unary-expression
    $prefix-expression)



;; 3. prefix
;;--------------------------------------------
(:: $prefix-expression
    (@or (@prefix 'prefix
                  $postfix-expression
                  $prefix-operator)
         $postfix-expression))


(:: $prefix-operator
     (@or (@= 'new (op "new") (@? $array-suffix))
          (@= 'delete (op "delete") (@? $array-suffix))
          (@= 'cast |(|  $type  |)| )
          (op "void")
          (op "sizeof")
          (op "++")
          (op "--")
          (op "+")
          (op "-")
          (op "~")
          (op "!")
          (op "*")                      ; indirection
          (op "&")                      ; address of
          (op "::")
))


(::= $array-suffix 'array-suffix
     |[| |]|)




;; 2. postfix
;;--------------------------------------------
(:: $postfix-expression
    (@or (@postfix 'postfix
                   $primary-expression
                   $postfix-operator)
         $primary-expression))


(:: $postfix-operator
     (@or (op "++")
          (op "--")
          $index-suffix
          $property-reference-suffix
          $type-parameter
          $arguments))


(::= $arguments 'argument
     |(|  (@? (@.@ $expression |,|))  |)|
)


(::= $index-suffix 'index
    |[|  $expression  |]|
)


(::= $property-reference-suffix 'field-access
     (@or (@~ ".") (@~ "->")) $identifier)



;; scope resolution ::
;---------------------------------------------
(:: $scope-resolution
    (@or (@infix-left 'scope
                      $id
                      ($$ "::"))

         $primary-expression
))



;; 1. primary
;;--------------------------------------------
(:: $primary-expression
    (@or (@= 'this ($$ "this"))
         $type-cast
         $ctype                         ; could be used in a macro argument
         $identifier
         $literal
         $array-literal
         $object-literal
         (@= #f |(|  $expression  |)|)
))


(::= $type-cast 'type-cast
     (@or ($$ "typeid")
          ($$ "const_cast")
          ($$ "dynamic_cast")
          ($$ "reinterpret_cast")
          ($$ "static_cast")))



;; literal
;;--------------------------------------------
(:: $literal
     (@or ($$ "null")
          ($$ "true")
          ($$ "false")
          $string-concat
          $float-literal
          $numeral-literal
          $string-literal
          $char-literal))


(::= $array-literal 'array-literal
     |{|  (@? (@.@ $expression |,|))  |}|
)


(::= $object-literal 'object-literal
     |{|  $property-name-value (@* (@... |,| $property-name-value))  |}|
)


(::= $property-name-value 'property-name-value
     $property-name |:| $assignment-expression)


(:: $property-name
     (@or $identifier
          $string-literal
          $numeral-literal))


(::= $float-literal 'float-literal
     $numeral-literal ($$ ".") $numeral-literal)


(::= $string-concat 'string-concat
     $string-literal (@* (@or $string-literal $expression)))



;-------------------------------------------------------------
;                    inline assembly
;-------------------------------------------------------------
(::= $inline-assembly 'inline-assembly
     (@or (@~ "asm")
          (@~ "__asm__"))
     (@? (@or ($$ "volatile")
              ($$ "__volatile__")))
     |(|   $string-concat  |)|
     |;|
)


(::= $extended-assembly 'extended-assembly
     (@or (@~ "asm")
          (@~ "__asm__"))
     (@? (@or ($$ "volatile")
              ($$ "__volatile__")))
     |(|  $string-concat
     |:|  (@= 'output-operands (@* $string-literal |(| $identifier |)|  ))
     |:|  (@= 'input-operands (@* $string-literal |(| $identifier |)|   ))
     |:|  (@= 'clobbered-registers (@? (@.@ $string-literal |,|)))
     |)|
     |;|
)





(define parse-cpp
  (lambda (s)
    (first-val
     ($eval $program
            (filter (lambda (x) (not (Comment? x)))
                    (scan s))))))




;-------------------------------------------------------------
;                          tests
;-------------------------------------------------------------

;; (test-file "simulator-arm.cc"
;;            "simulator-mips.cc"
;;            "d8-3404.cc"
;;            "d8-8424.cc"
;;            "assembler-arm-2.cc"
;;            "assembler-arm-7.cc"
;;            "assembler-arm-8309.cc"
;; )

