; Mackerel-030F bring-up smoke test, cut 3: LED counter + UART console +
; real SDRAM write/read-back test.
;
; Not run through a real assembler yet (no m68k-mackerel-elf- toolchain
; wired into this repo's build — see plan.md step 8's own bootloader
; item). Hand-assembled directly into rom.hex; kept here purely as the
; human-readable source so rom.hex is maintainable/regeneratable rather
; than an opaque hex blob. Every encoding verified by hand against the
; standard 68000 bit layouts, cross-checked twice independently
; (once by direct bit-field derivation, once by opcode-formula
; cross-check script) before publishing.
;
; Purpose: proves m68030_top can drive real off-chip SDRAM (a genuine
; 16-bit port via dynamic bus sizing) in addition to the 32-bit ROM/GPIO
; and 8-bit UART already proved by cuts 1-2 — a real write-then-read-
; back-and-compare, not just structural place-and-route success.
;
; On SDRAM mismatch: LEDs latch to all-on (0xFF) and the CPU halts in a
; tight self-branch loop — a distinct, obviously-wrong state from the
; normal counting pattern, observable both in simulation (PC stuck at
; FAIL_HALT, LED register readable directly) and on real hardware (LEDs
; solid instead of counting).
;
; Never touches the real stack (no JSR/exceptions expected — all
; interrupt sources are tied inactive in mackerel_030f.v), so SSP is set
; to $00001000 (just past the 4KB ROM window, inside the watchdog-
; BERR'd unmapped region) purely as a deliberate "must never actually be
; dereferenced" placeholder, not a real stack.
;
; UART divisor: uart16550's wb_clk_i is fed clk_4x (100 MHz, see
; clk_pll.v). 9600 baud -> divisor = 100,000,000 / (16*9600) = 651.04,
; rounded to 651 = $0288 (DLM=$02, DLL=$88).

        ORG     $000000
        DC.L    $00001000               ; initial SSP (placeholder, unused)
        DC.L    START                   ; initial PC

START:
        MOVEA.L #$FFFFFF00, A0          ; A0 = GPIO LED register
        MOVE.L  #0, D0                  ; D0 = LED pattern

        MOVEA.L #$FFFFFF10, A1          ; A1 = UART base (register 0 = THR/RBR)
        MOVE.B  #$80, (3,A1)            ; LCR = DLAB=1 (unlock divisor latch)
        MOVE.B  #$88, (0,A1)            ; DLL = $88   (divisor low byte)
        MOVE.B  #$02, (1,A1)            ; DLM = $02   (divisor high byte)
        MOVE.B  #$03, (3,A1)            ; LCR = $03   (DLAB=0, 8N1)

        ; --- SDRAM write/read-back test ---
        MOVEA.L #$02000000, A2          ; A2 = SDRAM base
        MOVE.L  #$5A5A5A5A, D3          ; test pattern
        MOVE.L  D3, (A2)                ; write to SDRAM
        MOVE.L  (A2), D4                ; read back
        CMP.L   D3, D4                  ; D4 - D3 (only equality matters)
        BEQ.S   SDRAM_OK
        MOVE.L  #$FFFFFFFF, (A0)        ; FAIL: LEDs all on
FAIL_HALT:
        BRA.S   FAIL_HALT               ; halt (distinct from normal operation)

SDRAM_OK:
LOOP:
        MOVE.L  D0, (A0)                ; drive LEDs from D0
        ADDQ.L  #1, D0                  ; increment pattern

        MOVE.B  (5,A1), D2              ; D2 = LSR
        BTST    #5, D2                  ; test THRE (bit 5, transmit holding reg empty)
        BEQ.S   SKIP_TX                 ; not ready -> skip this round
        MOVE.B  #$55, (0,A1)            ; THR = 'U' ($55) -- classic 01010101 test byte
SKIP_TX:
        MOVE.L  #$00030000, D1          ; software delay count

DELAY:
        SUBQ.L  #1, D1
        BNE.S   DELAY
        BRA.S   LOOP

; --- hand-encoding reference (big-endian, as packed into rom.hex) ---
; 00000000: 00001000            DC.L $00001000  (SSP)
; 00000004: 00000008            DC.L START      (PC)
; 00000008: 207C FFFF FF00      MOVEA.L #$FFFFFF00,A0
; 0000000E: 203C 0000 0000      MOVE.L  #0,D0
; 00000014: 227C FFFF FF10      MOVEA.L #$FFFFFF10,A1
; 0000001A: 137C 0080 0003      MOVE.B  #$80,(3,A1)     LCR DLAB=1
; 00000020: 137C 0088 0000      MOVE.B  #$88,(0,A1)     DLL
; 00000026: 137C 0002 0001      MOVE.B  #$02,(1,A1)     DLM
; 0000002C: 137C 0003 0003      MOVE.B  #$03,(3,A1)     LCR 8N1
; 00000032: 247C 0200 0000      MOVEA.L #$02000000,A2
; 00000038: 263C 5A5A 5A5A      MOVE.L  #$5A5A5A5A,D3
; 0000003E: 2483                MOVE.L  D3,(A2)
; 00000040: 2812                MOVE.L  (A2),D4
; 00000042: B883                CMP.L   D3,D4
; 00000044: 6708                BEQ.S   SDRAM_OK (disp=+8)
; 00000046: 20BC FFFF FFFF      MOVE.L  #$FFFFFFFF,(A0) FAIL
; 0000004C: 60FE                FAIL_HALT: BRA.S self (disp=-2)
; 0000004E: 2080                MOVE.L  D0,(A0)         ; SDRAM_OK/LOOP
; 00000050: 5280                ADDQ.L  #1,D0
; 00000052: 1429 0005           MOVE.B  (5,A1),D2       LSR -> D2
; 00000056: 0802 0005           BTST    #5,D2
; 0000005A: 6706                BEQ.S   SKIP_TX (disp=+6)
; 0000005C: 137C 0055 0000      MOVE.B  #$55,(0,A1)     THR = 'U'
; 00000062: 223C 0003 0000      MOVE.L  #$30000,D1      ; SKIP_TX
; 00000068: 5381                SUBQ.L  #1,D1           ; DELAY
; 0000006A: 66FC                BNE.S   DELAY   (disp=-4)
; 0000006C: 60E0                BRA.S   LOOP    (disp=-32)
; 0000006E: 0000                (padding, unreachable, keeps longword count even)
