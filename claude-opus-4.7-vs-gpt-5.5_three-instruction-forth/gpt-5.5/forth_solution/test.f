." three-instruction forth smoke suite" CR

." stack DUP " 7 DUP * 49 ASSERT=
." stack DROP " 1 2 DROP 1 ASSERT=
." stack SWAP " 3 9 SWAP - 6 ASSERT=
." stack OVER " 4 5 OVER + NIP 9 ASSERT=
." stack NIP " 8 13 NIP 13 ASSERT=
." stack TUCK " 2 5 TUCK * + 15 ASSERT=
." stack ROT " 2 3 4 ROT DROP * 12 ASSERT=
." stack ?DUP-zero " 0 ?DUP DEPTH 1 ASSERT= DROP
." stack DEPTH " DEPTH 0 ASSERT=

." arithmetic + " 19 23 + 42 ASSERT=
." arithmetic - " 99 57 - 42 ASSERT=
." arithmetic * " 6 7 * 42 ASSERT=
." arithmetic / " 84 2 / 42 ASSERT=
." arithmetic MOD " 101 59 MOD 42 ASSERT=
." arithmetic /MOD-rem " 101 59 /MOD SWAP 42 ASSERT= DROP
." arithmetic 1+ " 41 1+ 42 ASSERT=
." arithmetic 1- " 43 1- 42 ASSERT=
." arithmetic 2* " 21 2* 42 ASSERT=
." arithmetic 2/ " 84 2/ 42 ASSERT=
." arithmetic ABS " -42 ABS 42 ASSERT=
." arithmetic NEGATE " -42 NEGATE 42 ASSERT=
." arithmetic MIN " 42 99 MIN 42 ASSERT=
." arithmetic MAX " 1 42 MAX 42 ASSERT=
." arithmetic AND " 63 42 AND 42 ASSERT=
." arithmetic OR " 40 2 OR 42 ASSERT=
." arithmetic XOR " 40 2 XOR 42 ASSERT=
." arithmetic INVERT " 41 INVERT INVERT 41 ASSERT=
." arithmetic LSHIFT " 21 1 LSHIFT 42 ASSERT=
." arithmetic RSHIFT " 84 1 RSHIFT 42 ASSERT=
." arithmetic div-zero " 10 0 / 0 ASSERT=

." compare = " 42 42 = -1 ASSERT=
." compare <> " 42 43 <> -1 ASSERT=
." compare < " 41 42 < -1 ASSERT=
." compare > " 43 42 > -1 ASSERT=
." compare <= " 42 42 <= -1 ASSERT=
." compare >= " 42 42 >= -1 ASSERT=
." compare 0= " 0 0= -1 ASSERT=
." compare 0< " -1 0< -1 ASSERT=
." compare 0> " 1 0> -1 ASSERT=
." compare 0<> " 1 0<> -1 ASSERT=

." memory comma-fetch " HERE 42 , @ 42 ASSERT=
." memory store-fetch " HERE 8 ALLOT DUP 42 SWAP ! @ 42 ASSERT=
." memory c-store-fetch " HERE 1 ALLOT DUP 65 SWAP C! C@ 65 ASSERT=
." memory plus-store " HERE 0 , DUP 42 SWAP +! @ 42 ASSERT=
." memory cells " 3 CELLS 24 ASSERT=
." memory chars " 3 CHARS 3 ASSERT=

: ANSWER 42 ;
." dictionary colon-call " ANSWER 42 ASSERT=
." dictionary words " WORDS

." io emit " 79 EMIT 75 EMIT CR 42 42 ASSERT=
." io spaces " 3 SPACES 42 42 ASSERT=
." io dot " 42 . CR 42 42 ASSERT=
." system .S " 1 2 .S DROP DROP 42 42 ASSERT=

SUMMARY
BYE
