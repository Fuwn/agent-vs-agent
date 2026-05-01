// boot.s — Three-Instruction Forth kernel for macOS arm64
//
// This file implements the bare-metal kernel. Only the primitives listed
// below are written in assembly; everything else is built in Forth in
// core.f. The "three instructions" are STORE (!), FETCH (@), and CALL —
// the inner-interpreter dispatch (DOCOL/EXIT) realises CALL/return for
// indirect-threaded code. KEY/EMIT (and BYE for clean exit) are the only
// additional assembly primitives the spec allows.
//
// Threading model: indirect-threaded code (ITC).
// Stacks: full-descending, separate parameter and return stacks.
//
// Register conventions:
//   x12 = IP   (instruction pointer for threaded Forth code)
//   x13 = RSP  (return stack pointer)
//   x14 = PSP  (parameter stack pointer)
//   x0..x11, x15..x17 = scratch
//
// Word header layout (in dictionary linked list):
//   +0  link          : 8 bytes, address of previous header (0 = end)
//   +8  flags+nlen    : 1 byte (high bits flags, low 6 bits length)
//   +9  name bytes    : nlen bytes
//   +9+nlen           : padded to 8-byte alignment
//   +CFA              : 8 bytes, code-field address
//                        - for primitives: address of native code
//                        - for colon defs: address of `docol_indirect`
//                          which itself contains address of docol routine
//   +CFA+8            : body (sequence of CFA pointers, terminated by EXIT)

.equ F_IMMED,   0x80
.equ F_HIDDEN,  0x20
.equ F_LENMASK, 0x1f

.equ STDIN,     0
.equ STDOUT,    1
.equ SYS_EXIT,  1
.equ SYS_READ,  3
.equ SYS_WRITE, 4

// === Threading macros =====================================================

.macro NEXT
    ldr x0, [x12], #8
    ldr x1, [x0]
    br  x1
.endm

.macro PUSH reg
    str \reg, [x14, #-8]!
.endm

.macro POP reg
    ldr \reg, [x14], #8
.endm

.macro PUSHR reg
    str \reg, [x13, #-8]!
.endm

.macro POPR reg
    ldr \reg, [x13], #8
.endm

// === Dictionary entry macros ==============================================
//
// defcode  : assembly primitive — code routine immediately follows.
// defword  : threaded colon definition — body of CFA pointers follows.
// defvar   : variable — pushes address of the named storage cell.
// defconst : constant — pushes the named immediate value.

.macro defcode name, label, prev, flags=0
    .data
    .balign 8
name_\label:
    .quad name_\prev
    .byte \flags + (8f - 7f)
7:  .ascii "\name"
8:  .balign 8
xt_\label:
    .quad code_\label
    .text
    .balign 4
code_\label:
.endm

.macro defcode_first name, label, flags=0
    .data
    .balign 8
name_\label:
    .quad 0
    .byte \flags + (8f - 7f)
7:  .ascii "\name"
8:  .balign 8
xt_\label:
    .quad code_\label
    .text
    .balign 4
code_\label:
.endm

.macro defword name, label, prev, flags=0
    .data
    .balign 8
name_\label:
    .quad name_\prev
    .byte \flags + (8f - 7f)
7:  .ascii "\name"
8:  .balign 8
xt_\label:
    .quad docol
.endm

.macro defvar name, label, prev, var, flags=0
    .data
    .balign 8
name_\label:
    .quad name_\prev
    .byte \flags + (8f - 7f)
7:  .ascii "\name"
8:  .balign 8
xt_\label:
    .quad code_\label
    .text
    .balign 4
code_\label:
    adrp x0, \var@PAGE
    add  x0, x0, \var@PAGEOFF
    PUSH x0
    NEXT
.endm

.macro defconst name, label, prev, value, flags=0
    .data
    .balign 8
name_\label:
    .quad name_\prev
    .byte \flags + (8f - 7f)
7:  .ascii "\name"
8:  .balign 8
xt_\label:
    .quad code_\label
    .text
    .balign 4
code_\label:
    mov  x0, #\value
    PUSH x0
    NEXT
.endm

// === Entry point ==========================================================

.text
.global _main
.balign 4
_main:
    adrp x14, dstack_top@PAGE
    add  x14, x14, dstack_top@PAGEOFF

    adrp x13, rstack_top@PAGE
    add  x13, x13, rstack_top@PAGEOFF

    adrp x0, dict_space@PAGE
    add  x0, x0, dict_space@PAGEOFF
    adrp x1, var_HERE@PAGE
    add  x1, x1, var_HERE@PAGEOFF
    str  x0, [x1]

    adrp x0, name_LATEST_INIT@PAGE
    add  x0, x0, name_LATEST_INIT@PAGEOFF
    adrp x1, var_LATEST@PAGE
    add  x1, x1, var_LATEST@PAGEOFF
    str  x0, [x1]

    adrp x12, xt_COLD@PAGE
    add  x12, x12, xt_COLD@PAGEOFF
    add  x12, x12, #8
    NEXT

// docol — entered when a colon definition's CFA dispatches.
// On entry, x0 holds the CFA address (set by NEXT before br).
docol:
    PUSHR x12
    add x12, x0, #8
    NEXT

.text

// === Primitives ===========================================================

defcode_first "EXIT", EXIT
    POPR x12
    NEXT

defcode "!", STORE, EXIT
    POP x0
    POP x1
    str x1, [x0]
    NEXT

defcode "@", FETCH, STORE
    POP x0
    ldr x1, [x0]
    PUSH x1
    NEXT

defcode "C!", CSTORE, FETCH
    POP x0
    POP x1
    strb w1, [x0]
    NEXT

defcode "C@", CFETCH, CSTORE
    POP x0
    ldrb w1, [x0]
    PUSH x1
    NEXT

defcode "KEY", KEY, CFETCH
    sub  sp, sp, #16
    mov  x16, #SYS_READ
    mov  x0, #STDIN
    mov  x1, sp
    mov  x2, #1
    svc  #0x80
    cmp  x0, #1
    b.ne 1f
    ldrb w1, [sp]
    add  sp, sp, #16
    PUSH x1
    NEXT
1:  add  sp, sp, #16
    mov  x1, #-1
    PUSH x1
    NEXT

defcode "EMIT", EMIT, KEY
    POP  x1
    sub  sp, sp, #16
    strb w1, [sp]
    mov  x16, #SYS_WRITE
    mov  x0, #STDOUT
    mov  x1, sp
    mov  x2, #1
    svc  #0x80
    add  sp, sp, #16
    NEXT

defcode "BYE", BYE, EMIT
    mov  x16, #SYS_EXIT
    mov  x0, #0
    svc  #0x80

defcode "LIT", LIT, BYE
    ldr x0, [x12], #8
    PUSH x0
    NEXT

defcode "BRANCH", BRANCH, LIT
    ldr x0, [x12]
    add x12, x12, x0
    NEXT

defcode "0BRANCH", ZBRANCH, BRANCH
    POP x1
    cbz x1, 1f
    add x12, x12, #8
    NEXT
1:  ldr x0, [x12]
    add x12, x12, x0
    NEXT

defcode "EXECUTE", EXECUTE, ZBRANCH
    POP x0
    ldr x1, [x0]
    br  x1

defcode "DUP", DUP, EXECUTE
    ldr x0, [x14]
    PUSH x0
    NEXT

defcode "DROP", DROP, DUP
    add x14, x14, #8
    NEXT

defcode "SWAP", SWAP, DROP
    ldr x0, [x14]
    ldr x1, [x14, #8]
    str x1, [x14]
    str x0, [x14, #8]
    NEXT

defcode "OVER", OVER, SWAP
    ldr x0, [x14, #8]
    PUSH x0
    NEXT

defcode "ROT", ROT, OVER
    ldr x0, [x14]
    ldr x1, [x14, #8]
    ldr x2, [x14, #16]
    str x1, [x14, #16]
    str x0, [x14, #8]
    str x2, [x14]
    NEXT

defcode "-ROT", NROT, ROT
    ldr x0, [x14]            // c (top)
    ldr x1, [x14, #8]        // b
    ldr x2, [x14, #16]       // a
    str x0, [x14, #16]       // bottom ← c
    str x2, [x14, #8]        // mid ← a
    str x1, [x14]            // top ← b
    NEXT

defcode ">R", TOR, NROT
    POP x0
    PUSHR x0
    NEXT

defcode "R>", FROMR, TOR
    POPR x0
    PUSH x0
    NEXT

defcode "R@", RFETCH, FROMR
    ldr x0, [x13]
    PUSH x0
    NEXT

defcode "SP@", SPFETCH, RFETCH
    mov x0, x14
    PUSH x0
    NEXT

defcode "SP!", SPSTORE, SPFETCH
    ldr x14, [x14]
    NEXT

defcode "RSP@", RSPFETCH, SPSTORE
    mov x0, x13
    PUSH x0
    NEXT

defcode "RSP!", RSPSTORE, RSPFETCH
    POP x13
    NEXT

defcode "+", PLUS, RSPSTORE
    POP x0
    POP x1
    add x0, x0, x1
    PUSH x0
    NEXT

defcode "-", MINUS, PLUS
    POP x0
    POP x1
    sub x0, x1, x0
    PUSH x0
    NEXT

defcode "*", MUL, MINUS
    POP x0
    POP x1
    mul x0, x0, x1
    PUSH x0
    NEXT

defcode "/MOD", SLASHMOD, MUL
    POP x1            // divisor
    POP x0            // dividend
    sdiv x2, x0, x1   // quotient
    msub x3, x2, x1, x0  // remainder = x0 - x2*x1
    PUSH x3
    PUSH x2
    NEXT

defcode "AND", AND_, SLASHMOD
    POP x0
    POP x1
    and x0, x0, x1
    PUSH x0
    NEXT

defcode "OR", OR_, AND_
    POP x0
    POP x1
    orr x0, x0, x1
    PUSH x0
    NEXT

defcode "XOR", XOR_, OR_
    POP x0
    POP x1
    eor x0, x0, x1
    PUSH x0
    NEXT

defcode "INVERT", INVERT, XOR_
    POP x0
    mvn x0, x0
    PUSH x0
    NEXT

defcode "LSHIFT", LSHIFT, INVERT
    POP x0
    POP x1
    lsl x0, x1, x0
    PUSH x0
    NEXT

defcode "RSHIFT", RSHIFT, LSHIFT
    POP x0
    POP x1
    lsr x0, x1, x0
    PUSH x0
    NEXT

defcode "=", EQ, RSHIFT
    POP x0
    POP x1
    cmp x0, x1
    cset x0, eq
    neg x0, x0
    PUSH x0
    NEXT

defcode "<", LT, EQ
    POP x0
    POP x1
    cmp x1, x0
    cset x0, lt
    neg x0, x0
    PUSH x0
    NEXT

defcode "0=", ZEQ, LT
    POP x0
    cmp x0, #0
    cset x0, eq
    neg x0, x0
    PUSH x0
    NEXT

defcode "0<", ZLT, ZEQ
    POP x0
    cmp x0, #0
    cset x0, lt
    neg x0, x0
    PUSH x0
    NEXT

defcode "DEPTH", DEPTH, ZLT
    adrp x0, dstack_top@PAGE
    add  x0, x0, dstack_top@PAGEOFF
    sub  x0, x0, x14
    asr  x0, x0, #3
    PUSH x0
    NEXT

defcode "S0", S0, DEPTH
    adrp x0, dstack_top@PAGE
    add  x0, x0, dstack_top@PAGEOFF
    PUSH x0
    NEXT

defcode "R0", R0, S0
    adrp x0, rstack_top@PAGE
    add  x0, x0, rstack_top@PAGEOFF
    PUSH x0
    NEXT

// === Variables and constants =============================================

defvar  "HERE",    HERE,    R0,      var_HERE
defvar  "LATEST",  LATEST,  HERE,    var_LATEST
defvar  "STATE",   STATE,   LATEST,  var_STATE
defvar  "BASE",    BASE,    STATE,   var_BASE

defconst "F_IMMED",   F_IMMEDC,   BASE,     0x80
defconst "F_HIDDEN",  F_HIDDENC,  F_IMMEDC, 0x20
defconst "F_LENMASK", F_LENMASKC, F_HIDDENC, 0x1f
defconst "DOCOL",     DOCOLC,     F_LENMASKC, 0     // patched at runtime

// === WORD primitive — parses next whitespace-delimited word from stdin ==

defcode "WORD", WORD_, DOCOLC
    adrp x10, word_buffer@PAGE
    add  x10, x10, word_buffer@PAGEOFF
    mov  x11, #0
1:  bl   _read_char
    cmn  x0, #1
    b.eq .Lword_eof
    cmp  x0, #'\\'
    b.ne 2f
3:  bl   _read_char        // skip line comment
    cmn  x0, #1
    b.eq .Lword_eof
    cmp  x0, #'\n'
    b.ne 3b
    b    1b
2:  cmp  x0, #' '
    b.le 1b
4:  strb w0, [x10, x11]
    add  x11, x11, #1
    bl   _read_char
    cmn  x0, #1
    b.eq .Lword_done
    cmp  x0, #' '
    b.gt 4b
.Lword_done:
    PUSH x10
    PUSH x11
    NEXT
.Lword_eof:
    cmp  x11, #0
    b.ne .Lword_done
    PUSH x10
    mov  x11, #0
    PUSH x11
    NEXT

_read_char:
    sub  sp, sp, #16
    mov  x16, #SYS_READ
    mov  x0, #STDIN
    mov  x1, sp
    mov  x2, #1
    svc  #0x80
    cmp  x0, #1
    b.ne 1f
    ldrb w0, [sp]
    add  sp, sp, #16
    ret
1:  add  sp, sp, #16
    mov  x0, #-1
    ret

// === FIND — search dictionary for name, return header addr or 0 ==========

defcode "FIND", FIND, WORD_
    POP x2                    // length
    POP x1                    // name addr
    adrp x0, var_LATEST@PAGE
    add  x0, x0, var_LATEST@PAGEOFF
    ldr  x3, [x0]             // current header
.Lfind_loop:
    cbz  x3, .Lfind_notfound
    ldrb w4, [x3, #8]         // flags+len byte
    tst  w4, #F_HIDDEN
    b.ne .Lfind_next
    and  w5, w4, #F_LENMASK
    cmp  w5, w2
    b.ne .Lfind_next
    add  x6, x3, #9           // name start
    mov  x7, x1               // candidate
    mov  x8, x2               // bytes to compare
.Lfind_cmp:
    cbz  x8, .Lfind_match
    ldrb w9, [x6], #1
    ldrb w10, [x7], #1
    cmp  w9, w10
    b.ne .Lfind_next
    sub  x8, x8, #1
    b    .Lfind_cmp
.Lfind_match:
    PUSH x3
    NEXT
.Lfind_next:
    ldr  x3, [x3]
    b    .Lfind_loop
.Lfind_notfound:
    mov  x3, #0
    PUSH x3
    NEXT

// === >CFA — convert dictionary header addr to CFA addr ===================

defcode ">CFA", TCFA, FIND
    POP x0
    ldrb w1, [x0, #8]
    and  w1, w1, #F_LENMASK
    add  x1, x1, #9           // skip link + flag/len byte + name
    add  x0, x0, x1
    add  x0, x0, #7
    and  x0, x0, #~7          // align up to 8
    PUSH x0
    NEXT

// === , (COMMA) — append cell at HERE, advance HERE =======================

defcode ",", COMMA, TCFA
    POP x0
    adrp x1, var_HERE@PAGE
    add  x1, x1, var_HERE@PAGEOFF
    ldr  x2, [x1]
    str  x0, [x2], #8
    str  x2, [x1]
    NEXT

defcode "C,", CCOMMA, COMMA
    POP x0
    adrp x1, var_HERE@PAGE
    add  x1, x1, var_HERE@PAGEOFF
    ldr  x2, [x1]
    strb w0, [x2], #1
    str  x2, [x1]
    NEXT

// === HEADER — read next word from input, create dictionary header ========
// ( -- )  side effect: extends dictionary with link+name, leaves HERE at
// position where CFA should be written (not advanced past CFA).

defcode "HEADER,", HEADER, CCOMMA
    // Parse a word
    adrp x10, word_buffer@PAGE
    add  x10, x10, word_buffer@PAGEOFF
    mov  x11, #0
1:  bl   _read_char
    cmn  x0, #1
    b.eq .Lhdr_eof
    cmp  x0, #'\\'
    b.ne 2f
3:  bl   _read_char
    cmn  x0, #1
    b.eq .Lhdr_eof
    cmp  x0, #'\n'
    b.ne 3b
    b    1b
2:  cmp  x0, #' '
    b.le 1b
4:  strb w0, [x10, x11]
    add  x11, x11, #1
    bl   _read_char
    cmn  x0, #1
    b.eq .Lhdr_have
    cmp  x0, #' '
    b.gt 4b
.Lhdr_have:
    // Build header at HERE
    adrp x5, var_HERE@PAGE
    add  x5, x5, var_HERE@PAGEOFF
    ldr  x6, [x5]               // header addr

    adrp x7, var_LATEST@PAGE
    add  x7, x7, var_LATEST@PAGEOFF
    ldr  x8, [x7]               // previous LATEST
    str  x6, [x7]               // new LATEST = header

    str  x8, [x6]               // link
    strb w11, [x6, #8]          // length byte
    add  x9, x6, #9
    mov  x4, #0
.Lhdr_copy:
    cmp  x4, x11
    b.ge .Lhdr_done
    ldrb w0, [x10, x4]
    strb w0, [x9, x4]
    add  x4, x4, #1
    b    .Lhdr_copy
.Lhdr_done:
    add  x9, x9, x11
    add  x9, x9, #7
    and  x9, x9, #~7            // align HERE up
    str  x9, [x5]
    NEXT
.Lhdr_eof:
    PUSH xzr
    PUSH xzr
    PUSH xzr
    POP  x16
    mov  x16, #SYS_EXIT
    mov  x0, #0
    svc  #0x80

// === IMMEDIATE — toggle immediate flag of latest word ====================

defcode "IMMEDIATE", IMMEDIATE, HEADER, F_IMMED
    adrp x0, var_LATEST@PAGE
    add  x0, x0, var_LATEST@PAGEOFF
    ldr  x1, [x0]
    ldrb w2, [x1, #8]
    eor  w2, w2, #F_IMMED
    strb w2, [x1, #8]
    NEXT

// === HIDDEN — toggle hidden flag of latest word ==========================

defcode "HIDDEN", HIDDEN, IMMEDIATE
    adrp x0, var_LATEST@PAGE
    add  x0, x0, var_LATEST@PAGEOFF
    ldr  x1, [x0]
    ldrb w2, [x1, #8]
    eor  w2, w2, #F_HIDDEN
    strb w2, [x1, #8]
    NEXT

// === DOCOL, — append docol_indirect address (start a colon definition) ==

defcode "DOCOL,", DOCOLCOMMA, HIDDEN
    adrp x0, docol@PAGE
    add  x0, x0, docol@PAGEOFF
    adrp x1, var_HERE@PAGE
    add  x1, x1, var_HERE@PAGEOFF
    ldr  x2, [x1]
    str  x0, [x2], #8
    str  x2, [x1]
    NEXT

// === [ and ] — toggle compile state (LBRACK is IMMEDIATE) ===============

defcode "[", LBRACK, DOCOLCOMMA, F_IMMED
    adrp x0, var_STATE@PAGE
    add  x0, x0, var_STATE@PAGEOFF
    str  xzr, [x0]
    NEXT

defcode "]", RBRACK, LBRACK
    adrp x0, var_STATE@PAGE
    add  x0, x0, var_STATE@PAGEOFF
    mov  x1, #1
    str  x1, [x0]
    NEXT

// === : (COLON) and ; (SEMI) =============================================

defword ":", COLON, RBRACK
    .quad xt_HEADER
    .quad xt_DOCOLCOMMA
    .quad xt_HIDDEN          // hide while compiling
    .quad xt_RBRACK          // enter compile state
    .quad xt_EXIT

defword ";", SEMI, COLON, F_IMMED
    .quad xt_LIT
    .quad xt_EXIT            // compile EXIT
    .quad xt_COMMA
    .quad xt_HIDDEN          // un-hide
    .quad xt_LBRACK          // leave compile state
    .quad xt_EXIT

// === LIT, — compile a literal: appends LIT then value ===================

defword "LITERAL", LITERAL, SEMI, F_IMMED
    .quad xt_LIT
    .quad xt_LIT
    .quad xt_COMMA
    .quad xt_COMMA
    .quad xt_EXIT

// === ' (TICK) — read next word, push its CFA ============================

defword "'", TICK, LITERAL
    .quad xt_WORD_
    .quad xt_FIND
    .quad xt_TCFA
    .quad xt_EXIT

// === ['] — IMMEDIATE compile-time tick.
// Equivalent to ' followed by LITERAL, but written at the asm level so
// that LITERAL's IMMEDIATE flag does not trigger during definition.
defword "[']", LBRACK_TICK, TICK, F_IMMED
    .quad xt_TICK
    .quad xt_LITERAL
    .quad xt_EXIT

// === NUMBER — convert string at addr/len to number =====================
// ( addr len -- value remaining )
// Parses leading optional '-' then digits in BASE.
// Returns value and number of unparsed chars (0 = success).

defcode "NUMBER", NUMBER, LBRACK_TICK
    POP x2                      // len
    POP x1                      // addr
    mov x3, #0                  // accumulator
    mov x4, #0                  // negate flag
    cbz x2, .Lnum_done
    ldrb w5, [x1]
    cmp  w5, #'-'
    b.ne .Lnum_loop
    mov  x4, #1
    add  x1, x1, #1
    sub  x2, x2, #1
    cbz  x2, .Lnum_failneg
.Lnum_loop:
    cbz  x2, .Lnum_done
    ldrb w5, [x1]
    sub  w6, w5, #'0'
    cmp  w6, #9
    b.ls .Lnum_digit
    sub  w6, w5, #'A'
    cmp  w6, #25
    b.hi .Lnum_failed
    add  w6, w6, #10
.Lnum_digit:
    adrp x7, var_BASE@PAGE
    add  x7, x7, var_BASE@PAGEOFF
    ldr  x7, [x7]
    cmp  w6, w7
    b.ge .Lnum_failed
    mul  x3, x3, x7
    add  x3, x3, x6
    add  x1, x1, #1
    sub  x2, x2, #1
    b    .Lnum_loop
.Lnum_failed:
.Lnum_done:
    cbz  x4, 1f
    neg  x3, x3
1:  PUSH x3
    PUSH x2
    NEXT
.Lnum_failneg:
    mov  x3, #0
    mov  x2, #1
    PUSH x3
    PUSH x2
    NEXT

// === INTERPRET — top of the outer interpreter ===========================
// Reads one word; if found in dict, executes (or compiles); else parses
// number; in compile mode, compiles LIT+value; in interpret mode, leaves
// value on stack. On unknown word, prints error message and aborts.

// INTERPRET — outer interpreter step.
// Body bytes (each cell is 8):
//   0   WORD                 ( -- addr len )
//   8   DUP
//  16   ZBRANCH
//  24     offset → eof (392)            target byte 424
//  32   OVER
//  40   OVER                 ( addr len addr len )
//  48   FIND                 ( addr len header|0 )
//  56   DUP
//  64   ZBRANCH
//  72     offset → number (208)         target byte 288
//  80   -ROT                 ( header addr len )
//  88   DROP
//  96   DROP                 ( header )
// 104   DUP
// 112   LIT
// 120     8
// 128   +
// 136   C@                   ( header flagbyte )
// 144   LIT
// 152     F_IMMED
// 160   AND                  ( header isimmed )
// 168   SWAP                 ( isimmed header )
// 176   >CFA                 ( isimmed cfa )
// 184   SWAP                 ( cfa isimmed )
// 192   STATE
// 200   @
// 208   0=                   ( cfa isimmed state=0? )
// 216   OR                   ( cfa exec? )
// 224   ZBRANCH
// 232     offset → compile (24)         target byte 264
// 240   EXECUTE
// 248   BRANCH
// 256     offset → top (-264)
// 264   ,                    (compile-target)
// 272   BRANCH
// 280     offset → top (-288)
// 288   DROP                 (number-target — drop the 0 from FIND)
// 296   NUMBER               ( value remaining )
// 304   ZBRANCH
// 312     offset → success (8)          target byte 328
// 320   ABORT_RT             (fail)
// 328   STATE                (success-target)
// 336   @
// 344   ZBRANCH
// 352     offset → leave-on-stack (48)  target byte 408
// 360   LIT
// 368     xt_LIT
// 376   ,
// 384   ,
// 392   BRANCH
// 400     offset → top (-400)
// 408   BRANCH               (leave-on-stack-target)
// 416     offset → top (-416)
// 424   DROP                 (eof-target)
// 432   DROP
// 440   BYE
// BRANCH semantics: offset cell at byte P+8 contains delta. After
// dispatch, new IP = (P + 8) + offset. So to jump from BRANCH at body
// byte P to target byte T: offset = T - P - 8.
defword "INTERPRET", INTERPRET, NUMBER
    .quad xt_WORD_              //   0
    .quad xt_DUP                //   8
    .quad xt_ZBRANCH            //  16
    .quad 400                   //  24  → eof at 424
    .quad xt_OVER               //  32
    .quad xt_OVER               //  40
    .quad xt_FIND               //  48
    .quad xt_DUP                //  56
    .quad xt_ZBRANCH            //  64
    .quad 216                   //  72  → number at 288
    .quad xt_NROT               //  80
    .quad xt_DROP               //  88
    .quad xt_DROP               //  96
    .quad xt_DUP                // 104
    .quad xt_LIT                // 112
    .quad 8                     // 120
    .quad xt_PLUS               // 128
    .quad xt_CFETCH             // 136
    .quad xt_LIT                // 144
    .quad F_IMMED               // 152
    .quad xt_AND_               // 160
    .quad xt_SWAP               // 168
    .quad xt_TCFA               // 176
    .quad xt_SWAP               // 184
    .quad xt_STATE              // 192
    .quad xt_FETCH              // 200
    .quad xt_ZEQ                // 208
    .quad xt_OR_                // 216
    .quad xt_ZBRANCH            // 224
    .quad 32                    // 232  → compile at 264
    .quad xt_EXECUTE            // 240
    .quad xt_BRANCH             // 248
    .quad -256                  // 256  → top
    .quad xt_COMMA              // 264
    .quad xt_BRANCH             // 272
    .quad -280                  // 280  → top
    .quad xt_DROP               // 288  (number target)
    .quad xt_NUMBER             // 296
    .quad xt_ZBRANCH            // 304
    .quad 16                    // 312  → success at 328
    .quad xt_ABORT_RT           // 320  (fail)
    .quad xt_STATE              // 328  (success target)
    .quad xt_FETCH              // 336
    .quad xt_ZBRANCH            // 344
    .quad 56                    // 352  → leave-on-stack at 408
    .quad xt_LIT                // 360
    .quad xt_LIT                // 368
    .quad xt_COMMA              // 376
    .quad xt_COMMA              // 384
    .quad xt_BRANCH             // 392
    .quad -400                  // 400  → top
    .quad xt_BRANCH             // 408  (leave-on-stack target)
    .quad -416                  // 416  → top
    .quad xt_DROP               // 424  (eof target)
    .quad xt_DROP               // 432
    .quad xt_BYE                // 440

// === ABORT_RT — runtime abort (prints message, exits) ===================

defcode "ABORT_RT", ABORT_RT, INTERPRET
    sub  sp, sp, #16
    mov  w0, #'?'
    strb w0, [sp]
    mov  w0, #'\n'
    strb w0, [sp, #1]
    mov  x16, #SYS_WRITE
    mov  x0, #STDOUT
    mov  x1, sp
    mov  x2, #2
    svc  #0x80
    add  sp, sp, #16
    mov  x16, #SYS_EXIT
    mov  x0, #1
    svc  #0x80

// === COLD — initial word: loops INTERPRET forever =======================

defword "COLD", COLD, ABORT_RT
    .quad xt_INTERPRET
    .quad xt_BRANCH
    .quad -16

// === LATEST_INIT marks the last assembled word's header =================
// This name is used at startup to populate var_LATEST.

.set name_LATEST_INIT, name_COLD

// === BSS data ============================================================

.section __DATA,__bss
.balign 16
dstack_bottom:
    .skip 65536
dstack_top:

rstack_bottom:
    .skip 65536
rstack_top:

dict_space:
    .skip 131072
dict_end:

word_buffer:
    .skip 256

.section __DATA,__data
.balign 8
var_HERE:    .quad 0
var_LATEST:  .quad 0
var_STATE:   .quad 0
var_BASE:    .quad 10
