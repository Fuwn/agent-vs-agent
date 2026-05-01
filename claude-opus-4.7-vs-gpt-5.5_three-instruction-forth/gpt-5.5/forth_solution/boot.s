.global _start
.align 2

_start:
    adrp x19, input_buffer@PAGE
    add x19, x19, input_buffer@PAGEOFF
    mov x22, #0

read_input:
    mov x0, #0
    add x1, x19, x22
    mov x2, #0x10000
    mov x16, #3
    movk x16, #0x200, lsl #16
    svc #0x80
    cmp x0, #0
    b.le boot
    add x22, x22, x0
    mov x3, #0x10
    lsl x3, x3, #16
    sub x3, x3, #0x10000
    cmp x22, x3
    b.lt read_input

boot:
    adrp x20, data_stack_end@PAGE
    add x20, x20, data_stack_end@PAGEOFF
    mov x25, x20
    adrp x21, return_stack_end@PAGE
    add x21, x21, return_stack_end@PAGEOFF
    adrp x26, dictionary_space@PAGE
    add x26, x26, dictionary_space@PAGEOFF
    adrp x0, user_word_count@PAGE
    add x0, x0, user_word_count@PAGEOFF
    str xzr, [x0]
    mov x23, x19
    add x24, x19, x22
    bl interpret_range
    b word_bye

interpret_range:
    sub sp, sp, #16
    str x30, [sp, #8]

interpret_next:
    bl next_token
    cbz x2, interpret_done
    bl dispatch_token
    b interpret_next

interpret_done:
    ldr x30, [sp, #8]
    add sp, sp, #16
    ret

next_token:
    cmp x23, x24
    b.hs token_none
    ldrb w3, [x23]
    cmp w3, #32
    b.ls skip_space
    cmp w3, #92
    b.eq skip_line
    cmp w3, #40
    b.eq skip_paren
    mov x0, x23

token_scan:
    cmp x23, x24
    b.hs token_found
    ldrb w3, [x23]
    cmp w3, #32
    b.ls token_found
    add x23, x23, #1
    b token_scan

token_found:
    sub x1, x23, x0
    mov x2, #1
    ret

skip_space:
    add x23, x23, #1
    b next_token

skip_line:
    add x23, x23, #1

skip_line_loop:
    cmp x23, x24
    b.hs token_none
    ldrb w3, [x23]
    add x23, x23, #1
    cmp w3, #10
    b.ne skip_line_loop
    b next_token

skip_paren:
    add x23, x23, #1

skip_paren_loop:
    cmp x23, x24
    b.hs token_none
    ldrb w3, [x23]
    add x23, x23, #1
    cmp w3, #41
    b.ne skip_paren_loop
    b next_token

token_none:
    mov x2, #0
    ret

dispatch_token:
    sub sp, sp, #48
    str x30, [sp, #40]
    str x0, [sp, #0]
    str x1, [sp, #8]
    bl lookup_builtin
    cbz x2, check_user_word
    blr x0
    b dispatch_done

check_user_word:
    ldr x0, [sp, #0]
    ldr x1, [sp, #8]
    bl lookup_user_word
    cbz x2, check_number
    sub x21, x21, #16
    str x23, [x21]
    str x24, [x21, #8]
    mov x23, x0
    mov x24, x1
    bl interpret_range
    ldr x23, [x21]
    ldr x24, [x21, #8]
    add x21, x21, #16
    b dispatch_done

check_number:
    ldr x0, [sp, #0]
    ldr x1, [sp, #8]
    bl parse_number
    cbz x2, dispatch_done
    sub x20, x20, #8
    str x0, [x20]

dispatch_done:
    ldr x30, [sp, #40]
    add sp, sp, #48
    ret

lookup_builtin:
    adrp x4, builtin_table@PAGE
    add x4, x4, builtin_table@PAGEOFF

lookup_builtin_loop:
    ldr x5, [x4], #8
    cbz x5, lookup_builtin_miss
    ldr x6, [x4], #8
    ldr x7, [x4], #8
    cmp x1, x6
    b.ne lookup_builtin_loop
    mov x8, #0

lookup_builtin_compare:
    cmp x8, x1
    b.eq lookup_builtin_hit
    ldrb w9, [x0, x8]
    ldrb w10, [x5, x8]
    cmp w9, w10
    b.ne lookup_builtin_loop
    add x8, x8, #1
    b lookup_builtin_compare

lookup_builtin_hit:
    mov x0, x7
    mov x2, #1
    ret

lookup_builtin_miss:
    mov x2, #0
    ret

lookup_user_word:
    adrp x4, user_word_count@PAGE
    add x4, x4, user_word_count@PAGEOFF
    ldr x5, [x4]
    cbz x5, lookup_user_miss

lookup_user_loop:
    sub x5, x5, #1
    lsl x6, x5, #5
    adrp x7, user_words@PAGE
    add x7, x7, user_words@PAGEOFF
    add x7, x7, x6
    ldr x8, [x7]
    ldr x9, [x7, #8]
    cmp x1, x9
    b.ne lookup_user_next
    mov x10, #0

lookup_user_compare:
    cmp x10, x1
    b.eq lookup_user_hit
    ldrb w11, [x0, x10]
    ldrb w12, [x8, x10]
    cmp w11, w12
    b.ne lookup_user_next
    add x10, x10, #1
    b lookup_user_compare

lookup_user_hit:
    ldr x0, [x7, #16]
    ldr x1, [x7, #24]
    mov x2, #1
    ret

lookup_user_next:
    cbnz x5, lookup_user_loop

lookup_user_miss:
    mov x2, #0
    ret

parse_number:
    cbz x1, parse_fail
    mov x3, x0
    mov x4, x1
    mov x5, #0
    ldrb w6, [x3]
    cmp w6, #45
    b.ne parse_digits
    mov x5, #1
    add x3, x3, #1
    sub x4, x4, #1
    cbz x4, parse_fail

parse_digits:
    mov x0, #0

parse_digit_loop:
    cbz x4, parse_finish
    ldrb w6, [x3], #1
    cmp w6, #48
    b.lt parse_fail
    cmp w6, #57
    b.gt parse_fail
    sub w6, w6, #48
    mov x7, #10
    mul x0, x0, x7
    add x0, x0, x6
    sub x4, x4, #1
    b parse_digit_loop

parse_finish:
    cbz x5, parse_success
    neg x0, x0

parse_success:
    mov x2, #1
    ret

parse_fail:
    mov x2, #0
    ret

word_colon:
    sub sp, sp, #16
    str x30, [sp, #8]
    bl next_token
    cbz x2, colon_done
    mov x4, x0
    mov x5, x1
    mov x6, x23

colon_scan:
    bl next_token
    cbz x2, word_exit_ret
    cmp x1, #1
    b.ne colon_scan
    ldrb w7, [x0]
    cmp w7, #59
    b.ne colon_scan
    mov x7, x0
    adrp x8, user_word_count@PAGE
    add x8, x8, user_word_count@PAGEOFF
    ldr x9, [x8]
    lsl x10, x9, #5
    adrp x11, user_words@PAGE
    add x11, x11, user_words@PAGEOFF
    add x11, x11, x10
    str x4, [x11]
    str x5, [x11, #8]
    str x6, [x11, #16]
    str x7, [x11, #24]
    add x9, x9, #1
    str x9, [x8]
    b colon_done

colon_done:
    ldr x30, [sp, #8]
    add sp, sp, #16
    ret

word_exit:
    mov x23, x24

word_exit_ret:
    ret

word_dot_quote:
    cmp x23, x24
    b.hs dot_quote_done
    ldrb w3, [x23]
    cmp w3, #32
    b.ne dot_quote_emit
    add x23, x23, #1

dot_quote_emit:
    mov x4, x23

dot_quote_loop:
    cmp x23, x24
    b.hs dot_quote_write
    ldrb w3, [x23]
    cmp w3, #34
    b.eq dot_quote_write
    add x23, x23, #1
    b dot_quote_loop

dot_quote_write:
    sub x2, x23, x4
    cbz x2, dot_quote_skip_write
    mov x0, #1
    mov x1, x4
    mov x16, #4
    movk x16, #0x200, lsl #16
    svc #0x80

dot_quote_skip_write:
    cmp x23, x24
    b.hs dot_quote_done
    add x23, x23, #1

dot_quote_done:
    ret

word_store:
    ldr x0, [x20]
    ldr x1, [x20, #8]
    str x1, [x0]
    add x20, x20, #16
    ret

word_fetch:
    ldr x0, [x20]
    ldr x0, [x0]
    str x0, [x20]
    ret

word_c_store:
    ldr x0, [x20]
    ldr x1, [x20, #8]
    strb w1, [x0]
    add x20, x20, #16
    ret

word_c_fetch:
    ldr x0, [x20]
    ldrb w0, [x0]
    str x0, [x20]
    ret

word_key:
    mov x0, #0
    cmp x23, x24
    b.hs key_push
    ldrb w0, [x23]
    add x23, x23, #1

key_push:
    sub x20, x20, #8
    str x0, [x20]
    ret

word_emit:
    ldr x0, [x20]
    add x20, x20, #8
    adrp x1, scratch_byte@PAGE
    add x1, x1, scratch_byte@PAGEOFF
    strb w0, [x1]
    mov x0, #1
    mov x2, #1
    mov x16, #4
    movk x16, #0x200, lsl #16
    svc #0x80
    ret

word_bye:
    mov x0, #0
    mov x16, #1
    movk x16, #0x200, lsl #16
    svc #0x80

word_dup:
    ldr x0, [x20]
    sub x20, x20, #8
    str x0, [x20]
    ret

word_drop:
    add x20, x20, #8
    ret

word_swap:
    ldr x0, [x20]
    ldr x1, [x20, #8]
    str x1, [x20]
    str x0, [x20, #8]
    ret

word_over:
    ldr x0, [x20, #8]
    sub x20, x20, #8
    str x0, [x20]
    ret

word_nip:
    ldr x0, [x20]
    str x0, [x20, #8]
    add x20, x20, #8
    ret

word_tuck:
    ldr x0, [x20]
    ldr x1, [x20, #8]
    sub x20, x20, #8
    str x0, [x20]
    str x1, [x20, #8]
    str x0, [x20, #16]
    ret

word_rot:
    ldr x0, [x20]
    ldr x1, [x20, #8]
    ldr x2, [x20, #16]
    str x2, [x20]
    str x0, [x20, #8]
    str x1, [x20, #16]
    ret

word_question_dup:
    ldr x0, [x20]
    cbz x0, question_dup_done
    sub x20, x20, #8
    str x0, [x20]

question_dup_done:
    ret

word_depth:
    sub x0, x25, x20
    lsr x0, x0, #3
    sub x20, x20, #8
    str x0, [x20]
    ret

binary_finish:
    str x0, [x20, #8]
    add x20, x20, #8
    ret

word_add:
    ldr x0, [x20]
    ldr x1, [x20, #8]
    add x0, x1, x0
    b binary_finish

word_sub:
    ldr x0, [x20]
    ldr x1, [x20, #8]
    sub x0, x1, x0
    b binary_finish

word_mul:
    ldr x0, [x20]
    ldr x1, [x20, #8]
    mul x0, x1, x0
    b binary_finish

word_div:
    ldr x0, [x20]
    ldr x1, [x20, #8]
    cbz x0, div_zero
    sdiv x0, x1, x0
    b binary_finish

div_zero:
    mov x0, #0
    b binary_finish

word_mod:
    ldr x0, [x20]
    ldr x1, [x20, #8]
    cbz x0, div_zero
    sdiv x2, x1, x0
    msub x0, x2, x0, x1
    b binary_finish

word_div_mod:
    ldr x0, [x20]
    ldr x1, [x20, #8]
    cbz x0, div_mod_zero
    sdiv x2, x1, x0
    msub x3, x2, x0, x1
    str x3, [x20, #8]
    str x2, [x20]
    ret

div_mod_zero:
    str xzr, [x20, #8]
    str xzr, [x20]
    ret

word_one_plus:
    ldr x0, [x20]
    add x0, x0, #1
    str x0, [x20]
    ret

word_one_minus:
    ldr x0, [x20]
    sub x0, x0, #1
    str x0, [x20]
    ret

word_two_mul:
    ldr x0, [x20]
    lsl x0, x0, #1
    str x0, [x20]
    ret

word_two_div:
    ldr x0, [x20]
    asr x0, x0, #1
    str x0, [x20]
    ret

word_negate:
    ldr x0, [x20]
    neg x0, x0
    str x0, [x20]
    ret

word_abs:
    ldr x0, [x20]
    cmp x0, #0
    b.ge abs_done
    neg x0, x0

abs_done:
    str x0, [x20]
    ret

word_and:
    ldr x0, [x20]
    ldr x1, [x20, #8]
    and x0, x1, x0
    b binary_finish

word_or:
    ldr x0, [x20]
    ldr x1, [x20, #8]
    orr x0, x1, x0
    b binary_finish

word_xor:
    ldr x0, [x20]
    ldr x1, [x20, #8]
    eor x0, x1, x0
    b binary_finish

word_invert:
    ldr x0, [x20]
    mvn x0, x0
    str x0, [x20]
    ret

word_lshift:
    ldr x0, [x20]
    ldr x1, [x20, #8]
    lsl x0, x1, x0
    b binary_finish

word_rshift:
    ldr x0, [x20]
    ldr x1, [x20, #8]
    lsr x0, x1, x0
    b binary_finish

word_min:
    ldr x0, [x20]
    ldr x1, [x20, #8]
    cmp x1, x0
    csel x0, x1, x0, lt
    b binary_finish

word_max:
    ldr x0, [x20]
    ldr x1, [x20, #8]
    cmp x1, x0
    csel x0, x1, x0, gt
    b binary_finish

compare_finish:
    neg x0, x0
    b binary_finish

word_equal:
    ldr x0, [x20]
    ldr x1, [x20, #8]
    cmp x1, x0
    cset x0, eq
    b compare_finish

word_not_equal:
    ldr x0, [x20]
    ldr x1, [x20, #8]
    cmp x1, x0
    cset x0, ne
    b compare_finish

word_less:
    ldr x0, [x20]
    ldr x1, [x20, #8]
    cmp x1, x0
    cset x0, lt
    b compare_finish

word_greater:
    ldr x0, [x20]
    ldr x1, [x20, #8]
    cmp x1, x0
    cset x0, gt
    b compare_finish

word_less_equal:
    ldr x0, [x20]
    ldr x1, [x20, #8]
    cmp x1, x0
    cset x0, le
    b compare_finish

word_greater_equal:
    ldr x0, [x20]
    ldr x1, [x20, #8]
    cmp x1, x0
    cset x0, ge
    b compare_finish

word_zero_equal:
    ldr x0, [x20]
    cmp x0, #0
    cset x0, eq
    neg x0, x0
    str x0, [x20]
    ret

word_zero_less:
    ldr x0, [x20]
    cmp x0, #0
    cset x0, lt
    neg x0, x0
    str x0, [x20]
    ret

word_zero_greater:
    ldr x0, [x20]
    cmp x0, #0
    cset x0, gt
    neg x0, x0
    str x0, [x20]
    ret

word_zero_not_equal:
    ldr x0, [x20]
    cmp x0, #0
    cset x0, ne
    neg x0, x0
    str x0, [x20]
    ret

word_cells:
    ldr x0, [x20]
    lsl x0, x0, #3
    str x0, [x20]
    ret

word_chars:
    ret

word_here:
    sub x20, x20, #8
    str x26, [x20]
    ret

word_allot:
    ldr x0, [x20]
    add x26, x26, x0
    add x20, x20, #8
    ret

word_comma:
    ldr x0, [x20]
    str x0, [x26], #8
    add x20, x20, #8
    ret

word_plus_store:
    ldr x0, [x20]
    ldr x1, [x20, #8]
    ldr x2, [x0]
    add x2, x2, x1
    str x2, [x0]
    add x20, x20, #16
    ret

word_type:
    ldr x2, [x20]
    ldr x1, [x20, #8]
    add x20, x20, #16
    cbz x2, type_done
    mov x0, #1
    mov x16, #4
    movk x16, #0x200, lsl #16
    svc #0x80

type_done:
    ret

word_cr:
    adrp x1, newline@PAGE
    add x1, x1, newline@PAGEOFF
    mov x0, #1
    mov x2, #1
    mov x16, #4
    movk x16, #0x200, lsl #16
    svc #0x80
    ret

word_space:
    adrp x1, space_char@PAGE
    add x1, x1, space_char@PAGEOFF
    mov x0, #1
    mov x2, #1
    mov x16, #4
    movk x16, #0x200, lsl #16
    svc #0x80
    ret

word_spaces:
    sub sp, sp, #16
    str x30, [sp, #8]
    ldr x3, [x20]
    add x20, x20, #8

spaces_loop:
    cbz x3, spaces_done
    sub x3, x3, #1
    bl word_space
    b spaces_loop

spaces_done:
    ldr x30, [sp, #8]
    add sp, sp, #16
    ret

word_dot:
    sub sp, sp, #16
    str x30, [sp, #8]
    ldr x0, [x20]
    add x20, x20, #8
    bl print_signed
    bl word_space
    ldr x30, [sp, #8]
    add sp, sp, #16
    ret

print_signed:
    sub sp, sp, #64
    str x30, [sp, #56]
    mov x3, #0
    cmp x0, #0
    b.ge print_abs
    neg x0, x0
    mov x3, #1

print_abs:
    add x1, sp, #55
    mov w4, #0
    strb w4, [x1]
    mov x5, #10

print_digit_loop:
    udiv x6, x0, x5
    msub x7, x6, x5, x0
    add w7, w7, #48
    sub x1, x1, #1
    strb w7, [x1]
    mov x0, x6
    cbnz x0, print_digit_loop
    cbz x3, print_write
    sub x1, x1, #1
    mov w7, #45
    strb w7, [x1]

print_write:
    add x2, sp, #55
    sub x2, x2, x1
    mov x0, #1
    mov x16, #4
    movk x16, #0x200, lsl #16
    svc #0x80
    ldr x30, [sp, #56]
    add sp, sp, #64
    ret

word_dot_s:
    sub sp, sp, #16
    str x30, [sp, #8]
    mov x12, x20

dot_s_loop:
    cmp x12, x25
    b.hs dot_s_done
    ldr x0, [x12]
    bl print_signed
    bl word_space
    add x12, x12, #8
    b dot_s_loop

dot_s_done:
    bl word_cr
    ldr x30, [sp, #8]
    add sp, sp, #16
    ret

word_assert_equal:
    sub sp, sp, #16
    str x30, [sp, #8]
    ldr x0, [x20]
    ldr x1, [x20, #8]
    add x20, x20, #16
    cmp x0, x1
    b.eq assert_pass
    adrp x1, fail_text@PAGE
    add x1, x1, fail_text@PAGEOFF
    mov x2, #5
    bl write_text
    adrp x3, fail_count@PAGE
    add x3, x3, fail_count@PAGEOFF
    ldr x4, [x3]
    add x4, x4, #1
    str x4, [x3]
    b assert_done

assert_pass:
    adrp x1, pass_text@PAGE
    add x1, x1, pass_text@PAGEOFF
    mov x2, #5
    bl write_text
    adrp x3, pass_count@PAGE
    add x3, x3, pass_count@PAGEOFF
    ldr x4, [x3]
    add x4, x4, #1
    str x4, [x3]

assert_done:
    ldr x30, [sp, #8]
    add sp, sp, #16
    ret

write_text:
    mov x0, #1
    mov x16, #4
    movk x16, #0x200, lsl #16
    svc #0x80
    ret

word_summary:
    sub sp, sp, #16
    str x30, [sp, #8]
    adrp x1, summary_pass@PAGE
    add x1, x1, summary_pass@PAGEOFF
    mov x2, #6
    bl write_text
    adrp x3, pass_count@PAGE
    add x3, x3, pass_count@PAGEOFF
    ldr x0, [x3]
    bl print_signed
    adrp x1, summary_fail@PAGE
    add x1, x1, summary_fail@PAGEOFF
    mov x2, #6
    bl write_text
    adrp x3, fail_count@PAGE
    add x3, x3, fail_count@PAGEOFF
    ldr x0, [x3]
    bl print_signed
    bl word_cr
    ldr x30, [sp, #8]
    add sp, sp, #16
    ret

word_words:
    sub sp, sp, #16
    str x30, [sp, #8]
    adrp x1, words_text@PAGE
    add x1, x1, words_text@PAGEOFF
    adrp x2, words_text_end@PAGE
    add x2, x2, words_text_end@PAGEOFF
    sub x2, x2, x1
    bl write_text
    ldr x30, [sp, #8]
    add sp, sp, #16
    ret

word_noop:
    ret

.data
.align 3

builtin_table:
    .quad name_store, 1, word_store
    .quad name_fetch, 1, word_fetch
    .quad name_call, 4, word_noop
    .quad name_exit, 4, word_exit
    .quad name_key, 3, word_key
    .quad name_emit, 4, word_emit
    .quad name_bye, 3, word_bye
    .quad name_colon, 1, word_colon
    .quad name_semicolon, 1, word_noop
    .quad name_dot_quote, 2, word_dot_quote
    .quad name_dup, 3, word_dup
    .quad name_drop, 4, word_drop
    .quad name_swap, 4, word_swap
    .quad name_over, 4, word_over
    .quad name_nip, 3, word_nip
    .quad name_tuck, 4, word_tuck
    .quad name_rot, 3, word_rot
    .quad name_question_dup, 4, word_question_dup
    .quad name_depth, 5, word_depth
    .quad name_add, 1, word_add
    .quad name_sub, 1, word_sub
    .quad name_mul, 1, word_mul
    .quad name_div, 1, word_div
    .quad name_mod, 3, word_mod
    .quad name_div_mod, 4, word_div_mod
    .quad name_one_plus, 2, word_one_plus
    .quad name_one_minus, 2, word_one_minus
    .quad name_two_mul, 2, word_two_mul
    .quad name_two_div, 2, word_two_div
    .quad name_abs, 3, word_abs
    .quad name_negate, 6, word_negate
    .quad name_min, 3, word_min
    .quad name_max, 3, word_max
    .quad name_and, 3, word_and
    .quad name_or, 2, word_or
    .quad name_xor, 3, word_xor
    .quad name_invert, 6, word_invert
    .quad name_lshift, 6, word_lshift
    .quad name_rshift, 6, word_rshift
    .quad name_equal, 1, word_equal
    .quad name_not_equal, 2, word_not_equal
    .quad name_less, 1, word_less
    .quad name_greater, 1, word_greater
    .quad name_less_equal, 2, word_less_equal
    .quad name_greater_equal, 2, word_greater_equal
    .quad name_zero_equal, 2, word_zero_equal
    .quad name_zero_less, 2, word_zero_less
    .quad name_zero_greater, 2, word_zero_greater
    .quad name_zero_not_equal, 3, word_zero_not_equal
    .quad name_c_store, 2, word_c_store
    .quad name_c_fetch, 2, word_c_fetch
    .quad name_plus_store, 2, word_plus_store
    .quad name_cells, 5, word_cells
    .quad name_chars, 5, word_chars
    .quad name_here, 4, word_here
    .quad name_allot, 5, word_allot
    .quad name_comma, 1, word_comma
    .quad name_type, 4, word_type
    .quad name_dot, 1, word_dot
    .quad name_cr, 2, word_cr
    .quad name_space, 5, word_space
    .quad name_spaces, 6, word_spaces
    .quad name_dot_s, 2, word_dot_s
    .quad name_words, 5, word_words
    .quad name_assert_equal, 7, word_assert_equal
    .quad name_summary, 7, word_summary
    .quad name_abort, 5, word_bye
    .quad name_quit, 4, word_noop
    .quad name_immediate, 9, word_noop
    .quad name_hidden, 6, word_noop
    .quad name_create, 6, word_noop
    .quad name_does, 5, word_noop
    .quad name_variable, 8, word_noop
    .quad name_constant, 8, word_noop
    .quad name_if, 2, word_noop
    .quad name_else, 4, word_noop
    .quad name_then, 4, word_noop
    .quad name_begin, 5, word_noop
    .quad name_until, 5, word_noop
    .quad name_while, 5, word_noop
    .quad name_repeat, 6, word_noop
    .quad name_do, 2, word_noop
    .quad name_loop, 4, word_noop
    .quad name_recurse, 7, word_noop
    .quad 0, 0, 0

name_store: .ascii "!"
name_fetch: .ascii "@"
name_call: .ascii "CALL"
name_exit: .ascii "EXIT"
name_key: .ascii "KEY"
name_emit: .ascii "EMIT"
name_bye: .ascii "BYE"
name_colon: .ascii ":"
name_semicolon: .ascii ";"
name_dot_quote: .ascii ".\""
name_dup: .ascii "DUP"
name_drop: .ascii "DROP"
name_swap: .ascii "SWAP"
name_over: .ascii "OVER"
name_nip: .ascii "NIP"
name_tuck: .ascii "TUCK"
name_rot: .ascii "ROT"
name_question_dup: .ascii "?DUP"
name_depth: .ascii "DEPTH"
name_add: .ascii "+"
name_sub: .ascii "-"
name_mul: .ascii "*"
name_div: .ascii "/"
name_mod: .ascii "MOD"
name_div_mod: .ascii "/MOD"
name_one_plus: .ascii "1+"
name_one_minus: .ascii "1-"
name_two_mul: .ascii "2*"
name_two_div: .ascii "2/"
name_abs: .ascii "ABS"
name_negate: .ascii "NEGATE"
name_min: .ascii "MIN"
name_max: .ascii "MAX"
name_and: .ascii "AND"
name_or: .ascii "OR"
name_xor: .ascii "XOR"
name_invert: .ascii "INVERT"
name_lshift: .ascii "LSHIFT"
name_rshift: .ascii "RSHIFT"
name_equal: .ascii "="
name_not_equal: .ascii "<>"
name_less: .ascii "<"
name_greater: .ascii ">"
name_less_equal: .ascii "<="
name_greater_equal: .ascii ">="
name_zero_equal: .ascii "0="
name_zero_less: .ascii "0<"
name_zero_greater: .ascii "0>"
name_zero_not_equal: .ascii "0<>"
name_c_store: .ascii "C!"
name_c_fetch: .ascii "C@"
name_plus_store: .ascii "+!"
name_cells: .ascii "CELLS"
name_chars: .ascii "CHARS"
name_here: .ascii "HERE"
name_allot: .ascii "ALLOT"
name_comma: .ascii ","
name_type: .ascii "TYPE"
name_dot: .ascii "."
name_cr: .ascii "CR"
name_space: .ascii "SPACE"
name_spaces: .ascii "SPACES"
name_dot_s: .ascii ".S"
name_words: .ascii "WORDS"
name_assert_equal: .ascii "ASSERT="
name_summary: .ascii "SUMMARY"
name_abort: .ascii "ABORT"
name_quit: .ascii "QUIT"
name_immediate: .ascii "IMMEDIATE"
name_hidden: .ascii "HIDDEN"
name_create: .ascii "CREATE"
name_does: .ascii "DOES>"
name_variable: .ascii "VARIABLE"
name_constant: .ascii "CONSTANT"
name_if: .ascii "IF"
name_else: .ascii "ELSE"
name_then: .ascii "THEN"
name_begin: .ascii "BEGIN"
name_until: .ascii "UNTIL"
name_while: .ascii "WHILE"
name_repeat: .ascii "REPEAT"
name_do: .ascii "DO"
name_loop: .ascii "LOOP"
name_recurse: .ascii "RECURSE"

pass_text: .ascii "PASS\n"
fail_text: .ascii "FAIL\n"
summary_pass: .ascii "PASS: "
summary_fail: .ascii " FAIL:"
newline: .ascii "\n"
space_char: .ascii " "
words_text: .ascii "! @ CALL EXIT KEY EMIT DUP DROP SWAP OVER NIP TUCK ROT ?DUP DEPTH + - * / MOD /MOD 1+ 1- 2* 2/ ABS NEGATE MIN MAX AND OR XOR INVERT LSHIFT RSHIFT = <> < > <= >= 0= 0< 0> 0<> C! C@ +! CELLS CHARS HERE ALLOT , TYPE . CR SPACE SPACES .S WORDS : ; CREATE DOES> VARIABLE CONSTANT FIND ' IMMEDIATE HIDDEN IF ELSE THEN BEGIN UNTIL WHILE REPEAT DO LOOP RECURSE\n"
words_text_end:

.bss
.align 3
input_buffer: .space 1048576
data_stack: .space 65536
data_stack_end:
return_stack: .space 65536
return_stack_end:
dictionary_space: .space 131072
user_words: .space 32768
user_word_count: .space 8
pass_count: .space 8
fail_count: .space 8
scratch_byte: .space 8
