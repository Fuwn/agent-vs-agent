\ test.f — Self-test suite for the Three-Instruction Forth.
\
\ Each test resets the data stack, runs a small piece of code that
\ produces a single result, and compares that result against an
\ expected value. PASS or FAIL is printed for each test, and at the
\ end the totals are printed.
\
\ The exit code is 0 when every test passes; non-zero otherwise.

VARIABLE PASS-COUNT
VARIABLE FAIL-COUNT

0 PASS-COUNT !
0 FAIL-COUNT !

: TEST-RESET  S0 SP! ;

: NOTE-PASS  1 PASS-COUNT +! ;
: NOTE-FAIL  1 FAIL-COUNT +! ;

: PASS    ." PASS " NOTE-PASS ;
: FAIL    ." FAIL " NOTE-FAIL ;

\ T= ( actual expected -- )  resets the stack on either side so a
\ failing test cannot leak into the next one.
: T=  ( actual expected -- )
    = IF PASS ELSE FAIL THEN
    TEST-RESET
;

: LBL  ( addr len -- )    TYPE 32 EMIT ;

\ ===========================================================================
\ Stack manipulation
\ ===========================================================================

TEST-RESET S" DUP "       LBL    1 DUP +              2 T= CR
TEST-RESET S" DROP "      LBL    1 2 DROP             1 T= CR
TEST-RESET S" SWAP-top "  LBL    1 2 SWAP             1 T= CR
TEST-RESET S" SWAP-bot "  LBL    1 2 SWAP DROP        2 T= CR
TEST-RESET S" OVER "      LBL    1 2 OVER             1 T= CR
TEST-RESET S" ROT "       LBL    1 2 3 ROT            1 T= CR
TEST-RESET S" -ROT "      LBL    1 2 3 -ROT           2 T= CR
TEST-RESET S" NIP "       LBL    1 2 NIP              2 T= CR
TEST-RESET S" TUCK-top "  LBL    1 2 TUCK             2 T= CR
TEST-RESET S" TUCK-bot "  LBL    1 2 TUCK DROP DROP   2 T= CR
TEST-RESET S" ?DUP-zero " LBL    0 ?DUP                0 T= CR
TEST-RESET S" ?DUP-non "  LBL    5 ?DUP +             10 T= CR
TEST-RESET S" 2DUP-top "  LBL    1 2 2DUP             2 T= CR
TEST-RESET S" 2DUP-3rd "  LBL    1 2 2DUP DROP DROP   2 T= CR
TEST-RESET S" 2DROP "     LBL    1 2 3 2DROP          1 T= CR
TEST-RESET S" 2SWAP "     LBL    1 2 3 4 2SWAP        2 T= CR
TEST-RESET S" DEPTH-3 "   LBL    1 2 3 DEPTH          3 T= CR
TEST-RESET S" DEPTH-0 "   LBL    DEPTH                0 T= CR

\ ===========================================================================
\ Arithmetic
\ ===========================================================================

TEST-RESET S" + "          LBL    2 3 +                 5  T= CR
TEST-RESET S" - "          LBL    10 3 -                7  T= CR
TEST-RESET S" * "          LBL    4 7 *                 28 T= CR
TEST-RESET S" / "          LBL    20 4 /                5  T= CR
TEST-RESET S" / -neg "     LBL    -20 4 /              -5  T= CR
TEST-RESET S" MOD "        LBL    20 6 MOD              2  T= CR
TEST-RESET S" /MOD-q "     LBL    23 5 /MOD SWAP DROP   4  T= CR
TEST-RESET S" /MOD-r "     LBL    23 5 /MOD DROP        3  T= CR
TEST-RESET S" 1+ "         LBL    5 1+                  6  T= CR
TEST-RESET S" 1- "         LBL    5 1-                  4  T= CR
TEST-RESET S" 2* "         LBL    7 2*                  14 T= CR
TEST-RESET S" 2/ "         LBL    14 2/                 7  T= CR
TEST-RESET S" 2/-neg "     LBL    -14 2/                -7 T= CR
TEST-RESET S" NEGATE "     LBL    5 NEGATE             -5  T= CR
TEST-RESET S" NEGATE-neg " LBL   -5 NEGATE              5  T= CR
TEST-RESET S" ABS-pos "    LBL    5 ABS                 5  T= CR
TEST-RESET S" ABS-neg "    LBL    -5 ABS                5  T= CR
TEST-RESET S" MIN "        LBL    3 7 MIN               3  T= CR
TEST-RESET S" MAX "        LBL    3 7 MAX               7  T= CR
TEST-RESET S" MIN-neg "    LBL    -3 -7 MIN            -7  T= CR
TEST-RESET S" MAX-neg "    LBL    -3 -7 MAX            -3  T= CR

\ ===========================================================================
\ Logic / bitwise
\ ===========================================================================

TEST-RESET S" AND "        LBL    12 10 AND             8  T= CR
TEST-RESET S" OR "         LBL    12 10 OR              14 T= CR
TEST-RESET S" XOR "        LBL    12 10 XOR             6  T= CR
TEST-RESET S" INVERT "     LBL    0 INVERT             -1  T= CR
TEST-RESET S" LSHIFT "     LBL    1 4 LSHIFT            16 T= CR
TEST-RESET S" RSHIFT "     LBL    16 3 RSHIFT           2  T= CR

\ ===========================================================================
\ Comparison
\ ===========================================================================

TEST-RESET S" =-true "     LBL    5 5 =                -1  T= CR
TEST-RESET S" =-false "    LBL    5 4 =                 0  T= CR
TEST-RESET S" <>-true "    LBL    5 4 <>               -1  T= CR
TEST-RESET S" <-true "     LBL    3 5 <                -1  T= CR
TEST-RESET S" <-false "    LBL    5 3 <                 0  T= CR
TEST-RESET S" >-true "     LBL    5 3 >                -1  T= CR
TEST-RESET S" <=-eq "      LBL    5 5 <=               -1  T= CR
TEST-RESET S" >=-eq "      LBL    5 5 >=               -1  T= CR
TEST-RESET S" 0=-zero "    LBL    0 0=                 -1  T= CR
TEST-RESET S" 0=-non "     LBL    1 0=                  0  T= CR
TEST-RESET S" 0<-neg "     LBL    -1 0<                -1  T= CR
TEST-RESET S" 0<-pos "     LBL    1 0<                  0  T= CR
TEST-RESET S" 0>-pos "     LBL    1 0>                 -1  T= CR
TEST-RESET S" 0<>-non "    LBL    5 0<>                -1  T= CR

\ ===========================================================================
\ Memory
\ ===========================================================================

VARIABLE TVAR
TEST-RESET S" !@ round-trip" LBL  42 TVAR ! TVAR @     42 T= CR
TEST-RESET S" +! "         LBL    10 TVAR ! 5 TVAR +! TVAR @  15 T= CR
TEST-RESET S" CELLS "      LBL    3 CELLS               24 T= CR
TEST-RESET S" CHARS "      LBL    7 CHARS               7  T= CR

\ Byte memory test using a small private buffer.
HERE @ 16 ALLOT CONSTANT TBUF
TEST-RESET S" C! C@ "      LBL    65 TBUF C! TBUF C@   65 T= CR

\ ===========================================================================
\ Constants and variables
\ ===========================================================================

100 CONSTANT HUNDRED
TEST-RESET S" CONSTANT "   LBL    HUNDRED               100 T= CR

VARIABLE V1
9 V1 !
TEST-RESET S" VARIABLE "   LBL    V1 @                  9 T= CR

\ ===========================================================================
\ Control flow
\ ===========================================================================

: IF-TRUE   1 IF 11 ELSE 22 THEN ;
: IF-FALSE  0 IF 11 ELSE 22 THEN ;
TEST-RESET S" IF-true "    LBL    IF-TRUE              11 T= CR
TEST-RESET S" IF-false "   LBL    IF-FALSE             22 T= CR

: NESTED-IF  ( n -- r )
    DUP 0 < IF
        DROP -1
    ELSE
        DUP 0 = IF
            DROP 0
        ELSE
            DROP 1
        THEN
    THEN
;
TEST-RESET S" nested-IF-neg" LBL   -5 NESTED-IF        -1 T= CR
TEST-RESET S" nested-IF-zero" LBL   0 NESTED-IF         0 T= CR
TEST-RESET S" nested-IF-pos"  LBL   5 NESTED-IF         1 T= CR

: SUM-DOWN  ( n -- s )
    0 SWAP
    BEGIN DUP 0 > WHILE
        TUCK + SWAP 1-
    REPEAT DROP
;
TEST-RESET S" BEGIN/WHILE/REPEAT" LBL  10 SUM-DOWN     55 T= CR

: COUNT-TO-FIVE  ( -- 5 )
    0 BEGIN 1+ DUP 5 = UNTIL
;
TEST-RESET S" BEGIN/UNTIL " LBL    COUNT-TO-FIVE        5 T= CR

\ Recursion
: FIB ( n -- f )
    DUP 2 < IF EXIT THEN
    DUP 1- RECURSE
    SWAP 2 - RECURSE
    +
;
TEST-RESET S" RECURSE-fib"  LBL    10 FIB              55 T= CR

\ Early EXIT
: EXIT-EARLY  ( n -- m )
    DUP 0> IF EXIT THEN
    DROP 99
;
TEST-RESET S" EXIT-pos "   LBL    7 EXIT-EARLY          7  T= CR
TEST-RESET S" EXIT-zero"   LBL    0 EXIT-EARLY          99 T= CR

\ ===========================================================================
\ Dictionary / interpreter
\ ===========================================================================

: ADDABC  ( a b c -- s )    + + ;
TEST-RESET S" colon def "  LBL    1 2 3 ADDABC          6 T= CR

: IMM-WORD IMMEDIATE  77 ;
TEST-RESET S" IMMEDIATE "  LBL    IMM-WORD              77 T= CR

\ ' EXECUTE round-trip
TEST-RESET S" tick+EXEC "  LBL    10 ' DUP EXECUTE +   20 T= CR

\ Number parsing
TEST-RESET S" decimal "    LBL    255                   255 T= CR
TEST-RESET S" negative "   LBL    -42                   -42 T= CR

\ ===========================================================================
\ String I/O
\ ===========================================================================

: SAYHI  ." HI" ;
TEST-RESET ." Output check (expect HI): "  SAYHI  CR

\ ===========================================================================
\ Summary
\ ===========================================================================

CR
." === RESULTS ===" CR
." Pass: " PASS-COUNT @ . CR
." Fail: " FAIL-COUNT @ . CR

\ Exit non-zero if any failure.
FAIL-COUNT @ 0= IF
    BYE
THEN

\ Failure path: trigger an unknown-word abort to give exit code 1.
TESTS-DID-NOT-ALL-PASS
