; Nabu Digital Rain
; Copyright 2023 Erik E. Johnson
; See LICENSE.txt for details

; To build homebrew .nabu file:
; sjasmplus --syntax=ab DigiRain.asm --lst=DigiRain.lst --raw=DigiRain.nabu

; To build a CP/M .com file:
; sjasmplus -DCPM --syntax=ab DigiRain.asm --lst=DigiRain.lst --raw=DigiRain.com

; -DF18A for F18A build

DEFAULT_DELAY = 5 ; how many frames do we wait between updates by default
DEFAULT_FONT = 1 ; 0 for thin font, 1 for chonky

    IFDEF CPM
        ; CP/M .com entry point
        org $100
    ELSE
        ; Homebrew .nabu entry point
        org $140D
        nop
        nop
        nop
    ENDIF

    ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
    ; Initialize the machine

    ; initialize video mode
    ; disabling the screen prevents flashing and allows faster
    ; vram writes during setup
    call setvdp

    ; Set up interrupts

    ; set interrupt mode 2
    di
    ld a, $ff ; High bits of interrupt vector
    ld i, a
    im 2 

    ; set interrupt handler functions
    ld hl, video_interrupt					
    ld ($ff00 + 6), hl
    ld hl, input_interrupt
    ld ($ff00 + 4), hl

    ; set up interrupts on PSG ports
    ld a, $07 ; Set reg 7
    out ($41), a
    ld a, $7F ; Port A write, B read, all sound off
    out ($40), a
    ld a, $0E ; Select port A.
    out ($41), a
    ld a, $30 ; vblank and input interrupts
    out ($40), a
    ei

    ; Clear video memory

    ; clear sprites
    ld hl, $3800
    call setwrt
    ld a, 0
    ld b, 8
1:  out (VDP0), a
    djnz 1b

    ld hl, $1b00
    call setwrt
    ld a, 0
    ld b, 32*4
1:  out (VDP0), a
    djnz 1b

    ; clear characters
    ld hl, $1800
    call setwrt
    ld a, 0
    ld b, 0
1:  out (VDP0), a
    djnz 1b
1:  out (VDP0), a
    djnz 1b
1:  out (VDP0), a
    djnz 1b

    ; Initialize fonts and colors
    ; Using a 64 character font and 4 colors.

    ; We need to copy font data to vram a bunch of times
    ; Written as a macro instead of a function for convenience,
    ; not because of any sort of performance consideration.
    MACRO LOADFONT location, font
        ld hl, location
        call setwrt
        ld hl, font
        ld c, VDP0
        ld d, 4
        ld b, 0
1:      otir
        dec d
        jr nz, 1b
    ENDM

    ; One full copy of the normal font for each color
    LOADFONT 0, rainFont
    LOADFONT FONTOFFSET*8, rainFont
    LOADFONT FONTOFFSET*8*2, rainFont

    ; The VDP Dark Green isn't much darker than Medium Green
    ; So for the fourth copy of the font we set every odd line to black
    ; For the F18A we can set custom colours so we skip this step.
    MACRO MANGLEFONT font
        IFNDEF F18A
            ld hl, font
            ld b, 0
1:          inc hl
            ld (hl), 0
            inc hl
            djnz 1b
        ENDIF
    ENDM

    MANGLEFONT rainFont

    LOADFONT FONTOFFSET*8*3, rainFont

    ; and 4 more copies to support the chonky font
    LOADFONT $800, chonkFont
    LOADFONT $800+FONTOFFSET*8, chonkFont
    LOADFONT $800+FONTOFFSET*8*2, chonkFont

    MANGLEFONT chonkFont

    LOADFONT $800+FONTOFFSET*8*3, chonkFont

    ; set up the color table for our four colors

    MACRO SETCOLOR location, color
        ld hl, location
        call setwrt
        ld a, color
        ld b, (FONTSIZE+1)/8
1:      out (VDP0), a
        djnz 1b
    ENDM

    SETCOLOR $2000, $f1 ; white on black
    SETCOLOR $2000+FONTOFFSET/8, $31 ; light green on black
    SETCOLOR $2000+FONTOFFSET/8*2, $21 ; medium green on black
    SETCOLOR $2000+FONTOFFSET/8*3, $c1 ; dark green on black

    ; enable screen
    di
    ld a, $e0 ; 16kb, mode 0, screen enabled, gen interrupts
    out (VDP1), a
    ld a, $81
    out (VDP1), a
    ei

    /*
    ; debug, lets see our font:
    ld hl, $1800
    call setwrt

    ld a, 0
1:  out (VDP0), a
    nop
    inc a
    jr nz, 1b

    di
    halt
    */

    ; set up RNG
    ld ix, randvars
    ld (ix+seed1), $34

    ; initialize some vars
    ld a, DEFAULT_DELAY
    ld (delay), a

    ld a, DEFAULT_FONT
    ld (fontToggle), a

    ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
    ; Main program logic

start:
    ; clear working ram    
    ld hl,sim ;; HL = start address of block
    ld e,l
    ld d,h
    inc de ;; DE = HL + 1
    ld (hl),0 ;; initialise first byte of block with data byte (&00)
    ld bc,768*2+32 ;; BC = length of block in bytes
    ldir ;; fill memory
    
    ; init drop state
    ld hl, nextdrop
    ld a, DROP
    ld b, 32
1:  ld (hl), a
    inc hl
    djnz 1b

    ld hl, countdown
    ld b, 32
1:  call random
    and $3f
    ld (hl), a
    inc hl
    djnz 1b

    xor a
    ld (lastInput), a

update:

/*
    memory layout:
    countdown - 32 bytes one for each column, that count down until the next drop or the next tail
    nextdrop - a byte for each column to track if a drop or a tail comes next
    sim - 768 byte simulation area that drops move through, value indicates a drop, a tail, or a color fade
    gutter - 32 bytes after the sim area that catches the drops
    buffer - the specific character data which is copied to vram every update

    approach (doesn't cover color fades)

    drop:
        set cell to empty
        set cell below to drop
        set char below to randrom white
        set this char to green
        set random white char
    
    tail:
        set cell to empty
        set cell below to tail
        set char to blank
*/

    ; cols 32
    ; rows 24

    ; main simulation
    ; scan from bottom up
    ld hl, sim + 32*24
    ld c, 3
    ld b, 0
rowloop:
    dec hl
    ld a, (hl)
    cp 0
    jr z, 3f ; most cells are 0, so shortcut
    cp DROP
    jr nz, 1f
    ; drop
    push bc
    ld (hl), DROPFADE1
    ld bc, hl
    ld de, bufferOffset
    add hl, de ; move to char memory
    ld a, (hl)
    add FONTOFFSET
    ld (hl), a ; change to bright green
    ld de, 32
    add hl, de ; next row
    call random
    and FONTSIZE
    ld (hl), a ; rand white char
    ld hl, bc ; back to cells
    add hl, de ; next row
    ld (hl), DROP ; drop moves down
    ld hl, bc
    pop bc
    jr 3f
1:  cp DROPFADE1
    jr nz, 1f
    ; fade step 1
    ld (hl), DROPFADE2
    jr 3f
1:  cp DROPFADE2
    jr nz, 1f
    ; fade step 2
    ld (hl), 0
    push hl
    ld de, bufferOffset
    add hl, de ; char memory
    ld a, (hl)
    add FONTOFFSET
    ld (hl), a ; change to medium green
    pop hl
    jr 3f
1:  cp TAIL
    jr nz, 1f
    ; tail
    push bc
    ld (hl), TAILFADE1 ; fade tail
    ld bc, hl
    ld de, bufferOffset
    add hl, de
    ld a, (hl)
    add FONTOFFSET
    ld (hl), a ; change to dark green
    ld hl, bc
    ld de, 32
    add hl, de
    ld (hl), TAIL ; move tail down
    ld hl, bc    
    pop bc
1:  cp TAILFADE1
    jr nz, 1f
    ; tail fade
    push hl
    ld (hl), 0 ; clear cell
    ld de, bufferOffset
    add hl, de
    ld (hl), 0 ; clear char
    pop hl
    jr 3f
1:
3:  djnz rowloop
    dec c
    jr nz, rowloop


    ; new drop & tail timing
    ld hl, countdown
    ld b, 32
tl:
    dec (hl)
    jr nz, 3f
    ; countdown done
    push hl
    ld de, 32
    add hl, de
    ld a, (hl)
    cp DROP
    jr nz, 1f
    ; new drop
    ld (hl), TAIL ; tail next
    add hl, de
    ld (hl), DROP ; set cell data
    ld de, 768
    add hl, de
    call random
    and FONTSIZE
    ld (hl), a ; random white char in char data
    pop hl
    call random
    and $7f
    add 3 ; minimum until tail drops
    ld (hl), a ; set new countdown timer
    jr 3f
1:  ; start tail
    ld (hl), DROP ; head next
    add hl, de
    ld (hl), TAIL ; set cell data
    pop hl
    call random
    and $7f
    ld (hl), a ; set new countdown timer
3:  inc hl
    djnz tl


; glitcher
/*
    radomly scramble chunks of columns
    scramble 8 chars every time
    randomly picks a starting row between 0 & 16
*/
    ld hl, buffer ; operating directly on chars
    ld b, 32
glitchloop:
    call random
    cp 240 ; 240 / 255 chance of glitch per column per update
    jr c, 4f
    push hl
    push bc
    call random
    and $0f ; random starting row
    ld de, 32
    ld b, a
1:  add hl, de ; move to offset
    djnz 1b
    ld b, 8 ; glitch 8 chars
2:  ld a, (hl)
    cp FONTOFFSET*2 ; check if we have a non-head character
    jr c, 3f
    call random
    and FONTSIZE
    add FONTOFFSET*2
    ld (hl), a
3:  add hl, de
    djnz 2b
    pop bc
    pop hl
4:  inc hl
    djnz glitchloop

;;;;;;;;;;; update complete

    ; copy buffer to vram
    call blit

    ;call vbi_blit

;;;;;;;;;;; timing

    ld a, (delay)
    ld b, a
    cp 0    
    jr z, 2f
1:  call vWait
    djnz 1b
2:

;;;;;;;;;;;; handle input

    ld a, (lastInput)

    cp 'c'
    jr nz, 1f
    ; Toggle chonk font!
    ; 0 points at 1st font's vram location
    ; 1 points at 2nd font
    ld a, (fontToggle)
    xor $ff
    and 1 ; xor bit 0
    ld (fontToggle), a 

    di
    out (VDP1), a ; change where the VDP looks for font data
    ld a, $84
    out (VDP1), a ; by writing to register 4
    ei

    jp doneInput

1:  cp '-'
    jr nz, 1f
    ; update slower, increase the delay
    ld a, (delay)
    inc a
    ld (delay), a

    jp doneInput

1:  cp '='
    jr nz, 1f
    ; update faster, decrease the delay
    ld a, (delay)
    cp 0
    jr z, doneInput ; can't go any faster than 0 delay
    dec a
    ld (delay), a

    jp doneInput

1:  cp 'r'
    jp nz, 1f
    jp start ; reset the screen

1:  cp $f9 ; pause key
    jp nz, 1f
    call pause

1:
doneInput:  
    xor a
    ld (lastInput), a

;;;;;;;;;;;;;

    jp update ; loop

;;;;;;;;;;;; end


pause:
    ld a, $23
    out (0), a ; turn on pause light
    xor a
    ld (lastInput), a ; clear input
pauseLoop:
    halt
    ld a, (lastInput)
    cp $f9
    jr nz, pauseLoop
    ld a, $03
    out (0), a ; turn off light
    ret


vWait:
    xor a
    ld (onSync), a
1:  halt
    ld a, (onSync)
    cp 0
    jr z, 1b
    ret

video_interrupt:
    push af
    ld a, 1
    ld (onSync), a
    in a, (VDP1)
    pop af
    ei
    reti

input_interrupt:
    push af
    in a, $90
    ld (lastInput), a
    pop af
    ei
    reti


/*vbi_blit:
    ; wait for vertical blanking interval and then do a max speed
    ; copy of 768 bytes to vram
    ld hl, $1800 ; vram destination
    call setwrt
    ld hl, buffer ; source
    ld c, VDP0
    ld b, 0
    call vWait ; wait for vblank
    REPT 768 ; lol, this uses 1.5kb of ram
    outi
    ENDR
    ret*/


blit:
    ld hl, $1800
    call setwrt
    ld hl, buffer
    ld c, VDP0
    ld b, 0

    ; write 768 bytes to vram as fast as possible without
    ; overwhelming the VDP
1:  outi
    jr nz, 1b
    nop
1:  outi
    jr nz, 1b
    nop
1:  outi
    jr nz, 1b

    ret

; set vram write address
setwrt:
    di
    ld a, l
    out (VDP1), a
    ld a, h
    and $3F
    or $40
    out (VDP1), a
    ei
    ret

; Initial VDP setup
vdpdata:
    db $00,$80 ; not mode 2
    db $a0,$81 ; 16kb, mode 0, screen disabled to start, gen interrupts
    db $06,$82 ; PNT at $1800
    db $80,$83 ; Color Table at $2000
    db DEFAULT_FONT, $84 ; PGT starting at either 0 or $0800
    db $36,$85 ; sprite attribute table at $1b00
    db $07,$86 ; sprite gen table at $3800
    db $f0,$87 ; FG and BG colour

setvdp:
	ld b, 16
	ld c, VDP1
	ld hl, vdpdata
	di
regloop:
	outi
	jr nz,regloop

    ; For F18A builds, we set a custom palette where dark green is darker and white is replaced
    ; with a very bright green

    IFDEF F18A
        ; Unlock access to F18A features by writting $c1 to F18A port 57 (Aka VDP port 1) twice:
        ld a, $c1 ; unlock key
        out (VDP1), a
        ld a, $80 + 57 ; port 57
        out (VDP1), a
        ld a, $c1
        out (VDP1), a
        ld a, $80 + 57
        out (VDP1), a

        ; Write the new palette to the F18A

        ; set up F18A to write palette
        ld a, $c0 ; value: 1100 0000, DPM = 1, AUTO INC = 1, start PR0.
        out (VDP1), a
        ld a, $80 + 47 ; Reg 47
        out (VDP1), a

        ld hl, newPalette
        ld b, 32 ; 2 bytes for each color entry
        ld c, VDP0
        otir

        ld a, 0
        out (VDP1), a ; value: 0000 0000, exit DMP
        ld a, $80 + 47 ; Reg 47
        out (VDP1), a

        ; reset to a sensible video mode, Reg 1 relocks F18A
        ld a, $a0 ; 16kb, mode 0, screen disabled to start, gen interrupts
        out (VDP1), a
        ld a, $81 ; Reg 1
        out (VDP1), a
    ENDIF

	ei
	ret

    include random.asm

; fonts derived from emutyworks 8x8DotJPFont
; https://github.com/emutyworks/8x8DotJPFont
; Which itself is derived from Num Kadoma's Misaki font
; http://littlelimit.net/misaki.htm
; See font files for full license information
rainFont:
    include rainfont.asm
chonkFont:
    include chonkfont.asm

    IFDEF F18A
newPalette:
        dw $0000 ;    * Transparent
        dw $0000 ;    * Black
        dw $02C3 ;    * Medium Green
        dw $05D6 ;    * Light Green
        dw $054F ;    * Dark Blue
        dw $076F ;    * Light Blue
        dw $0D54 ;    * Dark Red
        dw $04EF ;    * Cyan
        dw $0F54 ;    * Medium Red
        dw $0F76 ;    * Light Red
        dw $0DC3 ;    * Dark Yellow
        dw $0ED6 ;    * Light Yellow
        dw $0292 ;    * modified Darker than normal Dark Green
        dw $0C5C ;    * Magenta
        dw $0CCC ;    * Gray
        dw $0DFD ;    * modified greenish White
    ENDIF

VDP0 = $a0
VDP1 = $a1

FONTSIZE = $3f
FONTOFFSET = $40

DROP = 6
DROPFADE1 = 5
DROPFADE2 = 4
TAIL = 3
TAILFADE1 = 2

onSync ds 1
lastInput ds 1
fontToggle ds 1
delay ds 1

countdown ds 32
nextdrop ds 32
sim ds 768
gutter ds 32
buffer ds 768

bufferOffset = buffer - sim