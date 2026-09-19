; Mackerel-030F first bring-up smoke test.
;
; Not run through a real assembler yet (no m68k-mackerel-elf- toolchain
; wired into this repo's build — see plan.md step 8's own bootloader
; item). Hand-assembled directly into rom.hex; kept here purely as the
; human-readable source so rom.hex is maintainable/regeneratable rather
; than an opaque hex blob. Verified encoding by hand against the
; standard 68000 MOVE/MOVEA/ADDQ/SUBQ/Bcc bit layouts.
;
; Purpose: prove m68030_top boots on real ULX3S fabric and can drive an
; external bus write cycle (LED register) and read a ROM instruction
; stream correctly — the first entry in plan.md's own bring-up order,
; before UART/SDRAM/anything else.
;
; Never touches the stack (no JSR/exceptions expected — all interrupt
; sources are tied inactive in mackerel_030f.v), so SSP is set to
; $00001000 (just past the 4KB ROM window, inside the watchdog-BERR'd
; unmapped region) purely as a deliberate "must never actually be
; dereferenced" placeholder, not a real stack.

        ORG     $000000
        DC.L    $00001000               ; initial SSP (placeholder, unused)
        DC.L    START                   ; initial PC

START:
        MOVEA.L #$FFFFFF00, A0          ; A0 = GPIO LED register
        MOVE.L  #0, D0                  ; D0 = LED pattern

LOOP:
        MOVE.L  D0, (A0)                ; drive LEDs from D0
        ADDQ.L  #1, D0                  ; increment pattern
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
; 00000014: 2080                MOVE.L  D0,(A0)         ; LOOP
; 00000016: 5280                ADDQ.L  #1,D0
; 00000018: 223C 0003 0000      MOVE.L  #$30000,D1
; 0000001E: 5381                SUBQ.L  #1,D1           ; DELAY
; 00000020: 66FC                BNE.S   DELAY   (disp=-4)
; 00000022: 60F0                BRA.S   LOOP    (disp=-16)
