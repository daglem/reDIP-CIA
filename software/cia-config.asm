;; ----------------------------------------------------------------------------
;; This file is part of reDIP CIA, a MOS 6526/8520/8521 FPGA emulation platform.
;; Copyright (C) 2026  Dag Lem <resid@nimrod.no>
;;
;; This source describes Open Hardware and is licensed under the CERN-OHL-S v2.
;;
;; You may redistribute and modify this source and make products using it under
;; the terms of the CERN-OHL-S v2 (https://ohwr.org/cern_ohl_s_v2.txt).
;;
;; This source is distributed WITHOUT ANY EXPRESS OR IMPLIED WARRANTY,
;; INCLUDING OF MERCHANTABILITY, SATISFACTORY QUALITY AND FITNESS FOR A
;; PARTICULAR PURPOSE. Please see the CERN-OHL-S v2 for applicable conditions.
;;
;; Source location: https://github.com/daglem/reDIP-CIA
;; ----------------------------------------------------------------------------

INDEX  = $22            ; Utility Pointer Area
TXTPTR = $7a            ; Pointer: Current Byte of BASIC Text
FREKZP = $fb            ; Free O-Page Space for User Programs
BASZPT = $ff            ; BASIC Temp Data Area
COLOR  = $0286          ; Current Character Color Code
GDCOL  = $0287          ; Background Color Under Cursor

STRPTR = INDEX          ; String pointer
CIAPTR = INDEX + 2      ; Pointer to current CIA - 1 (-1 to handle dummy reads)
CIACUR = FREKZP         ; Current CIA configurations
CIACFG = FREKZP + 2     ; Saved CIA configurations
LINENO = BASZPT         ; Current CIA # - 1
CHROUT = $ffd2          ; Output a character
GETIN  = $ffe4          ; Get a character
SCNKEY = $ff9f          ; Scan the keyboard
STOP   = $ffe1          ; Check if STOP key is pressed

*   = $0801
    ; 6526 SYS2064CIA
    .word (+), 6526
    .text $9e, "2064cia", 0
+   .word 0
    ; Advance TXTPTR past "CIA".
    lda #13
    sta TXTPTR

    ; Store old and set new colors.
    lda COLOR
    pha
    lda $d020
    pha
    lda $d021
    pha
    lda #6              ; Blue
    sta $d020
    sta $d021

    ; Detect CIA models
    ldx #0
    jsr cia_detect
    ldx #1
    jsr cia_detect

    ; Print configuration screen
    #print txt_header
    ldx #0
    lda CIACFG          ; Any configurable CIAs?
    ora CIACFG + 1
    pha
    bne +
    dex                 ; No configurable CIAs, use non-existing line #
+   stx LINENO
    jsr print_cias

    pla                 ; Any configurable CIAs?
    bne config
    #print txt_noconf
    jmp done

config:
    #print txt_help

    ; Input loop
-   jsr GETIN
    cmp #'{stop}'
    beq stop
    cmp #'{f8}'
    beq save
    ldx LINENO
    cmp #'{up}'
    bne +
    cpx #0
    beq -               ; Already at first line
    dex
    bpl upd_line
+   cmp #'{down}'
    bne +
    cpx #1
    beq -               ; Already at last line
    inx
upd_line:
    stx LINENO
    bpl print_lines
+   ldy CIACFG, x
    beq -               ; Not configurable
    ldy CIACUR, x
+   cmp #'+'
    bne +
    cpy #2              ; Don't show 8520 once deselected (this is a C64!)
    bge -               ; 8521 (or 8520) already selected
    iny
    bpl upd_model
+   cmp #'-'
    bne -
    cpy #1
    beq -               ; 6526 already selected
    dey
upd_model:
    sty CIACUR, x
    jsr set_model
print_lines:
    jsr print_cias
    jmp -

stop:
    jsr models_unchanged
    beq exit
    #print txt_unsaved
-   jsr GETIN
    cmp #'y'
    beq exit
+   cmp #'n'
    beq +
    cmp #'{stop}'
    bne -
+   lda CIACFG
    sta CIACUR
    lda CIACFG + 1
    sta CIACUR + 1
    jsr set_models
    jmp exit

save:
    #print txt_header
    ldx #$ff            ; Use non-existing line #
    stx LINENO
    ldx #0
    jsr cia_save
    ldx #1
    jsr cia_save
    #print txt_saved

done:
-   jsr GETIN
    cmp #'{stop}'
    bne -

exit:
    ; Avoid "BREAK IN 6526"
-   jsr STOP
    beq -

    pla
    sta $d021
    pla
    sta $d020
    pla
    sta $0286
    #print txt_exit
    rts

cia_detect:
    txa
    jsr cia_addr
    lda #0              ; Read currently configured CIA model
    jsr cia_cfg
    bne +
    jmp cia_detect_irq
+   sta CIACUR, x
    lda #6              ; Read saved CIA model from flash
    jsr cia_cfg
    sta CIACFG, x
    rts

cia_addr:
    ; We must avoid dummy reads of the ICR register by sta (CIAPTR),y
    ; This is accomplished by using CIAPTR - 1 instead of CIAPTR, directing
    ; dummy reads to the previous page.
    clc
    adc #$db            ; DC00-1 or DD00-1
    sta CIAPTR + 1
    lda #$ff
    sta CIAPTR
    rts

cia_cfg:
    ; reDIP CIA CFG command, using ICR register
    jsr critical_section  ; Ensure that readout of ICR after CFG7 is not delayed
    pha
    ldy #$0d + 1        ; ICR
    lda #('c' - 64)*16
    sta (CIAPTR), y
    lda #('f' - 64)*16
    sta (CIAPTR), y
    lda #('g' - 64)*16
    sta (CIAPTR), y
    pla
    ; CFG command # in ICR bits 6:4
    asl
    asl
    asl
    asl
    sta (CIAPTR), y
    lda (CIAPTR), y
    ; CIA model or other info in ICR bits 6:5
    and #%01100000
    lsr
    lsr
    lsr
    lsr
    lsr
    cli
    rts

cia_detect_irq:
    jsr critical_section

    ; Set timer A
    lda #20 - 1         ; 20 cycles
    ldy #$04 + 1        ; Timer A low
    sta (CIAPTR), y
    lda #0
    iny                 ; Timer A high
    sta (CIAPTR), y

    ; Start timer and enable timer interrupt
    lda #%00011001      ; Force load, one-shot, start
    ldy #$0e + 1        ; CRA
    sta (CIAPTR), y
    lda #%10000001      ; Enable Timer A IRQ
    dey                 ; ICR
    sta (CIAPTR), y
    lda (CIAPTR), y     ; Clear ICR
    lda (CIAPTR), y     ; Read ICR
    ; For a MOS 6526, the interrupt is lost.
    ; For a CIA #2 MOS 8521, the kernal NMI routine will be called
    ; after the next instruction, without any ill effects.

    ; Store model #
    rol                 ; Move bit 7 (ICR IR) to bit 0
    rol
    and #$01
    clc
    adc #1
    sta CIACUR, x       ; Store model #
    lda #$00
    sta CIACFG, x       ; Not configurable

    ; Restore to default values
    lda timer_a_lo, x
    ldy #$04 + 1
    sta (CIAPTR), y
    lda timer_a_hi, x
    iny
    sta (CIAPTR), y
    lda icr, x
    ldy #$0d + 1
    sta (CIAPTR), y
    lda cra, x
    iny
    sta (CIAPTR), y

    cli
    rts

critical_section:
    ; We must avoid interrupts and VIC-II badlines.
    sei
    ; Wait for vertical blank (raster = 0)
-   bit $d011
    bpl -
-   bit $d011
    bmi -
    rts

models_unchanged:
    ldx #0
    jsr model_unchanged
    bne +
    inx
    jsr model_unchanged
+   rts

model_unchanged:
    lda CIACFG, x
    beq +
    cmp CIACUR, x
+   rts

set_models:
    ldx #0
    jsr set_model
    inx
    jmp set_model

set_model:
    txa
    jsr cia_addr
    lda CIACUR, x
    jsr cia_cfg         ; 1 = MOS6526, 2 = MOS8521
    rts

cia_save:
    jsr set_model
    lda CIACFG, x
    pha
    jsr print_cia
    pla
    bne +
    #print txt_skip
    rts
+   cmp CIACUR, x
    bne +
    #print txt_unchanged
    rts
+   lda #5              ; Read number of flash erase/program cycles
    jsr cia_cfg
    cmp #3              ; Must reset after 3 cycles
    bne +
    #print txt_progerr
    rts
+   lda #7              ; Write configuration to flash
    jsr cia_cfg
    #print txt_erase
    ldy #$0d + 1        ; ICR
-   lda (CIAPTR), y
    and #%01000000
    bne -               ; Wait for erase to finish
    lda #'✓'
    jsr CHROUT
    #print txt_program
    ldy #$0d + 1        ; ICR
-   lda (CIAPTR), y
    and #%00100000
    bne -               ; Wait for program to finish
    lda #'✓'
    jsr CHROUT
    rts

print_cias:
    lda #'{home}'
    jsr CHROUT
    jsr newline
    ldx #0
    jsr print_cia
    ldx #1
    ; jmp print_cia

print_cia:
    txa
    pha
    lda #'{lt blue}'
    cpx LINENO          ; Current line?
    bne +
    lda #'{white}'
+   jsr CHROUT
    #print txt_cia      ; Print "CIA #"
    pla
    tax
    clc
    adc #$31
    jsr CHROUT          ; Print "1" or "2"
    lda #' '
    jsr CHROUT
    jsr CHROUT

    lda CIACFG, x
    bne conf
    lda #' '            ; Not configurable
    jsr CHROUT
    jsr print_model
    lda #' '
    jmp CHROUT
conf:
    lda #'['            ; Configurable
    jsr CHROUT
    cpx LINENO          ; Current line?
    bne +
    lda #'{rvs on}'
    jsr CHROUT
+   jsr print_model
    lda #'{rvs off}'
    jsr CHROUT
    lda #']'
    jmp CHROUT

print_model:
    txa
    pha
    ldy CIACUR, x
    dey
    ldx model_lo, y
    lda model_hi, y
    tay
    jsr print_string
    pla
    tax
    rts

newline:
    lda #$0d
    jmp CHROUT

print_string:
    stx STRPTR
    sty STRPTR + 1
    ldy #$00
nxtchr:
    lda (STRPTR), y
    beq nul
    jsr CHROUT
    iny
    jmp nxtchr
nul:
    rts

print .macro string
    ldx #<\string
    ldy #>\string
    jsr print_string
    .endmacro

; Restore values for CIA #1 and CIA #2
timer_a_lo:
   .byte $25, $00
timer_a_hi:
   .byte $40, $00
icr:
   .byte $81, $7f
cra:
   .byte $11, $08

txt_header:
    .null "{clear}{up/lo lock on}{lower case}{white}reDIP CIA Configuration{lt blue}{cr}"
txt_cia:
    .null "{cr}CIA #"
txt_6526:
    .null "6526"
txt_8521:
    .null "8521"
txt_8520:
    .null "8520"
model_lo:
    .byte <txt_6526, <txt_8521, <txt_8520
model_hi:
    .byte >txt_6526, >txt_8521, >txt_8520
txt_skip:
    .null "  Not configurable"
txt_unchanged:
    .null "  Not changed"
txt_erase:
    .null "  {white}Erase "
txt_program:
    .null "  Program "
txt_progerr:
    .null "  {white}Max 3 saves per reset"
txt_noconf:
    .null "{cr}{cr}{white}STOP{lt blue} Exit  (No configurable CIA found)"
txt_help:
    .null "{cr}{cr}{white}STOP{lt blue} Exit  {white}Up{lt blue}/{white}Dn{lt blue} Sel  {white}+{lt blue}/{white}-{lt blue} Chg  {white}F8{lt blue} Save"
txt_unsaved:
    .null "{cr}{cr}{lt blue}Use unsaved config until reset ({white}Y{lt blue}/{white}N{lt blue})?      "
txt_saved:
    .null "{cr}{cr}{white}STOP{lt blue} Exit"
txt_exit:
    .null "{clear}{upper case}{up/lo lock off}"
