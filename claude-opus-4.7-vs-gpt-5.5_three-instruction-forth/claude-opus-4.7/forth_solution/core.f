\ core.f — Forth standard library, built on top of the boot.s primitives.
\
\ Every word here is a colon definition or a CONSTANT/VARIABLE built
\ from one. The only assembly-level entries are the primitives in
\ boot.s; everything below is composed from those primitives plus
\ already-defined Forth words.
\
\ Order matters: a word must be defined before any later word uses it.
\ Until ( is defined we use \ for line comments only.

\ ===========================================================================
\ Compile-time helpers
\ ===========================================================================

\ Patch a forward branch placeholder so it points to the current HERE.
\ Stack:  placeholder-addr  --
: !OFFSET HERE @ OVER - SWAP ! ;

\ ===========================================================================
\ Structured control flow (all IMMEDIATE compile-time helpers)
\ ===========================================================================

: IF IMMEDIATE
    ['] 0BRANCH , HERE @ 0 ,
;

: THEN IMMEDIATE !OFFSET ;

: ELSE IMMEDIATE
    ['] BRANCH , HERE @ 0 ,
    SWAP !OFFSET
;

: BEGIN IMMEDIATE HERE @ ;

: AGAIN IMMEDIATE
    ['] BRANCH , HERE @ - ,
;

: UNTIL IMMEDIATE
    ['] 0BRANCH , HERE @ - ,
;

: WHILE IMMEDIATE
    ['] 0BRANCH , HERE @ 0 ,
;

: REPEAT IMMEDIATE
    ['] BRANCH ,
    SWAP HERE @ - ,
    !OFFSET
;

\ Now we have BEGIN/UNTIL: define the parenthetical comment word.
: ( IMMEDIATE
    BEGIN KEY 41 = UNTIL
;

\ ===========================================================================
\ Stack manipulation
\ ===========================================================================

: NIP    ( a b -- b )            SWAP DROP ;
: TUCK   ( a b -- b a b )        SWAP OVER ;
: ?DUP   ( n -- n n | 0 )        DUP IF DUP THEN ;
: 2DUP   ( a b -- a b a b )      OVER OVER ;
: 2DROP  ( a b -- )              DROP DROP ;
: 2SWAP  ( a b c d -- c d a b )  ROT >R ROT R> ;

\ ===========================================================================
\ Useful constants
\ ===========================================================================

: TRUE  ( -- -1 )    -1 ;
: FALSE ( -- 0 )      0 ;
: BL    ( -- 32 )    32 ;
: NL    ( -- 10 )    10 ;

\ ===========================================================================
\ Arithmetic
\ ===========================================================================

: 1+     ( n -- n+1 )    1 + ;
: 1-     ( n -- n-1 )    1 - ;
: 2+     ( n -- n+2 )    2 + ;
: 2-     ( n -- n-2 )    2 - ;
: 2*     ( n -- 2n )     2 * ;
: NEGATE ( n -- -n )     0 SWAP - ;
: ABS    ( n -- |n| )    DUP 0< IF NEGATE THEN ;

: /      ( a b -- a/b )  /MOD NIP ;
: MOD    ( a b -- a%b )  /MOD DROP ;
: 2/     ( n -- n/2 )    2 / ;

: MIN    ( a b -- min )  2DUP < IF DROP ELSE NIP THEN ;
: MAX    ( a b -- max )  2DUP < IF NIP ELSE DROP THEN ;

\ ===========================================================================
\ Comparison
\ ===========================================================================

: <>    ( a b -- f )    = INVERT ;
: >     ( a b -- f )    SWAP < ;
: <=    ( a b -- f )    > INVERT ;
: >=    ( a b -- f )    < INVERT ;
: 0<>   ( n -- f )      0= INVERT ;
: 0>    ( n -- f )      0 SWAP < ;

\ ===========================================================================
\ Memory
\ ===========================================================================

: +!    ( n addr -- )    SWAP OVER @ + SWAP ! ;
: CELL    ( -- 8 )       8 ;
: CELLS   ( n -- 8n )    8 * ;
: CHARS   ( n -- n )     ;
: ALLOT   ( n -- )       HERE +! ;

\ ===========================================================================
\ Character helpers
\ ===========================================================================

: CHAR    ( "<spaces>name" -- c )    WORD DROP C@ ;

\ [CHAR] is IMMEDIATE: at compile time it reads the next word's first
\ char and compiles `LIT <c>` into the surrounding definition. We must
\ avoid invoking LITERAL directly in [CHAR]'s body, because LITERAL is
\ itself IMMEDIATE — it would fire during compilation of [CHAR] (with
\ an empty stack) instead of becoming a runtime call. Inline the LIT
\ compilation manually instead.
: [CHAR] IMMEDIATE
    CHAR
    ['] LIT , ,
;

\ ===========================================================================
\ I/O
\ ===========================================================================

: SPACE  ( -- )        BL EMIT ;
: CR     ( -- )        NL EMIT ;
: SPACES ( n -- )      BEGIN DUP 0> WHILE SPACE 1- REPEAT DROP ;

: TYPE   ( addr len -- )
    BEGIN DUP 0> WHILE
        OVER C@ EMIT
        SWAP 1+ SWAP 1-
    REPEAT 2DROP
;

: COUNT ( c-addr -- addr len )
    DUP 1+ SWAP C@
;

\ ===========================================================================
\ RECURSE — compile a call to the word currently being defined.
\ ===========================================================================

: RECURSE IMMEDIATE
    LATEST @ >CFA ,
;

\ ===========================================================================
\ Number printing
\ ===========================================================================

: DIGIT-CHAR ( d -- c )
    DUP 10 < IF 48 + ELSE 55 + THEN
;

: U.RAW ( u -- )
    DUP BASE @ < IF
        DIGIT-CHAR EMIT
    ELSE
        DUP BASE @ /     RECURSE
        BASE @ MOD DIGIT-CHAR EMIT
    THEN
;

: U.    ( u -- )    U.RAW SPACE ;

: .     ( n -- )
    DUP 0< IF
        45 EMIT NEGATE
    THEN
    U.RAW SPACE
;

\ ===========================================================================
\ Defining words: VARIABLE / CONSTANT / CREATE
\ ===========================================================================

: CREATE
    HEADER, DOCOL,
    ['] LIT ,
    HERE @ 16 +  ,
    ['] EXIT ,
;

: VARIABLE  CREATE 0 , ;

: CONSTANT  ( value -- )
    HEADER, DOCOL,
    ['] LIT ,
    ,
    ['] EXIT ,
;

\ ===========================================================================
\ -TRAILING — strip trailing spaces from a string.
\ ===========================================================================

: -TRAILING ( addr len -- addr len' )
    BEGIN
        DUP 0> IF
            2DUP + 1- C@ BL =
        ELSE
            FALSE
        THEN
    WHILE
        1-
    REPEAT
;

\ ===========================================================================
\ Inline string output: ."
\ Layout when compiled inside a colon def:
\     [BRANCH] [+offset]
\     [counted-string]                ( length byte + bytes )
\     [LIT] [string-addr]
\     [PRINT-COUNTED]
\ ===========================================================================

: PRINT-COUNTED ( addr -- )
    DUP C@                ( addr len )
    SWAP 1+ SWAP          ( addr+1 len )
    TYPE
;

\ Push an inline string at runtime: pushes (addr len). Used by S" below.
: PUSH-STRING ( addr -- addr len )
    DUP 1+ SWAP C@
;

\ S" — push the address and length of an inline string onto the stack.
\ Layout when compiled:
\     [BRANCH] [+offset]
\     [counted-string]
\     [LIT] [saddr]   [PUSH-STRING]
\ At interpret time, S" reads chars and stores them in a transient
\ buffer, leaving (addr len) on the stack pointing into that buffer.
\ The transient buffer is reused by every interpret-time S".

HERE @ 256 ALLOT CONSTANT S-BUF

: S" IMMEDIATE
    STATE @ IF
        ['] BRANCH ,
        HERE @ 0 ,            ( -- bptr )
        HERE @                ( -- bptr saddr )
        0 C,                  ( placeholder length )
        0                     ( -- bptr saddr count )
        BEGIN
            KEY DUP 34 <>
        WHILE
            C, 1+
        REPEAT DROP
        OVER C!               ( store length )
        SWAP                  ( -- saddr bptr )
        HERE @ OVER -
        SWAP !                ( -- saddr )
        ['] LIT , ,
        ['] PUSH-STRING ,
    ELSE
        \ Interpret mode: store chars into S-BUF and push (addr len).
        S-BUF 0
        BEGIN
            KEY DUP 34 <>
        WHILE
            >R 2DUP + R> SWAP C!
            1+
        REPEAT DROP
    THEN
;

: ." IMMEDIATE
    STATE @ IF
        \ Compile mode: emit a counted string and a runtime EMIT loop.
        ['] BRANCH ,
        HERE @ 0 ,            ( -- bptr )
        HERE @                ( -- bptr saddr )
        0 C,                  ( placeholder for length byte )
        0                     ( -- bptr saddr count )
        BEGIN
            KEY DUP 34 <>
        WHILE
            C, 1+
        REPEAT DROP
        OVER C!               ( store final length )
        SWAP                  ( -- saddr bptr )
        HERE @ OVER -         ( -- saddr bptr offset )
        SWAP !                ( -- saddr )
        ['] LIT ,
        ,
        ['] PRINT-COUNTED ,
    ELSE
        \ Interpret mode: emit chars directly until closing quote.
        BEGIN
            KEY DUP 34 <>
        WHILE
            EMIT
        REPEAT DROP
    THEN
;

\ ===========================================================================
\ DUMP — print N cells starting at addr in current BASE.
\ ===========================================================================

: DUMP ( addr n -- )
    BEGIN DUP 0> WHILE
        OVER @ .
        SWAP 8 + SWAP
        1-
    REPEAT 2DROP
;

\ ===========================================================================
\ ABORT — empty data stack; subsequent INTERPRET continues.
\ ===========================================================================

: ABORT
    S0 SP!
;

\ ===========================================================================
\ WORDS — list every visible dictionary entry.
\ ===========================================================================

: WORDS
    LATEST @
    BEGIN DUP 0= 0= WHILE
        DUP 8 + DUP C@        ( header flagaddr flagbyte )
        DUP 32 AND 0= IF
            31 AND
            SWAP 1+ SWAP
            TYPE SPACE
        ELSE
            DROP DROP
        THEN
        @
    REPEAT DROP CR
;
