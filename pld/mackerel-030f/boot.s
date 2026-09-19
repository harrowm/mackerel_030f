; Mackerel-030F bring-up smoke test, cut 2: LED counter + UART console.
;
; Not run through a real assembler yet (no m68k-mackerel-elf- toolchain
; wired into this repo's build — see plan.md step 8's own bootloader
; item). Hand-assembled directly into rom.hex; kept here purely as the
; human-readable source so rom.hex is maintainable/regeneratable rather
; than an opaque hex blob. Every encoding verified by hand against the
; standard 68000 bit layouts (MOVE/MOVEA/ADDQ/SUBQ/BTST/Bcc, plus the
; (d16,An) addressing mode used for the UART register accesses).
;
; Purpose: proves m68030_top can drive a genuine 8-bit-port peripheral
; (dynamic bus sizing down from its own 32-bit native width) in addition
; to the 32-bit-port ROM/GPIO cut-1 already proved — the uart16550's own
; register writes/reads are all single BYTE accesses.
;
; Never touches the stack (no JSR/exceptions expected — all interrupt
; sources are tied inactive in mackerel_030f.v), so SSP is set to
; $00001000 (just past the 4KB ROM window, inside the watchdog-BERR'd
; unmapped region) purely as a deliberate "must never actually be
; dereferenced" placeholder, not a real stack.
;
; UART divisor: uart16550's wb_clk_i is fed clk_4x (100 MHz, see
; clk_pll.v). 9600 baud -> divisor = 100,000,000 / (16*9600) = 651.04,
; rounded to 651 = $0288 (DLM=$02, DLL=$88) -- chosen for margin over a
; faster baud rate on a first bring-up, not for any particular reason
; tied to the real Mackerel-30/Mackerel-F baud rate.

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
; 00000032: 2080                MOVE.L  D0,(A0)         ; LOOP
; 00000034: 5280                ADDQ.L  #1,D0
; 00000036: 1429 0005           MOVE.B  (5,A1),D2       LSR -> D2
; 0000003A: 0802 0005           BTST    #5,D2
; 0000003E: 6706                BEQ.S   SKIP_TX (disp=+6)
; 00000040: 137C 0055 0000      MOVE.B  #$55,(0,A1)     THR = 'U'
; 00000046: 223C 0003 0000      MOVE.L  #$30000,D1      ; SKIP_TX
; 0000004C: 5381                SUBQ.L  #1,D1           ; DELAY
; 0000004E: 66FC                BNE.S   DELAY   (disp=-4)
; 00000050: 60E0                BRA.S   LOOP    (disp=-32)
; 00000052: 0000                (padding, unreachable, keeps longword count even)
